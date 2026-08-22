#!/system/bin/sh

EXPECTED_FINGERPRINT='Xiaomi/nezha/nezha:17/CP2A.260605.016/OS4.0.0.15.XPACNXM:user/release-keys'
POLICY_STOCK_SHA256=e0bd4444461df3608f2baa05d4f5db22d0d5ddfb23cabb36474ff5f5c22da3cb
POLICY_PREVIOUS_SHA256=44d6d59dd395c2a5dfee6d3cf2c2f1a485377633a9e6d3b78754cc2b1b3f92c3
POLICY_INTERIM_SHA256=34916265a7375e87db57125e3e603702a07335aed5f320ad61c58fa9c757b1b6
POLICY_V062_SHA256=5be0a369ec73ce27d531aa58de84b4cd292518dbdb92f9568d65340d853ba72a
POLICY_V064_SHA256=c3747853afee1ccf0734cf144e84190c4814b88ebe3ea57d2b6ec83c779015ab
POLICY_PATCHED_SHA256=9dcedf72cb0a682f507495f1f048fc89eec614d842412964d98ebcfd635e645b
FLINGER_STOCK_SHA256=d499d92e115dac7ee8e7e5dcbd53079e6a61ffccbe6d34481f239813e1f3695f
FLINGER_PATCHED_SHA256=66ce065150b8d1e7cb056a7fbc6040563c9e8ef87c3068dd40dc5e876d9e95e6
USB_STOCK_SHA256=d36085dbf0e4f7979ee6b94540b216d949d0f74ab0cda385fdfd5cfc8cd0c296
USB_PATCHED_SHA256=04cb4f2a7f4f4247995eb098b7d9a6ba8aeb6ff131144e87a6730d8a9ee4dad6
HAL_STOCK_SHA256=388afd93534a81747a874f70fac2577e737db998c42dec6c02d109073335d298
HAL_PATCHED_SHA256=3d21f137b48d18eaec31b7958820940110b74d65b900a57d3e80b9b464b4fa78
PRIMARY_XML_STOCK_SHA256=369b5a595837d78ee6d7f1ad7042129421d9cdc3ea27b1c229e8476a54c9f151
POLICY_MIN_SIZE=873924
FLINGER_MIN_SIZE=1772180
USB_MIN_SIZE=29056
HAL_MIN_SIZE=2918696
PRIMARY_XML_MIN_SIZE=28653
POLICY_SOURCE=/system/lib64/libaudiopolicymanagerdefault.so
FLINGER_SOURCE=/system/lib64/libaudioflinger.so
USB_SOURCE=/vendor/lib64/libdev_usb.so
HAL_SOURCE=/vendor/lib64/hw/libaudiocorehal.qti.so
PRIMARY_XML_SOURCE=/odm/etc/audio/audio_module_config_primary.xml
POLICY_DEST=$MODPATH/system/lib64/libaudiopolicymanagerdefault.so
FLINGER_DEST=$MODPATH/system/lib64/libaudioflinger.so
if [ "${KSU:-}" = "true" ] || [ -x /data/adb/ksud ]; then
    USB_DEST=$MODPATH/vendor/lib64/libdev_usb.so
    HAL_DEST=$MODPATH/vendor/lib64/hw/libaudiocorehal.qti.so
    PRIMARY_XML_DEST=$MODPATH/odm/etc/audio/audio_module_config_primary.xml
else
    USB_DEST=$MODPATH/system/vendor/lib64/libdev_usb.so
    HAL_DEST=$MODPATH/system/vendor/lib64/hw/libaudiocorehal.qti.so
    PRIMARY_XML_DEST=$MODPATH/system/odm/etc/audio/audio_module_config_primary.xml
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

region_sha() {
    dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | sha256sum | awk '{print $1}'
}

region_is_zero() {
    [ -z "$(dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null \
        | od -An -tx1 -v | tr -d ' 0\n')" ]
}

region_matches_file() {
    target=$1
    offset=$2
    patch=$3
    patch_size=$(stat -c '%s' "$patch" 2>/dev/null)
    [ -n "$patch_size" ] && [ "$(region_sha "$target" "$offset" "$patch_size")" = "$(sha_of "$patch")" ]
}

