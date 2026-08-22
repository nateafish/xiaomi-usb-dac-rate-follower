#!/system/bin/sh

EXPECTED_FINGERPRINT='Xiaomi/nezha/nezha:17/CP2A.260605.016/OS4.0.0.15.XPACNXM:user/release-keys'
POLICY_STOCK_SHA256=e0bd4444461df3608f2baa05d4f5db22d0d5ddfb23cabb36474ff5f5c22da3cb
POLICY_PREVIOUS_SHA256=44d6d59dd395c2a5dfee6d3cf2c2f1a485377633a9e6d3b78754cc2b1b3f92c3
POLICY_INTERIM_SHA256=34916265a7375e87db57125e3e603702a07335aed5f320ad61c58fa9c757b1b6
POLICY_V062_SHA256=5be0a369ec73ce27d531aa58de84b4cd292518dbdb92f9568d65340d853ba72a
POLICY_PATCHED_SHA256=0e92c652c81fbfbc7e0e0ce9aa2f01f957df0c58b7c660df694d895c57fabaa4
FLINGER_STOCK_SHA256=d499d92e115dac7ee8e7e5dcbd53079e6a61ffccbe6d34481f239813e1f3695f
FLINGER_PATCHED_SHA256=66ce065150b8d1e7cb056a7fbc6040563c9e8ef87c3068dd40dc5e876d9e95e6
USB_STOCK_SHA256=d36085dbf0e4f7979ee6b94540b216d949d0f74ab0cda385fdfd5cfc8cd0c296
USB_PATCHED_SHA256=04cb4f2a7f4f4247995eb098b7d9a6ba8aeb6ff131144e87a6730d8a9ee4dad6
POLICY_MIN_SIZE=873924
FLINGER_MIN_SIZE=1772180
USB_MIN_SIZE=29056
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

read_hex() {
    dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null \
        | od -An -tx1 | tr -d ' \n'
}

require_hex() {
    file=$1
    offset=$2
    count=$3
    expected=$4
    label=$5
    actual=$(read_hex "$file" "$offset" "$count")
    [ "$actual" = "$expected" ] || {
        ui_print "! Signature mismatch: $label"
        ui_print "! Offset $offset expected $expected"
        ui_print "! Found $actual"
        abort "! Refusing an unsafe binary patch"
    }
}

require_one_of_hex() {
    file=$1
    offset=$2
    count=$3
    allowed=$4
    label=$5
    actual=$(read_hex "$file" "$offset" "$count")
    case " $allowed " in
        *" $actual "*) ;;
        *)
            ui_print "! Unknown instruction state: $label"
            ui_print "! Offset $offset found $actual"
            abort "! Refusing a partial or incompatible patch state"
            ;;
    esac
}

require_elf64_aarch64() {
    file=$1
    minimum_size=$2
    label=$3
    [ -r "$file" ] || abort "! Missing readable $label: $file"
    actual_size=$(stat -c '%s' "$file" 2>/dev/null)
    [ "$actual_size" -ge "$minimum_size" ] || {
        ui_print "! Truncated $label: $actual_size bytes (minimum $minimum_size)"
        abort "! Target manifest does not match this binary"
    }
    require_hex "$file" 0 20 \
        7f454c460201010000000000000000000300b700 "$label ELF64/AArch64 header"
}

require_binary_string() {
    file=$1
    pattern=$2
    label=$3
    grep -a -q "$pattern" "$file" 2>/dev/null \
        || abort "! Missing semantic marker in $label: $pattern"
}

report_known_hash() {
    file=$1
    label=$2
    actual=$(sha_of "$file")
    case "$actual" in
        "$POLICY_STOCK_SHA256"|"$POLICY_PREVIOUS_SHA256"|"$POLICY_INTERIM_SHA256"|"$POLICY_V062_SHA256"|"$POLICY_PATCHED_SHA256"|"$FLINGER_STOCK_SHA256"|"$FLINGER_PATCHED_SHA256"|"$USB_STOCK_SHA256"|"$USB_PATCHED_SHA256")
            ui_print "- $label hash is a known reference state"
            ;;
        *)
            ui_print "- $label hash differs, structural signatures will decide"
            ui_print "  SHA-256: $actual"
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

require_elf64_aarch64 "$POLICY_SOURCE" "$POLICY_MIN_SIZE" AudioPolicyManager
require_elf64_aarch64 "$FLINGER_SOURCE" "$FLINGER_MIN_SIZE" AudioFlinger
require_elf64_aarch64 "$USB_SOURCE" "$USB_MIN_SIZE" Qualcomm-USB
POLICY_ORIGINAL_SIZE=$(stat -c '%s' "$POLICY_SOURCE")
FLINGER_ORIGINAL_SIZE=$(stat -c '%s' "$FLINGER_SOURCE")
USB_ORIGINAL_SIZE=$(stat -c '%s' "$USB_SOURCE")

