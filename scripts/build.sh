#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=0.5.0-alpha
OUTPUT_NAME="xiaomi-usb-dac-rate-follower-v${VERSION}.zip"
PATCHED_LIB_SHA256=04cb4f2a7f4f4247995eb098b7d9a6ba8aeb6ff131144e87a6730d8a9ee4dad6

find_ndk_build() {
    local candidate
    for candidate in \
        "${ANDROID_NDK_HOME:-}/ndk-build" \
        "${ANDROID_NDK_ROOT:-}/ndk-build"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
        candidate=$(find "$ANDROID_SDK_ROOT/ndk" -maxdepth 2 -type f -name ndk-build 2>/dev/null \
            | sort -V | tail -n 1)
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi
    return 1
}

NDK_BUILD=$(find_ndk_build) || {
    echo "Android NDK not found; set ANDROID_NDK_HOME or ANDROID_NDK_ROOT" >&2
    exit 1
}

BUILD_DIR=$(mktemp -d "${RUNNER_TEMP:-/tmp}/xiaomi-usb-rate-follower.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT

NATIVE_OBJ="$BUILD_DIR/native-obj"
NATIVE_LIBS="$BUILD_DIR/native-libs"
"$NDK_BUILD" -C "$ROOT_DIR/native/rate_follower" \
    NDK_PROJECT_PATH=. \
    APP_BUILD_SCRIPT=Android.mk \
    NDK_APPLICATION_MK=Application.mk \
    NDK_OUT="$NATIVE_OBJ" \
    NDK_LIBS_OUT="$NATIVE_LIBS"

MODULE_STAGE="$BUILD_DIR/module"
mkdir -p "$MODULE_STAGE" "$ROOT_DIR/dist"
cp -a "$ROOT_DIR/module/." "$MODULE_STAGE/"
mkdir -p "$MODULE_STAGE/zygisk"
cp "$NATIVE_LIBS/arm64-v8a/librate_follower.so" \
    "$MODULE_STAGE/zygisk/arm64-v8a.so"

actual_lib_sha256=$(sha256sum "$MODULE_STAGE/system/vendor/lib64/libdev_usb.so" | awk '{print $1}')
if [[ "$actual_lib_sha256" != "$PATCHED_LIB_SHA256" ]]; then
    echo "Patched libdev_usb.so checksum mismatch: $actual_lib_sha256" >&2
    exit 1
fi

grep -q 'name="hifi_playback" role="source" flags="BIT_PERFECT"' \
    "$MODULE_STAGE/system/odm/etc/audio/audio_module_config_primary.xml"
grep -q 'name="hifi_playback" role="source" flags="BIT_PERFECT"' \
    "$MODULE_STAGE/system/vendor/etc/audio/audio_module_config_primary.xml"
grep -A4 'name="deep_buffer_out"' \
    "$MODULE_STAGE/system/odm/etc/audio/audio_module_config_primary.xml" \
    | grep -q 'samplingRates="48000"'
grep -A4 'name="deep_buffer_out"' \
    "$MODULE_STAGE/system/vendor/etc/audio/audio_module_config_primary.xml" \
    | grep -q 'samplingRates="48000"'

grep -q '^author=nateafish$' "$MODULE_STAGE/module.prop"
grep -q '^version=0.5.0-alpha$' "$MODULE_STAGE/module.prop"
[[ ! -e "$MODULE_STAGE/service.sh" ]]
[[ ! -e "$MODULE_STAGE/bin/set-audio-parameters" ]]
[[ ! -e "$MODULE_STAGE/system/lib64/libaudiopolicymanagerdefault.so" ]]
[[ -s "$MODULE_STAGE/zygisk/arm64-v8a.so" ]]
file "$MODULE_STAGE/zygisk/arm64-v8a.so" | grep -q 'ARM aarch64'
grep -a -q 'native_setup' "$MODULE_STAGE/zygisk/arm64-v8a.so"
grep -a -q 'com.apple.android.music' "$MODULE_STAGE/zygisk/arm64-v8a.so"
grep -a -q 'com.netease.cloudmusic' "$MODULE_STAGE/zygisk/arm64-v8a.so"

chmod 0755 "$MODULE_STAGE/customize.sh" \
    "$MODULE_STAGE/post-fs-data.sh" "$MODULE_STAGE/mount-audio.sh"
chmod 0644 "$MODULE_STAGE/system/vendor/lib64/libdev_usb.so" \
    "$MODULE_STAGE/zygisk/arm64-v8a.so"

# ZIP stores file modification times even with -X. Normalize the staged tree so
# identical source and NDK inputs produce an identical release artifact.
find "$MODULE_STAGE" -exec touch -t 202601010000 {} +

rm -f "$ROOT_DIR/dist/$OUTPUT_NAME" "$ROOT_DIR/dist/$OUTPUT_NAME.sha256"
(
    cd "$MODULE_STAGE"
    zip -X -q -r "$ROOT_DIR/dist/$OUTPUT_NAME" .
)

(
    cd "$ROOT_DIR/dist"
    sha256sum "$OUTPUT_NAME" > "$OUTPUT_NAME.sha256"
)
unzip -t "$ROOT_DIR/dist/$OUTPUT_NAME"
cat "$ROOT_DIR/dist/$OUTPUT_NAME.sha256"
