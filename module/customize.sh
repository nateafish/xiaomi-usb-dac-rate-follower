#!/system/bin/sh

EXPECTED_SHA256=d36085dbf0e4f7979ee6b94540b216d949d0f74ab0cda385fdfd5cfc8cd0c296
PATCHED_SHA256=04cb4f2a7f4f4247995eb098b7d9a6ba8aeb6ff131144e87a6730d8a9ee4dad6
TARGET_LIB=/vendor/lib64/libdev_usb.so

ui_print "- Checking Xiaomi 17 Qualcomm USB audio library"

if [ "$(getprop ro.build.version.sdk)" != "37" ]; then
    abort "! Android 17 / SDK 37 is required"
fi
if [ ! -r "$TARGET_LIB" ]; then
    abort "! $TARGET_LIB is missing; this firmware is unsupported"
fi

actual_sha256=$(sha256sum "$TARGET_LIB" 2>/dev/null | awk '{print $1}')
case "$actual_sha256" in
    "$EXPECTED_SHA256"|"$PATCHED_SHA256") ;;
    *)
        ui_print "! Expected stock: $EXPECTED_SHA256"
        ui_print "! Found:          $actual_sha256"
        abort "! Firmware mismatch; refusing to install the USB capability patch"
        ;;
esac

set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/mount-audio.sh" 0 0 0755
set_perm "$MODPATH/system/vendor/lib64/libdev_usb.so" 0 0 0644
set_perm "$MODPATH/zygisk/arm64-v8a.so" 0 0 0644

ui_print "- Exposes USB rates: 44.1/48/88.2/96/176.4/192/384 kHz"
ui_print "- Enables Android's dynamic hifi_playback BitPerfectThread"
ui_print "- Hooks AudioTrack creation only in Apple Music and NetEase Cloud Music"
ui_print "- No audio-policy binary patch, polling daemon, or live audioserver restart"
if [ "${KSU:-}" = "true" ] || [ -x /data/adb/ksud ]; then
    ui_print "! KernelSU requires Zygisk Next (or another compatible Zygisk provider)"
fi
ui_print "! Experimental: review the documented recovery steps before enabling"