require_binary_string "$POLICY_SOURCE" deep_buffer_out AudioPolicyManager
require_binary_string "$POLICY_SOURCE" HifiSampleRateManager: AudioPolicyManager
require_binary_string "$FLINGER_SOURCE" readOutputParameters_l AudioFlinger
require_binary_string "$USB_SOURCE" readSupportedSampleRate Qualcomm-USB

# Validate stable instruction context around every target before considering
# the mutable four-byte instruction itself.
require_hex "$POLICY_SOURCE" 799320 8 00018052f7590094 'profile-init pre-context'
require_hex "$POLICY_SOURCE" 799332 12 739e42f9e0faffd0003c1491 'profile-init post-context'
require_hex "$POLICY_SOURCE" 867268 8 c0035fd657c2fd97 'app-hook pre-context'
require_hex "$POLICY_SOURCE" 867472 8 25c2fd973f2303d5 'app-hook post-context'
require_hex "$POLICY_SOURCE" 869052 8 e8ff00a9aa1efe97 'strategy pre-context'
require_hex "$POLICY_SOURCE" 869064 12 e0830091e2230091e103162a 'strategy post-context'
require_hex "$POLICY_SOURCE" 873900 8 685a41b91f090071 'effect-gate pre-context'
require_hex "$POLICY_SOURCE" 873912 12 42fafff042541c9160008052 'effect-gate post-context'
require_hex "$FLINGER_SOURCE" 1772156 8 097097521f01096b 'Mixer sync pre-context'
require_hex "$FLINGER_SOURCE" 1772168 12 000180520fa9029460020036 'Mixer sync post-context'

require_one_of_hex "$POLICY_SOURCE" 799328 4 '00050036 1f2003d5' 'profile initialization'
require_one_of_hex "$POLICY_SOURCE" 867300 12 \
    '480000d0088944f9165d40a9 2800403988000037097d0153' 'application hook'
require_one_of_hex "$POLICY_SOURCE" 869060 4 '030b40b9 e3031f2a' 'profile strategy'
require_one_of_hex "$POLICY_SOURCE" 873908 4 \
    '60010054 0b000014 62010054' 'effect-state gate'
require_one_of_hex "$FLINGER_SOURCE" 1772164 4 '480d0054 6a000014' 'Mixer synchronization'
require_one_of_hex "$USB_SOURCE" 29024 4 '20620500 44ac0000' 'USB rate slot 1'
require_one_of_hex "$USB_SOURCE" 29052 4 '44ac0000 20620500' 'USB rate slot 2'

report_known_hash "$POLICY_SOURCE" AudioPolicyManager
report_known_hash "$FLINGER_SOURCE" AudioFlinger
report_known_hash "$USB_SOURCE" Qualcomm-USB

mkdir -p "$MODPATH/system/lib64" || abort "! Cannot create system overlay"
mkdir -p "${USB_DEST%/*}" || abort "! Cannot create vendor overlay"
cp -p "$POLICY_SOURCE" "$POLICY_DEST" || abort "! Cannot stage AudioPolicyManager"
cp -p "$FLINGER_SOURCE" "$FLINGER_DEST" || abort "! Cannot stage AudioFlinger"
cp -p "$USB_SOURCE" "$USB_DEST" || abort "! Cannot stage Qualcomm USB library"

profile_state=$(read_hex "$POLICY_DEST" 799328 4)
hook_state=$(read_hex "$POLICY_DEST" 867300 12)
strategy_state=$(read_hex "$POLICY_DEST" 869060 4)
effect_state=$(read_hex "$POLICY_DEST" 873908 4)
case "$profile_state:$hook_state:$strategy_state:$effect_state" in
    00050036:480000d0088944f9165d40a9:030b40b9:60010054) policy_state=stock ;;
    00050036:2800403988000037097d0153:e3031f2a:60010054) policy_state=v061 ;;
    00050036:2800403988000037097d0153:e3031f2a:0b000014) policy_state=interim ;;
    00050036:2800403988000037097d0153:e3031f2a:62010054) policy_state=v062 ;;
    1f2003d5:2800403988000037097d0153:e3031f2a:62010054) policy_state=complete ;;
    *) abort "! AudioPolicyManager patch combination is inconsistent" ;;
esac
ui_print "- AudioPolicyManager structural state: $policy_state"

