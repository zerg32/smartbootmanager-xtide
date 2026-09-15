# Development And Reproduction Guide

This document describes how to recreate, change, debug, test, and deploy the
4 GiB CF image from scratch.

See [`BOOT_PROCESS.md`](BOOT_PROCESS.md) for a focused description of the
complete BIOS, MBR, shim, SBM, and XT-IDE startup sequence.

See [`THIRD_PARTY.md`](THIRD_PARTY.md) for the pinned upstream source versions,
licenses, and excluded proprietary material.

## Goal And Constraints

The target is a 486 using a 4 GiB CompactFlash card as primary IDE drive
`80h`. Its original BIOS can access only the first roughly 500 MiB, but it can
boot from a small partition on the card.

The system needs:

- Smart Boot Manager (SBM) to choose operating-system partitions.
- XT-IDE Universal BIOS (XT-IDE) to provide EDD/LBA INT 13h services before
  DOS or Windows accesses the full card.
- A 256 MiB FAT16 partition for MS-DOS 6.22 and Windows 3.11.
- A 2 GiB FAT16 partition for Windows 95 OSR2.

There is no ISA option-ROM card and no motherboard firmware-flashing path.
XT-IDE therefore cannot be installed as a genuine expansion ROM in the
`C0000h-DFFFFh` address range. A disk image cannot create that mapping: the
system BIOS owns that address range and scans it before it reads the MBR.

The solution loads the XT-IDE option-ROM image into conventional RAM from
reserved low disk sectors. SBM does this before it scans partitions, while the
original BIOS can still address the reserved sectors. It then invokes XT-IDE's
normal initialization path and retains its INT 13h services for SBM and the
selected operating system.

## Repository Contents

| Path | Purpose |
| --- | --- |
| `Makefile` | Builds all binary artifacts and the raw CF image. |
| `tools/make_cf_image.c` | Creates the sparse 4 GiB image, generic MBR, boot shim, partition table, and reserved boot area. |
| `tools/resize_cf_image.c` | Trims a full 4 GiB image to a card-sized image for a smaller CF card. |
| `btmgr-3.7-1/` | Smart Boot Manager 3.7.1 source tree. |
| `xtideuniversalbios/` | XT-IDE Universal BIOS source tree. |
| `DOS622-Disk1.img` through `DOS622-Disk3.img` | Licensed MS-DOS 6.22 setup floppies used for the verified install. |
| `build/` | Generated artifacts. Do not hand-edit these files. |

XT-IDE is based on:

```text
https://github.com/JayesonLS/xtideuniversalbios.git
commit 5961b06ba4d32c266b22e71c2b5fd429855efaf1
```

The supplied `btmgr-3.7-1.tar.gz` is the SBM source archive. If rebuilding the
workspace itself, first extract it and clone the pinned XT-IDE revision:

```sh
tar -xzf btmgr-3.7-1.tar.gz
git clone https://github.com/JayesonLS/xtideuniversalbios.git
git -C xtideuniversalbios checkout 5961b06ba4d32c266b22e71c2b5fd429855efaf1
```

