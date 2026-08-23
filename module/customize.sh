#!/system/bin/sh

EXPECTED_FINGERPRINT='Xiaomi/nezha/nezha:17/CP2A.260605.016/OS4.0.0.15.XPACNXM:user/release-keys'
POLICY_SOURCE=/system/lib64/libaudiopolicymanagerdefault.so
COMPONENTS_SOURCE=/system/lib64/libaudiopolicycomponents.so
IMPL_SOURCE=/system_ext/lib64/libaudiopolicymanagerimpl.so
FLINGER_SOURCE=/system/lib64/libaudioflinger.so
USB_SOURCE=/vendor/lib64/libdev_usb.so
HAL_SOURCE=/vendor/lib64/hw/libaudiocorehal.qti.so
POLICY_DEST=$MODPATH/system/lib64/libaudiopolicymanagerdefault.so
FLINGER_DEST=$MODPATH/system/lib64/libaudioflinger.so

if [ "${KSU:-}" = true ] || [ -x /data/adb/ksud ]; then
    USB_DEST=$MODPATH/vendor/lib64/libdev_usb.so
    HAL_DEST=$MODPATH/vendor/lib64/hw/libaudiocorehal.qti.so
else
    USB_DEST=$MODPATH/system/vendor/lib64/libdev_usb.so
    HAL_DEST=$MODPATH/system/vendor/lib64/hw/libaudiocorehal.qti.so
fi

ui_print "- Checking Xiaomi 17 Ultra Android 17 firmware"
[ "$(getprop ro.build.version.sdk)" = 37 ] \
    || abort "! Android 17 / SDK 37 is required"
[ "$(getprop ro.build.fingerprint)" = "$EXPECTED_FINGERPRINT" ] \
    || abort "! Exact OS4.0.0.15.XPACNXM firmware is required"
if { [ "${KSU:-}" = true ] || [ -x /data/adb/ksud ]; } \
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
            abort "! Refusing an unsafe binary patch"
            ;;
    esac
}

require_elf64_aarch64() {
    file=$1
    minimum_size=$2
    label=$3
    [ -r "$file" ] || abort "! Missing readable $label: $file"
    size=$(stat -c '%s' "$file" 2>/dev/null)
    [ "$size" -ge "$minimum_size" ] \
        || abort "! Truncated or incompatible $label ($size bytes)"
    require_hex "$file" 0 20 \
        7f454c460201010000000000000000000300b700 "$label ELF64/AArch64 header"
}

require_binary_string() {
    grep -a -q "$2" "$1" 2>/dev/null \
        || abort "! Missing semantic marker in $3: $2"
}

region_sha() {
    dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null \
        | sha256sum | awk '{print $1}'
}

region_is_zero() {
    [ -z "$(dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null \
        | od -An -tx1 -v | tr -d ' 0\n')" ]
}

region_matches_file() {
    target=$1
    offset=$2
    patch=$3
    size=$(stat -c '%s' "$patch" 2>/dev/null)
    [ -n "$size" ] \
        && [ "$(region_sha "$target" "$offset" "$size")" = "$(sha_of "$patch")" ]
}

region_matches_prefix_file() {
    target=$1
    offset=$2
    patch=$3
    size=$4
    [ "$(region_sha "$target" "$offset" "$size")" = \
        "$(region_sha "$patch" 0 "$size")" ]
}

write_patch() {
    dd if="$1" of="$2" bs=1 seek="$3" conv=notrunc 2>/dev/null \
        || abort "! Failed to patch $2 at $3"
}

