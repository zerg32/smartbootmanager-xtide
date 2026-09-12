#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

enum {
    SECTOR_SIZE = 512,
    MBR_CODE_SIZE = 440,
    PARTITION_TABLE_OFFSET = 446,
    SBM_KERNEL_LBA = 1,
    DEBUG_STAGE_LBA = 39,
    DEBUG_STAGE_SECTORS = 2,
    DEBUG_LOADER_LBA = 63,
    OLD_KERNEL_LBA = 64,
    OLD_KERNEL_SECTORS = 64,
    XTIDE_LBA = 128,
    DOS_PARTITION_LBA = 1008,
    DOS_PARTITION_SECTORS = 3145728,
    SECOND_PARTITION_LBA = 3146736,
    SECOND_PARTITION_SECTORS = 1572864,
    THIRD_PARTITION_LBA = 4719600,
    THIRD_PARTITION_SECTORS = 3242592,
};

static void fail(const char *message) {
    perror(message);
    exit(EXIT_FAILURE);
}

static uint8_t *read_file(const char *path, size_t *size) {
    struct stat st;
    uint8_t *data;
    FILE *file = fopen(path, "rb");

    if (file == NULL)
        fail(path);
    if (fstat(fileno(file), &st) != 0)
        fail(path);
    if (st.st_size <= 0) {
        fprintf(stderr, "%s is empty\n", path);
        exit(EXIT_FAILURE);
    }
    *size = (size_t)st.st_size;
    data = malloc(*size);
    if (data == NULL)
        fail("malloc");
    if (fread(data, 1, *size, file) != *size)
        fail(path);
    if (fclose(file) != 0)
        fail(path);
    return data;
}

static void write_at(int fd, uint64_t offset, const void *data, size_t size) {
    if (pwrite(fd, data, size, (off_t)offset) != (ssize_t)size)
        fail("writing debug image");
}

static uint32_t get_le32(const uint8_t *ptr) {
    return (uint32_t)ptr[0] | ((uint32_t)ptr[1] << 8) |
           ((uint32_t)ptr[2] << 16) | ((uint32_t)ptr[3] << 24);
}

static void set_le32(uint8_t *ptr, uint32_t value) {
    ptr[0] = (uint8_t)value;
    ptr[1] = (uint8_t)(value >> 8);
    ptr[2] = (uint8_t)(value >> 16);
    ptr[3] = (uint8_t)(value >> 24);
}

static void set_chs(uint8_t *ptr, uint32_t lba) {
    uint32_t cylinder = lba / (16 * 63);
    uint32_t remainder = lba % (16 * 63);
    uint8_t head = (uint8_t)(remainder / 63);
    uint8_t sector = (uint8_t)(remainder % 63 + 1);

    if (cylinder > 1023) {
        ptr[0] = 254;
        ptr[1] = 255;
        ptr[2] = 255;
        return;
    }
    ptr[0] = head;
    ptr[1] = (uint8_t)(sector | ((cylinder >> 2) & 0xC0));
    ptr[2] = (uint8_t)cylinder;
}

static void set_partition(uint8_t *entry, uint8_t boot, uint8_t type,
                          uint32_t start, uint32_t sectors) {
    memset(entry, 0, 16);
    entry[0] = boot;
    set_chs(entry + 1, start);
    entry[4] = type;
    set_chs(entry + 5, start + sectors - 1);
    set_le32(entry + 8, start);
    set_le32(entry + 12, sectors);
}

static size_t find_signature(const uint8_t *data, size_t size,
                             const char *signature) {
    size_t index;

    for (index = 0; index + 4 <= size; ++index) {
        if (memcmp(data + index, signature, 4) == 0)
            return index;
    }
    fprintf(stderr, "missing %.4s signature\n", signature);
    exit(EXIT_FAILURE);
}

static void checksum_sbm(uint8_t *main, size_t size) {
    size_t magic = find_signature(main, size, "SBMK");
    uint16_t total_size = (uint16_t)(main[magic + 6] |
                                     ((uint16_t)main[magic + 7] << 8));
    size_t checksum_offset = magic + 10;
    uint8_t sum = 0;
    size_t index;

    if (total_size == 0 || total_size > size || checksum_offset >= total_size) {
        fprintf(stderr, "invalid SBM kernel header\n");
        exit(EXIT_FAILURE);
    }
    main[checksum_offset] = 0;
    for (index = 0; index < total_size; ++index)
        sum = (uint8_t)(sum + main[index]);
    main[checksum_offset] = (uint8_t)(0 - sum);
}

