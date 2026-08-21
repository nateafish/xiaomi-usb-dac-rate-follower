#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=0.2.0-poc
OUTPUT_NAME="xiaomi17-bitperfect-v${VERSION}.zip"
PATCHED_LIB_SHA256=04cb4f2a7f4f4247995eb098b7d9a6ba8aeb6ff131144e87a6730d8a9ee4dad6

if [[ -z "${ANDROID_HOME:-}" ]]; then
    echo "ANDROID_HOME is not set" >&2
    exit 1
fi

D8_BIN="$ANDROID_HOME/build-tools/37.0.0/d8"
if [[ ! -x "$D8_BIN" ]]; then
    sdkmanager "build-tools;37.0.0" >/dev/null
fi

BUILD_DIR=$(mktemp -d "${RUNNER_TEMP:-/tmp}/xiaomi17-bitperfect.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT

MODULE_STAGE="$BUILD_DIR/module"
CLASS_DIR="$BUILD_DIR/classes"
DEX_DIR="$BUILD_DIR/dex"
mkdir -p "$MODULE_STAGE" "$CLASS_DIR" "$DEX_DIR" "$ROOT_DIR/dist"
cp -a "$ROOT_DIR/module/." "$MODULE_STAGE/"

javac --release 8 -d "$CLASS_DIR" "$ROOT_DIR/daemon/BitPerfectDaemon.java"
jar cf "$BUILD_DIR/BitPerfectDaemon.jar" -C "$CLASS_DIR" .
"$D8_BIN" --min-api 35 --output "$DEX_DIR" "$BUILD_DIR/BitPerfectDaemon.jar"
install -m 0644 "$DEX_DIR/classes.dex" "$MODULE_STAGE/bitperfect-daemon.dex"

actual_lib_sha256=$(sha256sum "$MODULE_STAGE/system/vendor/lib64/libdev_usb.so" | awk '{print $1}')
if [[ "$actual_lib_sha256" != "$PATCHED_LIB_SHA256" ]]; then
    echo "Patched libdev_usb.so checksum mismatch: $actual_lib_sha256" >&2
    exit 1
fi

grep -q 'name="hifi_playback" role="source" flags="BIT_PERFECT"' \
    "$MODULE_STAGE/system/odm/etc/audio/audio_module_config_primary.xml"
grep -q 'name="hifi_playback" role="source" flags="BIT_PERFECT"' \
    "$MODULE_STAGE/system/vendor/etc/audio/audio_module_config_primary.xml"

chmod 0755 "$MODULE_STAGE/customize.sh" "$MODULE_STAGE/service.sh"
chmod 0644 "$MODULE_STAGE/bitperfect-daemon.dex" \
    "$MODULE_STAGE/system/vendor/lib64/libdev_usb.so"

rm -f "$ROOT_DIR/dist/$OUTPUT_NAME" "$ROOT_DIR/dist/$OUTPUT_NAME.sha256"
(
    cd "$MODULE_STAGE"
    zip -X -q -r "$ROOT_DIR/dist/$OUTPUT_NAME" .
)

sha256sum "$ROOT_DIR/dist/$OUTPUT_NAME" > "$ROOT_DIR/dist/$OUTPUT_NAME.sha256"
unzip -t "$ROOT_DIR/dist/$OUTPUT_NAME"
cat "$ROOT_DIR/dist/$OUTPUT_NAME.sha256"
