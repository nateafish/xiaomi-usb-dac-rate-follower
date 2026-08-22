#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=0.6.5-alpha
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
    local sdk_root=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
    if [[ -n "$sdk_root" ]]; then
        find "$sdk_root/ndk" -path '*/toolchains/llvm/prebuilt/*/bin/clang' \
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
    "$ROOT_DIR/patches/preferred_hifi_hook.S" -o "$BUILD_DIR/preferred_hifi_hook.o"
"$LLVM_BIN/ld.lld" --entry=preferred_hifi_hook \
    --section-start=.hifi_config_branch=0x38800 \
    --section-start=.preferred_hifi_branch=0x5575c \
    --section-start=.preferred_hifi_cave=0xc37ac \
    --defsym=HIFI_INIT_RETURN=0x38804 \
    --defsym=GET_OUTPUT_HOOK_RETURN=0x55760 \
    --defsym=GET_PREFERRED_INFO=0x5aae0 \
    --defsym=SET_PREFERRED_ATTRIBUTES=0xa4ea0 \
    --defsym=REFBASE_DEC_STRONG_PLT=0xdb4d8 \
    "$BUILD_DIR/preferred_hifi_hook.o" -o "$BUILD_DIR/preferred_hifi_hook.elf"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .hifi_config_branch="$BUILD_DIR/hifi_config_branch.bin" \
    --dump-section .preferred_hifi_branch="$BUILD_DIR/preferred_hifi_branch.bin" \
    --dump-section .preferred_hifi_cave="$BUILD_DIR/preferred_hifi_cave.bin" \
    "$BUILD_DIR/preferred_hifi_hook.elf"

"$CLANG" --target=aarch64-linux-android35 -c \
    "$ROOT_DIR/patches/shared_usb_arbiter.S" -o "$BUILD_DIR/shared_usb_arbiter.o"
"$LLVM_BIN/ld.lld" --entry=shared_usb_arbiter \
    --section-start=.shared_arbiter_branch=0xd57bc \
    --section-start=.shared_arbiter_cave=0xc3928 \
    --defsym=PROFILE_LOOKUP=0xd4710 \
    --defsym=ARBITER_CALL_PATH=0xd57c0 \
    --defsym=ARBITER_SKIP_PATH=0xd5814 \
    "$BUILD_DIR/shared_usb_arbiter.o" -o "$BUILD_DIR/shared_usb_arbiter.elf"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .shared_arbiter_branch="$BUILD_DIR/shared_arbiter_branch.bin" \
    --dump-section .shared_arbiter_cave="$BUILD_DIR/shared_arbiter_cave.bin" \
    "$BUILD_DIR/shared_usb_arbiter.elf"

"$CLANG" --target=aarch64-linux-android35 -c \
    "$ROOT_DIR/patches/instruction_patches.S" -o "$BUILD_DIR/instruction_patches.o"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .strategy_restore_patch="$BUILD_DIR/strategy_restore_patch.bin" \
    --dump-section .profile_init_patch="$BUILD_DIR/profile_init_patch.bin" \
    --dump-section .effect_gate_patch="$BUILD_DIR/effect_gate_patch.bin" \
    --dump-section .flinger_sync_patch="$BUILD_DIR/flinger_sync_patch.bin" \
    --dump-section .hal_deep_buffer_reopen_patch="$BUILD_DIR/hal_deep_buffer_reopen_patch.bin" \
    --dump-section .usb_441_patch="$BUILD_DIR/usb_441_patch.bin" \
    --dump-section .usb_3528_patch="$BUILD_DIR/usb_3528_patch.bin" \
    "$BUILD_DIR/instruction_patches.o"

