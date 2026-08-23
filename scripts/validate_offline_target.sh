#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
    echo "usage: $0 ANDROID_MAJOR EXTRACTED_ROOT MODULE_ZIP HOST_ELFPATCHER" >&2
    exit 2
fi

ANDROID_MAJOR=$1
EXTRACTED_ROOT=${2%/}
MODULE_ZIP=$3
HOST_ELFPATCHER=$4
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TARGET_SOURCE=$ROOT_DIR/targets/android-$ANDROID_MAJOR/target.conf

[[ -r "$TARGET_SOURCE" ]] || {
    echo "missing target manifest: $TARGET_SOURCE" >&2
    exit 1
}
[[ -r "$MODULE_ZIP" ]] || {
    echo "missing module ZIP: $MODULE_ZIP" >&2
    exit 1
}
[[ -x "$HOST_ELFPATCHER" ]] || {
    echo "host elfpatcher is not executable: $HOST_ELFPATCHER" >&2
    exit 1
}

source "$TARGET_SOURCE"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rate-follower-target.XXXXXX")
if [[ ${KEEP_WORK:-0} != 1 ]]; then
    trap 'rm -rf "$WORK_DIR"' EXIT
fi

MODPATH=$WORK_DIR/module
TARGET_DIR=$MODPATH/targets/android-$ANDROID_MAJOR
mkdir -p "$MODPATH" "$WORK_DIR/work"
unzip -q "$MODULE_ZIP" -d "$MODPATH"

copy_target() {
    local source_path=$1 destination=$2
    [[ -r "$EXTRACTED_ROOT$source_path" ]] || {
        echo "missing extracted file: $EXTRACTED_ROOT$source_path" >&2
        exit 1
    }
    cp -p "$EXTRACTED_ROOT$source_path" "$destination"
}

POLICY_DEST=$WORK_DIR/work/policy.so
FLINGER_DEST=$WORK_DIR/work/flinger.so
USB_DEST=$WORK_DIR/work/usb.so
HAL_DEST=$WORK_DIR/work/hal.so
COMPONENTS_SOURCE=$EXTRACTED_ROOT$COMPONENTS_PATH
IMPL_SOURCE=$EXTRACTED_ROOT$POLICY_IMPL_PATH
ELFPATCHER=$HOST_ELFPATCHER

copy_target "$POLICY_PATH" "$POLICY_DEST"
copy_target "$FLINGER_PATH" "$FLINGER_DEST"
copy_target "$USB_PATH" "$USB_DEST"
copy_target "$CORE_HAL_PATH" "$HAL_DEST"
[[ -r "$COMPONENTS_SOURCE" && -r "$IMPL_SOURCE" ]] || {
    echo "missing policy layout libraries under $EXTRACTED_ROOT" >&2
    exit 1
}

ui_print() {
    echo "$*"
}

abort() {
    echo "ABORT: $*" >&2
    exit 1
}

PATCH_DRIVER=$MODPATH/lib/$TARGET_PATCH_DRIVER
source "$PATCH_DRIVER"
apply_target_patches
first_hashes=$(sha256sum "$WORK_DIR/work"/*.so)
apply_target_patches
second_hashes=$(sha256sum "$WORK_DIR/work"/*.so)
[[ "$first_hashes" == "$second_hashes" ]] || {
    echo "target patching is not idempotent" >&2
    exit 1
}

echo "offline target validation: PASS ($TARGET_ID)"
echo "$second_hashes"
if [[ ${KEEP_WORK:-0} == 1 ]]; then
    echo "kept patched files at: $WORK_DIR"
fi