report_known_hash() {
    file=$1
    label=$2
    actual=$(sha_of "$file")
    case "$actual" in
        "$POLICY_STOCK_SHA256"|"$POLICY_PREVIOUS_SHA256"|"$POLICY_INTERIM_SHA256"|"$POLICY_V062_SHA256"|"$POLICY_V064_SHA256"|"$POLICY_PATCHED_SHA256"|"$FLINGER_STOCK_SHA256"|"$FLINGER_PATCHED_SHA256"|"$USB_STOCK_SHA256"|"$USB_PATCHED_SHA256"|"$HAL_STOCK_SHA256"|"$HAL_PATCHED_SHA256"|"$PRIMARY_XML_STOCK_SHA256")
            ui_print "- $label hash is a known reference state"
            ;;
        *)
            ui_print "- $label hash differs, structural signatures will decide"
            ui_print "  SHA-256: $actual"
            ;;
    esac
}

require_exact_line_count() {
    file=$1
    pattern=$2
    expected=$3
    label=$4
    actual=$(grep -F -x -c "$pattern" "$file" 2>/dev/null)
    [ "$actual" = "$expected" ] || {
        ui_print "! XML structure mismatch: $label"
        ui_print "! Expected $expected exact line(s), found $actual"
        abort "! Refusing an unsafe audio policy XML edit"
    }
}

patch_primary_xml() {
    source_file=$1
    destination_file=$2
    state=$(deep_profile_state "$source_file")
    if [ "$state" = patched ]; then
        cp -p "$source_file" "$destination_file" \
            || abort "! Cannot stage the already-patched primary audio XML"
        return
    fi
    [ "$state" = stock ] \
        || abort "! Deep-buffer XML profile state is neither stock nor patched"
    awk '
        /<mixPort name="deep_buffer_out" role="source" flags="DEEP_BUFFER">/ {
            in_deep = 1
        }
        in_deep && /pcmType="INT_24_BIT"/ && /samplingRates="48000"/ {
            sub(/samplingRates="48000"/, "samplingRates=\"44100 48000\"")
            changed24++
        }
        in_deep && /pcmType="INT_32_BIT"/ && /samplingRates="48000"/ {
            sub(/samplingRates="48000"/, "samplingRates=\"44100 48000\"")
            changed32++
        }
        { print }
        in_deep && /<\/mixPort>/ { in_deep = 0 }
        END {
            if (changed24 != 1 || changed32 != 1) exit 42
        }
    ' "$source_file" > "$destination_file" \
        || abort "! Failed to restore the legacy deep-buffer XML rates"
}

deep_profile_state() {
    awk '
        /<mixPort name="deep_buffer_out" role="source" flags="DEEP_BUFFER">/ {
            in_deep = 1
            ports++
        }
        in_deep && /pcmType="INT_24_BIT"/ {
            if (/samplingRates="48000"/) stock24++
            else if (/samplingRates="44100 48000"/) patched24++
            else unknown++
        }
        in_deep && /pcmType="INT_32_BIT"/ {
            if (/samplingRates="48000"/) stock32++
            else if (/samplingRates="44100 48000"/) patched32++
            else unknown++
        }
        in_deep && /<\/mixPort>/ { in_deep = 0 }
        END {
            if (ports == 1 && stock24 == 1 && stock32 == 1 &&
                    patched24 == 0 && patched32 == 0 && unknown == 0) {
                print "stock"
            } else if (ports == 1 && stock24 == 0 && stock32 == 0 &&
                    patched24 == 1 && patched32 == 1 && unknown == 0) {
                print "patched"
            } else {
                print "unknown"
            }
        }
    ' "$1"
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
require_elf64_aarch64 "$HAL_SOURCE" "$HAL_MIN_SIZE" Qualcomm-AIDL-HAL
[ -r "$PRIMARY_XML_SOURCE" ] \
    || abort "! Missing active primary audio module XML"
[ "$(stat -c '%s' "$PRIMARY_XML_SOURCE" 2>/dev/null)" -ge "$PRIMARY_XML_MIN_SIZE" ] \
    || abort "! Primary audio module XML is truncated"
POLICY_ORIGINAL_SIZE=$(stat -c '%s' "$POLICY_SOURCE")
FLINGER_ORIGINAL_SIZE=$(stat -c '%s' "$FLINGER_SOURCE")
USB_ORIGINAL_SIZE=$(stat -c '%s' "$USB_SOURCE")
HAL_ORIGINAL_SIZE=$(stat -c '%s' "$HAL_SOURCE")
PRIMARY_XML_ORIGINAL_SIZE=$(stat -c '%s' "$PRIMARY_XML_SOURCE")

require_binary_string "$POLICY_SOURCE" deep_buffer_out AudioPolicyManager
require_binary_string "$POLICY_SOURCE" HifiSampleRateManager: AudioPolicyManager
require_binary_string "$FLINGER_SOURCE" readOutputParameters_l AudioFlinger
require_binary_string "$USB_SOURCE" readSupportedSampleRate Qualcomm-USB
require_binary_string "$HAL_SOURCE" 'Hifi: coming samplerate is' Qualcomm-AIDL-HAL
require_binary_string "$HAL_SOURCE" DEEP_BUFFER_PLAYBACK Qualcomm-AIDL-HAL
require_binary_string "$HAL_SOURCE" HIFI_PLAYBACK Qualcomm-AIDL-HAL
require_exact_line_count "$PRIMARY_XML_SOURCE" \
    '        <mixPort name="deep_buffer_out" role="source" flags="DEEP_BUFFER">' \
    1 'deep_buffer_out mixPort'
require_exact_line_count "$PRIMARY_XML_SOURCE" \
    '        <mixPort name="hifi_playback" role="source">' \
    1 'unflagged hifi_playback mixPort'
PRIMARY_XML_STATE=$(deep_profile_state "$PRIMARY_XML_SOURCE")
case "$PRIMARY_XML_STATE" in
    stock|patched) ;;
    *) abort "! Deep-buffer XML profiles are structurally incompatible" ;;