[[ $(wc -c < "$BUILD_DIR/is_app_allowed_hook.bin") -eq 196 ]]
[[ $(wc -c < "$BUILD_DIR/hifi_config_branch.bin") -eq 4 ]]
[[ $(wc -c < "$BUILD_DIR/preferred_hifi_branch.bin") -eq 4 ]]
[[ $(wc -c < "$BUILD_DIR/preferred_hifi_cave.bin") -eq 374 ]]
[[ $(wc -c < "$BUILD_DIR/shared_arbiter_branch.bin") -eq 4 ]]
[[ $(wc -c < "$BUILD_DIR/shared_arbiter_cave.bin") -eq 440 ]]
[[ $(wc -c < "$BUILD_DIR/strategy_restore_patch.bin") -eq 4 ]]
[[ $(wc -c < "$BUILD_DIR/profile_init_patch.bin") -eq 4 ]]
[[ $(wc -c < "$BUILD_DIR/effect_gate_patch.bin") -eq 4 ]]
[[ $(wc -c < "$BUILD_DIR/flinger_sync_patch.bin") -eq 4 ]]
[[ $(wc -c < "$BUILD_DIR/hal_deep_buffer_reopen_patch.bin") -eq 16 ]]
[[ $(wc -c < "$BUILD_DIR/usb_441_patch.bin") -eq 4 ]]
[[ $(wc -c < "$BUILD_DIR/usb_3528_patch.bin") -eq 4 ]]
[[ $(xxd -p "$BUILD_DIR/strategy_restore_patch.bin") == 030b40b9 ]]
[[ $(xxd -p "$BUILD_DIR/hifi_config_branch.bin") == eb2b0214 ]]
[[ $(xxd -p "$BUILD_DIR/preferred_hifi_branch.bin") == 19b80114 ]]
[[ $(xxd -p "$BUILD_DIR/shared_arbiter_branch.bin") == 5bb8ff17 ]]
[[ $(xxd -p "$BUILD_DIR/profile_init_patch.bin") == 1f2003d5 ]]
[[ $(xxd -p "$BUILD_DIR/effect_gate_patch.bin") == 62010054 ]]
[[ $(xxd -p "$BUILD_DIR/flinger_sync_patch.bin") == 6a000014 ]]
[[ $(xxd -p "$BUILD_DIR/hal_deep_buffer_reopen_patch.bin") == 092184522925c81a090200361f2003d5 ]]
[[ $(xxd -p "$BUILD_DIR/usb_441_patch.bin") == 44ac0000 ]]
[[ $(xxd -p "$BUILD_DIR/usb_3528_patch.bin") == 20620500 ]]
"$LLVM_BIN/llvm-readelf" -r "$BUILD_DIR/is_app_allowed_hook.elf" \
    | grep -q 'There are no relocations'
"$LLVM_BIN/llvm-readelf" -r "$BUILD_DIR/preferred_hifi_hook.elf" \
    | grep -q 'There are no relocations'
"$LLVM_BIN/llvm-readelf" -r "$BUILD_DIR/shared_usb_arbiter.elf" \
    | grep -q 'There are no relocations'
grep -a -q 'hifi_playback' "$BUILD_DIR/shared_arbiter_cave.bin"
grep -a -q 'deep_buffer_out' "$BUILD_DIR/shared_arbiter_cave.bin"
grep -a -q 'com.apple.android.music' "$BUILD_DIR/is_app_allowed_hook.bin"
grep -a -q 'com.netease.cloudmusic' "$BUILD_DIR/is_app_allowed_hook.bin"
xxd -p -c 10000 "$BUILD_DIR/preferred_hifi_cave.bin" \
    | grep -q '63006f006d002e006100700070006c0065002e0061006e00640072006f00690064002e006d0075007300690063000000'
xxd -p -c 10000 "$BUILD_DIR/preferred_hifi_cave.bin" \
    | grep -q '63006f006d002e006e006500740065006100730065002e0063006c006f00750064006d0075007300690063000000'

MODULE_STAGE="$BUILD_DIR/module"
mkdir -p "$MODULE_STAGE/patches" "$ROOT_DIR/dist"
cp -a "$ROOT_DIR/module/." "$MODULE_STAGE/"
cp "$BUILD_DIR/is_app_allowed_hook.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/hifi_config_branch.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/preferred_hifi_branch.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/preferred_hifi_cave.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/shared_arbiter_branch.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/shared_arbiter_cave.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/strategy_restore_patch.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/profile_init_patch.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/effect_gate_patch.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/flinger_sync_patch.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/hal_deep_buffer_reopen_patch.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/usb_441_patch.bin" "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/usb_3528_patch.bin" "$MODULE_STAGE/patches/"

grep -q '^author=nateafish$' "$MODULE_STAGE/module.prop"
grep -q '^version=0.6.5-alpha$' "$MODULE_STAGE/module.prop"
grep -q 'POLICY_STOCK_SHA256=e0bd4444' "$MODULE_STAGE/customize.sh"
grep -q 'FLINGER_STOCK_SHA256=d499d92e' "$MODULE_STAGE/customize.sh"
grep -q 'USB_STOCK_SHA256=d36085db' "$MODULE_STAGE/customize.sh"
grep -q 'PRIMARY_XML_STOCK_SHA256=369b5a59' "$MODULE_STAGE/customize.sh"
grep -q 'patch_primary_xml' "$MODULE_STAGE/customize.sh"
grep -q 'require_elf64_aarch64' "$MODULE_STAGE/customize.sh"
grep -q 'AudioPolicyManager structural state' "$MODULE_STAGE/customize.sh"
grep -q 'Refusing a partial or incompatible patch state' "$MODULE_STAGE/customize.sh"
[[ ! -e "$MODULE_STAGE/post-fs-data.sh" ]]
[[ ! -e "$MODULE_STAGE/service.sh" ]]
[[ ! -e "$MODULE_STAGE/mount-audio.sh" ]]
[[ ! -e "$MODULE_STAGE/zygisk" ]]
[[ ! -e "$MODULE_STAGE/system" ]]
[[ ! -e "$MODULE_STAGE/vendor" ]]
[[ ! -e "$MODULE_STAGE/odm" ]]
sh -n "$MODULE_STAGE/customize.sh"
python3 "$ROOT_DIR/tests/rate_arbiter_model.py"

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
