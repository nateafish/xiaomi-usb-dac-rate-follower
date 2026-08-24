#!/system/bin/sh

. "$MODPATH/lib/install-state.sh" \
    || abort "! Missing install-state helper"
. "$MODPATH/lib/target-selection.sh" \
    || abort "! Missing target-selection helper"

ELFPATCHER=$MODPATH/bin/elfpatcher
chmod 0755 "$ELFPATCHER" 2>/dev/null \
    || abort "! Cannot make the ELF patch engine executable"
[ -x "$ELFPATCHER" ] || abort "! Missing ELF patch engine"

prepare_install_state \
    || abort "! A clean uninstall and reboot are required before installation"
select_audio_target

POLICY_LIVE=$POLICY_PATH
COMPONENTS_LIVE=$COMPONENTS_PATH
IMPL_LIVE=$POLICY_IMPL_PATH
FLINGER_LIVE=$FLINGER_PATH
USB_LIVE=$USB_PATH
HAL_LIVE=$CORE_HAL_PATH

POLICY_DEST=$(overlay_destination_for "$POLICY_LIVE") \
    || abort "! Cannot map AudioPolicyManager overlay path"
FLINGER_DEST=$(overlay_destination_for "$FLINGER_LIVE") \
    || abort "! Cannot map AudioFlinger overlay path"
USB_DEST=$(overlay_destination_for "$USB_LIVE") \
    || abort "! Cannot map Qualcomm USB overlay path"
HAL_DEST=$(overlay_destination_for "$HAL_LIVE") \
    || abort "! Cannot map Qualcomm HAL overlay path"

POLICY_SOURCE=$(patch_source_for "$POLICY_LIVE") \
    || abort "! Cannot resolve the AudioPolicyManager patch base"
COMPONENTS_SOURCE=$(patch_source_for "$COMPONENTS_LIVE") \
    || abort "! Cannot resolve the AudioPolicyComponents validation base"
IMPL_SOURCE=$(patch_source_for "$IMPL_LIVE") \
    || abort "! Cannot resolve the Xiaomi AudioPolicyImpl validation base"
FLINGER_SOURCE=$(patch_source_for "$FLINGER_LIVE") \
    || abort "! Cannot resolve the AudioFlinger patch base"
USB_SOURCE=$(patch_source_for "$USB_LIVE") \
    || abort "! Cannot resolve the Qualcomm USB patch base"
HAL_SOURCE=$(patch_source_for "$HAL_LIVE") \
    || abort "! Cannot resolve the Qualcomm audio HAL patch base"

if { [ "${KSU:-}" = true ] || [ -x /data/adb/ksud ]; } \
        && [ ! -L /data/adb/metamodule ]; then
    abort "! KernelSU requires an active metamodule (meta-overlayfs recommended)"
fi

require_elf() {
    elf_file=$1
    elf_label=$2
    elf_info=$($ELFPATCHER info "$elf_file" 2>&1) || {
        ui_print "! $elf_label: $elf_info"
        abort "! Invalid or unsupported ELF"
    }
    echo "$elf_info" | grep -q '^machine=aarch64$' \
        || abort "! $elf_label is not AArch64"
}

require_binary_string() {
    grep -a -q "$2" "$1" 2>/dev/null \
        || abort "! Missing semantic marker in $3: $2"
}

