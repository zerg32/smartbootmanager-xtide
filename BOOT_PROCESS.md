# Boot Process Reference

This document describes the boot path used by the 486 CF card from CPU reset
until the Smart Boot Manager (SBM) menu appears. It also records the important
memory addresses, disk sectors, validation checks, and CHS-related failure
modes found during physical testing.

Sections 1-17 describe the original active-shim layout. The later sections
describe the diagnostic validation and the final loader-in-MBR layout now
deployed on the physical card.

## Overview

### Original shim layout (before diagnostic redesign)

```text
CPU reset
  -> motherboard BIOS POST
  -> BIOS bootstrap service
  -> active-partition MBR at LBA 0
  -> active SBM shim at LBA 63
  -> SBM kernel at LBA 64-127
  -> XT-IDE ROM at LBA 128-143
  -> XT-IDE installs enhanced INT 13h
  -> SBM scans partitions
  -> Smart Boot Manager menu
```

### Final loader-in-MBR layout (deployed)

```text
CPU reset
  -> motherboard BIOS POST
  -> BIOS bootstrap service
  -> SBM loader in the MBR at LBA 0
  -> loader reads the SBM kernel from LBA 1
  -> SBM loads XT-IDE from LBA 128
  -> XT-IDE installs enhanced INT 13h
  -> SBM scans partitions
  -> Smart Boot Manager menu
```

The final layout eliminates the type-`DAh` shim partition entirely. The SBM
loader occupies the first 446 bytes of the MBR. The kernel and XT-IDE ROM are at
fixed LBAs. The partition table contains only real filesystem partitions.

## Relevant Disk Layout

The active 7,962,192-sector card uses this layout:

### Final loader-in-MBR layout (current)

| LBA range | Purpose |
| --- | --- |
| 0 | SBM loader (440 bytes boot code) + normal DOS partition table |
| 1-38 | SBM kernel (19,304 bytes / 38 sectors) |
| 39-127 | Reserved |
| 128-143 | 8 KiB XT-IDE ROM |
| 144-1007 | Reserved; never partition or format |
| 1008-3146735 | 1.5 GiB FAT16 partition for MS-DOS and Windows 3.1 |
| 3146736-4719599 | 768 MiB FAT16 partition area |
| 4719600-7962191 | 1.5 GiB FAT16 partition |

The partition table contains only real filesystem partitions:

```text
P1  active  FAT16  start=1008     size=3145728  DOS and Windows
P2          FAT16  start=3146736  size=1572864
P3          FAT16  start=4719600  size=3242592
P4          empty
```

The active flag remains on DOS for compatibility with BIOS and DOS tools, but
the SBM loader in sector zero does not use the active flag to start SBM.

### Original shim layout (historical)

| LBA range | Purpose |
| --- | --- |
| 0 | MBR code, partition table, and `55 AA` signature |
| 1-62 | Unused |
| 63 | Active type-`DAh` SBM loader shim |
| 64-127 | SBM kernel area |
| 128-143 | 8 KiB XT-IDE ROM |
| 144-1007 | Reserved; never partition or format |
| 1008-3146735 | 1.5 GiB FAT16 partition for MS-DOS and Windows 3.1 |
| 3146736-4719599 | 768 MiB FAT16 partition area |
| 4719600-7962191 | 1.5 GiB FAT16 partition |

## 1. CPU Reset And BIOS POST

At power-on the 486 starts executing motherboard firmware from the reset
vector near physical address `0xFFFF0`.

The BIOS:

1. Performs the power-on self-test.
2. Initializes RAM, chipset, video, keyboard, and IDE hardware.
3. Creates the interrupt vector table at physical address zero.
4. Installs its original disk service at interrupt `INT 13h`.
5. Scans the normal option-ROM memory range.
6. Chooses the configured boot device.

XT-IDE is not available during the normal option-ROM scan. Its ROM image is on
the CF card rather than mapped into option-ROM memory. The motherboard BIOS's
limited `INT 13h` implementation must therefore load the MBR, kernel, and
XT-IDE preload sectors.

All boot components needed before XT-IDE initialization are kept below LBA
144, comfortably inside the BIOS's approximate 500 MiB disk limit.

