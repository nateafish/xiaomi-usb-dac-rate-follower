#!/system/bin/sh

MODDIR=${0%/*}

# KernelSU 3+ delegates system-file overlays to a metamodule. Keep the module
# self-contained when no metamodule exists. Magisk and KernelSU with an active
# metamodule use their normal systemless overlay path.
if { [ "${KSU:-}" = "true" ] || [ -x /data/adb/ksud ]; } \
        && [ ! -e /data/adb/metamodule ]; then
    "$MODDIR/mount-audio.sh" post-fs-data
fi
