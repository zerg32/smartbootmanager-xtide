#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="$ROOT/build/cf-4gb.img"
BACKUP_DIR="$ROOT/build/dos622-backup"

test -f "$BACKUP_DIR/part2.img"
test -f "$BACKUP_DIR/part3.img"
test -f "$BACKUP_DIR/part4.img"

dd if="$BACKUP_DIR/part2.img" of="$IMG" bs=512 seek=1008 conv=notrunc status=progress
dd if="$BACKUP_DIR/part3.img" of="$IMG" bs=512 seek=525296 count=3145728 conv=notrunc status=progress
dd if="$BACKUP_DIR/part4.img" of="$IMG" bs=512 seek=4719600 conv=notrunc status=progress

sfdisk -A "$IMG" 1
fdisk -l "$IMG"