if [ "$hook_state" = 480000d0088944f9165d40a9 ]; then
    write_patch "$MODPATH/patches/is_app_allowed_hook.bin" "$POLICY_DEST" 867276
fi
if [ "$strategy_state" = 030b40b9 ]; then
    write_patch "$MODPATH/patches/latest_max_patch.bin" "$POLICY_DEST" 869060
fi
case "$effect_state" in
    60010054|0b000014) write_patch "$MODPATH/patches/effect_gate_patch.bin" "$POLICY_DEST" 873908 ;;
esac
if [ "$profile_state" = 00050036 ]; then
    write_patch "$MODPATH/patches/profile_init_patch.bin" "$POLICY_DEST" 799328
fi

flinger_state=$(read_hex "$FLINGER_DEST" 1772164 4)
if [ "$flinger_state" = 480d0054 ]; then
    write_patch "$MODPATH/patches/flinger_sync_patch.bin" "$FLINGER_DEST" 1772164
fi

usb_state=$(read_hex "$USB_DEST" 29024 4):$(read_hex "$USB_DEST" 29052 4)
case "$usb_state" in
    20620500:44ac0000)
    write_patch "$MODPATH/patches/usb_441_patch.bin" "$USB_DEST" 29024
    write_patch "$MODPATH/patches/usb_3528_patch.bin" "$USB_DEST" 29052
        ;;
    44ac0000:20620500) ;;
    *) abort "! Qualcomm USB rate-table slots are inconsistent" ;;
esac

# Post-write verification is based on the target semantics, not a whole-file
# hash. This permits harmless vendor rebuild differences while refusing any
# shifted offset, mixed patch generation, truncated write, or wrong ISA.
[ "$(stat -c '%s' "$POLICY_DEST")" = "$POLICY_ORIGINAL_SIZE" ] \
    || abort "! AudioPolicyManager size changed during patching"
[ "$(stat -c '%s' "$FLINGER_DEST")" = "$FLINGER_ORIGINAL_SIZE" ] \
    || abort "! AudioFlinger size changed during patching"
[ "$(stat -c '%s' "$USB_DEST")" = "$USB_ORIGINAL_SIZE" ] \
    || abort "! Qualcomm USB library size changed during patching"
require_hex "$POLICY_DEST" 799328 4 1f2003d5 'patched profile initialization'
require_hex "$POLICY_DEST" 867300 12 2800403988000037097d0153 'patched application hook'
require_hex "$POLICY_DEST" 869060 4 e3031f2a 'patched profile strategy'
require_hex "$POLICY_DEST" 873908 4 62010054 'patched effect-state gate'
require_hex "$FLINGER_DEST" 1772164 4 6a000014 'patched Mixer synchronization'
require_hex "$USB_DEST" 29024 4 44ac0000 'patched USB 44.1 slot'
require_hex "$USB_DEST" 29052 4 20620500 'patched USB 352.8 slot'
require_binary_string "$POLICY_DEST" com.apple.android.music 'patched package allowlist'
require_binary_string "$POLICY_DEST" com.netease.cloudmusic 'patched package allowlist'
report_known_hash "$POLICY_DEST" 'patched AudioPolicyManager'
report_known_hash "$FLINGER_DEST" 'patched AudioFlinger'
report_known_hash "$USB_DEST" 'patched Qualcomm-USB'

rm -rf "$MODPATH/patches"
set_perm "$POLICY_DEST" 0 0 0644 u:object_r:system_lib_file:s0
set_perm "$FLINGER_DEST" 0 0 0644 u:object_r:system_lib_file:s0
set_perm "$USB_DEST" 0 0 0644 u:object_r:vendor_file:s0

ui_print "- Whitelist: Apple Music and NetEase Cloud Music only"
ui_print "- Profile: initialize Xiaomi deep_buffer_out without globally enabling Feature 8"
ui_print "- Strategy: Xiaomi LATEST_MAX across overlapping song tracks"
ui_print "- USB deep-buffer: accept NONE/UNKNOWN; still block Dolby/MiSound"
ui_print "- Mixer: synchronize in place for 44.1/48/88.2/96/192 kHz changes"
ui_print "- USB capability: 44.1 kHz is inside Qualcomm's seven-rate list"
ui_print "- PCM32 remains the HAL/mixer format; no Float HAL claim"
ui_print "- No daemon, Zygisk, XML edit, preferred-mixer writer, or live restart"
ui_print "- System overlay is delegated to Magisk or the active KernelSU metamodule"
ui_print "! Experimental and exact-firmware-only; reboot is required"
