#define _FILE_OFFSET_BITS 64
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

#ifdef __linux__
#include <linux/fs.h>
#endif

enum {
    SECTOR_SIZE = 512,
    MBR_CODE_SIZE = 446,
    PARTITION_TABLE_OFFSET = 446,
    SBM_KERNEL_LBA = 1,
    XTIDE_LBA = 128,
    XTIDE_MAX_SECTORS = 32,
    BOOT_AREA_SECTORS = XTIDE_LBA + XTIDE_MAX_SECTORS,
    RESERVED_SECTORS = 1008,
    FIRST_PARTITION_LBA = RESERVED_SECTORS,
};

struct components {
    uint8_t *loader;
    size_t loader_size;
    size_t loader_magic;
    uint8_t *kernel;
    size_t kernel_size;
    size_t kernel_magic;
    uint32_t kernel_sectors;
    uint8_t *xtide;
    size_t xtide_size;
    uint32_t xtide_sectors;
};

struct status {
    int partitions_ok;
    int mbr_ok;
    int kernel_ok;
    int xtide_ok;
};

static void fail(const char *message) {
    perror(message);
    exit(EXIT_FAILURE);
}

static void fail_message(const char *message) {
    fprintf(stderr, "%s\n", message);
    exit(EXIT_FAILURE);
}

