#!/system/bin/sh

MODDIR=${0%/*}

# Xiaomi ships ro.vendor.audio.hifi.config=13. Bit 0x2 is the gate used by
# FeatureManager::isFeatureEnable(8), which creates the deep_buffer_out
# HifiSampleRateManager profile during AudioPolicyManager initialization.
current_hifi=$(getprop ro.vendor.audio.hifi.config)
case "$current_hifi" in
    ''|*[!0-9]*) target_hifi=15 ;;
    *) target_hifi=$((current_hifi | 2)) ;;
esac

if command -v resetprop >/dev/null 2>&1; then
    resetprop ro.vendor.audio.hifi.config "$target_hifi"
elif [ -x /data/adb/ksu/bin/resetprop ]; then
    /data/adb/ksu/bin/resetprop ro.vendor.audio.hifi.config "$target_hifi"
fi

# KernelSU 3+ delegates system file mounting to a metamodule. Keep the module
# self-contained when no metamodule is installed. Magisk and KernelSU devices
# with an active metamodule keep using their native systemless mount path.
if { [ "${KSU:-}" = "true" ] || [ -x /data/adb/ksud ]; } \
        && [ ! -e /data/adb/metamodule ]; then
    "$MODDIR/mount-audio.sh" post-fs-data
fi