## 2. BIOS Loads The MBR

The BIOS bootstrap process reads the first sector of the CF card:

```text
Disk sector:     LBA 0
Memory address:  0000:7C00
Boot drive:      DL = 80h
Size:            512 bytes
```

The MBR sector contains:

| Offset | Size | Contents |
| ---: | ---: | --- |
| 0 | 440 bytes | Executable SBM loader code and associated data |
| 446 | 64 bytes | Four 16-byte DOS partition entries |
| 510 | 2 bytes | `55 AA` boot signature |

`DL=80h` identifies the first BIOS hard disk and is preserved through the boot
chain.

## 3. The SBM Loader In The MBR

In the final layout, the SBM loader occupies the first 446 bytes of sector
zero. It is built from `btmgr-3.7-1/manager/loader.asm` and assembled into
`build/sbm-loader.bin`, then placed directly in the MBR by
`tools/prepare_final_image.c`.

The loader:

1. Relocates itself from `0000:7C00` to `0000:0600`.
2. Reads the SBM kernel from LBA 1 (38 sectors).
3. Validates the `SBMK` magic, version, size, and checksum.
4. Executes XT-IDE preload from LBA 128.
5. Transfers control to the SBM kernel at `1000:0000`.

No active partition or shim sector is involved. The partition table contains
only filesystem partitions.

## 4. The MBR Selects The Active Partition (Original Layout Only)

The original active-partition MBR scanned the four partition entries and
counted entries whose boot byte was `80h`. It expected exactly one active
partition.

The required active entry in the original layout was:

```text
Partition:  P1
Boot flag:  80h
Type:       DAh (non-filesystem data)
Start:      LBA 63
Length:     1 sector
```

Type `DAh` prevented DOS and normal filesystem utilities from treating the shim
as a filesystem.

If the DOS partition was marked active instead, the MBR bypassed SBM and XT-IDE.
The original motherboard BIOS might then be unable to boot or access the disk
correctly.

**This section no longer applies to the deployed image.** The final layout has
no type-`DAh` partition.

## 5. EDD And CHS Reading (Original Layout)

The original MBR used either extended or legacy BIOS disk access.

### EDD Path

It checks for enhanced disk-drive services with:

```text
INT 13h, AH=41h, BX=55AAh
```

When supported, it reads LBA 63 using an EDD disk-address packet and:

```text
INT 13h, AH=42h
```

QEMU normally exercises this path.

### CHS Path

The physical 486 BIOS may require legacy CHS access through:

```text
INT 13h, AH=02h
```

The validated partition-table CHS start for LBA 63 is:

```text
Cylinder 0
Head     1
Sector   1
```

Using the image's 16-head, 63-sector partition-table geometry:

```text
LBA = ((cylinder * heads) + head) * sectors_per_track + sector - 1
    = ((0 * 16) + 1) * 63 + 1 - 1
    = 63
```

The complete MBR sector must be preserved when changing the partition table.
During the DOS partition expansion, `sfdisk` retained the correct LBA starts
but regenerated incompatible CHS fields. P1 then pointed to sector 2 instead of
sector 1, making the MBR load LBA 64 and execute SBM kernel data as boot code.
The result was garbled text before SBM appeared.

Restoring sector zero from the validated image repaired both the MBR code and
the CHS partition fields:

```sh
dd if=build/cf-3.8gb-dos-1.5gb.img of=/dev/sde bs=512 count=1 conv=fsync
```

This command is safe only when the image contains the intended partition table.

## 6. The MBR Loads The LBA-63 Shim (Original Layout)

The MBR reads the active partition's one sector into `0000:7C00`, verifies the
`55 AA` signature at offsets 510-511, restores `DL=80h`, and transfers control
to the loaded sector.

Execution has now moved from the MBR at LBA 0 to the SBM loader shim at LBA 63.

## 7. The Shim Relocates Itself (Original Layout)

The shim is built as `build/sbm-loader.bin` from
`btmgr-3.7-1/manager/loader.asm`.

It begins at `0000:7C00`, initializes a temporary stack, copies its complete
512-byte sector to `0000:0600`, and continues from the relocated copy. This
again frees `0000:7C00` for later boot-sector use.