require_elf64_aarch64 "$POLICY_SOURCE" 873924 AudioPolicyManager
require_elf64_aarch64 "$COMPONENTS_SOURCE" 739584 AudioPolicyComponents
require_elf64_aarch64 "$IMPL_SOURCE" 702272 Xiaomi-AudioPolicyImpl
require_elf64_aarch64 "$FLINGER_SOURCE" 1772180 AudioFlinger
require_elf64_aarch64 "$USB_SOURCE" 29056 Qualcomm-USB
require_elf64_aarch64 "$HAL_SOURCE" 2918696 Qualcomm-AIDL-Audio-HAL
require_binary_string "$POLICY_SOURCE" HifiSampleRateManager: AudioPolicyManager
require_binary_string "$POLICY_SOURCE" hifi_playback AudioPolicyManager
require_binary_string "$IMPL_SOURCE" AudioPolicyManagerImpl Xiaomi-AudioPolicyImpl
require_binary_string "$USB_SOURCE" readSupportedSampleRate Qualcomm-USB
require_binary_string "$HAL_SOURCE" HifiPlayback Qualcomm-AIDL-Audio-HAL

# Exact call-site and object-layout anchors. Whole-file hashes are diagnostic;
# these local semantic signatures decide whether the patch is safe.
require_hex "$POLICY_SOURCE" 356864 20 \
    a14240f9a2021291a3a20291a43300d1e00315aa \
    'AOSP-to-Xiaomi selectOutput argument setup'
require_hex "$POLICY_SOURCE" 356888 16 \
    a8835df8a0435fb8080100b4a9835ef8 \
    'selectOutput callback return context'
require_hex "$POLICY_SOURCE" 867264 12 \
    bf2303d5c0035fd657c2fd97 'HIFI app-filter pre-context'
require_hex "$POLICY_SOURCE" 867280 16 \
    fd7bbca9f85f01a9f65702a9f44f03a9 'HIFI app-filter post-context'
require_hex "$POLICY_SOURCE" 515984 4 5f2403d5 \
    'sampling-rate sender pre-context'
require_hex "$POLICY_SOURCE" 515992 16 \
    3f2303d5ffc301d1fd7b04a9f65705a9 \
    'sampling-rate sender post-context'
require_hex "$POLICY_SOURCE" 800672 12 \
    1c5800940041201ed1ffff17 'native cave pre-context'
require_one_of_hex "$POLICY_SOURCE" 801644 16 \
    '00000000000000000000000000000000 a90240f9e90100b42ac140392bc50091' \
    'HIFI dynamic-default cave entry'
require_hex "$POLICY_SOURCE" 864400 16 \
    42b0059160008052e1031faae3190094 \
    'LATEST_MAX final-stop pre-context'
require_hex "$POLICY_SOURCE" 864420 16 \
    82faffd04280079160008052e1031faa \
    'LATEST_MAX final-stop post-context'
require_hex "$POLICY_SOURCE" 865824 16 \
    1f0100712001881ac0035fd6081040f9 \
    'LATEST_MAX active-rate pre-context'
require_one_of_hex "$POLICY_SOURCE" 873596 4 \
    '1f050071 91b9ff17' 'HIFI idle-rate caller hook'
require_hex "$POLICY_SOURCE" 873600 12 \
    a1000054692345291f010071 \
    'HIFI idle-rate caller post-context'
require_hex "$POLICY_SOURCE" 865844 16 \
    098c41f8a90000b4e80309aa290540f9 \
    'LATEST_MAX active-rate post-context'
require_hex "$POLICY_SOURCE" 432208 16 \
    e00316aa02017eb203017db24dc60194 \
    'dynamic profile picker pre-context'
require_hex "$POLICY_SOURCE" 432228 16 \
    e8cb41b9e9570391b6035ef8e00319aa \
    'dynamic profile picker post-context'
require_hex "$POLICY_SOURCE" 893536 16 \
    30000090115640f910a2029120021fd6 \
    'AudioOutputDescriptor isActive PLT entry'

# SwAudioOutputCollection is 16-byte key/value items. The descriptor stores
# its current DeviceVector at +0xe8 and DeviceDescriptor::type at +0x148.
require_hex "$COMPONENTS_SOURCE" 331308 64 \
    810240f9980a40f9e00315aade5201947f0218eb22020054810240f9e80201cb08410f910815c8931f7900f1c8030054c826c81a88030036880640f90011138b \
    'output collection item layout'