esac
ui_print "- Primary audio XML structural state: $PRIMARY_XML_STATE"

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
require_hex "$POLICY_SOURCE" 231408 16 \
    00e4006f69ffff90293d3991e9ff0aa9 'HIFI config pre-context'
require_hex "$POLICY_SOURCE" 231428 12 \
    08f0a752f8430191e9d300b9 'HIFI config post-context'
require_hex "$POLICY_SOURCE" 350028 16 \
    23008052e203182a00013fd6e203002a 'Preferred Mixer hook pre-context'
require_hex "$POLICY_SOURCE" 350048 16 \
    e0031aaae103172a23008052790e0294 'Preferred Mixer hook post-context'
require_hex "$POLICY_SOURCE" 874412 16 \
    a8024039a90a40f91f0100728303899a 'shared USB arbiter pre-context'
require_hex "$POLICY_SOURCE" 874432 16 \
    62faffb042140f9160008052e1031faa 'shared USB arbiter post-context'
require_hex "$POLICY_SOURCE" 800672 12 \
    1c5800940041201ed1ffff17 'executable cave pre-context'
require_hex "$POLICY_SOURCE" 802816 16 \
    5f2403d5880a9cd2e81cb7f2c86edcf2 '__cfi_check cave boundary'
require_hex "$FLINGER_SOURCE" 1772156 8 097097521f01096b 'Mixer sync pre-context'
require_hex "$FLINGER_SOURCE" 1772168 12 000180520fa9029460020036 'Mixer sync post-context'
require_hex "$HAL_SOURCE" 2295940 16 2800805288521e3988f24679809207b9 'HAL usecase-gate pre-context'
require_hex "$HAL_SOURCE" 2295972 16 88e641f9a80100b480e225915ce10194 'HAL usecase-gate post-context'

require_one_of_hex "$POLICY_SOURCE" 799328 4 '00050036 1f2003d5' 'profile initialization'
require_one_of_hex "$POLICY_SOURCE" 867300 12 \
    '480000d0088944f9165d40a9 2800403988000037097d0153' 'application hook'
require_one_of_hex "$POLICY_SOURCE" 869060 4 '030b40b9 e3031f2a' 'profile strategy'
require_one_of_hex "$POLICY_SOURCE" 873908 4 \
    '60010054 0b000014 62010054' 'effect-state gate'
require_one_of_hex "$POLICY_SOURCE" 231424 4 \
    '0980a052 eb2b0214' 'HIFI profile default-rate hook'
require_one_of_hex "$POLICY_SOURCE" 350044 4 \
    'a8c303d1 19b80114' 'Preferred Mixer routing hook'
require_one_of_hex "$POLICY_SOURCE" 874428 4 \
    'd9020036 5bb8ff17' 'shared USB backend arbiter'
