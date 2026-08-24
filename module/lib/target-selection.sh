#!/system/bin/sh

prop_first() {
    for prop_name in "$@"; do
        prop_value=$(getprop "$prop_name")
        [ -n "$prop_value" ] && {
            echo "$prop_value"
            return 0
        }
    done
    return 1
}

is_qualcomm_platform() {
    manufacturer=$(getprop ro.soc.manufacturer)
    hardware=$(getprop ro.boot.hardware)
    platform=$(getprop ro.board.platform)
    case "$manufacturer:$hardware:$platform" in
        QTI:*:*|Qualcomm:*:*|*:qcom:*|*:*:canoe|*:*:kalama|*:*:pineapple|*:*:sun) return 0 ;;
    esac
    grep -R -q 'vendor/qcom\|libaudiocorehal\.qti\|audiohalservice\.qti' \
        /vendor/etc/vintf /odm/etc/vintf /vendor/etc/init /odm/etc/init \
        2>/dev/null
}

detect_audio_core_aidl_major() {
    for manifest in $(list_vintf_device_manifests); do
        grep -q 'android.hardware.audio.core' "$manifest" 2>/dev/null \
            || continue
        awk '
            /<name>[[:space:]]*android.hardware.audio.core[[:space:]]*<\/name>/ {
                audio_core = 1
            }
            audio_core && /<version>[[:space:]]*[0-9]+[[:space:]]*<\/version>/ {
                value = $0
                sub(/^.*<version>[[:space:]]*/, "", value)
                sub(/[[:space:]]*<\/version>.*$/, "", value)
                print value
                exit
            }
        ' "$manifest"
    done | sort -n | tail -n 1
}

confirm_theoretical_installation() {
    ui_print "! WARNING: this target has not been tested on hardware"
    ui_print "! OTA extraction, semantic patching and idempotence were verified"
    ui_print "! Audio stability and strict bit-perfect output are not confirmed"
    command -v getevent >/dev/null 2>&1 \
        || abort "! Cannot read a hardware key for confirmation"
    ui_print "- Press either volume key to acknowledge and continue"
    while true; do
        confirmation_event=$(getevent -qlc 1 2>/dev/null) \
            || abort "! Failed to read the confirmation key"
        case "$confirmation_event" in
            *KEY_VOLUMEUP*|*KEY_VOLUMEDOWN*) break ;;
        esac
    done
    ui_print "- Theoretical-target warning acknowledged"
}

