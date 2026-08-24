#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 7 ]]; then
    echo "usage: $0 POLICY FLINGER USB HAL COMPONENTS IMPL MODULE_ZIP" >&2
    exit 2
fi

POLICY_STOCK=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
FLINGER_STOCK=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
USB_STOCK=$(cd "$(dirname "$3")" && pwd)/$(basename "$3")
HAL_STOCK=$(cd "$(dirname "$4")" && pwd)/$(basename "$4")
COMPONENTS_STOCK=$(cd "$(dirname "$5")" && pwd)/$(basename "$5")
IMPL_STOCK=$(cd "$(dirname "$6")" && pwd)/$(basename "$6")
MODULE_ZIP=$(cd "$(dirname "$7")" && pwd)/$(basename "$7")
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/xiaomi-usb-installer.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

prepare_module() {
    local destination=$1 policy=$2 flinger=$3 usb=$4 hal=$5
    mkdir -p "$destination"
    unzip -q "$MODULE_ZIP" -d "$destination"
    sed \
        -e "s|^POLICY_SOURCE=.*|POLICY_SOURCE='$policy'|" \
        -e "s|^COMPONENTS_SOURCE=.*|COMPONENTS_SOURCE='$COMPONENTS_STOCK'|" \
        -e "s|^IMPL_SOURCE=.*|IMPL_SOURCE='$IMPL_STOCK'|" \
        -e "s|^FLINGER_SOURCE=.*|FLINGER_SOURCE='$flinger'|" \
        -e "s|^USB_SOURCE=.*|USB_SOURCE='$usb'|" \
        -e "s|^HAL_SOURCE=.*|HAL_SOURCE='$hal'|" \
        "$destination/customize.sh" > "$destination/customize.host.sh"
}

run_installer() {
    local module_path=$1
    MODPATH="$module_path" KSU=false bash -c '
        set -e
        ui_print() { printf "%s\n" "$*"; }
        abort() { printf "%s\n" "$*" >&2; exit 1; }
        set_perm() { :; }
        getprop() {
            case "$1" in
                ro.build.version.sdk) printf "%s\n" 37 ;;
                ro.build.fingerprint)
                    printf "%s\n" "Xiaomi/nezha/nezha:17/CP2A.260605.016/OS4.0.0.15.XPACNXM:user/release-keys"
                    ;;
            esac
        }
        stat() {
            if [ "$1" = -c ]; then
                /usr/bin/stat -f "%z" "$3"
            else
                /usr/bin/stat "$@"
            fi
        }
        . "$1"
    ' _ "$module_path/customize.host.sh"
}

FIRST="$TEST_ROOT/first"
prepare_module "$FIRST" "$POLICY_STOCK" "$FLINGER_STOCK" "$USB_STOCK" "$HAL_STOCK"
run_installer "$FIRST"
[[ ! -e "$FIRST/patches" ]]

PATCHED_POLICY="$FIRST/system/lib64/libaudiopolicymanagerdefault.so"
PATCHED_FLINGER="$FIRST/system/lib64/libaudioflinger.so"
PATCHED_USB="$FIRST/system/vendor/lib64/libdev_usb.so"
PATCHED_HAL="$FIRST/system/vendor/lib64/hw/libaudiocorehal.qti.so"
for output in "$PATCHED_POLICY" "$PATCHED_FLINGER" "$PATCHED_USB" "$PATCHED_HAL"; do
    [[ -s "$output" ]]
done

echo "host installer simulation: clean stock installation passed"
