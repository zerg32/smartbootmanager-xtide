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
    DISK_SECTORS = 8388608,
    DISK_SIZE = (uint64_t)DISK_SECTORS * SECTOR_SIZE,
    BOOT_SHIM_LBA = 63,
    SBM_KERNEL_LBA = BOOT_SHIM_LBA + 1,
    XTIDE_LBA = 128,
    FIRST_PARTITION_LBA = 1008,
    DOS_PARTITION_SECTORS = 524288,
    WINDOWS_PARTITION_LBA = FIRST_PARTITION_LBA + DOS_PARTITION_SECTORS,
    WINDOWS_PARTITION_SECTORS = 4194304,
    SPARE_PARTITION_LBA = WINDOWS_PARTITION_LBA + WINDOWS_PARTITION_SECTORS,
    XTIDE_MAX_SECTORS = 32,
    SBM_MAX_SECTORS = XTIDE_LBA - SBM_KERNEL_LBA,
};

#define MBR_BOOT_CODE_SIZE 440

static void fail(const char *message) {
    perror(message);
    exit(EXIT_FAILURE);
}

static uint8_t *read_file(const char *path, size_t *size) {
    struct stat st;
    FILE *file = fopen(path, "rb");
    uint8_t *data;

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
        fail("writing image");
}

static uint32_t sector_count(size_t bytes) {
    return (uint32_t)((bytes + SECTOR_SIZE - 1) / SECTOR_SIZE);
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
    ptr[1] = (uint8_t)(sector | ((cylinder >> 2) & 0xc0));
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

static size_t find_signature(const uint8_t *data, size_t size, const char *signature) {
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
    uint16_t total_size = (uint16_t)(main[magic + 6] | ((uint16_t)main[magic + 7] << 8));
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
    uint8_t *loader;
    uint8_t *main;
    uint8_t *xtide;
    uint8_t *mbr_code;
    size_t mbr_code_size;
    uint8_t mbr[SECTOR_SIZE] = {0};
    uint8_t boot_shim[SECTOR_SIZE];
    size_t loader_size, main_size, xtide_size, loader_magic;
    uint32_t main_sectors, xtide_sectors;
    int fd;

    if (argc != 6) {
        fprintf(stderr, "usage: %s MBR LOADER MAIN XTIDE OUTPUT\n", argv[0]);
        return EXIT_FAILURE;
    }
    mbr_code = read_file(argv[1], &mbr_code_size);
    loader = read_file(argv[2], &loader_size);
    main = read_file(argv[3], &main_size);
    xtide = read_file(argv[4], &xtide_size);
    main_sectors = sector_count(main_size);
    xtide_sectors = sector_count(xtide_size);

    if (mbr_code_size < MBR_BOOT_CODE_SIZE) {
        fprintf(stderr, "invalid MBR boot code\n");
        return EXIT_FAILURE;
    }
    if (loader_size != SECTOR_SIZE || main_sectors > SBM_MAX_SECTORS ||
        xtide_sectors == 0 || xtide_sectors > XTIDE_MAX_SECTORS ||
        xtide_size < (size_t)xtide[2] * SECTOR_SIZE ||
        xtide[0] != 0x55 || xtide[1] != 0xaa || xtide[2] != xtide_sectors) {
        fprintf(stderr, "invalid loader, SBM kernel, or XT-IDE image\n");
        return EXIT_FAILURE;
    }

    checksum_sbm(main, main_size);
    loader_magic = find_signature(loader, loader_size, "SBML");
    if (loader_magic + 6 + 5 > 446) {
        fprintf(stderr, "invalid SBM loader header\n");
        return EXIT_FAILURE;
    }
    loader[loader_magic + 6] = (uint8_t)main_sectors;
    set_le32(loader + loader_magic + 7, SBM_KERNEL_LBA);

    memcpy(mbr, mbr_code, MBR_BOOT_CODE_SIZE);
    set_partition(mbr + 446, 0x80, 0xda, BOOT_SHIM_LBA, 1);
    set_partition(mbr + 462, 0x00, 0x06, FIRST_PARTITION_LBA, DOS_PARTITION_SECTORS);
    set_partition(mbr + 478, 0x00, 0x06, WINDOWS_PARTITION_LBA,
                  WINDOWS_PARTITION_SECTORS);
    set_partition(mbr + 494, 0x00, 0x06, SPARE_PARTITION_LBA,
                  DISK_SECTORS - SPARE_PARTITION_LBA);
    mbr[510] = 0x55;
    mbr[511] = 0xaa;

    memcpy(boot_shim, loader, sizeof(boot_shim));
    memcpy(boot_shim + 446, mbr + 446, 64);

    fd = open(argv[5], O_CREAT | O_TRUNC | O_WRONLY, 0644);
    if (fd < 0)
        fail(argv[5]);
    if (ftruncate(fd, DISK_SIZE) != 0)
        fail(argv[5]);
    write_at(fd, 0, mbr, sizeof(mbr));
    write_at(fd, (uint64_t)BOOT_SHIM_LBA * SECTOR_SIZE, boot_shim, sizeof(boot_shim));
    write_at(fd, (uint64_t)SBM_KERNEL_LBA * SECTOR_SIZE, main, main_size);
    write_at(fd, (uint64_t)XTIDE_LBA * SECTOR_SIZE, xtide, xtide_size);
    if (fsync(fd) != 0 || close(fd) != 0)
        fail(argv[5]);

    free(mbr_code);
    free(loader);
    free(main);
    free(xtide);
    return EXIT_SUCCESS;
}