select_audio_target() {
    compatibility_file=$MODPATH/targets/common/compatibility.conf
    [ -r "$compatibility_file" ] \
        || abort "! Missing common compatibility policy"
    . "$compatibility_file" \
        || abort "! Cannot load common compatibility policy"

    android_release=$(prop_first ro.system.build.version.release \
        ro.build.version.release) || abort "! Cannot detect Android release"
    android_major=${android_release%%.*}
    TARGET_DIR=$MODPATH/targets/android-$android_major
    [ -r "$TARGET_DIR/target.conf" ] \
        || abort "! No target manifest for Android $android_major"
    . "$TARGET_DIR/target.conf" \
        || abort "! Cannot load the Android $android_major target manifest"

    android_sdk=$(prop_first ro.system.build.version.sdk \
        ro.build.version.sdk) || abort "! Cannot detect Android SDK"
    [ "$android_sdk" = "$TARGET_ANDROID_SDK" ] \
        || abort "! Android SDK does not match $TARGET_ID"
    case "${COMPAT_REQUIRE_PLATFORM:-qualcomm}:$TARGET_PLATFORM_FAMILY" in
        qualcomm:qualcomm)
            is_qualcomm_platform \
                || abort "! $TARGET_ID requires a Qualcomm audio platform"
            ;;
        *) abort "! Unsupported target platform policy" ;;
    esac
    actual_hal=$(detect_audio_hal_generation)
    [ "$actual_hal" = "$TARGET_HAL_GENERATION" ] \
        || abort "! Audio HAL generation is $actual_hal, expected $TARGET_HAL_GENERATION"

    if [ "$actual_hal" = aidl ]; then
        actual_aidl_major=$(detect_audio_core_aidl_major)
        supported_aidl_majors=${TARGET_SUPPORTED_AIDL_CORE_MAJORS:-${TARGET_REQUIRED_AIDL_CORE_MAJOR:-}}
        aidl_major_supported=0
        for supported_aidl_major in $supported_aidl_majors; do
            [ "$actual_aidl_major" = "$supported_aidl_major" ] \
                && aidl_major_supported=1
        done
        [ "$aidl_major_supported" = 1 ] \
            || abort "! Audio Core AIDL is v${actual_aidl_major:-unknown}, supported: ${supported_aidl_majors:-none}"
    fi

    device=$(getprop ro.product.device)
    soc=$(getprop ro.soc.model)
    board=$(getprop ro.board.platform)
    TARGET_DEVICE_VERIFIED=0
    matched_baseline=
    baseline_directory=$TARGET_DIR/${TARGET_BASELINE_DIR:-baselines}
    for baseline_file in "$baseline_directory"/*.conf; do
        [ -r "$baseline_file" ] || continue
        if (
            unset BASELINE_DEVICE BASELINE_SOC_MODEL BASELINE_BOARD_PLATFORM
            . "$baseline_file" || exit 1
            [ "$device" = "$BASELINE_DEVICE" ] \
                && [ "$soc" = "$BASELINE_SOC_MODEL" ] \
                && [ "$board" = "$BASELINE_BOARD_PLATFORM" ]
        ); then
            [ -z "$matched_baseline" ] \
                || abort "! Multiple recorded device baselines matched"
            matched_baseline=$baseline_file
        fi
    done
    if [ -n "$matched_baseline" ]; then
        . "$matched_baseline" || abort "! Cannot load recorded device baseline"
        [ "$BASELINE_HAL_GENERATION" = "$actual_hal" ] \
            || abort "! Recorded baseline HAL generation is inconsistent"
        if [ "$actual_hal" = aidl ]; then
            [ "$BASELINE_AUDIO_CORE_MAJOR" = "$actual_aidl_major" ] \
                || abort "! Recorded baseline Audio Core version is inconsistent"
        fi
        TARGET_DEVICE_VERIFIED=1
        ui_print "- Recorded device baseline: $BASELINE_ID"
        ui_print "- Device tuple: $device / $soc / $board"
        if [ "${BASELINE_INSTALLABLE:-0}" != 1 ]; then
            ui_print "! Baseline status: ${BASELINE_STATUS:-unknown}"
            ui_print "! Patch profile: ${BASELINE_PATCH_PROFILE:-not-enabled}"
            abort "! $BASELINE_ID is retained for research, not installation"
        fi
    else
        for recorded_aidl_major in ${TARGET_REQUIRE_RECORDED_AIDL_CORE_MAJORS:-}; do
            if [ "$actual_hal" = aidl ] \
                    && [ "$actual_aidl_major" = "$recorded_aidl_major" ]; then
                abort "! Audio Core AIDL v$actual_aidl_major requires an exact recorded device baseline"
            fi
        done
        [ "${COMPAT_ALLOW_UNVERIFIED:-0}" = 1 ] \
            || abort "! This device/SoC tuple is not enabled"
        ui_print "! WARNING: this device/SoC tuple has not been tested"
        ui_print "! Detected: ${device:-unknown} / ${soc:-unknown} / ${board:-unknown}"
        ui_print "! Installation continues only after every semantic ELF check passes"
        ui_print "! Confirm USB DAC rates and audio stability yourself after reboot"
    fi

    # A recorded device may move vendor implementations without changing the
    # common Android target.  Apply only explicit per-baseline path overrides.
    USB_PATH=${BASELINE_USB_PATH:-$USB_PATH}
    CORE_HAL_PATH=${BASELINE_CORE_HAL_PATH:-$CORE_HAL_PATH}

    if [ "${TARGET_INSTALLABLE:-0}" != 1 ]; then
        ui_print "! Target status: ${TARGET_STATUS:-unknown}"
        ui_print "! Its use cases are retained for offline porting, not device installation"
        abort "! $TARGET_ID is not enabled for installation yet"
    fi
    validation_type=${BASELINE_VALIDATION_TYPE:-${TARGET_VALIDATION_TYPE:-}}
    case "$validation_type" in
        hardware) ;;
        theoretical|'') confirm_theoretical_installation ;;
        *) abort "! Unknown target validation type: $validation_type" ;;
    esac
    ui_print "- Selected target: $TARGET_ID (${TARGET_STATUS:-unknown})"
}

overlay_destination_for() {
    source_path=$1
    if [ "${KSU:-}" = true ] || [ -x /data/adb/ksud ]; then
        echo "$MODPATH$source_path"
        return
    fi
    case "$source_path" in
        /system/*) echo "$MODPATH/system/${source_path#/system/}" ;;
        /*) echo "$MODPATH/system$source_path" ;;
        *) return 1 ;;
    esac
}