The image builder copies the MBR partition table into the shim at offset 446,
so the loader retains the current disk-partition metadata.

## 8. The Shim Loads The SBM Kernel (Original Layout)

During image construction, `tools/make_cf_image.c` patched the shim's `SBML`
header with:

```text
Kernel start LBA: 64
Kernel sectors:   size of build/sbm-main.bin rounded to sectors
```

The shim loaded the kernel to:

```text
Segment:          1000h
Offset:           0000h
Physical address: 10000h
```

It reads one sector at a time. It prefers EDD but can ask the BIOS for geometry
with `INT 13h AH=08h`, convert each LBA to CHS, and read with
`INT 13h AH=02h`.

The kernel region is limited to LBA 64-127, or 64 sectors/32 KiB.

## 9. The Shim Validates The Kernel (Original Layout)

After loading, the shim verifies:

1. The `SBMK` kernel magic.
2. The expected kernel version.
3. The advertised total size.
4. An additive checksum over the complete kernel.

The checksum must sum to zero. A failure prints `SBMK Bad!` and invokes the BIOS
fallback boot path. A successful validation jumps to `1000:0000`.

At this point the SBM kernel is executing, but the visible menu has not yet
been initialized.

## 10. Initial SBM Kernel Setup

The SBM kernel:

1. Creates its main stack at `SS:SP = 3000:1000`.
2. Saves the boot drive number from `DL`.
3. Backs up its kernel image.
4. Decompresses the compressed runtime section when required.
5. Clears its temporary data area.

Before probing partitions, this project-specific build calls
`preload_xtide`. This order is essential because the original motherboard BIOS
cannot reliably address the whole CF card.

## 11. SBM Reads The XT-IDE ROM

The XT-IDE option-ROM image begins at LBA 128. The current image is 8 KiB, so it
occupies 16 sectors, LBA 128-143.

SBM first reads LBA 128 into a temporary buffer and checks the standard PC
option-ROM header:

```text
Offset 0: 55 AA
Offset 2: ROM length in 512-byte units
```

It rejects a zero-sized ROM or one exceeding the configured 32-sector limit.

## 12. XT-IDE Preload CHS Fallback

XT-IDE is not initialized yet, so the preload still uses the motherboard's
original `INT 13h` implementation.

It tries EDD first. If unavailable, it:

1. Calls `INT 13h AH=08h` for geometry.
2. Saves sectors per track.
3. Saves the head count before division can overwrite `DH`.
4. Converts each requested LBA to CHS.
5. Reads each sector through `INT 13h AH=02h`.

The debug build prints lines resembling:

```text
XTIDE CHS SPT=3F HEADS=10 CHS=02/03/00
```

Values are hexadecimal.

An earlier physical failure came from reading the head count after a division
had cleared `EDX/DH`. The old code treated the disk as having one head and read
the wrong physical sector for LBA 128. Saving the geometry first fixed the
problem.

## 13. SBM Reserves Conventional Memory

SBM calls `INT 12h` to obtain the amount of conventional memory. It subtracts
enough memory for the XT-IDE ROM and updates the BIOS Data Area word at
`0040:0013`.

This prevents DOS or another program from allocating memory over the relocated
ROM.

The ROM is placed at the top of the remaining conventional-memory area. One
QEMU run placed it at `9DC0:0000`; the exact segment depends on available base
memory.

## 14. SBM Loads And Validates XT-IDE

SBM reads the ROM one sector at a time into the reserved memory and verifies
that its additive option-ROM checksum equals zero.

Preload failure codes are:

| Code | Meaning |
| ---: | --- |
| 1 | Header-sector read failed |
| 2 | Missing `55 AA` signature |
| 3 | Zero ROM length |
| 4 | ROM exceeds configured maximum |
| 5 | Insufficient conventional memory |
| 6 | ROM-body read failed |
| 7 | Invalid option-ROM checksum |

Failures appear as `XTIDE preload failed: N`.

## 15. SBM Executes XT-IDE

A standard option ROM begins with a header at offset zero. Its executable entry
point is offset 3, so SBM performs a far transfer to:

```text
XTIDE_segment:0003
```

It must not execute offset zero, which contains the `55 AA` signature and ROM
metadata rather than initialization code.

The option-ROM entry performs XT-IDE's early setup and installs its custom
`INT 19h` path.

## 16. XT-IDE Installs Enhanced Disk Services

After the option-ROM entry returns, SBM invokes `INT 19h`. This project builds
XT-IDE with `XTIDE_SBM_RETURN`, which changes the normal boot behavior.

Instead of immediately booting an operating system, the custom handler:

1. Switches to XT-IDE's dedicated stack.
2. Detects IDE drives.
3. Creates XT-IDE drive parameter tables.
4. Installs XT-IDE's enhanced `INT 13h` handler.
5. Restores the temporary timer interrupt used by hotkey detection.
6. Restores SBM's stack.
7. Returns to SBM with `IRET`.

The disk-service transition is now:

```text
Before: INT 13h -> limited motherboard BIOS
After:  INT 13h -> XT-IDE -> full CF-card access
```

## 17. SBM Initializes The Visible Menu

Control returns to the SBM kernel. It then:

1. Initializes its disk-access layer.
2. Initializes the theme, commands, and video mode.
3. Scans the disk through XT-IDE's `INT 13h` service.
4. Converts the partition entries into SBM boot records.

The card appears approximately as:

```text
Primary 1  Unknown/type DA  active shim
Primary 2  FAT16            MS-DOS and Windows 3.1
Primary 3  FAT16
Primary 4  FAT16
```

SBM then displays the `Smart Boot Manager 3.7.1` boot menu. No DOS or Windows
code has run yet.

Selecting `Primary 2` causes SBM to load the FAT16 volume boot sector from LBA
1008 to `0000:7C00` with `DL=80h`. If SBM asks to save changes, answer `N`
unless a persistent SBM configuration change is intended.

## Verification

### Final loader-in-MBR layout

Verify the MBR, kernel, and XT-IDE region against the validated image:

```sh
cmp -n 512 /dev/sdX build/cf-final-direct.img
cmp -n $((39 * 512)) -i 512 /dev/sdX build/cf-final-direct.img
cmp -n $((16 * 512)) -i $((128 * 512)) /dev/sdX build/cf-final-direct.img
```

For a non-persistent QEMU test of a physical card:

```sh
qemu-system-i386 -cpu 486 -m 16M \
  -drive if=ide,format=raw,file=/dev/sdX -snapshot -boot c
```

Expected sequence:

```text
Smart Boot Manager menu
  -> select Primary 1
  -> answer N to save prompt
  -> Starting MS-DOS...
```

### Original shim layout

Verify the complete MBR and the shim/SBM/XT-IDE region against the validated
card-sized image:

```sh
cmp -n 512 /dev/sdX build/cf-3.8gb-dos-1.5gb.img
cmp -n $((81 * 512)) -i $((63 * 512)):$((63 * 512)) \
  /dev/sdX build/cf-3.8gb-dos-1.5gb.img
```

## Legacy Shim-Layout Rules

These rules apply to the original active type-`DAh` shim image, not the compact
diagnostic partition table described below.

- Keep P1 at LBA 63 active and keep P2 inactive.
- Do not run `FDISK /MBR`.
- Do not partition or format LBA 0-1007.
- Do not regenerate MBR CHS fields without restoring and verifying sector zero.
- Keep the complete XT-IDE ROM at LBA 128-143.
- Test the actual physical card in QEMU with `-snapshot` after changing boot
  sectors or partition metadata.

## Implemented Shimless Layout

The one-sector type-`DAh` partition has been removed. The SBM loader now
occupies the first 446 bytes of the MBR, eliminating the LBA-63 shim entirely.

The final hidden-sector layout is:

```text
LBA 0       SBM loader and normal DOS partition table
LBA 1-38    SBM kernel (19,304 bytes / 38 sectors)
LBA 39-127  Reserved
LBA 128-143 XT-IDE ROM
LBA 144-1007 Reserved
LBA 1008... DOS and Windows FAT16 partition
```

The partition table contains only real filesystem partitions:

```text
P1  active  FAT16  start=1008     size=3145728  DOS and Windows
P2          FAT16  start=3146736  size=1572864
P3          FAT16  start=4719600  size=3242592
P4          empty
```

The active flag remains on DOS for compatibility with BIOS and DOS tools, but
the SBM loader in sector zero does not use the active flag to start SBM.

The final boot path is:

```text
BIOS
  -> SBM loader in the MBR
  -> loader relocates itself to 0000:0600
  -> loader reads the SBM kernel from LBA 1
  -> SBM loads XT-IDE from LBA 128
  -> XT-IDE installs INT 13h
  -> SBM scans the filesystem partitions
  -> DOS and Windows appear as Primary 1
```

No final-stage component needs LBA 63. Fixed LBAs identify hidden components,
but a BIOS without EDD translates those LBAs to CHS using the geometry returned
by `INT 13h AH=08h`. The partition table's CHS fields are therefore no longer
used to locate SBM.

### Deployment Status

The final image was built with `tools/prepare_final_image.c` and validated in
QEMU. LBA 0-143 was written to the physical 7,962,192-sector card. The card
boots through SBM to DOS on the real 486.

### Rollback

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

## Diagnostic MBR Test (Completed)

The old BIOS was tested before making the shimless layout the default. The
diagnostic MBR reported the BIOS disk interface and proved that the future
hidden-sector locations are readable. This test is now complete and the final
loader-in-MBR image is deployed.

### Temporary Diagnostic Layout

```text
LBA 0       Diagnostic MBR
LBA 1-38    SBM kernel
LBA 39-40   Diagnostic display and validation payload
LBA 41-62   Reserved
LBA 63      Temporary normal SBM loader used only for handoff
LBA 64-127  Reserved
LBA 128-143 XT-IDE ROM
LBA 144-1007 Reserved
LBA 1008... DOS and Windows as partition 1
```

LBA 63 is not represented by a type-`DAh` partition in this image. It is only a
temporary hidden copy of the normal SBM loader, allowing the diagnostic MBR to
print its results and then exercise the same loader that will eventually occupy
sector zero.

The final image removes this temporary LBA-63 dependency.

### Diagnostic Output

The detailed output does not fit in the 440-byte MBR boot-code area. The
440-byte stage-1 MBR loads a 1024-byte diagnostic payload from LBA 39-40. Both
stages use the same EDD-or-runtime-CHS policy, so reaching the detailed display
also proves that sector zero successfully found the hidden diagnostic payload.

The diagnostic payload prints through BIOS video interrupt `INT 10h`. Its
compact display is:

```text
SBM BIOS DEBUG
DL=80 EDD=N C/H/S=....
K@00000001 cylinder/head/sector OK
X@00000080 cylinder/head/sector OK
L@0000003F cylinder/head/sector OK
KEY TO START SBM
```

Numbers are hexadecimal. Actual CHS values depend on the geometry reported by
the BIOS. `K`, `X`, and `L` identify the SBM kernel, XT-IDE ROM, and temporary
SBM loader respectively.

### Diagnostic Operations

The diagnostic MBR performs these operations:

1. Preserves and displays the BIOS boot drive from `DL`.
2. Queries `INT 13h AH=08h` and displays cylinders, heads, and sectors per track.
3. Queries EDD support with `INT 13h AH=41h`.
4. Uses EDD when available and runtime CHS conversion otherwise.
5. Reads LBA 1 and verifies the SBM kernel's `SBMK` signature.
6. Reads LBA 128 and verifies the XT-IDE ROM's `55 AA` signature.
7. Reads the temporary normal SBM loader at LBA 63 and verifies `SBML`.
8. Pauses so the output can be recorded on the real hardware.
9. Executes the normal loader from LBA 63.
10. Lets that loader read and validate the kernel from LBA 1.
11. Continues through XT-IDE initialization and the normal SBM menu.

### Completed Test Steps

1. Preserved the working card as `build/sde-before-debug-20260903.img`.
2. Built `tools/debug_mbr.asm` as the 440-byte diagnostic stage-1 MBR.
3. Built `tools/debug_stage2.asm` as the two-sector display and validation
   payload at LBA 39-40.
