#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=0.6.2-alpha
OUTPUT_NAME="xiaomi-usb-dac-rate-follower-v${VERSION}.zip"

find_clang() {
    local root candidate
    for root in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
        candidate="$root/toolchains/llvm/prebuilt"
        if [[ -d "$candidate" ]]; then
            find "$candidate" -mindepth 3 -maxdepth 3 -name clang -print -quit
            return
        fi
    done
    if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
        find "$ANDROID_SDK_ROOT/ndk" -path '*/toolchains/llvm/prebuilt/*/bin/clang' \
            2>/dev/null | sort -V | tail -n 1
    fi
}

CLANG=$(find_clang)
[[ -x "$CLANG" ]] || {
    echo "Android NDK LLVM toolchain not found" >&2
    exit 1
}
LLVM_BIN=$(dirname "$CLANG")

BUILD_DIR=$(mktemp -d "${RUNNER_TEMP:-/tmp}/xiaomi-usb-rate-follower.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT

"$CLANG" --target=aarch64-linux-android35 -c \
    "$ROOT_DIR/patches/is_app_allowed_hook.S" -o "$BUILD_DIR/is_app_allowed_hook.o"
"$LLVM_BIN/ld.lld" --entry=is_app_allowed_hook --section-start=.text=0xd3bcc \
    "$BUILD_DIR/is_app_allowed_hook.o" -o "$BUILD_DIR/is_app_allowed_hook.elf"
"$LLVM_BIN/llvm-objcopy" -O binary --only-section=.text \
    "$BUILD_DIR/is_app_allowed_hook.elf" "$BUILD_DIR/is_app_allowed_hook.bin"

"$CLANG" --target=aarch64-linux-android35 -c \
    "$ROOT_DIR/patches/instruction_patches.S" -o "$BUILD_DIR/instruction_patches.o"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .latest_max_patch="$BUILD_DIR/latest_max_patch.bin" \
    --dump-section .effect_gate_patch="$BUILD_DIR/effect_gate_patch.bin" \
    --dump-section .flinger_sync_patch="$BUILD_DIR/flinger_sync_patch.bin" \
    --dump-section .usb_441_patch="$BUILD_DIR/usb_441_patch.bin" \
    --dump-section .usb_3528_patch="$BUILD_DIR/usb_3528_patch.bin" \
    "$BUILD_DIR/instruction_patches.o"

[[ $(wc -c < "$BUILD_DIR/is_app_allowed_hook.bin") -eq 196 ]]
[[ $(wc -c < "$BUILD_DIR/latest_max_patch.bin") -eq 4 ]]
[[ $(wc -c < "$BUILD_DIR/effect_gate_patch.bin") -eq 4 ]]
[[ $(wc -c < "$BUILD_DIR/flinger_sync_patch.bin") -eq 4 ]]
[[ $(wc -c < "$BUILD_DIR/usb_441_patch.bin") -eq 4 ]]
[[ $(wc -c < "$BUILD_DIR/usb_3528_patch.bin") -eq 4 ]]
[[ $(xxd -p "$BUILD_DIR/latest_max_patch.bin") == e3031f2a ]]
[[ $(xxd -p "$BUILD_DIR/effect_gate_patch.bin") == 62010054 ]]
[[ $(xxd -p "$BUILD_DIR/flinger_sync_patch.bin") == 6a000014 ]]
[[ $(xxd -p "$BUILD_DIR/usb_441_patch.bin") == 44ac0000 ]]
[[ $(xxd -p "$BUILD_DIR/usb_3528_patch.bin") == 20620500 ]]
"$LLVM_BIN/llvm-readelf" -r "$BUILD_DIR/is_app_allowed_hook.elf" \
    | grep -q 'There are no relocations'
grep -a -q 'com.apple.android.music' "$BUILD_DIR/is_app_allowed_hook.bin"
grep -a -q 'com.netease.cloudmusic' "$BUILD_DIR/is_app_allowed_hook.bin"

MODULE_STAGE="$BUILD_DIR/module"
mkdir -p "$MODULE_STAGE/patches" "$ROOT_DIR/dist"
cp -a "$ROOT_DIR/module/." "$MODULE_STAGE/"
cp "$BUILD_DIR/is_app_allowed_hook.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/latest_max_patch.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/effect_gate_patch.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/flinger_sync_patch.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/usb_441_patch.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/usb_3528_patch.bin" "$MODULE_STAGE/patches/"

grep -q '^author=nateafish$' "$MODULE_STAGE/module.prop"
grep -q '^version=0.6.2-alpha$' "$MODULE_STAGE/module.prop"
grep -q 'POLICY_STOCK_SHA256=e0bd4444' "$MODULE_STAGE/customize.sh"
grep -q 'FLINGER_STOCK_SHA256=d499d92e' "$MODULE_STAGE/customize.sh"
grep -q 'USB_STOCK_SHA256=d36085db' "$MODULE_STAGE/customize.sh"
[[ ! -e "$MODULE_STAGE/post-fs-data.sh" ]]
[[ ! -e "$MODULE_STAGE/service.sh" ]]
[[ ! -e "$MODULE_STAGE/mount-audio.sh" ]]
[[ ! -e "$MODULE_STAGE/zygisk" ]]
[[ ! -e "$MODULE_STAGE/system" ]]
[[ ! -e "$MODULE_STAGE/vendor" ]]
[[ ! -e "$MODULE_STAGE/odm" ]]

chmod 0755 "$MODULE_STAGE/customize.sh"
chmod 0644 "$MODULE_STAGE/module.prop" "$MODULE_STAGE/README.txt" \
    "$MODULE_STAGE"/patches/*.bin
find "$MODULE_STAGE" -exec touch -t 202601010000 {} +

rm -f "$ROOT_DIR/dist/$OUTPUT_NAME" "$ROOT_DIR/dist/$OUTPUT_NAME.sha256"
(
    cd "$MODULE_STAGE"
    find . -type f -print | LC_ALL=C sort | zip -X -q "$ROOT_DIR/dist/$OUTPUT_NAME" -@
)
(
    cd "$ROOT_DIR/dist"
    sha256sum "$OUTPUT_NAME" > "$OUTPUT_NAME.sha256"
)

unzip -t "$ROOT_DIR/dist/$OUTPUT_NAME"
cat "$ROOT_DIR/dist/$OUTPUT_NAME.sha256"
