#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=0.7.2-alpha
OUTPUT_NAME="xiaomi-usb-dac-rate-follower-v${VERSION}.zip"

find_clang() {
    local root candidate sdk_root
    for root in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
        candidate="$root/toolchains/llvm/prebuilt"
        if [[ -d "$candidate" ]]; then
            find "$candidate" -mindepth 3 -maxdepth 3 -name clang -print -quit
            return
        fi
    done
    sdk_root=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
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

require_size() {
    local file=$1 expected=$2 actual
    actual=$(wc -c < "$file")
    [[ "$actual" -eq "$expected" ]] || {
        echo "unexpected size for $file: $actual (expected $expected)" >&2
        exit 1
    }
}

require_hex() {
    local file=$1 expected=$2 actual
    actual=$(xxd -p "$file")
    [[ "$actual" == "$expected" ]] || {
        echo "unexpected bytes for $file: $actual (expected $expected)" >&2
        exit 1
    }
}

"$CLANG" --target=aarch64-linux-android35 -c \
    "$ROOT_DIR/patches/native_hifi_select_hook.S" \
    -o "$BUILD_DIR/native_hifi_select_hook.o"
"$LLVM_BIN/ld.lld" --entry=native_hifi_select_hook \
    --section-start=.select_output_branch=0x57214 \
    --section-start=.hifi_app_branch=0xd3bcc \
    --section-start=.latest_max_final_stop_patch=0xd30a0 \
    --section-start=.latest_max_idle_rate_patch=0xd3630 \
    --section-start=.native_hifi_cave=0xc37ac \
    --defsym=VENDOR_SELECT_OUTPUT_STUB=0xda110 \
    --defsym=SELECT_OUTPUT_RETURN=0x57218 \
    --defsym=HIFI_APP_STOCK_CONTINUE=0xd3bd0 \
    --defsym=LATEST_MAX_TRUE_RETURN=0xd2e80 \
    "$BUILD_DIR/native_hifi_select_hook.o" \
    -o "$BUILD_DIR/native_hifi_select_hook.elf"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .select_output_branch="$BUILD_DIR/select_output_branch.bin" \
    --dump-section .hifi_app_branch="$BUILD_DIR/hifi_app_branch.bin" \
    --dump-section .latest_max_final_stop_patch="$BUILD_DIR/latest_max_final_stop_patch.bin" \
    --dump-section .latest_max_idle_rate_patch="$BUILD_DIR/latest_max_idle_rate_patch.bin" \
    --dump-section .native_hifi_cave="$BUILD_DIR/native_hifi_cave.bin" \
    "$BUILD_DIR/native_hifi_select_hook.elf"

"$CLANG" --target=aarch64-linux-android35 -c \
    "$ROOT_DIR/patches/usb_output_gate.S" -o "$BUILD_DIR/usb_output_gate.o"
"$LLVM_BIN/ld.lld" --entry=usb_output_gate \
    --section-start=.usb_output_gate_branch=0x7df94 \
    --section-start=.usb_output_gate_cave=0xc3ae0 \
    --defsym=SENDKEY_BODY=0x7df98 \
    --defsym=SENDKEY_ZERO_PATH=0x7e0f0 \
    "$BUILD_DIR/usb_output_gate.o" -o "$BUILD_DIR/usb_output_gate.elf"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .usb_output_gate_branch="$BUILD_DIR/usb_output_gate_branch.bin" \
    --dump-section .usb_output_gate_cave="$BUILD_DIR/usb_output_gate_cave.bin" \
    "$BUILD_DIR/usb_output_gate.elf"

"$CLANG" --target=aarch64-linux-android35 -c \
    "$ROOT_DIR/patches/instruction_patches.S" \
    -o "$BUILD_DIR/instruction_patches.o"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .flinger_sync_patch="$BUILD_DIR/flinger_sync_patch.bin" \
    --dump-section .usb_441_patch="$BUILD_DIR/usb_441_patch.bin" \
    --dump-section .usb_3528_patch="$BUILD_DIR/usb_3528_patch.bin" \
    "$BUILD_DIR/instruction_patches.o"

"$CLANG" --target=aarch64-linux-android35 -c \
    "$ROOT_DIR/patches/qti_hifi_hal_patches.S" \
    -o "$BUILD_DIR/qti_hifi_hal_patches.o"
"$LLVM_BIN/ld.lld" --entry=hifi_frame_count_cap_patch \
    --section-start=.hifi_frame_count_cap_patch=0x279bd8 \
    --section-start=.hifi_usecase_reconfigure_patch=0x230894 \
    --defsym=HIFI_FRAME_COUNT_EPILOGUE=0x279c10 \
    --defsym=HIFI_USECASE_SKIP_RECONFIGURE=0x2308dc \
    "$BUILD_DIR/qti_hifi_hal_patches.o" \
    -o "$BUILD_DIR/qti_hifi_hal_patches.elf"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .hifi_frame_count_cap_patch="$BUILD_DIR/hifi_frame_count_cap_patch.bin" \
    --dump-section .hifi_usecase_reconfigure_patch="$BUILD_DIR/hifi_usecase_reconfigure_patch.bin" \
    "$BUILD_DIR/qti_hifi_hal_patches.elf"

require_size "$BUILD_DIR/select_output_branch.bin" 4
require_size "$BUILD_DIR/hifi_app_branch.bin" 4
require_size "$BUILD_DIR/native_hifi_cave.bin" 744
require_size "$BUILD_DIR/latest_max_final_stop_patch.bin" 4
require_size "$BUILD_DIR/latest_max_idle_rate_patch.bin" 4
require_size "$BUILD_DIR/usb_output_gate_branch.bin" 4
require_size "$BUILD_DIR/usb_output_gate_cave.bin" 140
require_size "$BUILD_DIR/flinger_sync_patch.bin" 4
require_size "$BUILD_DIR/usb_441_patch.bin" 4
require_size "$BUILD_DIR/usb_3528_patch.bin" 4
require_size "$BUILD_DIR/hifi_frame_count_cap_patch.bin" 24
require_size "$BUILD_DIR/hifi_usecase_reconfigure_patch.bin" 16
require_hex "$BUILD_DIR/select_output_branch.bin" 66b10114
require_hex "$BUILD_DIR/hifi_app_branch.bin" 38bfff17
require_hex "$BUILD_DIR/latest_max_final_stop_patch.bin" 78ffff17
require_hex "$BUILD_DIR/latest_max_idle_rate_patch.bin" e822f8b4
require_hex "$BUILD_DIR/usb_output_gate_branch.bin" d3160114
require_hex "$BUILD_DIR/flinger_sync_patch.bin" 6a000014
require_hex "$BUILD_DIR/usb_441_patch.bin" 44ac0000
require_hex "$BUILD_DIR/usb_3528_patch.bin" 20620500
require_hex "$BUILD_DIR/hifi_frame_count_cap_patch.bin" 087097521f00086b0030881a280380520008c81a09000014
require_hex "$BUILD_DIR/hifi_usecase_reconfigure_patch.bin" 092184522925c81a090200361f2003d5
"$LLVM_BIN/llvm-readelf" -r "$BUILD_DIR/native_hifi_select_hook.elf" \
    | grep -q 'There are no relocations'
"$LLVM_BIN/llvm-readelf" -r "$BUILD_DIR/usb_output_gate.elf" \
    | grep -q 'There are no relocations'
"$LLVM_BIN/llvm-readelf" -r "$BUILD_DIR/qti_hifi_hal_patches.elf" \
    | grep -q 'There are no relocations'
grep -a -q hifi_playback "$BUILD_DIR/native_hifi_cave.bin"
grep -a -q com.apple.android.music "$BUILD_DIR/native_hifi_cave.bin"
grep -a -q com.netease.cloudmusic "$BUILD_DIR/native_hifi_cave.bin"
"$LLVM_BIN/llvm-nm" -n "$BUILD_DIR/native_hifi_select_hook.elf" \
    | grep -q '^00000000000c3a8c .* latest_max_idle_rate$'
python3 "$ROOT_DIR/tests/native_hifi_select_model.py"
python3 "$ROOT_DIR/tests/usb_output_gate_model.py"

MODULE_STAGE="$BUILD_DIR/module"
mkdir -p "$MODULE_STAGE/patches" "$ROOT_DIR/dist"
cp -a "$ROOT_DIR/module/." "$MODULE_STAGE/"
cp "$BUILD_DIR"/*.bin "$MODULE_STAGE/patches/"

grep -q '^author=nateafish$' "$MODULE_STAGE/module.prop"
grep -q '^version=0.7.2-alpha$' "$MODULE_STAGE/module.prop"
grep -q 'EXPECTED_FINGERPRINT=' "$MODULE_STAGE/customize.sh"
grep -q 'require_elf64_aarch64' "$MODULE_STAGE/customize.sh"
grep -q 'Refusing an unsafe binary patch' "$MODULE_STAGE/customize.sh"
grep -q 'KernelSU requires an active metamodule' "$MODULE_STAGE/customize.sh"
[[ ! -e "$MODULE_STAGE/post-fs-data.sh" ]]
[[ ! -e "$MODULE_STAGE/service.sh" ]]
[[ ! -e "$MODULE_STAGE/zygisk" ]]
sh -n "$MODULE_STAGE/customize.sh"

chmod 0755 "$MODULE_STAGE/customize.sh"
chmod 0644 "$MODULE_STAGE/module.prop" "$MODULE_STAGE/README.txt" \
    "$MODULE_STAGE"/patches/*.bin
find "$MODULE_STAGE" -exec touch -t 202601010000 {} +

rm -f "$ROOT_DIR/dist/$OUTPUT_NAME" "$ROOT_DIR/dist/$OUTPUT_NAME.sha256"
(
    cd "$MODULE_STAGE"
    find . -type f -print | LC_ALL=C sort \
        | zip -X -q "$ROOT_DIR/dist/$OUTPUT_NAME" -@
)
(
    cd "$ROOT_DIR/dist"
    sha256sum "$OUTPUT_NAME" > "$OUTPUT_NAME.sha256"
)
unzip -t "$ROOT_DIR/dist/$OUTPUT_NAME"
cat "$ROOT_DIR/dist/$OUTPUT_NAME.sha256"
