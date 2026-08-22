#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=0.3.1-alpha
OUTPUT_NAME="xiaomi17-bitperfect-v${VERSION}.zip"
PATCHED_LIB_SHA256=04cb4f2a7f4f4247995eb098b7d9a6ba8aeb6ff131144e87a6730d8a9ee4dad6
HELPER_SHA256=e830886ad9f321d9893d58297e8560be6b2ccd74f1b7dfff2919c0baaa24f491

BUILD_DIR=$(mktemp -d "${RUNNER_TEMP:-/tmp}/xiaomi17-bitperfect.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT

MODULE_STAGE="$BUILD_DIR/module"
mkdir -p "$MODULE_STAGE" "$ROOT_DIR/dist"
cp -a "$ROOT_DIR/module/." "$MODULE_STAGE/"

actual_lib_sha256=$(sha256sum "$MODULE_STAGE/system/vendor/lib64/libdev_usb.so" | awk '{print $1}')
if [[ "$actual_lib_sha256" != "$PATCHED_LIB_SHA256" ]]; then
    echo "Patched libdev_usb.so checksum mismatch: $actual_lib_sha256" >&2
    exit 1
fi

grep -A5 'name="deep_buffer_out"' \
    "$MODULE_STAGE/system/odm/etc/audio/audio_module_config_primary.xml" \
    | grep -q 'samplingRates="44100 48000"'
grep -A7 'name="deep_buffer_out"' \
    "$MODULE_STAGE/system/vendor/etc/audio/audio_module_config_primary.xml" \
    | grep -q 'samplingRates="44100 48000"'
grep -q 'name="hifi_playback" role="source" flags="BIT_PERFECT"' \
    "$MODULE_STAGE/system/odm/etc/audio/audio_module_config_primary.xml"
grep -q 'name="hifi_playback" role="source" flags="BIT_PERFECT"' \
    "$MODULE_STAGE/system/vendor/etc/audio/audio_module_config_primary.xml"

grep -q '^author=nateafish$' "$MODULE_STAGE/module.prop"
grep -q '^version=0.3.1-alpha$' "$MODULE_STAGE/module.prop"
grep -q '^com.apple.android.music$' "$MODULE_STAGE/config/packages.list"
grep -q '^com.netease.cloudmusic$' "$MODULE_STAGE/config/packages.list"
actual_helper_sha256=$(sha256sum "$MODULE_STAGE/bin/set-audio-parameters" | awk '{print $1}')
if [[ "$actual_helper_sha256" != "$HELPER_SHA256" ]]; then
    echo "set-audio-parameters checksum mismatch: $actual_helper_sha256" >&2
    exit 1
fi

chmod 0755 "$MODULE_STAGE/customize.sh" "$MODULE_STAGE/service.sh" \
    "$MODULE_STAGE/post-fs-data.sh" "$MODULE_STAGE/mount-audio.sh" \
    "$MODULE_STAGE/bin/set-audio-parameters"
chmod 0644 "$MODULE_STAGE/system/vendor/lib64/libdev_usb.so" \
    "$MODULE_STAGE/config/packages.list"

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
