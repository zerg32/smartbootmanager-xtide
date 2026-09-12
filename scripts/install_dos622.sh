#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="$ROOT/build/cf-4gb.img"
DOS1="$ROOT/DOS622-Disk1.img"
MON="/tmp/opencode/dosmon.sock"

make -C "$ROOT" -B GENERIC_MBR=0 build/cf-4gb.img
sfdisk -A "$IMG" 1 >/dev/null
rm -f "$MON"

exec qemu-system-i386 \
  -cpu 486 \
  -m 16M \
  -drive if=ide,format=raw,file="$IMG" \
  -drive if=floppy,format=raw,file="$DOS1" \
  -boot a \
  -monitor unix:"$MON",server,nowait
