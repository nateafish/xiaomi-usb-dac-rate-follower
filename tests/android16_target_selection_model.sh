#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/module/lib/install-state.sh"
source "$ROOT_DIR/module/lib/target-selection.sh"

TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rate-follower-a16-target.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
MANIFEST=$TEST_DIR/audio.xml
printf '%s\n' \
    '<manifest version="8.0" type="device">' \
    '  <hal format="aidl">' \
    '    <name>android.hardware.audio.core</name>' \
    '    <version>2</version>' \
    '    <fqname>IModule/default</fqname>' \
    '  </hal>' \
    '</manifest>' > "$MANIFEST"

list_vintf_device_manifests() {
    printf '%s\n' "$MANIFEST"
}

ui_print() {
    :
}

confirm_theoretical_installation() {
    :
}

getprop() {
    case "$1" in
        ro.system.build.version.release|ro.build.version.release) printf '16\n' ;;
        ro.system.build.version.sdk|ro.build.version.sdk) printf '36\n' ;;
        ro.product.device) printf '%s\n' "$TEST_DEVICE" ;;
        ro.soc.model) printf '%s\n' "$TEST_SOC" ;;
        ro.board.platform) printf '%s\n' "$TEST_BOARD" ;;
        ro.soc.manufacturer) printf 'QTI\n' ;;
        *) printf '\n' ;;
    esac
}

run_selection() (
    abort() {
        printf '%s\n' "$*" >&2
        exit 77
    }
    MODPATH=$ROOT_DIR
    select_audio_target
    printf '%s|%s|%s\n' "$BASELINE_ID" "$USB_PATH" "$BASELINE_PATCH_PROFILE"
)

TEST_DEVICE=dada TEST_SOC=SM8750 TEST_BOARD=sun
dada_result=$(run_selection)
[[ "$dada_result" == \
    'dada-sm8750-sun-aidl-v2|/vendor/lib64/libar-pal.so|policy-hifi-with-dada-worker-rate-handler' ]]

TEST_DEVICE=unknown TEST_SOC=SM8750 TEST_BOARD=sun
if run_selection >/dev/null 2>&1; then
    echo 'Android 16 target selection accepted an unrecorded AIDL v2 device' >&2
    exit 1
fi

TEST_DEVICE=dada TEST_SOC=SM8750 TEST_BOARD=canoe
if run_selection >/dev/null 2>&1; then
    echo 'Android 16 target selection accepted a Dada board mismatch' >&2
    exit 1
fi

sed -i.bak 's/<version>2<\/version>/<version>3<\/version>/' "$MANIFEST"
TEST_DEVICE=nezha TEST_SOC=SM8850 TEST_BOARD=canoe
nezha_result=$(run_selection)
[[ "$nezha_result" == \
    'nezha-sm8850-canoe-aidl-v3|/vendor/lib64/libdev_usb.so|native-hifi-usecase-guard' ]]

TEST_DEVICE=dada TEST_SOC=SM8750 TEST_BOARD=sun
if run_selection >/dev/null 2>&1; then
    echo 'Android 16 target selection accepted Dada with AIDL v3' >&2
    exit 1
fi

TEST_DEVICE=pandora TEST_SOC=SM8850 TEST_BOARD=canoe
pandora_result=$(run_selection)
[[ "$pandora_result" == \
    'pandora-sm8850-canoe-aidl-v3|/vendor/lib64/libdev_usb.so|policy-hifi-with-pointer-rate-handler' ]]

sed -i.bak 's/<version>3<\/version>/<version>1<\/version>/' "$MANIFEST"
TEST_DEVICE=dada TEST_SOC=SM8750 TEST_BOARD=sun
if run_selection >/dev/null 2>&1; then
    echo 'Android 16 target selection accepted unsupported AIDL v1' >&2
    exit 1
fi

echo 'Android 16 target-selection model: PASS'
