# 486 CF Boot Image

This project creates a 4 GiB raw CompactFlash image for a 486 whose original
BIOS only reaches the first 500 MiB. Smart Boot Manager (SBM) runs from the
MBR, loads XT-IDE Universal BIOS from reserved low sectors, and then presents
the normal SBM partition menu.

For complete reproduction, implementation, DOS installation, QEMU/GDB
debugging, and physical-deployment instructions, see
[`DEVELOPMENT.md`](DEVELOPMENT.md).

For a detailed sector-by-sector explanation of the path from BIOS startup to
the visible SBM menu, see [`BOOT_PROCESS.md`](BOOT_PROCESS.md).

Upstream source provenance and licensing are in [`THIRD_PARTY.md`](THIRD_PARTY.md).

Status: the full pre-OS chain boots on the real 486. The final layout places
the SBM loader directly in the MBR (sector zero), eliminating the type-`DAh`
shim partition. The SBM kernel is at LBA 1 and the XT-IDE ROM at LBA 128.
The known hardware-tested reference image used MS-DOS 6.22 and transferred
Compaq Windows 3.1 as `Primary 1`. Licensed operating-system media and installed
images are deliberately excluded from this repository.

Two physical-boot failures were found and fixed in hardware:

1. The shipped image marked the DOS partition active instead of the boot shim,
   so the MBR booted DOS directly. Fixed by marking the LBA-63 shim active.
2. The XT-IDE preload's CHS fallback divided by a heads value of 1 (instead of
   the geometry reported by `INT 13h AH=08h`), reading the wrong sector for
   LBA 128 and failing with `xtide preload failed: 2`. Fixed
   `preload_read_sector` and it now boots.

See [`DEVELOPMENT.md`][dev] for the diagnoses and hardware-test status.

[dev]: DEVELOPMENT.md

## Layout

The image boots through the SBM loader placed directly in the MBR (sector
zero). The partition table contains only real filesystem partitions:

| LBA range | Content |
| --- | --- |
| 0 | SBM loader (440 bytes boot code) and normal DOS partition table |
| 1-38 | SBM kernel (19,304 bytes / 38 sectors) |
| 39-127 | Reserved |
| 128 | 8 KiB XT-IDE 386 ROM (loaded by SBM) |
| 129-1007 | Reserved; do not partition or format |
| 1008-3146735 | 1.5 GiB FAT16 partition for MS-DOS 6.22 and Windows 3.1 |
| 3146736-4719599 | 768 MiB FAT16 partition |
| 4719600-end | 1.5 GiB FAT16 partition |

Windows 3.1 is installed over MS-DOS and does not need a distinct partition.

## Build

The build requires `nasm`, `perl`, and a C compiler. It uses the checked-out
XTIDE Universal BIOS source at `xtideuniversalbios` and builds its 8 KiB 386
variant, including the Windows 9x compatibility module. Its build-specific
INT 19h entry performs XT-IDE's usual initialization and returns to SBM with
XT-IDE's INT 13h handler installed.

```sh
make
```

The resulting `build/cf-4gb.img` is sparse but represents a 4 GiB device. The
physical card is smaller, so a card-sized image is produced with
`build/resize_cf_image` (see [`DEVELOPMENT.md`](DEVELOPMENT.md)).

## QEMU

Install QEMU and run:

```sh
make qemu
```

The current image includes DOS 6.22 and Compaq Windows 3.1 on the first FAT16
partition. The other FAT16 partitions remain data/setup areas and will report
`No Operating System` if selected.

If you need to reuse the installed DOS state after a rebuild, back up and
restore the DOS partitions with `scripts/backup_dos622.sh` and
`scripts/restore_dos622.sh`. The backup lives in `build/dos622-backup/`.

Note: the current QEMU build uses a stripped-down SBM US theme with no custom
background, brand, or font replacement, because the stock theme assets caused
corrupted headers and popup text during partition selection.

## Physical CF card

Do not run `FDISK /MBR`, repartition LBA 0-1007, or format the reserved area:
any of those actions remove SBM or XT-IDE.

Use SBM to select the desired primary partition. The active flag is on DOS for
compatibility, but the SBM loader in sector zero starts SBM regardless.
Stock SBM marks normal bootable FAT partition types active before booting them;
that write is safe in the loader-in-MBR layout because SBM does not depend on
the active flag to start.

The full card backup before debug patching is at:

```text
build/sde-before-debug-20260903.img
SHA-256 edab9580c64233dbc72a30632936ebee91ef6d4031e2b2000c1c11ac943f0356
```

See [`DEVELOPMENT.md`](DEVELOPMENT.md) for the layout, rollback details, and
hardware-test history.

### Install Or Repair A New Card

Build the small boot components as the regular user, then run the installer as
root:

```sh
make boot-components
sudo scripts/install_bootloader.sh /dev/sdX 1536
```

The size is an integer MiB value from 16 through 2047. Installation erases LBA
0-1007, creates one active type-`06h` FAT16 partition at LBA 1008, formats it
blank with label `DOS`, and leaves the remaining card space unallocated. It does
not install DOS system files; use DOS Setup or `SYS` afterwards.

Inspect a card without writing it:

```sh
scripts/install_bootloader.sh --verify /dev/sdX
```

For a byte-for-byte comparison of LBA 0-159 against the current generated
components and canonical one-partition layout:

```sh
sudo scripts/install_bootloader.sh --verify-exact /dev/sdX
```

This path was verified on the target 486 on 2026-09-15: a 500 MiB P1 card
passed strict LBA 0-159 comparison and started SBM. It contained no operating
system yet.

Repair boot components after an OS installer overwrites them:

```sh
sudo scripts/install_bootloader.sh --repair /dev/sdX
```

Repair preserves a valid partition table, SBM kernel/menu settings, and XT-IDE
ROM. It only replaces invalid components and writes the MBR loader last. It
backs up LBA 0-159 and the partition table to `build/` first, and refuses GPT,
an empty/corrupt partition table, or partitions overlapping the reserved boot
area. It does not repair the FAT16 volume boot sector or filesystem.