Then restore the project-specific source changes listed in
[Build-Specific Source Changes](#build-specific-source-changes). The source
trees in this workspace already include those changes; do not reset them to
the upstream versions before building.

## Host Dependencies

On Ubuntu/Debian, install the build and test tools with:

```sh
sudo apt-get update
sudo apt-get install -y build-essential nasm perl python3 qemu-system-x86 gdb
```

Useful optional tools:

```sh
sudo apt-get install -y util-linux
```

`util-linux` supplies `fdisk` for image-layout inspection. Python is used as a
small Unix-socket HMP monitor client. `ffmpeg` is useful for converting QEMU
`screendump` PPM images to PNG during headless debugging.

The verified tool versions were:

```text
NASM 2.16.01
QEMU 8.2.2
GDB 15.1
```

## Build

For an incremental build:

```sh
make
```

For a fully clean and reproducible build:

```sh
make clean
make
```

The important outputs are:

| File | Description |
| --- | --- |
| `build/sbm-loader.bin` | 512-byte SBM loader, linked against the boot shim at LBA 63. |
| `build/sbm-main.bin` | SBM kernel. |
| `build/xtide-386.bin` | Checksummed 8 KiB XT-IDE 386 ROM. |
| `build/make_cf_image` | Image-construction utility. |
| `build/resize_cf_image` | Card-sized image utility. |
| `build/cf-4gb.img` | Sparse 4 GiB CF image. |

`make clean && make` recreates a blank partition payload. Reinstall DOS after
a clean build if the final image must include DOS.

### Adapting To A Smaller CF Card

The base image requires exactly 8,388,608 sectors (4,294,967,296 bytes). Some
cards sold as 4 GB contain fewer sectors. Do not truncate or partially write
the base image: its spare partition would extend past the end of the card.

`tools/resize_cf_image.c` copies the image prefix verbatim, validates the
partition layout, patches the spare partition's end sector to the target card
size, and writes a card-sized image. The boot chain and the DOS and Windows
partitions are preserved unchanged. Read the target card's sector count:

```sh
cat /sys/class/block/sdX/size
```

For the verified Multi-Card reader, the card has 8,198,064 sectors:

```sh
make build/resize_cf_image
build/resize_cf_image build/cf-4gb.img build/cf-3.9gb.img 8198064
fdisk -l build/cf-3.9gb.img
```

The generated `build/cf-3.9gb.img` is 4,197,408,768 bytes and fits the card.
It retains the installed DOS partition and boot sectors, and it booted to
`C:\>` in QEMU.

The smaller development card is 7,962,192 sectors. Build a matching image:

```sh
build/resize_cf_image build/cf-4gb.img build/cf-dev/small-7962192.img 7962192
```

Rebuilding `make` from a clean tree produces a blank `cf-4gb.img` (no DOS), so
keep a DOS-bearing image separately if you need it. To update only the SBM
kernel on an already-flashed card without rewriting the whole 3.8 GiB, patch
just the kernel region (LBA 64-127):

```sh
build/resize_cf_image build/cf-4gb.img build/cf-dev/small-7962192-fixed.img 7962192
dd if=build/cf-dev/small-7962192-fixed.img of=/dev/sdX bs=512 skip=64 seek=64 count=64 conv=fsync
```

This leaves the MBR, boot shim, XT-IDE ROM, and all partition data untouched.

## Image Layout

The image contains 8,388,608 512-byte sectors (4 GiB).

### Final loader-in-MBR layout (current)

| LBA range | Sectors | Contents |
| --- | ---: | --- |
| 0 | 1 | SBM loader (440 bytes) and DOS partition table. |
| 1-38 | 38 | SBM kernel. |
| 39-127 | 89 | Reserved. |
| 128-143 | 16 | XT-IDE 8 KiB option-ROM image (loaded one sector at a time). |
| 144-1007 | 864 | Reserved. Never partition or format this range. |
| 1008-525295 | 524,288 | Active 256 MiB FAT16 primary partition for MS-DOS 6.22 / Windows 3.1. |
| 525296-4719599 | 4,194,304 | 2 GiB FAT16 primary partition. |
| 4719600-8388607 | 3,669,008 | Spare FAT16 partition. |

### Original shim layout (historical)

| LBA range | Sectors | Contents |
| --- | ---: | --- |
| 0 | 1 | Generic active-partition MBR and DOS partition table. |
| 63 | 1 | Active boot shim (`0xda`, boot flag). Runs the SBM loader. |
| 64-127 | 64 | SBM kernel area. |
| 128 | 1 | XT-IDE 8 KiB option-ROM image (loaded one sector at a time). |
| 129-1007 | 879 | Reserved. Never partition or format this range. |
| 1008-525295 | 524,288 | Active 256 MiB FAT16 primary partition for MS-DOS 6.22 / Windows 3.1. |
| 525296-4719599 | 4,194,304 | 2 GiB FAT16 primary partition. |
| 4719600-8388607 | 3,669,008 | Spare FAT16 partition. |

LBA 1-62 between the MBR and the boot shim are unused. The MBR marks the boot
shim active, and the shim partition uses type `0xda` (non-FS data). The DOS,
Windows, and spare partitions all use type `06h` (FAT16). Verify these values
with:

```sh
fdisk -l build/cf-4gb.img
```

The current image includes a tested MS-DOS 6.22 and Compaq Windows 3.1
installation in the FAT16 partition at LBA 1008. The 2 GiB Windows 95
partition and the spare partition remain empty.

## Boot Architecture

### Final loader-in-MBR layout (current)

1. The motherboard BIOS reads LBA 0 using its limited legacy INT 13h service.
   The SBM loader in the MBR (sector zero) relocates itself to `0000:0600`,
   reads the SBM kernel from LBA 1, and validates it.
2. SBM loads the XT-IDE ROM from LBA 128 using EDD if available and
   geometry-correct CHS otherwise.
3. SBM validates the option-ROM signature, size, and checksum.
4. SBM places the ROM at the top of conventional RAM and executes its entry
   point at offset `0003h`.
5. XT-IDE's ROM-search entry installs its INT 19h handler and returns to SBM.
6. SBM scans the partitions using XT-IDE's INT 13h service and displays the
   menu. Selecting the DOS partition loads its boot sector at `0000:7C00` with
   `DL=80h`.

### Original shim layout (historical)

1. The motherboard BIOS reads LBA 0 using its limited legacy INT 13h service.
   The generic 440-byte MBR boot code (`tools/generic_mbr.asm`, a plain
   active-partition MBR) locates the single active partition and loads its boot
   sector. The original Syslinux-derived MBR is kept as `tools/syslinux_mbr.asm`
   and selected with `GENERIC_MBR=0`; the plain MBR is the default.
2. The active partition is the boot shim at LBA 63. It runs in the
   `0000:7C00` frame, loads the SBM kernel from LBA 64, and transfers control
   to it.
3. Before SBM enumerates records, `preload_xtide` reads the XT-IDE header at
   LBA 128 using EDD if available and geometry-correct CHS otherwise.
4. The loader validates `55 AA`, validates the advertised ROM length, reserves
   that many KiB through BDA word `40:13`, loads the ROM one sector at a time,
   and validates the option-ROM checksum.
5. The ROM is placed at the top of conventional RAM. In the QEMU test it is at
   segment `9DC0h`; physical placement varies with the available base memory.
6. The loader far-returns to `ROM_segment:0003`, the standard option-ROM entry
   point. It must not execute `ROM_segment:0000`, which contains the `55 AA`
   header rather than executable code.
7. XT-IDE's ROM-search entry installs its INT 19h handler and returns to SBM.
   The preload invokes INT 19h once. The `XTIDE_SBM_RETURN` handler runs
   `Initialize_AndDetectDrives`, installs XT-IDE disk services, restores the
   caller's stack, and returns to SBM with `IRET`.
8. SBM scans the partitions using XT-IDE's INT 13h service and displays the
   menu. Selecting the DOS partition loads its boot sector at `0000:7C00` with
   `DL=80h`.

## Build-Specific Source Changes

The project deliberately contains custom integration code. These changes are
required together; do not replace one component with an upstream version
without retesting the entire boot chain.

### SBM

- `btmgr-3.7-1/manager/xtide_preload.asm`
  - Loads XT-IDE from LBA 128.
  - Uses EDD reads with a geometry-correct CHS fallback for the old BIOS. The
    CHS path divides by the heads reported by `INT 13h AH=08h` (saved before
    the divide loop, which previously clobbered `EDX/DH` and treated the drive
    as a single head - see the hardware failure below).
  - Validates the option-ROM signature, size, and checksum.
  - Restores `DS` to the SBM segment after checksumming before the far call.
  - Calls the correct option-ROM entry at offset `0003h` and then triggers the
    custom XT-IDE INT 19h initialization path.
  - Prints a `XTIDE CHS SPT=.. HEADS=.. CHS=h/s/cyl` debug line before each CHS
    read so the real geometry and computed sector can be checked on hardware.
- `btmgr-3.7-1/manager/main.asm`
  - Calls `preload_xtide` before SBM disk probing.
  - Reports a numeric preload failure code if loading or validation fails.
- `btmgr-3.7-1/manager/myint13h_stub.asm`
  - Disables SBM's optional INT 13h wrapper so it cannot replace or uninstall
    XT-IDE's handler.
- `btmgr-3.7-1/manager/ui.asm`
  - Uses page zero when `XTIDE_PRELOAD` is defined. XT-IDE video activity made
    SBM's normal page-flip rendering invisible in QEMU.
- `btmgr-3.7-1/manager/knl.asm`
  - Matches upstream SBM 3.7.1. Its stock auto-active behavior marks selected
    normal primary FAT partition types active before booting. This is safe in
    the loader-in-MBR layout because SBM does not use the active flag to start.

SBM is assembled with:

```text
-DXTIDE_PRELOAD -DXTIDE_ROM_LBA=128 -DXTIDE_MAX_SECTORS=32 -DDISABLE_CDBOOT
```

### XT-IDE

- `xtideuniversalbios/XTIDE_Universal_BIOS/Src/Handlers/Int19h.asm`
  - Adds the `XTIDE_SBM_RETURN` path.
  - Uses XT-IDE's boot-menu stack for drive detection, restores the saved SBM
    stack, and returns through the INT 19h frame with `IRET`.
  - Restores the original INT 08h timer vector after initialization when
    `MODULE_HOTKEYS` is enabled.

The final timer cleanup is essential. `Initialize_AndDetectDrives` initializes
the hotkey subsystem, which temporarily hooks INT 08h. The normal XT-IDE boot
flow later restores that vector. The custom return path used to skip that
cleanup, causing the timer to re-enter XT-IDE while SBM was running.

XT-IDE is assembled as an 8 KiB 386 ROM with the flags in `Makefile`, including
`MODULE_EBIOS`, `MODULE_IRQ`, `MODULE_HOTKEYS`, `MODULE_ADVANCED_ATA`,
`MODULE_WIN9X_CMOS_HACK`, `USE_AT`, `USE_286`, `USE_386`, and
`XTIDE_SBM_RETURN`.

## QEMU Validation

Use the interactive target for normal testing:

```sh
make qemu
```

It uses a 486 CPU model, 16 MiB RAM, and the image as an IDE disk:

```sh
qemu-system-i386 -cpu 486 -m 16M \
  -drive if=ide,format=raw,file=build/cf-4gb.img -boot c
```

Expected result:

1. SBM appears.
2. The DOS primary partition is listed as FAT16.
3. Select the DOS primary partition.
4. If SBM asks whether to save changes, choose `N` unless intentionally
   changing SBM configuration.
5. MS-DOS starts and reaches `C:\>`.

The verified DOS boot output includes:

```text
Starting MS-DOS...
HIMEM is testing extended memory...done.
C:\>
```

QEMU's SeaBIOS does not emulate the real motherboard's 500 MiB BIOS limit, so
QEMU validates the boot chain and disk-service installation, not that original
firmware limitation.

## Installing MS-DOS 6.22

Use licensed MS-DOS media. The repository currently has all three setup
floppies as `DOS622-Disk1.img` through `DOS622-Disk3.img`.

For a repeatable rebuild/install cycle, use the helper scripts:

```sh
scripts/install_dos622.sh
scripts/activate_sbm.sh
scripts/backup_dos622.sh
scripts/restore_dos622.sh
```

`install_dos622.sh` rebuilds `build/cf-4gb.img`, marks the SBM shim partition
active, and starts QEMU with the DOS setup floppy attached. DOS Setup will
usually mark the DOS partition active during install, so run
`activate_sbm.sh` after setup finishes to restore the SBM boot chain.

After a successful DOS install, run `backup_dos622.sh` to snapshot the DOS FAT16
partitions into `build/dos622-backup/`. Use `restore_dos622.sh` after a later
rebuild to put those partitions back and reactivate SBM without reinstalling DOS.

Start QEMU with Disk 1 as a floppy and the CF image as IDE disk:

```sh
qemu-system-i386 -cpu 486 -m 16M \
  -drive if=ide,format=raw,file=build/cf-4gb.img \
  -drive if=floppy,format=raw,file=DOS622-Disk1.img \
  -boot a
```

In Setup:

1. Start Setup and choose **Format this drive** for `C:`. This formats only the
   FAT16 partition; it does not alter LBA 0-1007.
2. Accept the date/time settings and `C:\DOS` install directory, unless a
   different configuration is needed.
3. Swap to Disk 2 and Disk 3 when requested.
4. Remove/eject the floppy, let Setup finish, then restart.
5. In SBM select the DOS primary partition; decline the SBM save prompt unless
   intentionally saving manager configuration.

For headless QEMU runs, use a monitor socket and issue HMP commands such as:

```text
change floppy0 /absolute/path/DOS622-Disk2.img
change floppy0 /absolute/path/DOS622-Disk3.img
eject floppy0
sendkey ret
```

## Debugging Techniques And Findings

### Headless VGA Capture

Start QEMU with a monitor socket:

```sh
qemu-system-i386 -cpu 486 -m 16M \
  -drive if=ide,format=raw,file=build/cf-4gb.img -boot c \
  -display none -vga std \
  -monitor unix:/tmp/sbm-mon.sock,server,nowait
```

At the HMP prompt or through a Unix-socket client:

```text
screendump /tmp/sbm.ppm
```

Convert the PPM for inspection when needed:

```sh
ffmpeg -y -v error -i /tmp/sbm.ppm /tmp/sbm.png
```

This was used to verify both the SBM menu and the final DOS `C:\>` prompt.

### GDB And QEMU Stub

Run QEMU paused with a GDB server:

```sh
qemu-system-i386 -cpu 486 -m 16M \
  -drive if=ide,format=raw,file=build/cf-4gb.img -boot c \
  -display none -vga std -gdb tcp::1234 -S
```

Attach GDB:

```gdb
target remote :1234
hbreak *0x9dc00
continue
info registers
```

`0x9DC00` is only an example from the QEMU run. The loader chooses the actual
segment from the base-memory value returned by INT 12h.

The initial failure was an infinite invalid-opcode (`#UD`) loop at
`9DC0:0000`. The ROM itself was valid: its proper option-ROM entry is
`9DC0:0003`, which jumps to code at ROM offset `0405h`. Executing offset zero
runs the `55 AA` header and title string as instructions.

Before the fix, GDB showed the live IVT entries pointing into the relocated ROM:

```text
INT 08h timer: 9DC0:0B14
INT 13h disk:  9DC0:1738
INT 19h boot:  9DC0:0DF1
IRQ14 / INT76: 9DC0:1520
```

The relevant fault was INT 08h: the temporary XT-IDE hotkey timer hook remained
active after the custom INT 19h return. Restoring the prior INT 08h vector in
the `XTIDE_SBM_RETURN` path fixes the crash while leaving XT-IDE's required INT
13h and IDE IRQ handlers installed.

Use a guard breakpoint to prevent regressions:

```gdb
target remote :1234
hbreak *0x9dc00
continue
```

After the fix, the guard did not trigger during a 100-second QEMU run and the
SBM menu rendered normally.

To prove SBM hands off to the partition boot sector, ignore the initial MBR
execution at `0000:7C00`, then break on the second execution:

```gdb
target remote :1234
hbreak *0x7c00
ignore 1 1
continue
```

With the shim layout the `0000:7C00` frame is reused multiple times along the
chain: the generic MBR loads the boot shim there, the shim relocates itself and
jumps to the SBM kernel, and finally SBM loads the selected partition's boot
sector there. To break specifically on the DOS partition boot handoff, watch
for execution at `0000:7C00` *after* SBM has already loaded the XT-IDE ROM and
printed its menu.

The verified handoff state was:

```text
CS:IP = 0000:7C00
DL    = 80h
SS:SP = 0000:7C00
BP    = 07BEh (partition-table pointer)
```

### Binary Inspection

Inspect the DOS boot sector at the FAT16 start LBA:

```sh
xxd -s $((1008 * 512)) -l 512 build/cf-4gb.img
```

Expected indicators include `MSDOS5.0`, the FAT16 BPB, `IO      SYS`,
`MSDOS   SYS`, and the `55 AA` boot signature. The FAT16 root directory begins
at LBA 1521 after the DOS format; it should contain `IO.SYS`, `MSDOS.SYS`, and
`COMMAND.COM`.

## Physical CF Deployment

### Initialize Or Repair A Card

`scripts/install_bootloader.sh` installs the final loader-in-MBR boot layout on
a blank card without requiring a card-sized DOS/Windows image. Build its inputs
without root privileges:

```sh
make boot-components
```

Then create a single 1.5 GiB FAT16 P1 on a target card:

```sh
sudo scripts/install_bootloader.sh /dev/sdX 1536
```

The installer requires a whole, unmounted disk with no active swap descendants,
prints its model/serial/size, and requires the exact device path as confirmation.
It clears LBA 0-1007; writes the SBM loader at LBA 0, kernel at LBA 1, and
XT-IDE at LBA 128; creates active type-`06h` P1 at LBA 1008; then formats that
partition as FAT16. The size argument is an integer MiB value from 16 through
2047. Remaining disk space is deliberately unallocated.

The FAT16 volume is blank, not a DOS installation. Use DOS Setup or `SYS` to
install DOS boot code and system files after initialization.

Check a card without writing it:

```sh
scripts/install_bootloader.sh --verify /dev/sdX
```

For a strict byte-for-byte comparison of LBA 0-159 against the current built
loader, kernel, XT-IDE ROM, zero-filled reservations, and canonical one-P1 MBR
table, run:

```sh
sudo scripts/install_bootloader.sh --verify-exact /dev/sdX
```

On 2026-09-15, `/dev/sde` was initialized with a 500 MiB P1, passed this strict
check, and started SBM on the target 486. No operating system was installed on
that test partition.

Repair a boot area overwritten by an OS installer:

```sh
sudo scripts/install_bootloader.sh --repair /dev/sdX
```

Repair validates the partition table, SBM loader, SBM kernel checksum, and
XT-IDE header/checksum. It preserves valid components, including saved SBM menu
settings in a valid kernel, and replaces only failed components. The MBR loader
is always written last. Before a write, it saves LBA 0-159 and MBR partition
table bytes 446-509 in `build/`. It refuses GPT, an empty/corrupt table, or a
partition that overlaps LBA 0-1007. It cannot repair the FAT16 VBR, FAT tables,
or DOS files.

Only write the image sized for the intended CF card. Confirm the device name
first; this erases it completely. For the final loader-in-MBR image on the
7,962,192-sector development card:

```sh
sudo dd if=build/cf-final-direct.img of=/dev/sdX bs=4M conv=fsync
```

A full byte-for-byte comparison can take several minutes over a USB card
reader; use a generous timeout:

```sh
cmp -n 512 /dev/sdX build/cf-final-direct.img
cmp -n $((39 * 512)) -i 512 /dev/sdX build/cf-final-direct.img
cmp -n $((16 * 512)) -i $((128 * 512)) /dev/sdX build/cf-final-direct.img
```

Do not run `FDISK /MBR`, repartition LBA 0-1007, or format the reserved area.
Those actions remove SBM and/or the disk-resident XT-IDE ROM.

Always confirm the target device is the intended, correctly-sized card before
writing. The development card is 7,962,192 sectors (3,896 MiB). Verify sizes
match first:

```sh
cat /sys/class/block/sdX/size   # must equal 7962192
stat -c %s build/cf-final-direct.img    # 4,076,642,304 bytes
```

### Enlarging The DOS Partition On The 7,962,192-Sector Card (Completed)

The development card has the final deployed layout:

```text
P1  active  FAT16  start=1008     size=3145728  DOS and Windows
P2          FAT16  start=3146736  size=1572864
P3          FAT16  start=4719600  size=3242592
P4          empty
```

The SBM loader is in the MBR at sector zero. The kernel is at LBA 1-38 and
XT-IDE at LBA 128-143. No type-`DAh` shim partition exists.

`fatresize` 1.1.0 from this host was not usable for this conversion: it selected
the active one-sector shim rather than P2 on the physical device, and aborted
inside libparted when resizing the image. The validated migration instead creates
a 1.5 GiB FAT16 volume in an image, copies the DOS installation, then boots the
original MS-DOS 6.22 image in QEMU and runs `SYS D:` against that target. This
installs the DOS-native VBR and system files. Preserve `IO.SYS` and `MSDOS.SYS`
as hidden, system, read-only files.

### Final Image Deployment And Rollback

The final image was built with `tools/prepare_final_image.c`:

```sh
make final-image
```

LBA 0-143 was written to the card:

```sh
dd if=build/cf-final-direct.img of=/dev/sdX bs=512 count=144 conv=fsync
```

The card boots through SBM to DOS on the real 486.

The diagnostic boot region was saved before the final patch:

```text
build/sde-debug-success-20260903-lba0-143.bin  (72 KiB, LBA 0-143)
```

The full card was saved before the diagnostic patch:

```text
build/sde-before-debug-20260903.img
SHA-256 edab9580c64233dbc72a30632936ebee91ef6d4031e2b2000c1c11ac943f0356
```

To restore the diagnostic layout:

```sh
dd if=build/sde-debug-success-20260903-lba0-143.bin of=/dev/sdX bs=512 count=144 conv=fsync
```

To restore the original shim layout:

```sh
dd if=build/sde-before-debug-20260903.img of=/dev/sdX bs=4M conv=fsync
```

### Shimless-Table Diagnostic Hardware Validation (Completed)

The diagnostic test is complete. The final loader-in-MBR image is deployed
on the physical card and boots through SBM to DOS.

Build the diagnostic variants with:

```sh
make debug-images
```

The hardware-test image is `build/cf-debug-direct.img`. It uses:

```text
LBA 0       diagnostic stage-1 MBR
LBA 1-38    SBM kernel
LBA 39-40   diagnostic display/validation stage
LBA 63      temporary hidden SBM loader, not a partition
LBA 128-143 XT-IDE ROM
LBA 1008    active FAT16 Primary 1 containing DOS and Windows 3.1
```

The MBR and diagnostic stage reported the BIOS drive number, EDD support, and
runtime geometry. They validated the `SBMK` kernel signature at LBA 1, the
XT-IDE `55 AA` header at LBA 128, and the `SBML` loader signature at LBA 63.
After a key press, the temporary loader read the kernel from LBA 1 and started
the normal SBM/XT-IDE path.

The real 486 displayed successful diagnostic checks and reached the SBM menu
after a key press. SBM detected DOS/Windows as FAT16 `Primary 1`.

The final image was then built with `tools/prepare_final_image.c` and
deployed:

```sh
dd if=build/cf-final-direct.img of=/dev/sdX bs=512 count=144 conv=fsync
```

The card boots through SBM to DOS on the real 486.

## Real-486 Boot Failures And Fixes

Two distinct failures were found and fixed during physical testing. The card
now boots the full pre-OS chain on the 486.

### 1. Active-partition flag on the wrong partition

The first physical boot reached only a blinking cursor. `build/cf-3.9gb.img`
had the 256 MiB DOS partition (P2, LBA 1008) marked active (`0x80`) instead of
the boot shim (P1, LBA 63). The generic MBR boots whichever partition is
active, so the 486 loaded the DOS boot sector at LBA 1008 directly and skipped
the shim, SBM, and XT-IDE chain entirely.

This was diagnosed by comparing the inserted card's MBR with the working
Syslinux reference card:

```text
         boot  type  LBA   notes
Syslinux P1 80  01    63    active FAT12 Syslinux
Shipped  P1 00  da    63    shim present but INACTIVE
         P2 80  06    1008  DOS partition mistakenly ACTIVE
Fixed    P1 80  da    63    shim ACTIVE (correct)
         P2 00  06    1008  DOS inactive
```

The active flag must be set on the boot shim (P1, LBA 63). The current
`tools/make_cf_image.c` does this correctly (`set_partition(mbr + 446, 0x80,
0xda, BOOT_SHIM_LBA, 1)`). The incorrectly-flagged `cf-3.9gb.img` was a stale
artifact left over from the earlier two-partition design in which the DOS
partition was the active one; it was not regenerated from `cf-4gb.img` after
the shim layout was introduced. The DOS installation lived only in that stale
artifact, so the fix was to patch the two active-flag bytes in place rather than
rebuild from scratch and reinstall DOS:

```sh
# P1 (shim) active, P2 (DOS) inactive, preserving the installed DOS partition
dd if=build/cf-3.9gb.img of=build/cf-3.9gb-fixed.img
printf '\x80' | dd of=build/cf-3.9gb-fixed.img bs=1 seek=446 conv=notrunc
printf '\x00' | dd of=build/cf-3.9gb-fixed.img bs=1 seek=462 conv=notrunc
```

Note that QEMU masked this bug: SeaBIOS was able to boot the DOS-active image
directly to `C:\>` because it has no 500 MiB BIOS limit, so a QEMU pass did not
guarantee the real-486 boot worked. Always validate the shipped card-sized image
against the intended active-partition layout before physical deployment.

### 2. XT-IDE preload CHS heads bug (`xtide preload failed: 2`)

After the active-flag fix the card reached SBM but the XT-IDE preload failed
with code 2, meaning the header read at LBA 128 succeeded but contained no
`55 AA` signature. The ROM was present at LBA 128 in every correct build, so
the preload was reading the wrong physical sector.

The cause was in `preload_read_sector`'s CHS fallback
(`btmgr-3.7-1/manager/xtide_preload.asm`), used because the 486 has no EDD.
The code divided the LBA by sectors-per-track, then divided the quotient by a
"Heads" value read from `DH` *after* the 32-bit `div` had already zeroed `EDX`.
That second divisor was therefore always 1, so the drive was treated as having
a single head:

```asm
; before (buggy) - DH is 0 here, so heads is effectively 1
xor edx, edx
div esi
inc dx
push dx
movzx esi, dh     ; dh == 0 (div zeroed edx)
inc si            ; esi == 1  -> heads divisor = 1
div esi           ; always divides by 1
```

For LBA 128 with the common 63-sectors-per-track, heads = 2 geometry, this
computed CHS `(head 0, sector 3, cylinder 2)` instead of
`(head 2, sector 3, cylinder 0)`, reading LBA ~2018 (a reserved sector) and
finding no `55 AA`. With a 255-sectors-per-track geometry the bug is masked
because LBA 128 falls in the first head.

The fix saves the geometry heads right after `INT 13h AH=08h` (before any
division) and uses it as the second divisor:

```asm
mov [xtide_heads], dh       ; save heads before div clobbers EDX/DH
...
movzx esi, byte [xtide_heads]   ; real heads divisor
jz .bad_geometry_pop
xor edx, edx
div esi
```

A debug dump was also added: before each CHS read it prints via BIOS INT 10h

```text
XTIDE CHS SPT=3F HEADS=10 CHS=02/03/00
```

which shows the reported geometry (SPT, heads) and the computed CHS
(head/sector/cylinder). QEMU never exercised this code because SeaBIOS provides
EDD, so the CHS path was only validated on the real hardware.

After this fix the card booted the full chain on the 486: generic MBR → active
shim at LBA 63 → SBM → XT-IDE at LBA 128 → partition menu. Because only the SBM
kernel changed, it was patched in place by writing just the kernel region
(LBA 64-127) to the card, leaving the MBR, shim, XT-IDE ROM, and partitions
untouched:

```sh
dd if=build/cf-dev/small-7962192-fixed.img of=/dev/sde bs=512 skip=64 seek=64 count=64 conv=fsync
```

Before installing Windows 95, boot DOS through SBM and test access beyond the
original BIOS limit. Windows 3.11 is installed over the existing DOS partition.
Windows 95 OSR2 belongs in the 2 GiB FAT16 primary partition. (The old image
used a FAT32 partition for Windows 95; the current layout uses FAT16 throughout
so that the smaller DOS file system and FAT blocks survive the 8,198,064-sector
card resize cleanly.)