require_hex "$COMPONENTS_SOURCE" 292552 32 \
    c0035fd681a20391e00313aaf44f49a9f54340f9fd7b47a9ff830291bf2303d5 \
    'output current DeviceVector offset'
require_hex "$COMPONENTS_SOURCE" 533484 56 \
    e00317aae10318aaa111ff971a0040f91f2003d5486f1310410340f9080101cb08e13f910825c8931f0900f1621b0054484b41b91f011c6b \
    'DeviceDescriptor type offset'

# Xiaomi's linked implementation independently confirms mProfile at +0x1d0
# and the libc++ IOProfile name data beginning at profile +0x30.
require_hex "$IMPL_SOURCE" 377928 48 \
    08810591692a0ba9686200f9880240f968ea00f9c80000b4090140f96142079129815ef80001098b46fc00947fda01b9 \
    'SwAudioOutputDescriptor mProfile layout'
require_hex "$IMPL_SOURCE" 378404 48 \
    a8ea40f9480100b409c140390a2140f908c5009141feffb021ac2891a02300d13f01007202018a9a5bfa0094ff0b00f9 \
    'IOProfile name string layout'

require_one_of_hex "$POLICY_SOURCE" 356884 4 \
    'bf0b0294 66b10114' 'native selectOutput callback hook'
require_one_of_hex "$POLICY_SOURCE" 867276 4 \
    '3f2303d5 38bfff17' 'HIFI application filter hook'
require_one_of_hex "$POLICY_SOURCE" 515988 4 \
    'e20a0034 d3160114' 'USB-only sampling-rate sender gate'
require_one_of_hex "$POLICY_SOURCE" 864416 4 \
    'acffff17 78ffff17 86c2ff17' 'LATEST_MAX final-stop update result'
require_one_of_hex "$POLICY_SOURCE" 865840 4 \
    'a80100b4 e822f8b4 17c1ff17' 'LATEST_MAX idle-rate branch'
require_one_of_hex "$POLICY_SOURCE" 432224 4 \
    'e0e340fd c3680114' 'HIFI dynamic default hook'
require_one_of_hex "$FLINGER_SOURCE" 1772164 4 \
    '480d0054 6a000014' 'MixerThread HAL-rate synchronization'
require_one_of_hex "$USB_SOURCE" 29024 4 \
    '20620500 44ac0000' 'USB rate-table slot 1'
require_one_of_hex "$USB_SOURCE" 29052 4 \
    '44ac0000 20620500' 'USB rate-table slot 2'
require_hex "$HAL_SOURCE" 2595780 20 \
    3f2303d5fd7bbfa9fd03009160d20094400200b6 \
    'HIFI frame-count function entry'
require_hex "$HAL_SOURCE" 2595824 24 \
    e9f99ed2696abcf208f17dd3a974d3f28918e4f208fd43d3 \
    'HIFI frame-count function exit context'
require_hex "$HAL_SOURCE" 2295936 20 \
    680000372800805288521e3988f24679809207b9 \
    'HIFI sampling-rate usecase pre-context'
require_hex "$HAL_SOURCE" 2295972 16 \
    88e641f9a80100b480e225915ce10194 \
    'HIFI sampling-rate usecase post-context'
require_one_of_hex "$HAL_SOURCE" 2295956 16 \
    '1f350071600000541f210071e1010054 092184522925c81a090200361f2003d5' \
    'HIFI PAL reconfiguration usecases'
require_one_of_hex "$HAL_SOURCE" 2595800 24 \
    '087c409309058052097dc99bff0309ebc101005408c9208b 087097521f00086b0030881a280380520008c81a09000014' \
    'HIFI immutable FMQ frame-count cap'

NATIVE_CAVE_OFFSET=800684
NATIVE_CAVE_CAPACITY=820
NATIVE_V070_SIZE=735
NATIVE_V073_PREFIX_SIZE=736
NATIVE_V073_HELPER_OFFSET=801420
NATIVE_V073_HELPER_SIZE=8
NATIVE_V073_HELPER_HEX=00709752c0035fd6
NATIVE_V074_SIZE=780
NATIVE_CAVE_SIZE=$(stat -c '%s' "$MODPATH/patches/native_hifi_cave.bin" 2>/dev/null)
[ "$NATIVE_CAVE_SIZE" = 788 ] \
    || abort "! Native HIFI hook has an unexpected build size"
