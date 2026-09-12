#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="$ROOT/build/cf-4gb.img"

sfdisk -A "$IMG" 1
fdisk -l "$IMG"
