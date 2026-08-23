#!/system/bin/sh

RATE_FOLLOWER_MODULE_ID=xiaomi-usb-dac-rate-follower
RATE_FOLLOWER_ACTIVE_DIR=/data/adb/modules/$RATE_FOLLOWER_MODULE_ID
RATE_FOLLOWER_ACTIVE_IMAGE_DIR=/data/adb/metamodule/mnt/$RATE_FOLLOWER_MODULE_ID
RATE_FOLLOWER_IS_UPGRADE=0
RATE_FOLLOWER_FIRMWARE_CHANGED=0
RATE_FOLLOWER_MAGISK_MIRROR=

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

identity_value() {
    identity_file=$1
    identity_key=$2
    sed -n "s/^${identity_key}=//p" "$identity_file" 2>/dev/null | head -n 1
}

same_system_identity() {
    previous=$1
    current=$2
    changed=
    for identity_key in sdk release device odm_device board_platform \
            soc_manufacturer soc_model boot_hardware hal_generation \
            system_incremental vendor_incremental odm_incremental \
            product_incremental; do
        old_value=$(identity_value "$previous" "$identity_key")
        new_value=$(identity_value "$current" "$identity_key")
        if [ "$old_value" != "$new_value" ]; then
            changed="$changed $identity_key"
        fi
    done
    [ -z "$changed" ] && return 0
    ui_print "! Changed system identity fields:$changed"
    return 1
}

same_android_target_identity() {
    previous=$1
    current=$2
    old_release=$(identity_value "$previous" release)
    new_release=$(identity_value "$current" release)
    old_major=${old_release%%.*}
    new_major=${new_release%%.*}
    [ -n "$old_major" ] && [ "$old_major" = "$new_major" ] || {
        ui_print "! Android major version changed: ${old_major:-unknown} -> ${new_major:-unknown}"
        return 1
    }
    changed=
    for identity_key in sdk device odm_device board_platform soc_manufacturer \
            soc_model boot_hardware hal_generation; do
        old_value=$(identity_value "$previous" "$identity_key")
        new_value=$(identity_value "$current" "$identity_key")
        if [ "$old_value" != "$new_value" ]; then
            changed="$changed $identity_key"
        fi
    done
    [ -z "$changed" ] && return 0
    ui_print "! Changed target identity fields:$changed"
    return 1
}

find_magisk_mirror() {
    command -v magisk >/dev/null 2>&1 || return 1
    magisk_tmp=$(magisk --path 2>/dev/null)
    [ -n "$magisk_tmp" ] || return 1
    mirror=$magisk_tmp/.magisk/mirror
    [ -d "$mirror" ] || return 1
    RATE_FOLLOWER_MAGISK_MIRROR=$mirror
    return 0
}

prepare_upgrade_state() {
    mkdir -p "$MODPATH/state" \
        || abort "! Cannot create module state directory"
    current_identity=$MODPATH/state/system.conf
    write_system_identity "$current_identity" \
        || abort "! Cannot record the current system identity"

    find_magisk_mirror || true

    old_identity=$RATE_FOLLOWER_ACTIVE_DIR/state/system.conf
    if [ ! -f "$RATE_FOLLOWER_ACTIVE_DIR/module.prop" ]; then
        ui_print "- Fresh installation: using the unmodified system view"
        return
    fi

    if [ ! -r "$old_identity" ]; then
        ui_print "! The installed module predates system-identity tracking"
        ui_print "! The existing module has not been disabled or overwritten"
        ui_print "! Uninstall it, reboot, then install this build again"
        abort "! Refusing an unverifiable in-place upgrade"
    fi

    if ! same_android_target_identity "$old_identity" "$current_identity"; then
        ui_print "! The existing module has not been disabled or overwritten"
        abort "! Cross-version or cross-target in-place upgrade is blocked"
    fi

    if ! same_system_identity "$old_identity" "$current_identity"; then
        RATE_FOLLOWER_FIRMWARE_CHANGED=1
        ui_print "! WARNING: system partitions changed within the same Android version"
        ui_print "! The module remains enabled; all ELF checks will run again"
    fi

    RATE_FOLLOWER_IS_UPGRADE=1
    if [ -n "$RATE_FOLLOWER_MAGISK_MIRROR" ]; then
        ui_print "- Upgrade source: Magisk stock partition mirror"
    else
        ui_print "- Upgrade source: active module payload"
    fi
}

active_payload_file() {
    live_path=$1
    relative_path=${live_path#/}
    case "$live_path" in
        /vendor/*|/odm/*|/product/*|/system_ext/*)
            partition=${relative_path%%/*}
            within_partition=${relative_path#*/}
            for active_root in "$RATE_FOLLOWER_ACTIVE_IMAGE_DIR" \
                    "$RATE_FOLLOWER_ACTIVE_DIR"; do
                candidate=$active_root/$partition/$within_partition
                [ -r "$candidate" ] && {
                    echo "$candidate"
                    return 0
                }
                candidate=$active_root/system/$partition/$within_partition
                [ -r "$candidate" ] && {
                    echo "$candidate"
                    return 0
                }
            done
            ;;
        /system/*)
            within_partition=${live_path#/system/}
            for active_root in "$RATE_FOLLOWER_ACTIVE_IMAGE_DIR" \
                    "$RATE_FOLLOWER_ACTIVE_DIR"; do
                candidate=$active_root/system/$within_partition
                [ -r "$candidate" ] && {
                    echo "$candidate"
                    return 0
                }
            done
            ;;
    esac
    return 1
}

patch_source_for() {
    live_path=$1

    if [ -n "$RATE_FOLLOWER_MAGISK_MIRROR" ]; then
        mirrored=$RATE_FOLLOWER_MAGISK_MIRROR/${live_path#/}
        [ -r "$mirrored" ] && {
            echo "$mirrored"
            return 0
        }
    fi

    if [ "$RATE_FOLLOWER_IS_UPGRADE" = 1 ]; then
        previous=$(active_payload_file "$live_path") && {
            echo "$previous"
            return 0
        }
    fi

    [ -r "$live_path" ] || return 1
    echo "$live_path"
}
