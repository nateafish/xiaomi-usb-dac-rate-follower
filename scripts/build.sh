#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=0.8.4-alpha
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

bash "$ROOT_DIR/scripts/generate_player_packages.sh" \
    "$ROOT_DIR/config/player-packages.tsv" \
    "$BUILD_DIR/player_packages.inc"

require_size() {
    local file=$1 expected=$2 actual
    actual=$(wc -c < "$file")
    [[ "$actual" -eq "$expected" ]] || {
        echo "unexpected size for $file: $actual (expected $expected)" >&2
        exit 1
    }
}

"$CLANG" --target=aarch64-linux-android35 -c \
    -I "$BUILD_DIR" \
    "$ROOT_DIR/patches/native_hifi_select_hook.S" \
    -o "$BUILD_DIR/native_hifi_select_hook.o"
python3 "$ROOT_DIR/scripts/generate_relocation_manifest.py" \
    --readelf "$LLVM_BIN/llvm-readelf" \
    --object "$BUILD_DIR/native_hifi_select_hook.o" \
    --section .rela.native_hifi_cave \
    --prefix A17_NATIVE_HIFI \
    --output "$BUILD_DIR/a17_native_hifi_cave.relocations.conf" \
    --expect VENDOR_SELECT_OUTPUT_STUB=R_AARCH64_CALL26 \
    --expect SELECT_OUTPUT_RETURN=R_AARCH64_JUMP26 \
    --expect HIFI_APP_STOCK_CONTINUE=R_AARCH64_JUMP26 \
    --expect LATEST_MAX_RATE_EMPTY_RETURN=R_AARCH64_CONDBR19 \
    --expect LATEST_MAX_RATE_CONTINUE=R_AARCH64_JUMP26 \
    --expect LATEST_MAX_TRUE_RETURN=R_AARCH64_JUMP26 \
    --symbol native_hifi_select_hook \
    --symbol native_hifi_app_filter \
    --symbol native_hifi_usb_only_output \
    --symbol latest_max_idle_rate \
    --symbol latest_max_idle_transition
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .native_hifi_cave="$BUILD_DIR/native_hifi_cave.template.bin" \
    --dump-section .hifi_idle_rate_cave="$BUILD_DIR/hifi_idle_rate_cave.template.bin" \
    "$BUILD_DIR/native_hifi_select_hook.o"

"$CLANG" --target=aarch64-linux-android35 -c \
    "$ROOT_DIR/patches/hifi_dynamic_default.S" \
    -o "$BUILD_DIR/hifi_dynamic_default.o"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .hifi_dynamic_default_cave="$BUILD_DIR/hifi_dynamic_default_cave.template.bin" \
    "$BUILD_DIR/hifi_dynamic_default.o"

"$CLANG" --target=aarch64-linux-android35 -c \
    "$ROOT_DIR/patches/usb_output_gate.S" -o "$BUILD_DIR/usb_output_gate.o"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .usb_output_gate_cave="$BUILD_DIR/usb_output_gate_cave.template.bin" \
    --dump-section .usb_output_arbitration_cave="$BUILD_DIR/usb_output_arbitration_cave.template.bin" \
    "$BUILD_DIR/usb_output_gate.o"

"$CLANG" --target=aarch64-linux-android35 -c \
    -I "$BUILD_DIR" \
    "$ROOT_DIR/patches/android-16/native_hifi_route.S" \
    -o "$BUILD_DIR/a16_native_hifi_route.o"
python3 "$ROOT_DIR/scripts/generate_relocation_manifest.py" \
    --readelf "$LLVM_BIN/llvm-readelf" \
    --object "$BUILD_DIR/a16_native_hifi_route.o" \
    --section .rela.a16_native_hifi_route \
    --prefix A16_NATIVE_HIFI \
    --output "$BUILD_DIR/a16_native_hifi_route.relocations.conf" \
    --expect VENDOR_SELECT_OUTPUT_STUB=R_AARCH64_CALL26 \
    --expect SELECT_OUTPUT_RETURN=R_AARCH64_JUMP26
"$CLANG" --target=aarch64-linux-android35 -c \
    "$ROOT_DIR/patches/android-16/hifi_dynamic_default.S" \
    -o "$BUILD_DIR/a16_hifi_dynamic_default.o"
"$CLANG" --target=aarch64-linux-android35 -c \
    "$ROOT_DIR/patches/android-16/qti_hifi_reconfigure.S" \
    -o "$BUILD_DIR/a16_qti_hifi_reconfigure.o"
"$CLANG" --target=aarch64-linux-android35 -c \
    "$ROOT_DIR/patches/android-16/pudding_sampling_rate_handler.S" \
    -o "$BUILD_DIR/a16_pudding_sampling_rate_handler.o"