require_one_of_hex "$FLINGER_SOURCE" 1772164 4 '480d0054 6a000014' 'Mixer synchronization'
require_one_of_hex "$USB_SOURCE" 29024 4 '20620500 44ac0000' 'USB rate slot 1'
require_one_of_hex "$USB_SOURCE" 29052 4 '44ac0000 20620500' 'USB rate slot 2'
require_one_of_hex "$HAL_SOURCE" 2295956 16 \
    '1f350071600000541f210071e1010054 092184522925c81a090200361f2003d5' \
    'HAL sampling-rate reopen usecases'

if region_matches_file "$POLICY_SOURCE" 800684 "$MODPATH/patches/preferred_hifi_cave.bin"; then
    preferred_cave_state=patched
elif region_is_zero "$POLICY_SOURCE" 800684 374; then
    preferred_cave_state=stock
else
    abort "! Preferred Mixer executable cave is occupied or partially patched"
fi
region_is_zero "$POLICY_SOURCE" 801058 6 \
    || abort "! Alignment gap after Preferred Mixer cave is occupied"
ARBITER_CAVE_OFFSET=801064
ARBITER_CAVE_CAPACITY=1752
ARBITER_CAVE_SIZE=$(stat -c '%s' "$MODPATH/patches/shared_arbiter_cave.bin" 2>/dev/null)
[ -n "$ARBITER_CAVE_SIZE" ] && [ "$ARBITER_CAVE_SIZE" -le "$ARBITER_CAVE_CAPACITY" ] \
    || abort "! Shared USB arbiter exceeds the reserved executable cave"
ARBITER_CAVE_REMAINDER_OFFSET=$((ARBITER_CAVE_OFFSET + ARBITER_CAVE_SIZE))
ARBITER_CAVE_REMAINDER_SIZE=$((ARBITER_CAVE_CAPACITY - ARBITER_CAVE_SIZE))
if region_matches_file "$POLICY_SOURCE" "$ARBITER_CAVE_OFFSET" \
        "$MODPATH/patches/shared_arbiter_cave.bin"; then
    arbiter_cave_state=patched
elif region_is_zero "$POLICY_SOURCE" "$ARBITER_CAVE_OFFSET" "$ARBITER_CAVE_CAPACITY"; then
    arbiter_cave_state=stock
else
    abort "! Shared USB arbiter executable cave is occupied or partially patched"
fi
region_is_zero "$POLICY_SOURCE" "$ARBITER_CAVE_REMAINDER_OFFSET" \
    "$ARBITER_CAVE_REMAINDER_SIZE" \
    || abort "! Shared USB arbiter cave remainder is not empty"
ui_print "- Preferred Mixer cave structural state: $preferred_cave_state"
ui_print "- Shared USB arbiter cave structural state: $arbiter_cave_state"

report_known_hash "$POLICY_SOURCE" AudioPolicyManager
report_known_hash "$FLINGER_SOURCE" AudioFlinger
report_known_hash "$USB_SOURCE" Qualcomm-USB
report_known_hash "$HAL_SOURCE" Qualcomm-AIDL-HAL
report_known_hash "$PRIMARY_XML_SOURCE" primary-audio-XML

mkdir -p "$MODPATH/system/lib64" || abort "! Cannot create system overlay"
mkdir -p "${USB_DEST%/*}" || abort "! Cannot create vendor overlay"
mkdir -p "${HAL_DEST%/*}" || abort "! Cannot create HAL overlay"
mkdir -p "${PRIMARY_XML_DEST%/*}" || abort "! Cannot create ODM audio overlay"
cp -p "$POLICY_SOURCE" "$POLICY_DEST" || abort "! Cannot stage AudioPolicyManager"
cp -p "$FLINGER_SOURCE" "$FLINGER_DEST" || abort "! Cannot stage AudioFlinger"
cp -p "$USB_SOURCE" "$USB_DEST" || abort "! Cannot stage Qualcomm USB library"
cp -p "$HAL_SOURCE" "$HAL_DEST" || abort "! Cannot stage Qualcomm AIDL HAL"
patch_primary_xml "$PRIMARY_XML_SOURCE" "$PRIMARY_XML_DEST"

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
    1f2003d5:2800403988000037097d0153:030b40b9:62010054) policy_state=complete-scoped ;;
    *) abort "! AudioPolicyManager patch combination is inconsistent" ;;
esac
ui_print "- AudioPolicyManager structural state: $policy_state"