int main(int argc, char **argv) {
    uint8_t mbr[SECTOR_SIZE];
    uint8_t zeroes[OLD_KERNEL_SECTORS * SECTOR_SIZE] = {0};
    uint8_t *debug_mbr, *debug_stage, *loader, *main, *xtide;
    size_t debug_mbr_size, debug_stage_size, loader_size, main_size, xtide_size;
    size_t loader_magic;
    uint32_t main_sectors;
    struct stat st;
    int fd;

    if (argc != 7) {
        fprintf(stderr,
                "usage: %s DEBUG_MBR DEBUG_STAGE LOADER MAIN XTIDE IMAGE\n",
                argv[0]);
        return EXIT_FAILURE;
    }

    debug_mbr = read_file(argv[1], &debug_mbr_size);
    debug_stage = read_file(argv[2], &debug_stage_size);
    loader = read_file(argv[3], &loader_size);
    main = read_file(argv[4], &main_size);
    xtide = read_file(argv[5], &xtide_size);

    if (debug_mbr_size != MBR_CODE_SIZE ||
        debug_stage_size != DEBUG_STAGE_SECTORS * SECTOR_SIZE ||
        loader_size != SECTOR_SIZE || xtide_size != 8192) {
        fprintf(stderr, "invalid diagnostic, loader, or XT-IDE size\n");
        return EXIT_FAILURE;
    }

    main_sectors = (uint32_t)((main_size + SECTOR_SIZE - 1) / SECTOR_SIZE);
    if (main_sectors > DEBUG_STAGE_LBA - SBM_KERNEL_LBA) {
        fprintf(stderr, "SBM kernel overlaps the diagnostic payload\n");
        return EXIT_FAILURE;
    }
    checksum_sbm(main, main_size);

    loader_magic = find_signature(loader, loader_size, "SBML");
    if (loader_magic + 11 > PARTITION_TABLE_OFFSET) {
        fprintf(stderr, "invalid SBM loader header\n");
        return EXIT_FAILURE;
    }
    loader[loader_magic + 6] = (uint8_t)main_sectors;
    set_le32(loader + loader_magic + 7, SBM_KERNEL_LBA);

    fd = open(argv[6], O_RDWR);
    if (fd < 0)
        fail(argv[6]);
    if (fstat(fd, &st) != 0)
        fail(argv[6]);
    if ((uint64_t)st.st_size !=
        (uint64_t)(THIRD_PARTITION_LBA + THIRD_PARTITION_SECTORS) * SECTOR_SIZE) {
        fprintf(stderr, "image does not have the expected 7,962,192 sectors\n");
        return EXIT_FAILURE;
    }
    if (pread(fd, mbr, sizeof(mbr), 0) != sizeof(mbr))
        fail("reading image MBR");
    if (mbr[510] != 0x55 || mbr[511] != 0xAA ||
        get_le32(mbr + PARTITION_TABLE_OFFSET + 16 + 8) != DOS_PARTITION_LBA ||
        get_le32(mbr + PARTITION_TABLE_OFFSET + 16 + 12) != DOS_PARTITION_SECTORS ||
        get_le32(mbr + PARTITION_TABLE_OFFSET + 32 + 8) != SECOND_PARTITION_LBA ||
        get_le32(mbr + PARTITION_TABLE_OFFSET + 32 + 12) != SECOND_PARTITION_SECTORS ||
        get_le32(mbr + PARTITION_TABLE_OFFSET + 48 + 8) != THIRD_PARTITION_LBA ||
        get_le32(mbr + PARTITION_TABLE_OFFSET + 48 + 12) != THIRD_PARTITION_SECTORS) {
        fprintf(stderr, "source image does not have the expected current layout\n");
        return EXIT_FAILURE;
    }

    memset(mbr, 0, sizeof(mbr));
    memcpy(mbr, debug_mbr, debug_mbr_size);
    set_partition(mbr + PARTITION_TABLE_OFFSET, 0x80, 0x06,
                  DOS_PARTITION_LBA, DOS_PARTITION_SECTORS);
    set_partition(mbr + PARTITION_TABLE_OFFSET + 16, 0x00, 0x06,
                  SECOND_PARTITION_LBA, SECOND_PARTITION_SECTORS);
    set_partition(mbr + PARTITION_TABLE_OFFSET + 32, 0x00, 0x06,
                  THIRD_PARTITION_LBA, THIRD_PARTITION_SECTORS);
    mbr[510] = 0x55;
    mbr[511] = 0xAA;

    memcpy(loader + PARTITION_TABLE_OFFSET, mbr + PARTITION_TABLE_OFFSET, 64);
    loader[510] = 0x55;
    loader[511] = 0xAA;

    write_at(fd, 0, mbr, sizeof(mbr));
    write_at(fd, (uint64_t)SBM_KERNEL_LBA * SECTOR_SIZE, main, main_size);
    write_at(fd, (uint64_t)DEBUG_STAGE_LBA * SECTOR_SIZE,
             debug_stage, debug_stage_size);
    write_at(fd, (uint64_t)DEBUG_LOADER_LBA * SECTOR_SIZE,
             loader, loader_size);
    write_at(fd, (uint64_t)OLD_KERNEL_LBA * SECTOR_SIZE,
             zeroes, sizeof(zeroes));
    write_at(fd, (uint64_t)XTIDE_LBA * SECTOR_SIZE, xtide, xtide_size);

    if (fsync(fd) != 0 || close(fd) != 0)
        fail(argv[6]);

    free(debug_mbr);
    free(debug_stage);
    free(loader);
    free(main);
    free(xtide);
    return EXIT_SUCCESS;
}