python3 "$ROOT_DIR/scripts/generate_relocation_manifest.py" \
    --readelf "$LLVM_BIN/llvm-readelf" \
    --object "$BUILD_DIR/a16_pudding_sampling_rate_handler.o" \
    --section .rela.a16_pudding_sampling_rate_handler \
    --prefix A16_POINTER_RATE \
    --output "$BUILD_DIR/a16_pointer_rate.relocations.conf" \
    --expect STR_PARMS_GET_STR=R_AARCH64_CALL26 \
    --expect ATOI=R_AARCH64_CALL26 \
    --expect MUTEX_LOCK=R_AARCH64_CALL26 \
    --expect PUDDING_STANDBY=R_AARCH64_CALL26 \
    --expect MUTEX_UNLOCK=R_AARCH64_CALL26 \
    --expect PUDDING_RATE_RETURN=R_AARCH64_JUMP26
"$CLANG" --target=aarch64-linux-android35 -c \
    -DA16_POINTER_LAYOUT_SHIFT=0x28 \
    "$ROOT_DIR/patches/android-16/pudding_sampling_rate_handler.S" \
    -o "$BUILD_DIR/a16_shifted_pointer_rate_handler.o"
python3 "$ROOT_DIR/scripts/generate_relocation_manifest.py" \
    --readelf "$LLVM_BIN/llvm-readelf" \
    --object "$BUILD_DIR/a16_shifted_pointer_rate_handler.o" \
    --section .rela.a16_pudding_sampling_rate_handler \
    --prefix A16_SHIFTED_POINTER_RATE \
    --output "$BUILD_DIR/a16_shifted_pointer_rate.relocations.conf" \
    --expect STR_PARMS_GET_STR=R_AARCH64_CALL26 \
    --expect ATOI=R_AARCH64_CALL26 \
    --expect MUTEX_LOCK=R_AARCH64_CALL26 \
    --expect PUDDING_STANDBY=R_AARCH64_CALL26 \
    --expect MUTEX_UNLOCK=R_AARCH64_CALL26 \
    --expect PUDDING_RATE_RETURN=R_AARCH64_JUMP26
"$CLANG" --target=aarch64-linux-android35 -c \
    "$ROOT_DIR/patches/android-16/dada_sampling_rate_handler.S" \
    -o "$BUILD_DIR/a16_dada_sampling_rate_handler.o"
python3 "$ROOT_DIR/scripts/generate_relocation_manifest.py" \
    --readelf "$LLVM_BIN/llvm-readelf" \
    --object "$BUILD_DIR/a16_dada_sampling_rate_handler.o" \
    --section .rela.a16_dada_rate_parameter \
    --prefix A16_DADA_RATE_PARAMETER \
    --output "$BUILD_DIR/a16_dada_rate_parameter.relocations.conf" \
    --expect DADA_STR_PARMS_GET_STR=R_AARCH64_CALL26 \
    --expect DADA_ATOI=R_AARCH64_CALL26 \
    --expect DADA_RATE_RETURN=R_AARCH64_JUMP26
python3 "$ROOT_DIR/scripts/generate_relocation_manifest.py" \
    --readelf "$LLVM_BIN/llvm-readelf" \
    --object "$BUILD_DIR/a16_dada_sampling_rate_handler.o" \
    --section .rela.a16_dada_rate_worker \
    --prefix A16_DADA_RATE_WORKER \
    --output "$BUILD_DIR/a16_dada_rate_worker.relocations.conf" \
    --expect DADA_STANDBY=R_AARCH64_CALL26 \
    --expect DADA_WORKER_RETURN=R_AARCH64_JUMP26
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .a16_native_hifi_route="$BUILD_DIR/a16_native_hifi_route.template.bin" \
    "$BUILD_DIR/a16_native_hifi_route.o"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .a16_hifi_dynamic_default="$BUILD_DIR/a16_hifi_dynamic_default.template.bin" \
    "$BUILD_DIR/a16_hifi_dynamic_default.o"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .a16_qti_hifi_reconfigure="$BUILD_DIR/a16_qti_hifi_reconfigure.template.bin" \
    "$BUILD_DIR/a16_qti_hifi_reconfigure.o"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .a16_pudding_sampling_rate_handler="$BUILD_DIR/a16_pudding_sampling_rate_handler.template.bin" \
    "$BUILD_DIR/a16_pudding_sampling_rate_handler.o"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .a16_pudding_sampling_rate_handler="$BUILD_DIR/a16_shifted_pointer_rate_handler.template.bin" \
    "$BUILD_DIR/a16_shifted_pointer_rate_handler.o"
