#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64

#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

enum {
    SECTOR_SIZE = 512,
    MBR_CODE_SIZE = 446,
    PARTITION_TABLE_OFFSET = 446,
    SBM_KERNEL_LBA = 1,
    DEBUG_STAGE_LBA = 39,
    DEBUG_STAGE_SECTORS = 2,
    DEBUG_LOADER_LBA = 63,
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

static void write_at(int fd, uint64_t offset, const void *data, size_t size) {
    if (pwrite(fd, data, size, (off_t)offset) != (ssize_t)size)
        fail("writing final image");
}

int main(int argc, char **argv) {
    uint8_t mbr[SECTOR_SIZE];
    uint8_t zeroes[(DEBUG_LOADER_LBA + 1 - DEBUG_STAGE_LBA) * SECTOR_SIZE] = {0};
    uint8_t *loader;
    size_t loader_size, loader_magic;
    uint32_t kernel_sectors;
    struct stat st;
    int fd;

    if (argc != 3) {
        fprintf(stderr, "usage: %s LOADER IMAGE\n", argv[0]);
        return EXIT_FAILURE;
    }

    loader = read_file(argv[1], &loader_size);
    if (loader_size != SECTOR_SIZE) {
        fprintf(stderr, "invalid SBM loader size\n");
        return EXIT_FAILURE;
    }

    fd = open(argv[2], O_RDWR);
    if (fd < 0)
        fail(argv[2]);
    if (fstat(fd, &st) != 0)
        fail(argv[2]);
    if ((uint64_t)st.st_size !=
        (uint64_t)(THIRD_PARTITION_LBA + THIRD_PARTITION_SECTORS) * SECTOR_SIZE) {
        fprintf(stderr, "image does not have the expected 7,962,192 sectors\n");
        return EXIT_FAILURE;
    }
    if (pread(fd, mbr, sizeof(mbr), 0) != sizeof(mbr))
        fail("reading diagnostic MBR");
    if (mbr[510] != 0x55 || mbr[511] != 0xAA ||
        get_le32(mbr + PARTITION_TABLE_OFFSET + 8) != DOS_PARTITION_LBA ||
        get_le32(mbr + PARTITION_TABLE_OFFSET + 12) != DOS_PARTITION_SECTORS ||
        get_le32(mbr + PARTITION_TABLE_OFFSET + 16 + 8) != SECOND_PARTITION_LBA ||
        get_le32(mbr + PARTITION_TABLE_OFFSET + 16 + 12) != SECOND_PARTITION_SECTORS ||
        get_le32(mbr + PARTITION_TABLE_OFFSET + 32 + 8) != THIRD_PARTITION_LBA ||
        get_le32(mbr + PARTITION_TABLE_OFFSET + 32 + 12) != THIRD_PARTITION_SECTORS) {
        fprintf(stderr, "source image does not have the diagnostic compact layout\n");
        return EXIT_FAILURE;
    }

    loader_magic = find_signature(loader, loader_size, "SBML");
    if (loader_magic + 11 > PARTITION_TABLE_OFFSET) {
        fprintf(stderr, "invalid SBM loader header\n");
        return EXIT_FAILURE;
    }
    kernel_sectors = (uint32_t)((DEBUG_STAGE_LBA - SBM_KERNEL_LBA));
    while (kernel_sectors > 0) {
        uint8_t sector[SECTOR_SIZE];
        if (pread(fd, sector, sizeof(sector),
                  (off_t)(SBM_KERNEL_LBA + kernel_sectors - 1) * SECTOR_SIZE) !=
            sizeof(sector))
            fail("reading SBM kernel");
        if (memcmp(sector, (uint8_t[SECTOR_SIZE]){0}, SECTOR_SIZE) != 0)
            break;
        --kernel_sectors;
    }
    if (kernel_sectors == 0 || kernel_sectors > 255) {
        fprintf(stderr, "cannot determine SBM kernel size\n");
        return EXIT_FAILURE;
    }
    loader[loader_magic + 6] = (uint8_t)kernel_sectors;
    set_le32(loader + loader_magic + 7, SBM_KERNEL_LBA);

    memcpy(loader + PARTITION_TABLE_OFFSET,
           mbr + PARTITION_TABLE_OFFSET,
           SECTOR_SIZE - PARTITION_TABLE_OFFSET);
    memcpy(mbr, loader, MBR_CODE_SIZE);

    write_at(fd, 0, mbr, sizeof(mbr));
    write_at(fd, (uint64_t)DEBUG_STAGE_LBA * SECTOR_SIZE,
             zeroes, sizeof(zeroes));

    if (fsync(fd) != 0 || close(fd) != 0)
        fail(argv[2]);
    free(loader);
    return EXIT_SUCCESS;
}
