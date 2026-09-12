#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
IMAGE=$(mktemp)

cleanup() {
    rm -f -- "$IMAGE"
}
trap cleanup EXIT

truncate -s 64M "$IMAGE"
"$BUILD_DIR/install_bootloader" install "$IMAGE" 32 \
    "$BUILD_DIR/sbm-loader.bin" "$BUILD_DIR/sbm-main.bin" "$BUILD_DIR/xtide-386.bin"
"$BUILD_DIR/install_bootloader" exact "$IMAGE" \
    "$BUILD_DIR/sbm-loader.bin" "$BUILD_DIR/sbm-main.bin" "$BUILD_DIR/xtide-386.bin"

# A changed byte in the zero-filled XT-IDE tail must fail exact verification.
printf '\001' | dd of="$IMAGE" bs=1 seek=$((150 * 512)) count=1 conv=notrunc status=none
if "$BUILD_DIR/install_bootloader" exact "$IMAGE" \
    "$BUILD_DIR/sbm-loader.bin" "$BUILD_DIR/sbm-main.bin" "$BUILD_DIR/xtide-386.bin"; then
    printf 'exact verification accepted corrupted boot data\n' >&2
    exit 1
fi
"$BUILD_DIR/install_bootloader" repair "$IMAGE" \
    "$BUILD_DIR/sbm-loader.bin" "$BUILD_DIR/sbm-main.bin" "$BUILD_DIR/xtide-386.bin"
"$BUILD_DIR/install_bootloader" exact "$IMAGE" \
    "$BUILD_DIR/sbm-loader.bin" "$BUILD_DIR/sbm-main.bin" "$BUILD_DIR/xtide-386.bin"