NATIVE_REMAINDER_OFFSET=$((NATIVE_CAVE_OFFSET + NATIVE_CAVE_SIZE))
NATIVE_REMAINDER_SIZE=$((NATIVE_CAVE_CAPACITY - NATIVE_CAVE_SIZE))
if region_matches_file "$POLICY_SOURCE" "$NATIVE_CAVE_OFFSET" \
        "$MODPATH/patches/native_hifi_cave.bin"; then
    native_cave_state=v075
elif region_matches_prefix_file "$POLICY_SOURCE" "$NATIVE_CAVE_OFFSET" \
        "$MODPATH/patches/native_hifi_cave.bin" "$NATIVE_V074_SIZE" \
        && region_is_zero "$POLICY_SOURCE" \
            $((NATIVE_CAVE_OFFSET + NATIVE_V074_SIZE)) \
            $((NATIVE_CAVE_SIZE - NATIVE_V074_SIZE)); then
    native_cave_state=v074
elif region_matches_prefix_file "$POLICY_SOURCE" "$NATIVE_CAVE_OFFSET" \
        "$MODPATH/patches/native_hifi_cave.bin" "$NATIVE_V073_PREFIX_SIZE" \
        && [ "$(read_hex "$POLICY_SOURCE" "$NATIVE_V073_HELPER_OFFSET" \
            "$NATIVE_V073_HELPER_SIZE")" = "$NATIVE_V073_HELPER_HEX" ] \
        && region_is_zero "$POLICY_SOURCE" \
            $((NATIVE_V073_HELPER_OFFSET + NATIVE_V073_HELPER_SIZE)) \
            $((NATIVE_CAVE_SIZE - NATIVE_V073_PREFIX_SIZE - NATIVE_V073_HELPER_SIZE)); then
    native_cave_state=v073
elif region_matches_prefix_file "$POLICY_SOURCE" "$NATIVE_CAVE_OFFSET" \
        "$MODPATH/patches/native_hifi_cave.bin" "$NATIVE_V070_SIZE" \
        && region_is_zero "$POLICY_SOURCE" \
            $((NATIVE_CAVE_OFFSET + NATIVE_V070_SIZE)) \
            $((NATIVE_CAVE_SIZE - NATIVE_V070_SIZE)); then
    native_cave_state=v070
elif region_is_zero "$POLICY_SOURCE" "$NATIVE_CAVE_OFFSET" "$NATIVE_CAVE_CAPACITY"; then
    native_cave_state=stock
else
    abort "! Native HIFI executable cave is occupied or partially patched"
fi

HIFI_IDLE_CAVE_OFFSET=801472
HIFI_IDLE_CAVE_SIZE=32
if region_matches_file "$POLICY_SOURCE" "$HIFI_IDLE_CAVE_OFFSET" \
        "$MODPATH/patches/hifi_idle_rate_cave.bin"; then
    hifi_idle_cave_state=patched
elif [ "$(region_sha "$POLICY_SOURCE" "$HIFI_IDLE_CAVE_OFFSET" \
        "$HIFI_IDLE_CAVE_SIZE")" = \
        8a9bb82eff753002e0014d13f9a8987c83ba28082d338eaea689529a22d895cd ]; then
    hifi_idle_cave_state=v077
elif region_is_zero "$POLICY_SOURCE" "$HIFI_IDLE_CAVE_OFFSET" \
        "$HIFI_IDLE_CAVE_SIZE"; then
    hifi_idle_cave_state=stock
else
    abort "! HIFI idle-rate executable cave is occupied or partially patched"
fi

