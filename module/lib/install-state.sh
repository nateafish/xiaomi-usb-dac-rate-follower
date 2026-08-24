#!/system/bin/sh

RATE_FOLLOWER_MODULE_ID=xiaomi-usb-dac-rate-follower
RATE_FOLLOWER_ACTIVE_DIR=/data/adb/modules/$RATE_FOLLOWER_MODULE_ID

list_vintf_device_manifests() {
    find /vendor/etc/vintf /odm/etc/vintf /system/etc/vintf \
        /system_ext/etc/vintf /product/etc/vintf \
        -type f -name '*.xml' ! -name '*compatibility_matrix*' \
        2>/dev/null
}

detect_audio_hal_generation() {
    aidl_seen=0
    hidl_seen=0
    for audio_manifest in $(list_vintf_device_manifests); do
        if grep -q 'format="aidl"' "$audio_manifest" 2>/dev/null \
                && grep -q 'android.hardware.audio.core' \
                    "$audio_manifest" 2>/dev/null; then
            aidl_seen=1
        fi
        if grep -q 'format="hidl"' "$audio_manifest" 2>/dev/null \
                && grep -q 'android.hardware.audio@' \
                    "$audio_manifest" 2>/dev/null; then
            hidl_seen=1
        fi
    done
    case "$aidl_seen:$hidl_seen" in
        1:0) echo aidl ;;
        0:1) echo hidl ;;
        1:1) echo mixed ;;
        *) echo unknown ;;
    esac
}

write_system_identity() {
    destination=$1
    {
        echo "schema=2"
        echo "sdk=$(getprop ro.build.version.sdk)"
        echo "release=$(getprop ro.build.version.release)"
        echo "device=$(getprop ro.product.device)"
        echo "odm_device=$(getprop ro.product.odm.device)"
        echo "board_platform=$(getprop ro.board.platform)"
        echo "soc_manufacturer=$(getprop ro.soc.manufacturer)"
        echo "soc_model=$(getprop ro.soc.model)"
        echo "boot_hardware=$(getprop ro.boot.hardware)"
        echo "hal_generation=$(detect_audio_hal_generation)"
        echo "system_incremental=$(getprop ro.system.build.version.incremental)"
        echo "vendor_incremental=$(getprop ro.vendor.build.version.incremental)"
        echo "odm_incremental=$(getprop ro.odm.build.version.incremental)"
        echo "product_incremental=$(getprop ro.product.build.version.incremental)"
        echo "build_id=$(getprop ro.build.id)"
        echo "fingerprint=$(getprop ro.build.fingerprint)"
    } > "$destination"
}

require_fresh_install_state() {
    [ ! -f "$RATE_FOLLOWER_ACTIVE_DIR/module.prop" ] && return 0

    installed_version=$(sed -n 's/^version=//p' \
        "$RATE_FOLLOWER_ACTIVE_DIR/module.prop" 2>/dev/null | head -n 1)
    ui_print "! Installed module detected: ${installed_version:-unknown version}"
    ui_print "! In-place upgrades are intentionally unsupported"
    ui_print "! Delete the existing module, reboot, then install this build"
    abort "! Refusing to patch an active or residual module payload"
    return 1
}

prepare_install_state() {
    require_fresh_install_state || return 1

    mkdir -p "$MODPATH/state" \
        || abort "! Cannot create module state directory"
    current_identity=$MODPATH/state/system.conf
    write_system_identity "$current_identity" \
        || abort "! Cannot record the current system identity"
    ui_print "- Fresh installation: using the unmodified system view"
}

patch_source_for() {
    live_path=$1
    [ -r "$live_path" ] || return 1
    echo "$live_path"
}