"$LLVM_BIN/llvm-objcopy" \
    --dump-section .a16_dada_rate_parameter="$BUILD_DIR/a16_dada_rate_parameter.template.bin" \
    --dump-section .a16_dada_rate_worker="$BUILD_DIR/a16_dada_rate_worker.template.bin" \
    "$BUILD_DIR/a16_dada_sampling_rate_handler.o"

require_size "$BUILD_DIR/native_hifi_cave.template.bin" 788
require_size "$BUILD_DIR/hifi_idle_rate_cave.template.bin" 32
require_size "$BUILD_DIR/hifi_dynamic_default_cave.template.bin" 86
require_size "$BUILD_DIR/usb_output_gate_cave.template.bin" 140
require_size "$BUILD_DIR/usb_output_arbitration_cave.template.bin" 292
require_size "$BUILD_DIR/a16_native_hifi_route.template.bin" 640
require_size "$BUILD_DIR/a16_hifi_dynamic_default.template.bin" 86
require_size "$BUILD_DIR/a16_qti_hifi_reconfigure.template.bin" 16
require_size "$BUILD_DIR/a16_pudding_sampling_rate_handler.template.bin" 256
require_size "$BUILD_DIR/a16_shifted_pointer_rate_handler.template.bin" 256
require_size "$BUILD_DIR/a16_dada_rate_parameter.template.bin" 256
require_size "$BUILD_DIR/a16_dada_rate_worker.template.bin" 128
python3 "$ROOT_DIR/tests/dada_payload_binary_contract.py" \
    "$BUILD_DIR/a16_dada_rate_parameter.template.bin" \
    "$BUILD_DIR/a16_dada_rate_worker.template.bin"
python3 "$ROOT_DIR/tests/a16_pointer_rate_payload_contract.py" \
    "$BUILD_DIR/a16_pudding_sampling_rate_handler.template.bin" \
    "$BUILD_DIR/a16_pointer_rate.relocations.conf"
python3 "$ROOT_DIR/tests/a16_shifted_pointer_rate_payload_contract.py" \
    "$BUILD_DIR/a16_shifted_pointer_rate_handler.template.bin" \
    "$BUILD_DIR/a16_shifted_pointer_rate.relocations.conf"
grep -a -q hifi_playback "$BUILD_DIR/native_hifi_cave.template.bin"
grep -a -q com.apple.android.music "$BUILD_DIR/native_hifi_cave.template.bin"
grep -a -q com.netease.cloudmusic "$BUILD_DIR/native_hifi_cave.template.bin"
grep -a -q com.tencent.qqmusic "$BUILD_DIR/native_hifi_cave.template.bin"
grep -a -q com.spotify.music "$BUILD_DIR/native_hifi_cave.template.bin"
while IFS=$'\t' read -r player_package _; do
    [[ -n "$player_package" && ${player_package:0:1} != "#" ]] || continue
    grep -a -q "$player_package" "$BUILD_DIR/native_hifi_cave.template.bin"
    grep -a -q "$player_package" "$BUILD_DIR/a16_native_hifi_route.template.bin"
done < "$ROOT_DIR/config/player-packages.tsv"
python3 "$ROOT_DIR/tests/native_hifi_select_model.py"
python3 "$ROOT_DIR/tests/usb_output_gate_model.py"
python3 "$ROOT_DIR/tests/hifi_dynamic_default_model.py"
python3 "$ROOT_DIR/tests/hifi_idle_rate_model.py"
python3 "$ROOT_DIR/tests/dada_rate_handoff_model.py"
bash "$ROOT_DIR/tests/fresh_install_state_model.sh"
bash "$ROOT_DIR/tests/theoretical_confirmation_model.sh"
bash "$ROOT_DIR/tests/android16_target_selection_model.sh"

"${CXX:-c++}" -std=c++17 -O2 -Wall -Wextra -Werror \
    "$ROOT_DIR/tools/elfpatcher/main.cpp" -o "$BUILD_DIR/elfpatcher-host"

"$LLVM_BIN/clang++" --target=aarch64-linux-android35 -std=c++17 -Os \
    -fPIE -pie -static-libstdc++ "$ROOT_DIR/tools/elfpatcher/main.cpp" \
    -o "$BUILD_DIR/elfpatcher"
"$LLVM_BIN/llvm-strip" --strip-all "$BUILD_DIR/elfpatcher"
"$LLVM_BIN/llvm-readelf" -h "$BUILD_DIR/elfpatcher" \
    | grep 'Machine:.*AArch64' >/dev/null
"$LLVM_BIN/llvm-readelf" -d "$BUILD_DIR/elfpatcher" \
    | grep 'Shared library: \[libc.so\]' >/dev/null