USB_GATE_CAVE_OFFSET=801504
USB_GATE_CAVE_CAPACITY=140
if region_matches_file "$POLICY_SOURCE" "$USB_GATE_CAVE_OFFSET" \
        "$MODPATH/patches/usb_output_gate_cave.bin"; then
    usb_gate_cave_state=patched
elif region_matches_file "$POLICY_SOURCE" "$USB_GATE_CAVE_OFFSET" \
        "$MODPATH/patches/usb_output_gate_v076_cave.bin"; then
    usb_gate_cave_state=v076
elif region_is_zero "$POLICY_SOURCE" "$USB_GATE_CAVE_OFFSET" "$USB_GATE_CAVE_CAPACITY"; then
    usb_gate_cave_state=stock
else
    abort "! USB sender-gate executable cave is occupied or partially patched"
fi

USB_ARBITRATION_CAVE_OFFSET=801732
USB_ARBITRATION_CAVE_SIZE=$(stat -c '%s' \
    "$MODPATH/patches/usb_output_arbitration_cave.bin" 2>/dev/null)
[ "$USB_ARBITRATION_CAVE_SIZE" = 292 ] \
    || abort "! USB idle-arbitration hook has an unexpected build size"
if region_matches_file "$POLICY_SOURCE" "$USB_ARBITRATION_CAVE_OFFSET" \
        "$MODPATH/patches/usb_output_arbitration_cave.bin"; then
    usb_arbitration_cave_state=patched
elif [ "$(region_sha "$POLICY_SOURCE" "$USB_ARBITRATION_CAVE_OFFSET" \
        "$USB_ARBITRATION_CAVE_SIZE")" = \
        1889ede11bb1bda19da7d8bef2edae88a59783dc1aa1b898cc6856cc722f1e8a ]; then
    usb_arbitration_cave_state=v077
elif region_is_zero "$POLICY_SOURCE" "$USB_ARBITRATION_CAVE_OFFSET" \
        "$USB_ARBITRATION_CAVE_SIZE"; then
    usb_arbitration_cave_state=stock
else
    abort "! USB idle-arbitration executable cave is occupied or partially patched"
fi
case "$usb_gate_cave_state:$usb_arbitration_cave_state" in
    stock:stock|v076:stock|patched:v077|patched:patched) ;;
    *) abort "! Refusing a mixed USB idle-arbitration patch state" ;;
esac

HIFI_DEFAULT_CAVE_OFFSET=801644
HIFI_DEFAULT_CAVE_CAPACITY=86
if region_matches_file "$POLICY_SOURCE" "$HIFI_DEFAULT_CAVE_OFFSET" \
        "$MODPATH/patches/hifi_dynamic_default_cave.bin"; then
    hifi_default_cave_state=patched
elif region_is_zero "$POLICY_SOURCE" "$HIFI_DEFAULT_CAVE_OFFSET" \
        "$HIFI_DEFAULT_CAVE_CAPACITY"; then
    hifi_default_cave_state=stock
else
    abort "! HIFI dynamic-default executable cave is occupied or partially patched"
fi

select_state=$(read_hex "$POLICY_SOURCE" 356884 4)
app_state=$(read_hex "$POLICY_SOURCE" 867276 4)
gate_state=$(read_hex "$POLICY_SOURCE" 515988 4)
latest_stop_state=$(read_hex "$POLICY_SOURCE" 864416 4)
idle_rate_state=$(read_hex "$POLICY_SOURCE" 865840 4)
idle_caller_state=$(read_hex "$POLICY_SOURCE" 873596 4)
default_rate_state=$(read_hex "$POLICY_SOURCE" 432224 4)
case "$default_rate_state:$hifi_default_cave_state" in
    e0e340fd:stock) hifi_default_state=stock ;;
    c3680114:patched) hifi_default_state=patched ;;
    *) abort "! Refusing a mixed HIFI dynamic-default patch state" ;;