4. Built separate automatic-EDD and forced-CHS debug images.
5. Patched the SBM loader header to load the kernel from LBA 1.
6. Wrote the kernel at LBA 1-38.
7. Put the temporary patched loader at LBA 63 without creating a partition for
   it.
8. Kept XT-IDE at LBA 128-143.
9. Compacted the real filesystem entries into partition slots 1-3.
10. Marked the DOS and Windows FAT16 partition active.
11. Validated the automatic-EDD image in QEMU through the complete SBM path.
12. Validated the forced-CHS image in QEMU through the complete SBM path.
13. Patched LBA 0-143 onto the physical CF card.
14. Confirmed the diagnostic checks on the real 486.
15. Confirmed that pressing a key reaches the SBM menu on the real 486.

The final loader-in-MBR image has been deployed. LBA 0-143 was written from
`build/cf-final-direct.img` to the physical card. The card boots through SBM
to DOS on the real 486.

### Success Criteria

The diagnostic test passes when:

- The BIOS boot drive is `80h`.
- The BIOS geometry is displayed without an `INT 13h` error.
- LBA 1 is readable and contains a valid `SBMK` header.
- LBA 128 is readable and contains a valid XT-IDE option-ROM header.
- The temporary loader is readable and contains a valid `SBML` header.
- Pressing a key continues into the normal SBM menu.
- SBM detects the DOS and Windows FAT16 volume as `Primary 1`.

All diagnostic success criteria passed on the real 486. The BIOS loaded the
diagnostic path, the hidden-sector checks reported success, and the handoff
reached the SBM menu with DOS/Windows shown as FAT16 `Primary 1`.

The final loader-in-MBR image was then built, validated in QEMU, and deployed
to the physical card. The card boots through SBM to DOS on the real 486.

### Generated Debug Images

Build both diagnostic variants with:

```sh
make debug-images
```

The outputs are:

| File | Purpose |
| --- | --- |
| `build/cf-debug-direct.img` | Hardware-test image; detects EDD and falls back to CHS |
| `build/cf-debug-direct-chs.img` | QEMU regression image that deliberately disables EDD in both diagnostic stages |

Both images retain the DOS/Windows filesystem byte-for-byte. They use the
compact three-partition table and display DOS/Windows as `Primary 1`.

The automatic and forced-CHS images were tested in QEMU. Both reported valid
SBM kernel, XT-IDE, and temporary loader signatures and continued to the SBM
menu. The forced-CHS image intentionally displays `EDD=N` even under a BIOS
that supports EDD.

The automatic image was then patched onto the 7,962,192-sector development
card. The real 486 displayed successful hidden-sector checks and continued to
the SBM menu after a key press. This validates the BIOS-visible geometry path,
the LBA-to-CHS conversion, kernel LBA 1, XT-IDE LBA 128, and the compact
three-partition table on the target hardware.

Before patching, the complete card and its old partition table were saved as:

```text
build/sde-before-debug-20260903.img
build/sde-before-debug-20260903.sfdisk
```

The backup image SHA-256 is:

```text
edab9580c64233dbc72a30632936ebee91ef6d4031e2b2000c1c11ac943f0356
```

The QEMU diagnostic output uses this compact format:

```text
SBM BIOS DEBUG
DL=80 EDD=Y C/H/S=03DA/0080/003F
K@00000001 0000/0000/0002 OK
X@00000080 0000/0002/0003 OK
L@0000003F 0000/0001/0001 OK
KEY TO START SBM
```

`C/H/S` on the first line are the BIOS-reported cylinder, head, and
sectors-per-track counts. The three following CHS triples are the computed
cylinder/head/sector addresses for the fixed LBAs.

For the real 486 test, write only the automatic image to a card containing
exactly 7,962,192 sectors:

```sh
cat /sys/class/block/sdX/size
# Must print 7962192.

dd if=build/cf-debug-direct.img of=/dev/sdX bs=4M conv=fsync status=progress
```

Photograph or record the complete diagnostic display before pressing a key.
Do not use the forced-CHS image for the primary hardware test because it would
hide whether the BIOS actually advertises EDD.