sha_of() {
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

require_elf "$POLICY_SOURCE" AudioPolicyManager
require_elf "$COMPONENTS_SOURCE" AudioPolicyComponents
require_elf "$IMPL_SOURCE" Xiaomi-AudioPolicyImpl
require_elf "$FLINGER_SOURCE" AudioFlinger
require_elf "$USB_SOURCE" Qualcomm-USB
require_elf "$HAL_SOURCE" Qualcomm-Audio-HAL
require_binary_string "$POLICY_SOURCE" HifiSampleRateManager: AudioPolicyManager
require_binary_string "$POLICY_SOURCE" hifi_playback AudioPolicyManager
require_binary_string "$IMPL_SOURCE" AudioPolicyManagerImpl Xiaomi-AudioPolicyImpl
require_binary_string "$USB_SOURCE" readSupportedSampleRate Qualcomm-USB
if ! grep -a -q HifiPlayback "$HAL_SOURCE" 2>/dev/null; then
    require_binary_string "$HAL_SOURCE" DeepBufferPlayback Qualcomm-Audio-HAL
    require_binary_string "$HAL_SOURCE" MiStreamOutPrimary Qualcomm-Audio-HAL
fi

mkdir -p "${POLICY_DEST%/*}" "${FLINGER_DEST%/*}" \
    "${USB_DEST%/*}" "${HAL_DEST%/*}" \
    || abort "! Cannot create overlay directories"
cp -p "$POLICY_SOURCE" "$POLICY_DEST" \
    || abort "! Cannot stage AudioPolicyManager"
cp -p "$FLINGER_SOURCE" "$FLINGER_DEST" \
    || abort "! Cannot stage AudioFlinger"
cp -p "$USB_SOURCE" "$USB_DEST" \
    || abort "! Cannot stage Qualcomm USB library"
cp -p "$HAL_SOURCE" "$HAL_DEST" \
    || abort "! Cannot stage Qualcomm audio HAL"

POLICY_SIZE=$(stat -c '%s' "$POLICY_DEST")
FLINGER_SIZE=$(stat -c '%s' "$FLINGER_DEST")
USB_SIZE=$(stat -c '%s' "$USB_DEST")
HAL_SIZE=$(stat -c '%s' "$HAL_DEST")

PATCH_DRIVER=$MODPATH/lib/$TARGET_PATCH_DRIVER
[ -r "$PATCH_DRIVER" ] || abort "! Missing target patch driver: $TARGET_PATCH_DRIVER"
. "$PATCH_DRIVER" || abort "! Cannot load target patch driver"
apply_target_patches

[ "$(stat -c '%s' "$POLICY_DEST")" = "$POLICY_SIZE" ] \
    || abort "! AudioPolicyManager size changed"
[ "$(stat -c '%s' "$FLINGER_DEST")" = "$FLINGER_SIZE" ] \
    || abort "! AudioFlinger size changed"
[ "$(stat -c '%s' "$USB_DEST")" = "$USB_SIZE" ] \
    || abort "! Qualcomm USB library size changed"
[ "$(stat -c '%s' "$HAL_DEST")" = "$HAL_SIZE" ] \
    || abort "! Qualcomm audio HAL size changed"
PLAYER_MANIFEST=$MODPATH/config/player-packages.tsv
[ -r "$PLAYER_MANIFEST" ] || abort "! Missing player package manifest"
PLAYER_LABELS=
player_tab=$(printf '\t')
while IFS="$player_tab" read -r player_package player_label player_validation; do
    case "$player_package" in
        ''|'#'*) continue ;;
    esac
    require_binary_string "$POLICY_DEST" "$player_package" \
        'patched package policy'
    if [ -z "$PLAYER_LABELS" ]; then
        PLAYER_LABELS=$player_label
    else
        PLAYER_LABELS="$PLAYER_LABELS, $player_label"
    fi
done < "$PLAYER_MANIFEST"

ui_print "- AudioPolicyManager SHA-256: $(sha_of "$POLICY_DEST")"
ui_print "- AudioFlinger SHA-256: $(sha_of "$FLINGER_DEST")"
ui_print "- Qualcomm USB SHA-256: $(sha_of "$USB_DEST")"
ui_print "- Qualcomm HAL SHA-256: $(sha_of "$HAL_DEST")"

rm -rf "$MODPATH/patches" "$MODPATH/bin" "$MODPATH/targets" \
    "$MODPATH/config"
set_perm "$POLICY_DEST" 0 0 0644 u:object_r:system_lib_file:s0
case "$FLINGER_LIVE" in
    /system_ext/*) set_perm "$FLINGER_DEST" 0 0 0644 u:object_r:system_lib_file:s0 ;;
    *) set_perm "$FLINGER_DEST" 0 0 0644 u:object_r:system_lib_file:s0 ;;
esac
set_perm "$USB_DEST" 0 0 0644 u:object_r:vendor_file:s0
set_perm "$HAL_DEST" 0 0 0644 u:object_r:vendor_file:s0

ui_print "- Packages: $PLAYER_LABELS"
ui_print "- Route: Xiaomi native hifi_playback on USB-only outputs"
ui_print "- Matching: Android/SoC/HAL baseline plus unique semantic ELF signatures"
ui_print "- Injection: runtime AArch64 relocation; no fixed file offsets"
ui_print "- Bluetooth, speaker, mixed, empty and stale routes fail closed"
ui_print "- No daemon, polling loop, Zygisk or application hook"
ui_print "! Experimental alpha; reboot is required"