if [ "$hook_state" = 480000d0088944f9165d40a9 ]; then
    write_patch "$MODPATH/patches/is_app_allowed_hook.bin" "$POLICY_DEST" 867276
fi
if [ "$strategy_state" = e3031f2a ]; then
    write_patch "$MODPATH/patches/strategy_restore_patch.bin" "$POLICY_DEST" 869060
fi
case "$effect_state" in
    60010054|0b000014) write_patch "$MODPATH/patches/effect_gate_patch.bin" "$POLICY_DEST" 873908 ;;
esac
if [ "$profile_state" = 00050036 ]; then
    write_patch "$MODPATH/patches/profile_init_patch.bin" "$POLICY_DEST" 799328
fi

hifi_config_state=$(read_hex "$POLICY_DEST" 231424 4)
preferred_branch_state=$(read_hex "$POLICY_DEST" 350044 4)
case "$hifi_config_state:$preferred_branch_state:$preferred_cave_state" in
    0980a052:a8c303d1:stock)
        write_patch "$MODPATH/patches/preferred_hifi_cave.bin" "$POLICY_DEST" 800684
        write_patch "$MODPATH/patches/hifi_config_branch.bin" "$POLICY_DEST" 231424
        write_patch "$MODPATH/patches/preferred_hifi_branch.bin" "$POLICY_DEST" 350044
        ;;
    eb2b0214:19b80114:patched) ;;
    *) abort "! Preferred Mixer/HIFI patch combination is inconsistent" ;;
esac

arbiter_branch_state=$(read_hex "$POLICY_DEST" 874428 4)
case "$arbiter_branch_state:$arbiter_cave_state" in
    d9020036:stock)
        write_patch "$MODPATH/patches/shared_arbiter_cave.bin" "$POLICY_DEST" \
            "$ARBITER_CAVE_OFFSET"
        write_patch "$MODPATH/patches/shared_arbiter_branch.bin" "$POLICY_DEST" 874428
        ;;
    5bb8ff17:patched) ;;
    *) abort "! Shared USB arbiter patch combination is inconsistent" ;;
esac

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

hal_state=$(read_hex "$HAL_DEST" 2295956 16)
case "$hal_state" in
    1f350071600000541f210071e1010054)
        write_patch "$MODPATH/patches/hal_deep_buffer_reopen_patch.bin" "$HAL_DEST" 2295956
        ;;
    092184522925c81a090200361f2003d5) ;;
    *) abort "! Qualcomm AIDL HAL usecase gate is inconsistent" ;;
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
[ "$(stat -c '%s' "$HAL_DEST")" = "$HAL_ORIGINAL_SIZE" ] \
    || abort "! Qualcomm AIDL HAL size changed during patching"
if [ "$PRIMARY_XML_STATE" = stock ]; then
    [ "$(stat -c '%s' "$PRIMARY_XML_DEST")" -gt "$PRIMARY_XML_ORIGINAL_SIZE" ] \
        || abort "! Primary audio XML did not gain the legacy 44.1 kHz declarations"
else
    [ "$(stat -c '%s' "$PRIMARY_XML_DEST")" = "$PRIMARY_XML_ORIGINAL_SIZE" ] \
        || abort "! Already-patched primary audio XML changed unexpectedly"
fi
require_hex "$POLICY_DEST" 799328 4 1f2003d5 'patched profile initialization'
require_hex "$POLICY_DEST" 867300 12 2800403988000037097d0153 'patched application hook'
require_hex "$POLICY_DEST" 869060 4 030b40b9 'restored per-profile strategy load'
require_hex "$POLICY_DEST" 873908 4 62010054 'patched effect-state gate'
require_hex "$POLICY_DEST" 231424 4 eb2b0214 'patched HIFI default-rate branch'
require_hex "$POLICY_DEST" 350044 4 19b80114 'patched Preferred Mixer routing branch'
region_matches_file "$POLICY_DEST" 800684 "$MODPATH/patches/preferred_hifi_cave.bin" \
    || abort "! Preferred Mixer executable cave write verification failed"
region_is_zero "$POLICY_DEST" 801058 6 \
    || abort "! Preferred Mixer patch overflowed its reserved cave region"
require_hex "$POLICY_DEST" 874428 4 5bb8ff17 'patched shared USB arbiter branch'
region_matches_file "$POLICY_DEST" "$ARBITER_CAVE_OFFSET" \
    "$MODPATH/patches/shared_arbiter_cave.bin" \
    || abort "! Shared USB arbiter executable cave write verification failed"