static uint16_t get_le16(const uint8_t *ptr) {
    return (uint16_t)ptr[0] | ((uint16_t)ptr[1] << 8);
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

static uint8_t *read_file(const char *path, size_t *size) {
    struct stat st;
    uint8_t *data;
    FILE *file = fopen(path, "rb");

    if (file == NULL)
        fail(path);
    if (fstat(fileno(file), &st) != 0)
        fail(path);
    if (st.st_size <= 0)
        fail_message("boot component is empty");
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

static void pread_all(int fd, void *buffer, size_t size, uint64_t offset) {
    if (pread(fd, buffer, size, (off_t)offset) != (ssize_t)size)
        fail("reading device");
}

static void pwrite_all(int fd, const void *buffer, size_t size, uint64_t offset) {
    if (pwrite(fd, buffer, size, (off_t)offset) != (ssize_t)size)
        fail("writing device");
}

static uint64_t device_size(int fd, const struct stat *st) {
    uint64_t size;

    if (S_ISREG(st->st_mode))
        return (uint64_t)st->st_size;
#ifdef BLKGETSIZE64
    if (ioctl(fd, BLKGETSIZE64, &size) == 0)
        return size;
#endif
    fail_message("target must be a regular file or a Linux block device");
    return 0;
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

static int checksum_is_zero(const uint8_t *data, size_t size) {
    uint8_t sum = 0;
    size_t index;

    for (index = 0; index < size; ++index)
        sum = (uint8_t)(sum + data[index]);
    return sum == 0;
}

static int kernel_is_valid(const uint8_t *kernel, size_t size, size_t *magic_out) {
    size_t magic;
    uint16_t total_size;

    for (magic = 0; magic + 11 <= size; ++magic) {
        if (memcmp(kernel + magic, "SBMK", 4) == 0)
            break;
    }
    if (magic + 11 > size)
        return 0;
    total_size = get_le16(kernel + magic + 6);
    if (total_size == 0 || total_size > size)
        return 0;
    if (!checksum_is_zero(kernel, total_size))
        return 0;
    if (magic_out != NULL)
        *magic_out = magic;
    return 1;
}

static int xtide_is_valid(const uint8_t *rom, size_t size, uint32_t *sectors_out) {
    uint32_t sectors;
    size_t bytes;

    if (size < 3 || rom[0] != 0x55 || rom[1] != 0xaa)
        return 0;
    sectors = rom[2];
    bytes = (size_t)sectors * SECTOR_SIZE;
    if (sectors == 0 || sectors > XTIDE_MAX_SECTORS || bytes != size)
        return 0;
    if (!checksum_is_zero(rom, bytes))
        return 0;
    if (sectors_out != NULL)
        *sectors_out = sectors;
    return 1;
}

static void checksum_kernel(uint8_t *kernel, size_t size, size_t magic) {
    uint16_t total_size = get_le16(kernel + magic + 6);
    uint8_t sum = 0;
    size_t index;

    if (total_size == 0 || total_size > size || magic + 10 >= total_size)
        fail_message("invalid SBM kernel header");
    kernel[magic + 10] = 0;
    for (index = 0; index < total_size; ++index)
        sum = (uint8_t)(sum + kernel[index]);
    kernel[magic + 10] = (uint8_t)(0 - sum);
}

static void load_components(struct components *components, const char *loader_path,
                            const char *kernel_path, const char *xtide_path) {
    components->loader = read_file(loader_path, &components->loader_size);
    components->kernel = read_file(kernel_path, &components->kernel_size);
    components->xtide = read_file(xtide_path, &components->xtide_size);

    if (components->loader_size != SECTOR_SIZE)
        fail_message("SBM loader must be exactly one sector");
    components->loader_magic = find_signature(components->loader,
                                               components->loader_size, "SBML");
    if (components->loader_magic + 11 > MBR_CODE_SIZE)
        fail_message("invalid SBM loader header");

    components->kernel_sectors =
        (uint32_t)((components->kernel_size + SECTOR_SIZE - 1) / SECTOR_SIZE);
    if (components->kernel_sectors == 0 ||
        components->kernel_sectors > XTIDE_LBA - SBM_KERNEL_LBA)
        fail_message("SBM kernel overlaps XT-IDE reservation");
    components->kernel_magic = find_signature(components->kernel,
                                               components->kernel_size, "SBMK");
    checksum_kernel(components->kernel, components->kernel_size,
                    components->kernel_magic);
    if (!kernel_is_valid(components->kernel, components->kernel_size, NULL))
        fail_message("cannot generate a valid SBM kernel checksum");

    if (!xtide_is_valid(components->xtide, components->xtide_size,
                        &components->xtide_sectors))
        fail_message("invalid XT-IDE ROM");

    components->loader[components->loader_magic + 6] =
        (uint8_t)components->kernel_sectors;
    set_le32(components->loader + components->loader_magic + 7, SBM_KERNEL_LBA);
}

static void free_components(struct components *components) {
    free(components->loader);
    free(components->kernel);
    free(components->xtide);
}

static int partitions_are_valid(const uint8_t *mbr, uint64_t total_sectors) {
    uint64_t starts[4] = {0};
    uint64_t ends[4] = {0};
    size_t count = 0;
    size_t index;

    for (index = 0; index < 4; ++index) {
        const uint8_t *entry = mbr + PARTITION_TABLE_OFFSET + index * 16;
        uint64_t start = get_le32(entry + 8);
        uint64_t sectors = get_le32(entry + 12);

        if (entry[4] == 0) {
            uint8_t empty[16] = {0};
            if (memcmp(entry, empty, sizeof(empty)) != 0)
                return 0;
            continue;
        }
        if (entry[4] == 0xee || (entry[0] != 0 && entry[0] != 0x80) ||
            sectors == 0 || start < RESERVED_SECTORS ||
            start + sectors > total_sectors)
            return 0;
        starts[count] = start;
        ends[count] = start + sectors;
        ++count;
    }
    for (index = 0; index < count; ++index) {
        size_t other;
        for (other = index + 1; other < count; ++other) {
            if (starts[index] < ends[other] && starts[other] < ends[index])
                return 0;
        }
    }
    return count != 0;
}

static struct status inspect(int fd, uint64_t total_sectors,
                             const struct components *components, uint8_t *mbr) {
    struct status status = {0};
    uint8_t *kernel;
    uint8_t *xtide;

    pread_all(fd, mbr, SECTOR_SIZE, 0);
    status.partitions_ok = partitions_are_valid(mbr, total_sectors);
    status.mbr_ok = mbr[510] == 0x55 && mbr[511] == 0xaa &&
                    memcmp(mbr + components->loader_magic, "SBML", 4) == 0 &&
                    mbr[components->loader_magic + 6] == components->kernel_sectors &&
                    get_le32(mbr + components->loader_magic + 7) == SBM_KERNEL_LBA;

    kernel = calloc(components->kernel_sectors, SECTOR_SIZE);
    xtide = calloc(XTIDE_MAX_SECTORS, SECTOR_SIZE);
    if (kernel == NULL || xtide == NULL)
        fail("calloc");
    pread_all(fd, kernel, (size_t)components->kernel_sectors * SECTOR_SIZE,
              (uint64_t)SBM_KERNEL_LBA * SECTOR_SIZE);
    pread_all(fd, xtide, XTIDE_MAX_SECTORS * SECTOR_SIZE,
              (uint64_t)XTIDE_LBA * SECTOR_SIZE);
    status.kernel_ok = kernel_is_valid(kernel,
                                       (size_t)components->kernel_sectors * SECTOR_SIZE,
                                       NULL);
    if (xtide[2] != 0 && xtide[2] <= XTIDE_MAX_SECTORS)
        status.xtide_ok = xtide_is_valid(xtide,
                                         (size_t)xtide[2] * SECTOR_SIZE, NULL);
    free(kernel);
    free(xtide);
    return status;
}

static void print_status(const struct status *status) {
    printf("partition table: %s\n", status->partitions_ok ? "valid" : "invalid");
    printf("SBM MBR loader:  %s\n", status->mbr_ok ? "valid" : "invalid");
    printf("SBM kernel:      %s\n", status->kernel_ok ? "valid" : "invalid");
    printf("XT-IDE ROM:      %s\n", status->xtide_ok ? "valid" : "invalid");
}

static void verify_write(int fd, const void *expected, size_t size, uint64_t offset) {
    uint8_t *actual = malloc(size);
    if (actual == NULL)
        fail("malloc");
    pread_all(fd, actual, size, offset);
    if (memcmp(actual, expected, size) != 0)
        fail_message("written boot area does not verify");
    free(actual);
}

static void clear_reserved_tail(int fd, uint32_t lba, uint32_t sectors,
                                const char *description) {
    uint8_t *actual;
    uint8_t *zeroes;
    size_t bytes;

    if (sectors == 0)
        return;
    bytes = (size_t)sectors * SECTOR_SIZE;
    actual = malloc(bytes);
    zeroes = calloc(sectors, SECTOR_SIZE);
    if (actual == NULL || zeroes == NULL)
        fail("allocating reservation buffers");
    pread_all(fd, actual, bytes, (uint64_t)lba * SECTOR_SIZE);
    if (memcmp(actual, zeroes, bytes) != 0) {
        pwrite_all(fd, zeroes, bytes, (uint64_t)lba * SECTOR_SIZE);
        printf("cleared stale %s\n", description);
    }
    free(actual);
    free(zeroes);
}

static void install(int fd, uint64_t total_sectors, const struct components *components,
                    uint32_t partition_sectors) {
    uint8_t *reserved = calloc(RESERVED_SECTORS, SECTOR_SIZE);
    uint8_t mbr[SECTOR_SIZE] = {0};

    if (reserved == NULL)
        fail("calloc");
    if ((uint64_t)FIRST_PARTITION_LBA + partition_sectors > total_sectors)
        fail_message("requested partition does not fit on target");

    memcpy(mbr, components->loader, MBR_CODE_SIZE);
    set_partition(mbr + PARTITION_TABLE_OFFSET, 0x80, 0x06,
                  FIRST_PARTITION_LBA, partition_sectors);
    mbr[510] = 0x55;
    mbr[511] = 0xaa;

    pwrite_all(fd, reserved, RESERVED_SECTORS * SECTOR_SIZE, 0);
    pwrite_all(fd, components->kernel, components->kernel_size,
               (uint64_t)SBM_KERNEL_LBA * SECTOR_SIZE);
    pwrite_all(fd, components->xtide, components->xtide_size,
               (uint64_t)XTIDE_LBA * SECTOR_SIZE);
    pwrite_all(fd, mbr, sizeof(mbr), 0);
    if (fsync(fd) != 0)
        fail("fsync");
    verify_write(fd, mbr, sizeof(mbr), 0);
    verify_write(fd, components->kernel, components->kernel_size,
                 (uint64_t)SBM_KERNEL_LBA * SECTOR_SIZE);
    verify_write(fd, components->xtide, components->xtide_size,
                 (uint64_t)XTIDE_LBA * SECTOR_SIZE);
    free(reserved);
}

static void repair(int fd, const struct components *components, uint8_t *mbr,
                   const struct status *status) {
    uint8_t zeroes[(XTIDE_LBA - SBM_KERNEL_LBA) * SECTOR_SIZE] = {0};

    if (!status->partitions_ok)
        fail_message("refusing to repair an invalid or GPT partition table");
    if (!status->kernel_ok) {
        pwrite_all(fd, zeroes, (XTIDE_LBA - SBM_KERNEL_LBA) * SECTOR_SIZE,
                   (uint64_t)SBM_KERNEL_LBA * SECTOR_SIZE);
        pwrite_all(fd, components->kernel, components->kernel_size,
                   (uint64_t)SBM_KERNEL_LBA * SECTOR_SIZE);
        printf("repaired SBM kernel\n");
    }
    if (!status->xtide_ok) {
        pwrite_all(fd, zeroes, XTIDE_MAX_SECTORS * SECTOR_SIZE,
                   (uint64_t)XTIDE_LBA * SECTOR_SIZE);
        pwrite_all(fd, components->xtide, components->xtide_size,
                   (uint64_t)XTIDE_LBA * SECTOR_SIZE);
        printf("repaired XT-IDE ROM\n");
    }
    if (!status->mbr_ok) {
        memcpy(mbr, components->loader, MBR_CODE_SIZE);
        mbr[510] = 0x55;
        mbr[511] = 0xaa;
        pwrite_all(fd, mbr, SECTOR_SIZE, 0);
        printf("repaired SBM MBR loader\n");
    }
    clear_reserved_tail(fd, SBM_KERNEL_LBA + components->kernel_sectors,
                        XTIDE_LBA - (SBM_KERNEL_LBA + components->kernel_sectors),
                        "SBM reserved sectors");
    clear_reserved_tail(fd, XTIDE_LBA + components->xtide_sectors,
                        XTIDE_MAX_SECTORS - components->xtide_sectors,
                        "XT-IDE reserved sectors");
    if (fsync(fd) != 0)
        fail("fsync");
}

static int canonical_partition_table_matches(const uint8_t *mbr,
                                             uint64_t total_sectors) {
    uint8_t expected[64] = {0};
    uint32_t partition_sectors = get_le32(mbr + PARTITION_TABLE_OFFSET + 12);

    if (mbr[PARTITION_TABLE_OFFSET] != 0x80 ||
        mbr[PARTITION_TABLE_OFFSET + 4] != 0x06 ||
        get_le32(mbr + PARTITION_TABLE_OFFSET + 8) != FIRST_PARTITION_LBA ||
        partition_sectors == 0 ||
        (uint64_t)FIRST_PARTITION_LBA + partition_sectors > total_sectors)
        return 0;
    set_partition(expected, 0x80, 0x06, FIRST_PARTITION_LBA, partition_sectors);
    return memcmp(mbr + PARTITION_TABLE_OFFSET, expected, sizeof(expected)) == 0;
}

static int boot_area_matches_exactly(int fd, uint64_t total_sectors,
                                     const struct components *components) {
    uint8_t expected_mbr[SECTOR_SIZE] = {0};
    uint8_t actual_mbr[SECTOR_SIZE];
    uint8_t *expected_kernel;
    uint8_t *actual_kernel;
    uint8_t expected_xtide[XTIDE_MAX_SECTORS * SECTOR_SIZE] = {0};
    uint8_t actual_xtide[XTIDE_MAX_SECTORS * SECTOR_SIZE];
    uint32_t partition_sectors;
    int matches = 0;

    pread_all(fd, actual_mbr, sizeof(actual_mbr), 0);
    if (!canonical_partition_table_matches(actual_mbr, total_sectors)) {
        fprintf(stderr, "partition table is not the canonical single-P1 layout\n");
        return 0;
    }
    partition_sectors = get_le32(actual_mbr + PARTITION_TABLE_OFFSET + 12);
    memcpy(expected_mbr, components->loader, MBR_CODE_SIZE);
    set_partition(expected_mbr + PARTITION_TABLE_OFFSET, 0x80, 0x06,
                  FIRST_PARTITION_LBA, partition_sectors);
    expected_mbr[510] = 0x55;
    expected_mbr[511] = 0xaa;
    if (memcmp(actual_mbr, expected_mbr, sizeof(actual_mbr)) != 0) {
        fprintf(stderr, "MBR does not match the generated loader and partition table\n");
        return 0;
    }

    expected_kernel = calloc(XTIDE_LBA - SBM_KERNEL_LBA, SECTOR_SIZE);
    actual_kernel = malloc((XTIDE_LBA - SBM_KERNEL_LBA) * SECTOR_SIZE);
    if (expected_kernel == NULL || actual_kernel == NULL)
        fail("allocating kernel comparison buffers");
    memcpy(expected_kernel, components->kernel, components->kernel_size);
    pread_all(fd, actual_kernel, (XTIDE_LBA - SBM_KERNEL_LBA) * SECTOR_SIZE,
              (uint64_t)SBM_KERNEL_LBA * SECTOR_SIZE);
    if (memcmp(actual_kernel, expected_kernel,
               (XTIDE_LBA - SBM_KERNEL_LBA) * SECTOR_SIZE) != 0) {
        fprintf(stderr, "SBM kernel reservation does not match generated bytes\n");
        goto done;
    }

    memcpy(expected_xtide, components->xtide, components->xtide_size);
    pread_all(fd, actual_xtide, sizeof(actual_xtide),
              (uint64_t)XTIDE_LBA * SECTOR_SIZE);
    if (memcmp(actual_xtide, expected_xtide, sizeof(actual_xtide)) != 0) {
        fprintf(stderr, "XT-IDE reservation does not match generated bytes\n");
        goto done;
    }
    matches = 1;

done:
    free(expected_kernel);
    free(actual_kernel);
    return matches;
}

static uint32_t parse_partition_sectors(const char *value) {
    char *end;
    unsigned long mib;

    errno = 0;
    mib = strtoul(value, &end, 10);
    if (errno != 0 || *value == '\0' || *end != '\0' || mib < 16 || mib > 2047)
        fail_message("partition size must be an integer from 16 to 2047 MiB");
    return (uint32_t)mib * 2048;
}

int main(int argc, char **argv) {
    const char *mode;
    const char *device;
    struct components components = {0};
    struct stat st;
    uint64_t bytes, sectors;
    uint8_t mbr[SECTOR_SIZE];
    struct status status;
    int fd;

    if (argc != 6 && argc != 7) {
        fprintf(stderr,
                "usage: %s install DEVICE SIZE_MIB LOADER KERNEL XTIDE\n"
                "       %s verify DEVICE LOADER KERNEL XTIDE\n"
                "       %s exact DEVICE LOADER KERNEL XTIDE\n"
                "       %s repair DEVICE LOADER KERNEL XTIDE\n",
                argv[0], argv[0], argv[0], argv[0]);
        return EXIT_FAILURE;
    }
    mode = argv[1];
    device = argv[2];
    if (strcmp(mode, "install") == 0) {
        if (argc != 7)
            fail_message("install requires a partition size");
        load_components(&components, argv[4], argv[5], argv[6]);
    } else {
        if (argc != 6 || (strcmp(mode, "verify") != 0 &&
                          strcmp(mode, "exact") != 0 &&
                          strcmp(mode, "repair") != 0))
            fail_message("unknown mode");
        load_components(&components, argv[3], argv[4], argv[5]);
    }

    fd = open(device, (strcmp(mode, "verify") == 0 || strcmp(mode, "exact") == 0)
                           ? O_RDONLY : O_RDWR);
    if (fd < 0)
        fail(device);
    if (fstat(fd, &st) != 0)
        fail(device);
    bytes = device_size(fd, &st);
    if (bytes % SECTOR_SIZE != 0 || bytes / SECTOR_SIZE < RESERVED_SECTORS)
        fail_message("target is too small or does not use 512-byte sectors");
    sectors = bytes / SECTOR_SIZE;

    if (strcmp(mode, "install") == 0) {
        install(fd, sectors, &components, parse_partition_sectors(argv[3]));
        printf("installed bootloader and created active FAT16 P1 at LBA %u\n",
               FIRST_PARTITION_LBA);
    } else {
        status = inspect(fd, sectors, &components, mbr);
        print_status(&status);
        if (strcmp(mode, "repair") == 0) {
            repair(fd, &components, mbr, &status);
            status = inspect(fd, sectors, &components, mbr);
            print_status(&status);
        }
        if (!status.partitions_ok || !status.mbr_ok || !status.kernel_ok || !status.xtide_ok) {
            close(fd);
            free_components(&components);
            return EXIT_FAILURE;
        }
        if (strcmp(mode, "exact") == 0) {
            if (!boot_area_matches_exactly(fd, sectors, &components)) {
                close(fd);
                free_components(&components);
                return EXIT_FAILURE;
            }
            printf("LBA 0-159 matches generated boot-area bytes exactly\n");
        }
    }
    if (close(fd) != 0)
        fail(device);
    free_components(&components);
    return EXIT_SUCCESS;
}
