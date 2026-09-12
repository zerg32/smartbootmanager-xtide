#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="$ROOT/build/cf-4gb.img"
BACKUP_DIR="$ROOT/build/dos622-backup"

mkdir -p "$BACKUP_DIR"

sfdisk -d "$IMG" > "$BACKUP_DIR/cf-4gb.sfdisk"

dd if="$IMG" of="$BACKUP_DIR/part2.img" bs=512 skip=1008 count=524288 status=progress
dd if="$IMG" of="$BACKUP_DIR/part3.img" bs=512 skip=525296 count=3145728 status=progress
dd if="$IMG" of="$BACKUP_DIR/part4.img" bs=512 skip=4719600 count=3669008 status=progress

printf 'Backed up DOS partitions to %s\n' "$BACKUP_DIR"
