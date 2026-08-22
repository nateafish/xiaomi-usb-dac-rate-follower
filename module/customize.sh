#!/system/bin/sh

EXPECTED_FINGERPRINT='Xiaomi/nezha/nezha:17/CP2A.260605.016/OS4.0.0.15.XPACNXM:user/release-keys'
POLICY_STOCK_SHA256=e0bd4444461df3608f2baa05d4f5db22d0d5ddfb23cabb36474ff5f5c22da3cb
POLICY_PREVIOUS_SHA256=44d6d59dd395c2a5dfee6d3cf2c2f1a485377633a9e6d3b78754cc2b1b3f92c3
POLICY_PATCHED_SHA256=34916265a7375e87db57125e3e603702a07335aed5f320ad61c58fa9c757b1b6
FLINGER_STOCK_SHA256=d499d92e115dac7ee8e7e5dcbd53079e6a61ffccbe6d34481f239813e1f3695f
FLINGER_PATCHED_SHA256=66ce065150b8d1e7cb056a7fbc6040563c9e8ef87c3068dd40dc5e876d9e95e6
USB_STOCK_SHA256=d36085dbf0e4f7979ee6b94540b216d949d0f74ab0cda385fdfd5cfc8cd0c296
USB_PATCHED_SHA256=04cb4f2a7f4f4247995eb098b7d9a6ba8aeb6ff131144e87a6730d8a9ee4dad6
POLICY_SOURCE=/system/lib64/libaudiopolicymanagerdefault.so
FLINGER_SOURCE=/system/lib64/libaudioflinger.so
USB_SOURCE=/vendor/lib64/libdev_usb.so
POLICY_DEST=$MODPATH/system/lib64/libaudiopolicymanagerdefault.so
FLINGER_DEST=$MODPATH/system/lib64/libaudioflinger.so
if [ "${KSU:-}" = "true" ] || [ -x /data/adb/ksud ]; then
    USB_DEST=$MODPATH/vendor/lib64/libdev_usb.so
else
    USB_DEST=$MODPATH/system/vendor/lib64/libdev_usb.so
fi

ui_print "- Checking Xiaomi 17 Ultra Android 17 firmware"

if [ "$(getprop ro.build.version.sdk)" != "37" ]; then
    abort "! Android 17 / SDK 37 is required"
fi
if [ "$(getprop ro.build.fingerprint)" != "$EXPECTED_FINGERPRINT" ]; then
    abort "! Exact OS4.0.0.15.XPACNXM firmware is required"
fi
if { [ "${KSU:-}" = "true" ] || [ -x /data/adb/ksud ]; } \
        && [ ! -L /data/adb/metamodule ]; then
    abort "! KernelSU requires an active metamodule (meta-overlayfs recommended)"
fi

sha_of() {
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

require_known_source() {
    source_file=$1
    stock_sha=$2
    patched_sha=$3
    actual_sha=$(sha_of "$source_file")
    case "$actual_sha" in
        "$stock_sha"|"$patched_sha") ;;
        *)
            ui_print "! Unsupported library: $source_file"
            ui_print "! Found SHA-256: $actual_sha"
            abort "! Refusing to patch mismatched firmware"
            ;;
    esac
}

require_known_policy() {
    actual_sha=$(sha_of "$POLICY_SOURCE")
    case "$actual_sha" in
        "$POLICY_STOCK_SHA256"|"$POLICY_PREVIOUS_SHA256"|"$POLICY_PATCHED_SHA256") ;;
        *)
            ui_print "! Unsupported library: $POLICY_SOURCE"
            ui_print "! Found SHA-256: $actual_sha"
            abort "! Refusing to patch mismatched firmware"
            ;;
    esac
}

write_patch() {
    patch_file=$1
    target_file=$2
    target_offset=$3
    dd if="$patch_file" of="$target_file" bs=1 seek="$target_offset" conv=notrunc 2>/dev/null \
        || abort "! Failed to patch $target_file at $target_offset"
}

require_known_policy
require_known_source "$FLINGER_SOURCE" "$FLINGER_STOCK_SHA256" "$FLINGER_PATCHED_SHA256"
require_known_source "$USB_SOURCE" "$USB_STOCK_SHA256" "$USB_PATCHED_SHA256"

mkdir -p "$MODPATH/system/lib64" || abort "! Cannot create system overlay"
mkdir -p "${USB_DEST%/*}" || abort "! Cannot create vendor overlay"
cp -p "$POLICY_SOURCE" "$POLICY_DEST" || abort "! Cannot stage AudioPolicyManager"
cp -p "$FLINGER_SOURCE" "$FLINGER_DEST" || abort "! Cannot stage AudioFlinger"
cp -p "$USB_SOURCE" "$USB_DEST" || abort "! Cannot stage Qualcomm USB library"

if [ "$(sha_of "$POLICY_DEST")" = "$POLICY_STOCK_SHA256" ]; then
    write_patch "$MODPATH/patches/is_app_allowed_hook.bin" "$POLICY_DEST" 867276
    write_patch "$MODPATH/patches/latest_max_patch.bin" "$POLICY_DEST" 869060
fi
if [ "$(sha_of "$POLICY_DEST")" = "$POLICY_PREVIOUS_SHA256" ]; then
    write_patch "$MODPATH/patches/effect_gate_patch.bin" "$POLICY_DEST" 873908
fi
if [ "$(sha_of "$FLINGER_DEST")" = "$FLINGER_STOCK_SHA256" ]; then
    write_patch "$MODPATH/patches/flinger_sync_patch.bin" "$FLINGER_DEST" 1772164
fi
if [ "$(sha_of "$USB_DEST")" = "$USB_STOCK_SHA256" ]; then
    write_patch "$MODPATH/patches/usb_441_patch.bin" "$USB_DEST" 29024
    write_patch "$MODPATH/patches/usb_3528_patch.bin" "$USB_DEST" 29052
fi

[ "$(sha_of "$POLICY_DEST")" = "$POLICY_PATCHED_SHA256" ] \
    || abort "! Patched AudioPolicyManager checksum failed"
[ "$(sha_of "$FLINGER_DEST")" = "$FLINGER_PATCHED_SHA256" ] \
    || abort "! Patched AudioFlinger checksum failed"
[ "$(sha_of "$USB_DEST")" = "$USB_PATCHED_SHA256" ] \
    || abort "! Patched Qualcomm USB checksum failed"

rm -rf "$MODPATH/patches"
set_perm "$POLICY_DEST" 0 0 0644 u:object_r:system_lib_file:s0
set_perm "$FLINGER_DEST" 0 0 0644 u:object_r:system_lib_file:s0
set_perm "$USB_DEST" 0 0 0644 u:object_r:vendor_file:s0

ui_print "- Whitelist: Apple Music and NetEase Cloud Music only"
ui_print "- Strategy: Xiaomi LATEST_MAX across overlapping song tracks"
ui_print "- USB deep-buffer: ignore the false global Dolby/MiSound gate, then apply the whitelist"
ui_print "- Mixer: synchronize in place for 44.1/48/88.2/96/192 kHz changes"
ui_print "- USB capability: 44.1 kHz is inside Qualcomm's seven-rate list"
ui_print "- PCM32 remains the HAL/mixer format; no Float HAL claim"
ui_print "- No daemon, Zygisk, XML edit, preferred-mixer writer, or live restart"
ui_print "- System overlay is delegated to Magisk or the active KernelSU metamodule"
ui_print "! Experimental and exact-firmware-only; reboot is required"