esac
flinger_state=$(read_hex "$FLINGER_SOURCE" 1772164 4)
usb_state=$(read_hex "$USB_SOURCE" 29024 4):$(read_hex "$USB_SOURCE" 29052 4)
case "$select_state:$app_state:$native_cave_state:$gate_state:$usb_gate_cave_state:$flinger_state:$usb_state:$latest_stop_state:$idle_rate_state" in
    bf0b0294:3f2303d5:stock:e20a0034:stock:480d0054:20620500:44ac0000:acffff17:a80100b4)
        module_state=stock ;;
    66b10114:38bfff17:v070:d3160114:v076:6a000014:44ac0000:20620500:acffff17:a80100b4)
        module_state=v070 ;;
    66b10114:38bfff17:v073:d3160114:v076:6a000014:44ac0000:20620500:78ffff17:e822f8b4)
        module_state=v073 ;;
    66b10114:38bfff17:v074:d3160114:v076:6a000014:44ac0000:20620500:78ffff17:17c1ff17)
        module_state=v074 ;;
    66b10114:38bfff17:v075:d3160114:v076:6a000014:44ac0000:20620500:86c2ff17:17c1ff17)
        module_state=v075 ;;
    66b10114:38bfff17:v075:d3160114:patched:6a000014:44ac0000:20620500:86c2ff17:17c1ff17)
        module_state=v077 ;;
    *) abort "! Refusing a mixed, older, or incompatible patch state" ;;
esac
case "$idle_caller_state" in
    1f050071) idle_caller_state=stock ;;
    91b9ff17) idle_caller_state=patched ;;
    *) abort "! Refusing an unknown HIFI idle-rate caller state" ;;
esac
case "$idle_caller_state:$hifi_idle_cave_state" in
    stock:stock) ;;
    patched:v077) ;;
    patched:patched) ;;
    *) abort "! Refusing a mixed HIFI idle-rate caller patch state" ;;
esac

hal_usecase_state=$(read_hex "$HAL_SOURCE" 2295956 16)
hal_frame_state=$(read_hex "$HAL_SOURCE" 2595800 24)
case "$hal_usecase_state:$hal_frame_state" in
    1f350071600000541f210071e1010054:087c409309058052097dc99bff0309ebc101005408c9208b)
        hal_state=stock ;;
    092184522925c81a090200361f2003d5:087c409309058052097dc99bff0309ebc101005408c9208b)
        hal_state=legacy-usecase ;;
    092184522925c81a090200361f2003d5:087097521f00086b0030881a280380520008c81a09000014)
        hal_state=v072 ;;
    *) abort "! Refusing a mixed or incompatible Qualcomm HIFI HAL state" ;;
esac

ui_print "- Structural state: $module_state"
ui_print "- HIFI 48 kHz open state: $hifi_default_state"
ui_print "- Qualcomm HIFI HAL state: $hal_state"
ui_print "- AudioPolicyManager SHA-256: $(sha_of "$POLICY_SOURCE")"
ui_print "- AudioFlinger SHA-256: $(sha_of "$FLINGER_SOURCE")"
ui_print "- Qualcomm USB SHA-256: $(sha_of "$USB_SOURCE")"
ui_print "- Qualcomm AIDL HAL SHA-256: $(sha_of "$HAL_SOURCE")"

mkdir -p "$MODPATH/system/lib64" || abort "! Cannot create system overlay"
mkdir -p "${USB_DEST%/*}" || abort "! Cannot create vendor overlay"
mkdir -p "${HAL_DEST%/*}" || abort "! Cannot create AIDL HAL overlay"
cp -p "$POLICY_SOURCE" "$POLICY_DEST" || abort "! Cannot stage AudioPolicyManager"
cp -p "$FLINGER_SOURCE" "$FLINGER_DEST" || abort "! Cannot stage AudioFlinger"
cp -p "$USB_SOURCE" "$USB_DEST" || abort "! Cannot stage Qualcomm USB library"
cp -p "$HAL_SOURCE" "$HAL_DEST" || abort "! Cannot stage Qualcomm AIDL HAL"
POLICY_SIZE=$(stat -c '%s' "$POLICY_SOURCE")
FLINGER_SIZE=$(stat -c '%s' "$FLINGER_SOURCE")
USB_SIZE=$(stat -c '%s' "$USB_SOURCE")
HAL_SIZE=$(stat -c '%s' "$HAL_SOURCE")

