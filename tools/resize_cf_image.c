#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

enum {
    SECTOR_SIZE = 512,
    BOOT_SHIM_LBA = 63,
    FIRST_PARTITION_LBA = 1008,
    DOS_PARTITION_SECTORS = 524288,
    WINDOWS_PARTITION_LBA = FIRST_PARTITION_LBA + DOS_PARTITION_SECTORS,
    WINDOWS_PARTITION_SECTORS = 4194304,
    SPARE_PARTITION_LBA = WINDOWS_PARTITION_LBA + WINDOWS_PARTITION_SECTORS,
    COPY_BUFFER_SIZE = 1024 * 1024,
};

static void fail(const char *message) {
    perror(message);
    exit(EXIT_FAILURE);
}

static uint32_t get_le32(const uint8_t *ptr) {
    return (uint32_t)ptr[0] |
           ((uint32_t)ptr[1] << 8) |
           ((uint32_t)ptr[2] << 16) |
           ((uint32_t)ptr[3] << 24);
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

static uint64_t parse_sectors(const char *text) {
    char *end;
    unsigned long long value;

    errno = 0;
    value = strtoull(text, &end, 10);
    if (errno != 0 || *text == '\0' || *end != '\0' || value > UINT32_MAX) {
        fprintf(stderr, "invalid sector count: %s\n", text);
        exit(EXIT_FAILURE);
    }
    return value;
}

static void copy_prefix(int input, int output, uint64_t bytes) {
    uint8_t *buffer = malloc(COPY_BUFFER_SIZE);
    uint64_t offset = 0;

    if (buffer == NULL)
        fail("malloc");
    while (offset < bytes) {
        size_t count = (bytes - offset > COPY_BUFFER_SIZE)
                           ? COPY_BUFFER_SIZE
                           : (size_t)(bytes - offset);
        ssize_t received = pread(input, buffer, count, (off_t)offset);

        if (received < 0)
            fail("reading source image");
        if ((size_t)received != count) {
            fprintf(stderr, "source image ended unexpectedly\n");
            exit(EXIT_FAILURE);
        }
        if (pwrite(output, buffer, count, (off_t)offset) != (ssize_t)count)
            fail("writing resized image");
        offset += count;
    }
    free(buffer);
}

int main(int argc, char **argv) {
    const char *input_path;
    const char *output_path;
    uint64_t sectors;
    uint64_t bytes;
    uint8_t mbr[SECTOR_SIZE];
    struct stat input_stat;
    struct stat output_stat;
    int input;
    int output;

    if (argc != 4) {
        fprintf(stderr, "usage: %s INPUT OUTPUT SECTORS\n", argv[0]);
        return EXIT_FAILURE;
    }
    input_path = argv[1];
    output_path = argv[2];
    sectors = parse_sectors(argv[3]);
    if (sectors <= SPARE_PARTITION_LBA) {
        fprintf(stderr, "target is too small for the DOS, Windows, and spare partition layout\n");
        return EXIT_FAILURE;
    }
    bytes = sectors * SECTOR_SIZE;

    input = open(input_path, O_RDONLY);
    if (input < 0)
        fail(input_path);
    if (fstat(input, &input_stat) != 0)
        fail(input_path);
    if ((uint64_t)input_stat.st_size < bytes) {
        fprintf(stderr, "source image is smaller than requested target\n");
        return EXIT_FAILURE;
    }
    if (pread(input, mbr, sizeof(mbr), 0) != sizeof(mbr))
        fail("reading MBR");
    if (mbr[510] != 0x55 || mbr[511] != 0xaa ||
        get_le32(mbr + 446 + 8) != BOOT_SHIM_LBA ||
        get_le32(mbr + 462 + 8) != FIRST_PARTITION_LBA ||
        get_le32(mbr + 462 + 12) != DOS_PARTITION_SECTORS ||
        get_le32(mbr + 478 + 8) != WINDOWS_PARTITION_LBA ||
        get_le32(mbr + 478 + 12) != WINDOWS_PARTITION_SECTORS ||
        get_le32(mbr + 494 + 8) != SPARE_PARTITION_LBA) {
        fprintf(stderr, "source does not have the expected CF image layout\n");
        return EXIT_FAILURE;
    }

    output = open(output_path, O_CREAT | O_WRONLY, 0644);
    if (output < 0)
        fail(output_path);
    if (fstat(output, &output_stat) != 0)
        fail(output_path);
    if (input_stat.st_dev == output_stat.st_dev && input_stat.st_ino == output_stat.st_ino) {
        fprintf(stderr, "input and output must be different files\n");
        return EXIT_FAILURE;
    }
    if (ftruncate(output, (off_t)bytes) != 0)
        fail(output_path);

    copy_prefix(input, output, bytes);
    set_chs(mbr + 494 + 5, (uint32_t)(sectors - 1));
    set_le32(mbr + 494 + 12, (uint32_t)(sectors - SPARE_PARTITION_LBA));
    if (pwrite(output, mbr, sizeof(mbr), 0) != sizeof(mbr))
        fail("writing resized MBR");
    if (fsync(output) != 0)
        fail(output_path);
    if (close(output) != 0)
        fail(output_path);
    if (close(input) != 0)
        fail(input_path);
    return EXIT_SUCCESS;
}
