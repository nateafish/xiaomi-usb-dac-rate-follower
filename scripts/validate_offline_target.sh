#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 || $# -gt 5 ]]; then
    echo "usage: $0 ANDROID_MAJOR EXTRACTED_ROOT MODULE_ZIP HOST_ELFPATCHER [BASELINE_CONF]" >&2
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
if [[ -n ${5:-} ]]; then
    BASELINE_SOURCE=$5
    if [[ ! -r "$BASELINE_SOURCE" ]]; then
        BASELINE_SOURCE=$ROOT_DIR/targets/android-$ANDROID_MAJOR/baselines/$5
    fi
    [[ -r "$BASELINE_SOURCE" ]] || {
        echo "missing baseline manifest: $5" >&2
        exit 1
    }
    source "$BASELINE_SOURCE"
    USB_PATH=${BASELINE_USB_PATH:-$USB_PATH}
    CORE_HAL_PATH=${BASELINE_CORE_HAL_PATH:-$CORE_HAL_PATH}
fi
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rate-follower-target.XXXXXX")
if [[ ${KEEP_WORK:-0} != 1 ]]; then
    trap 'rm -rf "$WORK_DIR"' EXIT
fi

MODPATH=$WORK_DIR/module
TARGET_DIR=$MODPATH/targets/android-$ANDROID_MAJOR
mkdir -p "$MODPATH" "$WORK_DIR/work"
unzip -q "$MODULE_ZIP" -d "$MODPATH"

copy_target() {
    local source_path=$1 destination=$2 resolved
    resolved=$(resolve_extracted_path "$source_path") || {
        echo "missing extracted file: $EXTRACTED_ROOT$source_path" >&2
        exit 1
    }
    cp -p "$resolved" "$destination"
}

resolve_extracted_path() {
    local source_path=$1 candidate
    for candidate in "$EXTRACTED_ROOT$source_path" \
            "$EXTRACTED_ROOT/system$source_path"; do
        if [[ -r "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

POLICY_DEST=$WORK_DIR/work/policy.so
FLINGER_DEST=$WORK_DIR/work/flinger.so
USB_DEST=$WORK_DIR/work/usb.so
HAL_DEST=$WORK_DIR/work/hal.so
COMPONENTS_SOURCE=$(resolve_extracted_path "$COMPONENTS_PATH") || {
    echo "missing policy components under $EXTRACTED_ROOT" >&2
    exit 1
}
IMPL_SOURCE=$(resolve_extracted_path "$POLICY_IMPL_PATH") || {
    echo "missing policy implementation under $EXTRACTED_ROOT" >&2
    exit 1
}
ELFPATCHER=$HOST_ELFPATCHER

copy_target "$POLICY_PATH" "$POLICY_DEST"
copy_target "$FLINGER_PATH" "$FLINGER_DEST"
copy_target "$USB_PATH" "$USB_DEST"
copy_target "$CORE_HAL_PATH" "$HAL_DEST"
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

if [[ ${HAL_PATCH_KIND:-} == dada-worker-rate-handler ]]; then
    mixed_hal=$WORK_DIR/work/hal-mixed.so
    cp -p "$HAL_DEST" "$mixed_hal"
    "$ELFPATCHER" branch "$mixed_hal" "$DADA_WORKER_SITE" \
        "$((DADA_WORKER_SITE + 4))" B
    if (
        HAL_DEST=$mixed_hal
        apply_target_patches
    ) >/dev/null 2>&1; then
        echo "Dada mixed hook state was not rejected" >&2
        exit 1
    fi
elif [[ ${HAL_PATCH_KIND:-} == a16-pointer-rate-handler \
        || ${HAL_PATCH_KIND:-} == a16-shifted-pointer-rate-handler ]]; then
    mixed_hal=$WORK_DIR/work/hal-mixed.so
    cp -p "$HAL_DEST" "$mixed_hal"
    "$ELFPATCHER" branch "$mixed_hal" "$PUDDING_RATE_SITE" \
        "$((PUDDING_RATE_SITE + 4))" B
    if (
        HAL_DEST=$mixed_hal
        apply_target_patches
    ) >/dev/null 2>&1; then
        echo "Android 16 mixed pointer-rate hook state was not rejected" >&2
        exit 1
    fi
elif [[ ${HAL_PATCH_KIND:-} == nezha-usecase-guard ]]; then
    mixed_hal=$WORK_DIR/work/hal-mixed.so
    cp -p "$HAL_DEST" "$mixed_hal"
    "$ELFPATCHER" branch "$mixed_hal" "$QTI_SITE" \
        "$((QTI_SITE + 4))" B
    if (
        HAL_DEST=$mixed_hal
        apply_target_patches
    ) >/dev/null 2>&1; then
        echo "Android 16 mixed Qualcomm guard state was not rejected" >&2
        exit 1
    fi
fi

echo "offline target validation: PASS ($TARGET_ID${BASELINE_ID:+ / $BASELINE_ID})"
echo "$second_hashes"
if [[ ${KEEP_WORK:-0} == 1 ]]; then
    echo "kept patched files at: $WORK_DIR"
fi