if [ "$module_state" = stock ]; then
    write_patch "$MODPATH/patches/native_hifi_cave.bin" "$POLICY_DEST" "$NATIVE_CAVE_OFFSET"
    write_patch "$MODPATH/patches/select_output_branch.bin" "$POLICY_DEST" 356884
    write_patch "$MODPATH/patches/hifi_app_branch.bin" "$POLICY_DEST" 867276
    write_patch "$MODPATH/patches/usb_output_gate_branch.bin" "$POLICY_DEST" 515988
    write_patch "$MODPATH/patches/flinger_sync_patch.bin" "$FLINGER_DEST" 1772164
    write_patch "$MODPATH/patches/usb_441_patch.bin" "$USB_DEST" 29024
    write_patch "$MODPATH/patches/usb_3528_patch.bin" "$USB_DEST" 29052
fi
if [ "$usb_gate_cave_state" != patched ] \
        || [ "$usb_arbitration_cave_state" != patched ]; then
    write_patch "$MODPATH/patches/usb_output_gate_cave.bin" \
        "$POLICY_DEST" "$USB_GATE_CAVE_OFFSET"
    write_patch "$MODPATH/patches/usb_output_arbitration_cave.bin" \
        "$POLICY_DEST" "$USB_ARBITRATION_CAVE_OFFSET"
fi
if [ "$module_state" != v075 ]; then
    write_patch "$MODPATH/patches/native_hifi_cave.bin" "$POLICY_DEST" "$NATIVE_CAVE_OFFSET"
    write_patch "$MODPATH/patches/latest_max_final_stop_patch.bin" "$POLICY_DEST" 864416
    write_patch "$MODPATH/patches/latest_max_idle_rate_patch.bin" "$POLICY_DEST" 865840
fi
if [ "$hifi_default_state" = stock ]; then
    write_patch "$MODPATH/patches/hifi_dynamic_default_cave.bin" \
        "$POLICY_DEST" "$HIFI_DEFAULT_CAVE_OFFSET"
    write_patch "$MODPATH/patches/hifi_dynamic_default_branch.bin" \
        "$POLICY_DEST" 432224
fi
if [ "$idle_caller_state" = stock ] \
        || [ "$hifi_idle_cave_state" != patched ]; then
    write_patch "$MODPATH/patches/hifi_idle_rate_cave.bin" \
        "$POLICY_DEST" "$HIFI_IDLE_CAVE_OFFSET"
    write_patch "$MODPATH/patches/hifi_idle_rate_branch.bin" \
        "$POLICY_DEST" 873596
fi
if [ "$hal_state" = stock ]; then
    write_patch "$MODPATH/patches/hifi_usecase_reconfigure_patch.bin" \
        "$HAL_DEST" 2295956
fi
if [ "$hal_state" = v072 ]; then
    write_patch "$MODPATH/patches/hifi_frame_count_stock.bin" \
        "$HAL_DEST" 2595800
fi

[ "$(stat -c '%s' "$POLICY_DEST")" = "$POLICY_SIZE" ] \
    || abort "! AudioPolicyManager size changed"
[ "$(stat -c '%s' "$FLINGER_DEST")" = "$FLINGER_SIZE" ] \
    || abort "! AudioFlinger size changed"
[ "$(stat -c '%s' "$USB_DEST")" = "$USB_SIZE" ] \
    || abort "! Qualcomm USB library size changed"
[ "$(stat -c '%s' "$HAL_DEST")" = "$HAL_SIZE" ] \
    || abort "! Qualcomm AIDL HAL size changed"
require_hex "$POLICY_DEST" 356884 4 66b10114 'patched native selectOutput hook'
require_hex "$POLICY_DEST" 867276 4 38bfff17 'patched HIFI app filter hook'
require_hex "$POLICY_DEST" 515988 4 d3160114 'patched USB sender gate'
require_hex "$POLICY_DEST" 864416 4 86c2ff17 \
    'patched LATEST_MAX final-stop idle rate branch'
