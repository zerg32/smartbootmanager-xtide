#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
HELPER="$BUILD_DIR/install_bootloader"
LOADER="$BUILD_DIR/sbm-loader.bin"
KERNEL="$BUILD_DIR/sbm-main.bin"
XTIDE="$BUILD_DIR/xtide-386.bin"

usage() {
    cat <<'EOF'
Usage:
  install_bootloader.sh DEVICE SIZE_MIB
  install_bootloader.sh --verify DEVICE
  install_bootloader.sh --verify-exact DEVICE
  install_bootloader.sh --repair DEVICE

Install creates one active FAT16 primary partition at LBA 1008, formats it,
and leaves all remaining sectors unallocated. SIZE_MIB must be 16 through 2047.

Build the boot components as the regular user before running install or repair:
  make boot-components
EOF
}

mode=install
if [[ ${1:-} == "--verify" || ${1:-} == "--verify-exact" || ${1:-} == "--repair" ]]; then
    mode=${1#--}
    shift
fi

if [[ $mode == install ]]; then
    [[ $# -eq 2 ]] || { usage >&2; exit 2; }
    device=$1
    size_mib=$2
    [[ $size_mib =~ ^[0-9]+$ ]] || {
        printf 'SIZE_MIB must be an integer.\n' >&2
        exit 2
    }
else
    [[ $# -eq 1 ]] || { usage >&2; exit 2; }
    device=$1
fi

device=$(readlink -f -- "$device")
[[ -b $device ]] || {
    printf 'Target must be a whole block device: %s\n' "$device" >&2
    exit 2
}
[[ $(lsblk -dn -o TYPE -- "$device") == disk ]] || {
    printf 'Target must be a whole disk, not a partition: %s\n' "$device" >&2
    exit 2
}

for artifact in "$HELPER" "$LOADER" "$KERNEL" "$XTIDE"; do
    if [[ $artifact == "$HELPER" ]]; then
        if [[ -f $artifact && -x $artifact ]]; then
            present=yes
        else
            present=no
        fi
    else
        if [[ -f $artifact ]]; then
            present=yes
        else
            present=no
        fi
    fi
    [[ $present == yes ]] || {
        printf 'Missing build artifact: %s\nRun: make boot-components\n' "$artifact" >&2
        exit 2
    }
done

if [[ $mode == verify ]]; then
    exec "$HELPER" verify "$device" "$LOADER" "$KERNEL" "$XTIDE"
fi
if [[ $mode == verify-exact ]]; then
    exec "$HELPER" exact "$device" "$LOADER" "$KERNEL" "$XTIDE"
fi

[[ $EUID -eq 0 ]] || {
    printf '%s requires root privileges.\n' "$mode" >&2
    exit 2
}

if [[ $mode == install && ( $size_mib -lt 16 || $size_mib -gt 2047 ) ]]; then
    printf 'SIZE_MIB must be from 16 to 2047.\n' >&2
    exit 2
fi

while read -r child mountpoint; do
    if [[ -n ${mountpoint:-} ]]; then
        printf 'Refusing to modify %s: %s is mounted at %s\n' \
            "$device" "$child" "$mountpoint" >&2
        exit 1
    fi
done < <(lsblk -nrpo NAME,MOUNTPOINT -- "$device")

while read -r swap; do
    [[ -n $swap ]] || continue
    while read -r child; do
        if [[ $swap == "$child" ]]; then
            printf 'Refusing to modify %s: %s is active swap\n' "$device" "$swap" >&2
            exit 1
        fi
    done < <(lsblk -nrpo NAME -- "$device")
done < <(swapon --show=NAME --noheadings --raw)

printf 'Target device:\n'
lsblk -dno NAME,MODEL,SERIAL,SIZE -- "$device"
if [[ $mode == install ]]; then
    printf '\nInstall layout:\n'
    printf '  LBA 0-1007       SBM, XT-IDE, and reserved sectors\n'
    printf '  LBA 1008...      active FAT16 P1 (%s MiB), formatted blank\n' "$size_mib"
    printf '  Remaining space  unallocated\n'
else
    printf '\nRepair preserves a valid partition table, SBM kernel, and XT-IDE ROM.\n'
    printf 'Invalid boot components are replaced; the MBR loader is written last.\n'
fi
printf '\nThis writes to %s. Type the complete device path to continue: ' "$device"
read -r confirmation
[[ $confirmation == "$device" ]] || {
    printf 'Confirmation did not match; no changes made.\n' >&2
    exit 1
}

mkdir -p -- "$BUILD_DIR"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
base=$(basename -- "$device")
if [[ $mode == install ]]; then
    backup_sectors=1008
    backup_range=lba0-1007
else
    backup_sectors=160
    backup_range=lba0-159
fi
backup="$BUILD_DIR/${base}-${stamp}-pre-${mode}-${backup_range}.bin"
table_backup="$BUILD_DIR/${base}-${stamp}-pre-${mode}-partition-table.bin"
dd if="$device" of="$backup" bs=512 count="$backup_sectors" conv=fsync status=none
dd if="$device" of="$table_backup" bs=1 skip=446 count=64 conv=fsync status=none
printf 'Saved boot-area backup: %s\n' "$backup"
printf 'Saved partition-table backup: %s\n' "$table_backup"

if [[ $mode == install ]]; then
    "$HELPER" install "$device" "$size_mib" "$LOADER" "$KERNEL" "$XTIDE"
    blockdev --rereadpt "$device" || true
    udevadm settle || true
    if [[ $device =~ [0-9]$ ]]; then
        partition_device="${device}p1"
    else
        partition_device="${device}1"
    fi
    if [[ -n $partition_device && -b $partition_device ]]; then
        mkfs.fat --invariant -F 16 -S 512 -h 1008 -g 255/63 -D 128 -n DOS \
            "$partition_device"
    else
        printf 'No partition node appeared; formatting the bounded raw-device offset.\n' >&2
        mkfs.fat --invariant -I -F 16 -S 512 -h 1008 -g 255/63 -D 128 -n DOS \
            --offset=1008 "$device" "$((size_mib * 1024))"
    fi
    "$HELPER" verify "$device" "$LOADER" "$KERNEL" "$XTIDE"
else
    "$HELPER" repair "$device" "$LOADER" "$KERNEL" "$XTIDE"
fi
