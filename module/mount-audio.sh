#!/system/bin/sh

MODDIR=${0%/*}
LOGDIR=/data/adb/xiaomi17-bitperfect
LOGFILE=$LOGDIR/mount.log
PATCHED_SHA256=04cb4f2a7f4f4247995eb098b7d9a6ba8aeb6ff131144e87a6730d8a9ee4dad6

mkdir -p "$LOGDIR"
chmod 0700 "$LOGDIR"

log_mount() {
    echo "[mount] $*" >> "$LOGFILE"
}

VENDOR_ROOT=$MODDIR/system/vendor
ODM_ROOT=$MODDIR/system/odm
[ -d "$MODDIR/vendor" ] && VENDOR_ROOT=$MODDIR/vendor
[ -d "$MODDIR/odm" ] && ODM_ROOT=$MODDIR/odm

bind_one() {
    source_file=$1
    target_file=$2
    source_context=$3

    if [ ! -r "$source_file" ] || [ ! -e "$target_file" ]; then
        log_mount "missing source or target: $source_file -> $target_file"
        return 1
    fi
    if cmp -s "$source_file" "$target_file"; then
        log_mount "already active: $target_file"
        return 0
    fi

    chcon "$source_context" "$source_file" || return 1
    mount -o bind "$source_file" "$target_file" || return 1
    log_mount "bound: $source_file -> $target_file"
}

log_mount "stage=${1:-unknown} KSU=${KSU:-unset}"

bind_one "$VENDOR_ROOT/lib64/libdev_usb.so" \
    /vendor/lib64/libdev_usb.so u:object_r:vendor_file:s0 || exit 1
bind_one "$VENDOR_ROOT/etc/audio/audio_module_config_primary.xml" \
    /vendor/etc/audio/audio_module_config_primary.xml \
    u:object_r:vendor_configs_file:s0 || exit 1
bind_one "$ODM_ROOT/etc/audio/audio_module_config_primary.xml" \
    /odm/etc/audio/audio_module_config_primary.xml \
    u:object_r:vendor_configs_file:s0 || exit 1

actual_sha256=$(sha256sum /vendor/lib64/libdev_usb.so 2>/dev/null | awk '{print $1}')
if [ "$actual_sha256" != "$PATCHED_SHA256" ]; then
    log_mount "verification failed: libdev_usb.so sha256=$actual_sha256"
    exit 1
fi
if ! grep -A4 'name="deep_buffer_out"' \
        /odm/etc/audio/audio_module_config_primary.xml | grep -q '44100 48000'; then
    log_mount "verification failed: ODM deep_buffer_out 44.1 kHz profile missing"
    exit 1
fi

log_mount "verification passed"