require_hex "$POLICY_DEST" 865840 4 17c1ff17 \
    'patched LATEST_MAX idle-rate branch'
require_hex "$POLICY_DEST" 873596 4 91b9ff17 \
    'patched HIFI idle-rate caller hook'
require_hex "$POLICY_DEST" 432224 4 c3680114 \
    'patched HIFI 48 kHz dynamic default hook'
region_matches_file "$POLICY_DEST" "$NATIVE_CAVE_OFFSET" \
    "$MODPATH/patches/native_hifi_cave.bin" \
    || abort "! Native HIFI cave verification failed"
region_matches_file "$POLICY_DEST" "$HIFI_IDLE_CAVE_OFFSET" \
    "$MODPATH/patches/hifi_idle_rate_cave.bin" \
    || abort "! HIFI idle-rate cave verification failed"
region_matches_file "$POLICY_DEST" "$USB_GATE_CAVE_OFFSET" \
    "$MODPATH/patches/usb_output_gate_cave.bin" \
    || abort "! USB sender-gate cave verification failed"
region_matches_file "$POLICY_DEST" "$USB_ARBITRATION_CAVE_OFFSET" \
    "$MODPATH/patches/usb_output_arbitration_cave.bin" \
    || abort "! USB idle-arbitration cave verification failed"
region_matches_file "$POLICY_DEST" "$HIFI_DEFAULT_CAVE_OFFSET" \
        "$MODPATH/patches/hifi_dynamic_default_cave.bin" \
    || abort "! HIFI dynamic-default cave verification failed"
require_hex "$FLINGER_DEST" 1772164 4 6a000014 'patched Mixer synchronization'
require_hex "$USB_DEST" 29024 4 44ac0000 'patched USB 44.1 slot'
require_hex "$USB_DEST" 29052 4 20620500 'preserved USB 352.8 slot'
require_hex "$HAL_DEST" 2295956 16 \
    092184522925c81a090200361f2003d5 \
    'patched HIFI PAL reconfiguration usecases'
require_hex "$HAL_DEST" 2595800 24 \
    087c409309058052097dc99bff0309ebc101005408c9208b \
    'restored stock HIFI frame-count calculation'
require_binary_string "$POLICY_DEST" com.apple.android.music 'patched package policy'
require_binary_string "$POLICY_DEST" com.netease.cloudmusic 'patched package policy'

rm -rf "$MODPATH/patches"
set_perm "$POLICY_DEST" 0 0 0644 u:object_r:system_lib_file:s0
set_perm "$FLINGER_DEST" 0 0 0644 u:object_r:system_lib_file:s0
set_perm "$USB_DEST" 0 0 0644 u:object_r:vendor_file:s0
set_perm "$HAL_DEST" 0 0 0644 u:object_r:vendor_file:s0

ui_print "- Packages: Apple Music and NetEase Cloud Music"
ui_print "- Route: native Xiaomi hifi_playback only when the selected route is USB-only"
ui_print "- Rate: Xiaomi HifiSampleRateManager remains the sole start/stop controller"
ui_print "- Idle: final HIFI release keeps the last rate until standby"
ui_print "- Handoff: active ordinary USB output restores the backend to 48000 Hz"
ui_print "- Mixer: synchronize 44.1/48 kHz changes from the accepted HAL rate"
ui_print "- Open: hifi_playback starts at PCM32 48 kHz with a native 1920-frame FMQ"
ui_print "- HAL: enable HIFI PAL reconfiguration; preserve QTI's stock frame calculation"
ui_print "- USB: expose 44.1 kHz inside Qualcomm's seven returned rates"
ui_print "- Bluetooth, speaker, mixed, empty, and stale routes fail closed"
ui_print "- No Preferred Mixer, Deep Buffer patch, XML edit, daemon, or Zygisk"
ui_print "! Experimental exact-firmware alpha; reboot is required"
