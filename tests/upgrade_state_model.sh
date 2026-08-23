#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/module/lib/upgrade-state.sh"

ui_print() {
    :
}

fail() {
    echo "upgrade-state test failed: $*" >&2
    exit 1
}

assert_equal() {
    [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"
}

TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rate-follower-upgrade.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

cat > "$TEST_DIR/old.conf" <<'EOF'
schema=1
sdk=37
release=17
device=nezha
odm_device=nezha
board_platform=canoe
soc_manufacturer=QTI
soc_model=SM8850
boot_hardware=qcom
hal_generation=aidl
system_incremental=system-a
vendor_incremental=vendor-a
odm_incremental=odm-a
product_incremental=product-a
EOF
cp "$TEST_DIR/old.conf" "$TEST_DIR/current.conf"
sed -i.bak 's/^schema=1$/schema=2/' "$TEST_DIR/current.conf"
rm -f "$TEST_DIR/current.conf.bak"
same_system_identity "$TEST_DIR/old.conf" "$TEST_DIR/current.conf" \
    || fail "schema-only changes must remain compatible"

cp "$TEST_DIR/current.conf" "$TEST_DIR/changed.conf"
sed -i.bak 's/^vendor_incremental=vendor-a$/vendor_incremental=vendor-b/' \
    "$TEST_DIR/changed.conf"
rm -f "$TEST_DIR/changed.conf.bak"
if same_system_identity "$TEST_DIR/old.conf" "$TEST_DIR/changed.conf"; then
    fail "a vendor partition update must not be treated as the same system"
fi

RATE_FOLLOWER_ACTIVE_DIR=$TEST_DIR/modules/$RATE_FOLLOWER_MODULE_ID
RATE_FOLLOWER_ACTIVE_IMAGE_DIR=$TEST_DIR/image/$RATE_FOLLOWER_MODULE_ID
mkdir -p "$RATE_FOLLOWER_ACTIVE_DIR/system/lib64"
mkdir -p "$RATE_FOLLOWER_ACTIVE_IMAGE_DIR/vendor/lib64"
printf active-policy > \
    "$RATE_FOLLOWER_ACTIVE_DIR/system/lib64/libaudiopolicymanagerdefault.so"
printf active-usb > "$RATE_FOLLOWER_ACTIVE_IMAGE_DIR/vendor/lib64/libdev_usb.so"

assert_equal \
    "$(active_payload_file /system/lib64/libaudiopolicymanagerdefault.so)" \
    "$RATE_FOLLOWER_ACTIVE_DIR/system/lib64/libaudiopolicymanagerdefault.so"
assert_equal "$(active_payload_file /vendor/lib64/libdev_usb.so)" \
    "$RATE_FOLLOWER_ACTIVE_IMAGE_DIR/vendor/lib64/libdev_usb.so"

RATE_FOLLOWER_IS_UPGRADE=1
RATE_FOLLOWER_MAGISK_MIRROR=
assert_equal "$(patch_source_for /vendor/lib64/libdev_usb.so)" \
    "$RATE_FOLLOWER_ACTIVE_IMAGE_DIR/vendor/lib64/libdev_usb.so"

RATE_FOLLOWER_MAGISK_MIRROR=$TEST_DIR/mirror
mkdir -p "$RATE_FOLLOWER_MAGISK_MIRROR/vendor/lib64"
printf stock-usb > "$RATE_FOLLOWER_MAGISK_MIRROR/vendor/lib64/libdev_usb.so"
assert_equal "$(patch_source_for /vendor/lib64/libdev_usb.so)" \
    "$RATE_FOLLOWER_MAGISK_MIRROR/vendor/lib64/libdev_usb.so"

echo "upgrade-state model: PASS"