region_is_zero "$POLICY_DEST" "$ARBITER_CAVE_REMAINDER_OFFSET" \
    "$ARBITER_CAVE_REMAINDER_SIZE" \
    || abort "! Shared USB arbiter overflowed its reserved cave region"
require_hex "$FLINGER_DEST" 1772164 4 6a000014 'patched Mixer synchronization'
require_hex "$USB_DEST" 29024 4 44ac0000 'patched USB 44.1 slot'
require_hex "$USB_DEST" 29052 4 20620500 'patched USB 352.8 slot'
require_hex "$HAL_DEST" 2295956 16 092184522925c81a090200361f2003d5 \
    'patched HAL sampling-rate reopen usecases'
require_exact_line_count "$PRIMARY_XML_DEST" \
    '            <profile samplingRates="44100 48000" channelLayouts="LAYOUT_STEREO" formatType="PCM" pcmType="INT_24_BIT" />' \
    1 'patched deep-buffer PCM24 rates'
require_exact_line_count "$PRIMARY_XML_DEST" \
    '            <profile samplingRates="44100 48000" channelLayouts="LAYOUT_STEREO" formatType="PCM" pcmType="INT_32_BIT" />' \
    1 'patched deep-buffer PCM32 rates'
require_binary_string "$POLICY_DEST" com.apple.android.music 'patched package allowlist'
require_binary_string "$POLICY_DEST" com.netease.cloudmusic 'patched package allowlist'
report_known_hash "$POLICY_DEST" 'patched AudioPolicyManager'
report_known_hash "$FLINGER_DEST" 'patched AudioFlinger'
report_known_hash "$USB_DEST" 'patched Qualcomm-USB'
report_known_hash "$HAL_DEST" 'patched Qualcomm-AIDL-HAL'

rm -rf "$MODPATH/patches"
set_perm "$POLICY_DEST" 0 0 0644 u:object_r:system_lib_file:s0
set_perm "$FLINGER_DEST" 0 0 0644 u:object_r:system_lib_file:s0
set_perm "$USB_DEST" 0 0 0644 u:object_r:vendor_file:s0
set_perm "$HAL_DEST" 0 0 0644 u:object_r:vendor_file:s0
set_perm "$PRIMARY_XML_DEST" 0 0 0644 u:object_r:vendor_configs_file:s0

ui_print "- Whitelist: Apple Music and NetEase Cloud Music only"
ui_print "- Routing: whitelist media selects the native dynamic USB hifi_playback profile"
ui_print "- Preferred Mixer: DEFAULT behavior, PCM32/stereo bootstrap; never BIT_PERFECT"
ui_print "- Ownership: preserve repeated-track counts; replace only when whitelist UID changes"
ui_print "- HIFI profile: repair Xiaomi's zero default rate; retain native LATEST_MAX strategy"
ui_print "- USB arbitration: native HIFI/Deep counters control their one shared backend"
ui_print "- Concurrency: Deep temporarily wins; HIFI rate is restored when Deep becomes idle"
ui_print "- Profile: initialize Xiaomi deep_buffer_out without globally enabling Feature 8"
ui_print "- Strategy: LATEST_MAX only for Deep Buffer/HIFI; preserve VoIP's stock policy"
ui_print "- USB deep-buffer: accept NONE/UNKNOWN; still block Dolby/MiSound"
ui_print "- Mixer: synchronize in place for 44.1/48/88.2/96/192 kHz changes"
ui_print "- HAL: reopen PAL for DEEP_BUFFER(3), preserving VOIP(8) and HIFI(13)"
ui_print "- XML: restore the HIDL-era 44.1/48 kHz PCM24/PCM32 deep-buffer profiles"
ui_print "- USB capability: 44.1 kHz is inside Qualcomm's seven-rate list"
ui_print "- PCM32 remains the HAL/mixer format; no Float HAL claim"
ui_print "- HIFI: retain Xiaomi's native manager; do not force the unstable BIT_PERFECT usecase"
ui_print "- No daemon, Zygisk, polling loop, userspace watcher, or live restart"
ui_print "- System overlay is delegated to Magisk or the active KernelSU metamodule"
ui_print "! Experimental and exact-firmware-only; reboot is required"