"$BUILD_DIR/elfpatcher-host" info "$BUILD_DIR/elfpatcher" \
    | grep '^machine=aarch64$' >/dev/null

MODULE_STAGE="$BUILD_DIR/module"
mkdir -p "$MODULE_STAGE/patches" "$MODULE_STAGE/bin" \
    "$MODULE_STAGE/config" "$ROOT_DIR/dist"
cp -a "$ROOT_DIR/module/." "$MODULE_STAGE/"
cp "$ROOT_DIR/config/player-packages.tsv" "$MODULE_STAGE/config/"
cp "$BUILD_DIR"/*.template.bin "$MODULE_STAGE/patches/"
cp "$BUILD_DIR"/*.relocations.conf "$MODULE_STAGE/patches/"
cp "$BUILD_DIR/elfpatcher" "$MODULE_STAGE/bin/elfpatcher"
cp -a "$ROOT_DIR/targets" "$MODULE_STAGE/targets"

grep -q '^author=nateafish$' "$MODULE_STAGE/module.prop"
grep -q '^version=0.8.4-alpha$' "$MODULE_STAGE/module.prop"
grep -q '^TARGET_INSTALLABLE=1$' \
    "$MODULE_STAGE/targets/android-16/target.conf"
grep -q '^TARGET_VALIDATION_TYPE=theoretical$' \
    "$MODULE_STAGE/targets/android-16/target.conf"
grep -q '^TARGET_INSTALLABLE=1$' \
    "$MODULE_STAGE/targets/android-17/target.conf"
test -r "$MODULE_STAGE/targets/android-16/baselines/nezha-sm8850-canoe.conf"
test -r "$MODULE_STAGE/targets/android-16/baselines/dada-sm8750-sun.conf"
test -r "$MODULE_STAGE/targets/android-16/baselines/byron-sm8850-canoe.conf"
test -r "$MODULE_STAGE/targets/android-16/baselines/pandora-sm8850-canoe.conf"
test -r "$MODULE_STAGE/targets/android-16/baselines/myron-sm8850-canoe.conf"
test -r "$MODULE_STAGE/targets/android-17/baselines/nezha-sm8850-canoe.conf"
grep -q 'patch_source_for' "$MODULE_STAGE/customize.sh"
grep -q 'In-place upgrades are intentionally unsupported' \
    "$MODULE_STAGE/lib/install-state.sh"
grep -q 'confirm_theoretical_installation' \
    "$MODULE_STAGE/lib/target-selection.sh"
grep -q 'select_audio_target' "$MODULE_STAGE/customize.sh"
grep -q 'runtime AArch64 relocation' "$MODULE_STAGE/customize.sh"
grep -q 'KernelSU requires an active metamodule' "$MODULE_STAGE/customize.sh"
[[ ! -e "$MODULE_STAGE/post-fs-data.sh" ]]
[[ ! -e "$MODULE_STAGE/service.sh" ]]
[[ ! -e "$MODULE_STAGE/zygisk" ]]
sh -n "$MODULE_STAGE/customize.sh"
sh -n "$MODULE_STAGE/lib/install-state.sh"
sh -n "$MODULE_STAGE/lib/target-selection.sh"
sh -n "$MODULE_STAGE/lib/elf-runtime.sh"
sh -n "$MODULE_STAGE/lib/apply-android-16.sh"
sh -n "$MODULE_STAGE/lib/apply-android-17.sh"

chmod 0755 "$MODULE_STAGE/customize.sh" "$MODULE_STAGE/bin/elfpatcher"
chmod 0644 "$MODULE_STAGE/module.prop" "$MODULE_STAGE/README.txt" \
    "$MODULE_STAGE/config/player-packages.tsv" \
    "$MODULE_STAGE/lib"/*.sh "$MODULE_STAGE"/patches/*.bin \
    "$MODULE_STAGE"/patches/*.conf \
    "$MODULE_STAGE/targets"/*.md "$MODULE_STAGE/targets"/*/*.conf \
    "$MODULE_STAGE/targets"/*/usecases/*.conf \
    "$MODULE_STAGE/targets"/*/baselines/*.conf
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

if [[ -n ${ANDROID16_AUDIO_ROOT:-} ]]; then
    validation_args=(
        16 "$ANDROID16_AUDIO_ROOT" "$ROOT_DIR/dist/$OUTPUT_NAME"
        "$BUILD_DIR/elfpatcher-host"
    )
    if [[ -n ${ANDROID16_BASELINE:-} ]]; then
        validation_args+=("$ANDROID16_BASELINE")
    fi
    bash "$ROOT_DIR/scripts/validate_offline_target.sh" \
        "${validation_args[@]}"
fi
