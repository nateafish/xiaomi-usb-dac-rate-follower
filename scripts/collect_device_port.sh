#!/usr/bin/env bash
set -Eeuo pipefail

COLLECTOR_VERSION=2
MODULE_ID=xiaomi-usb-dac-rate-follower

usage() {
    cat <<'EOF'
Usage:
  bash scripts/collect_device_port.sh port [options] [output-directory]
  bash scripts/collect_device_port.sh issue [options] [output-directory]

Modes:
  port   Collect an unmodified stock baseline for adapting a new device.
         The Xiaomi USB DAC Rate Follower module must not be installed.
  issue  Collect runtime evidence after this module has been installed.
         The installed module payload and its patched overlays are included.

Options:
  -s, --serial SERIAL       Select one adb device (also accepts ANDROID_SERIAL).
  -o, --output DIRECTORY   Set the output directory name.
      --capture-transitions
                            Interactively record all seven target rates, return
                            to 44.1 kHz, stop, and DAC reconnect in one window.
      --keep-directory     Keep the unpacked directory as well as the archive.
      --no-archive         Keep only the unpacked directory.
  -h, --help               Show this help.

The collection is read-only on the Android device. It does not install or
remove modules, clear logs, copy APKs/music, or extract partition images.
By default only one xiaomi-usb-dac-{port,issue}-*.tar.gz is kept on the host.
Always review the archive for personal information before attaching it to an
Issue.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

MODE=
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi
case "${1:-}" in
    port|issue) MODE=$1; shift ;;
    '') usage >&2; exit 2 ;;
    *) die "the first argument must be 'port' or 'issue' (use --help)" ;;
esac

SERIAL=${ANDROID_SERIAL:-}
OUT_ARG=
CAPTURE_TRANSITIONS=0
KEEP_DIRECTORY=0
CREATE_ARCHIVE=1
while (($#)); do
    case "$1" in
        -s|--serial)
            (($# >= 2)) || die "$1 requires a value"
            SERIAL=$2
            shift 2
            ;;
        -o|--output)
            (($# >= 2)) || die "$1 requires a value"
            [[ -z "$OUT_ARG" ]] || die "the output directory was specified twice"
            OUT_ARG=$2
            shift 2
            ;;
        --capture-transitions)
            CAPTURE_TRANSITIONS=1
            shift
            ;;
        --keep-directory)
            KEEP_DIRECTORY=1
            shift
            ;;
        --no-archive)
            CREATE_ARCHIVE=0
            KEEP_DIRECTORY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            (($# <= 1)) || die "too many positional arguments"
            if (($# == 1)); then
                [[ -z "$OUT_ARG" ]] || die "the output directory was specified twice"
                OUT_ARG=$1
            fi
            shift "$#"
            ;;
        -*) die "unknown option: $1" ;;
        *)
            [[ -z "$OUT_ARG" ]] || die "too many output directories"
            OUT_ARG=$1
            shift
            ;;
    esac
done

if ((CAPTURE_TRANSITIONS)) && [[ ! -t 0 ]]; then
    die "--capture-transitions requires an interactive terminal"
fi

ADB_BIN=${ADB:-adb}
command -v "$ADB_BIN" >/dev/null 2>&1 || die "adb is required"
ADB_CMD=("$ADB_BIN")
[[ -z "$SERIAL" ]] || ADB_CMD+=( -s "$SERIAL" )

adb_run() {
    "${ADB_CMD[@]}" "$@"
}

adb_run get-state >/dev/null 2>&1 \
    || die "no selected adb device is ready; use --serial when several are connected"

ROOT_ID=$(adb_run exec-out su -c id 2>/dev/null | tr -d '\r' || true)
[[ "$ROOT_ID" == *"uid=0"* ]] \
    || die "a working root shell through 'adb shell su -c' is required"

remote() {
    adb_run exec-out su -c "$1" 2>/dev/null | tr -d '\r'
}

DEVICE=$(remote 'getprop ro.product.device' | head -n 1)
DEVICE=${DEVICE:-unknown-device}
DEVICE=${DEVICE//[^[:alnum:]_.-]/_}
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
if [[ -z "$OUT_ARG" ]]; then
    OUT_ARG="xiaomi-usb-dac-${MODE}-${DEVICE}-${TIMESTAMP}"
fi

OUT_PARENT=$(dirname "$OUT_ARG")
OUT_BASE=$(basename "$OUT_ARG")
case "$OUT_BASE" in
    ''|.|..) die "unsafe output directory: $OUT_ARG" ;;
esac
mkdir -p "$OUT_PARENT"
OUT_PARENT=$(cd "$OUT_PARENT" && pwd -P)
OUT="$OUT_PARENT/$OUT_BASE"
ARCHIVE="$OUT.tar.gz"
[[ ! -e "$OUT" ]] || die "output directory already exists: $OUT"
if ((CREATE_ARCHIVE)); then
    [[ ! -e "$ARCHIVE" && ! -e "$ARCHIVE.part" ]] \
        || die "output archive already exists: $ARCHIVE"
fi

MODULE_PATHS="/data/adb/modules/$MODULE_ID /data/adb/modules_update/$MODULE_ID"
MODULE_PRESENT=$(remote "for d in $MODULE_PATHS; do [ -f \"\$d/module.prop\" ] && echo \"\$d\"; done" || true)
if [[ "$MODE" == port && -n "$MODULE_PRESENT" ]]; then
    die "port mode requires a stock view; uninstall $MODULE_ID, reboot, then collect again"
fi
if [[ "$MODE" == issue && -z "$MODULE_PRESENT" ]]; then
    die "issue mode requires the installed $MODULE_ID module; use 'port' for a new device"
fi
if [[ "$MODE" == port ]]; then
    FOREIGN_AUDIO_OVERLAYS=$(remote '
        for d in /data/adb/modules/*; do
            [ -d "$d" ] || continue
            [ "${d##*/}" = xiaomi-usb-dac-rate-follower ] && continue
            [ -e "$d/disable" ] && continue
            find "$d/system" -type f \( \
                -name "libaudiopolicymanagerdefault.so" -o \
                -name "libaudioflinger.so" -o -name "libaudioflingerimpl.so" -o \
                -name "libdev_usb.so" -o -name "libar-pal.so" -o \
                -iname "*audiocorehal*.so" -o -iname "audio.primary*.so" \
                \) -print 2>/dev/null
        done
    ' || true)
    [[ -z "$FOREIGN_AUDIO_OVERLAYS" ]] || die \
        "another active module overlays a target audio library; disable or uninstall it, reboot, then collect the stock baseline"
fi

mkdir -p "$OUT/files" "$OUT/state" "$OUT/logs"
printf '%s\n' "$COLLECTOR_VERSION" > "$OUT/.collector-created"
WARNINGS="$OUT/state/collection-warnings.txt"
: > "$WARNINGS"
LOG_PID=
FINISHED=0

cleanup() {
    local status=$?
    if [[ -n "$LOG_PID" ]]; then
        kill "$LOG_PID" >/dev/null 2>&1 || true
        wait "$LOG_PID" >/dev/null 2>&1 || true
    fi
    if ((status != 0)) && [[ -d "$OUT" ]]; then
        printf 'Collection failed; partial files were kept at %s\n' "$OUT" >&2
    fi
    if ((FINISHED == 0 && status == 0)); then
        status=1
    fi
    return "$status"
}
trap cleanup EXIT

warn() {
    printf '%s\n' "$*" >> "$WARNINGS"
}

save_text() {
    local name=$1
    local command=$2
    local destination="$OUT/$name"
    mkdir -p "$(dirname "$destination")"
    if remote "$command" > "$destination.part"; then
        mv "$destination.part" "$destination"
    else
        mv "$destination.part" "$destination" 2>/dev/null || true
        warn "Command was incomplete: $name"
    fi
}

copy_root_file() {
    local source=$1
    local relative destination
    [[ "$source" == /* ]] || {
        warn "Skipped a non-absolute device path: $source"
        return 0
    }
    if [[ ! "$source" =~ ^/[[:alnum:]_./@:+,=-]+$ ]]; then
        warn "Skipped a device path with unsafe characters: $source"
        return 0
    fi
    relative=${source#/}
    destination="$OUT/files/$relative"
    [[ ! -e "$destination" ]] || return 0
    mkdir -p "$(dirname "$destination")"
    if adb_run exec-out su -c "test -r '$source' && cat '$source'" \
            > "$destination.part" 2>/dev/null \
            && [[ -s "$destination.part" ]]; then
        mv "$destination.part" "$destination"
    else
        rm -f "$destination.part"
        warn "Could not copy: $source"
    fi
}

copy_list() {
    local command=$1
    local path
    while IFS= read -r path; do
        [[ -z "$path" ]] || copy_root_file "$path"
    done < <(remote "$command" || true)
}

collect_common_state() {
    save_text state/target-identity.txt '
        printf "=== build identity ===\n"
        for p in ro.system.build.version.sdk ro.system.build.version.release ro.build.version.sdk ro.build.version.release ro.product.model ro.product.device ro.product.system.device ro.product.odm.device ro.product.vendor.device ro.board.platform ro.soc.manufacturer ro.soc.model ro.boot.hardware ro.boot.hardware.sku ro.build.id ro.build.version.incremental ro.system.build.version.incremental ro.vendor.build.version.incremental ro.odm.build.version.incremental ro.product.build.version.incremental ro.build.fingerprint; do
            printf "%s=" "$p"; getprop "$p"
        done
        printf "\n=== kernel and root ===\n"
        uname -a
        id
        command -v su 2>/dev/null || true
        su -V 2>/dev/null || true
        magisk -V 2>/dev/null || true
        ksud -V 2>/dev/null || true
        printf "\n=== Audio Core declarations ===\n"
        grep -RniE "<hal format=\"(aidl|hidl)\">|android.hardware.audio.(core|effect)|android.hardware.audio@" /vendor/etc/vintf /odm/etc/vintf /system/etc/vintf /system_ext/etc/vintf /product/etc/vintf 2>/dev/null || true
    '
    save_text state/audio-properties.txt '
        getprop | grep -iE "\[(ro\.(product|system|vendor|odm|boot|soc|board)|persist\.(vendor\.)?audio|vendor\.audio|audio|sound|usb)[^]]*\]" || true
    '
    save_text state/audio-services.txt '
        service list 2>/dev/null | grep -iE "audio|sound" || true
        printf "\n=== dumpsys services ===\n"
        dumpsys -l 2>/dev/null | grep -iE "audio|sound" || true
        printf "\n=== lshal ===\n"
        lshal 2>/dev/null | grep -iE "audio|effect" || true
    '
    save_text state/audio-processes.txt '
        for d in /proc/[0-9]*; do
            p=${d##*/}
            cmd=$(tr "\000" " " < "$d/cmdline" 2>/dev/null)
            case "$cmd" in
                *audioserver*|*audiohal*|*hardware.audio*|*audio.service*|*vendor.audio*)
                    context=$(cat "$d/attr/current" 2>/dev/null)
                    exe=$(readlink "$d/exe" 2>/dev/null)
                    printf "pid=%s context=%s exe=%s cmd=%s\n" "$p" "$context" "$exe" "$cmd"
                    ;;
            esac
        done
    '
    save_text state/root-overlay.txt '
        printf "=== this module ===\n"
        for d in /data/adb/modules/xiaomi-usb-dac-rate-follower /data/adb/modules_update/xiaomi-usb-dac-rate-follower; do
            [ -e "$d" ] || continue
            echo "--- $d ---"
            ls -la "$d" 2>/dev/null || true
            cat "$d/module.prop" 2>/dev/null || true
            find "$d" -maxdepth 3 -type f 2>/dev/null | sort
        done
        printf "\n=== installed module metadata ===\n"
        find /data/adb/modules /data/adb/modules_update -mindepth 2 -maxdepth 2 -type f -name module.prop -print -exec cat {} \; 2>/dev/null || true
        printf "\n=== metamodule ===\n"
        ls -la /data/adb/metamodule 2>/dev/null || true
    '
    save_text state/audio-policy.txt 'dumpsys media.audio_policy 2>&1'
    save_text state/audio-flinger.txt 'dumpsys media.audio_flinger 2>&1'
    save_text state/alsa.txt '
        cat /proc/asound/cards 2>/dev/null || true
        printf "\n=== pcm ===\n"
        cat /proc/asound/pcm 2>/dev/null || true
        printf "\n=== streams ===\n"
        find /proc/asound -type f \( -name stream0 -o -name stream1 \) -print 2>/dev/null | sort | while read -r f; do echo "=== $f ==="; cat "$f"; done
    '
    save_text state/usb.txt '
        dumpsys usb 2>/dev/null || true
        printf "\n=== USB sound descriptors ===\n"
        for f in /proc/asound/card*/stream*; do [ -r "$f" ] && { echo "=== $f ==="; cat "$f"; }; done
    '
    save_text state/audio-process-maps.txt '
        for d in /proc/[0-9]*; do
            p=${d##*/}
            cmd=$(tr "\000" " " < "$d/cmdline" 2>/dev/null)
            case "$cmd" in
                *audioserver*|*audiohal*|*hardware.audio*|*audio.service*|*vendor.audio*)
                    echo "=== PID $p: $cmd ==="
                    cat "$d/maps" 2>/dev/null || true
                    ;;
            esac
        done
    '
    save_text logs/audio-health-recent.txt '
        printf "=== filtered logcat ===\n"
        logcat -d -b all -v threadtime -t 6000 2>/dev/null | grep -iE "audio|audioserver|audioflinger|audiopolicy|audiocore|pal|agm|alsa|usb|hifi|sample.?rate|sampling_rate|tombstone|fatal|abort" || true
        printf "\n=== crash buffer ===\n"
        logcat -d -b crash -v threadtime -t 1000 2>/dev/null || true
        printf "\n=== filtered kernel log ===\n"
        dmesg 2>/dev/null | tail -n 4000 | grep -iE "audio|alsa|usb|snd|audioserver|avc:.*(audio|vendor_file|system_lib_file)" || true
    '
}

collect_port_files() {
    save_text state/library-inventory.txt '
        find /system/lib /system/lib64 /system_ext/lib /system_ext/lib64 /vendor/lib /vendor/lib64 /odm/lib /odm/lib64 /product/lib /product/lib64 /vendor/bin /vendor/bin/hw /odm/bin /odm/bin/hw -type f \( -iname "*audio*" -o -iname "*pal*" -o -iname "*agm*" -o -iname "*acdb*" -o -iname "*sndcard*" \) -print 2>/dev/null | sort -u
    '

    copy_list 'find /system/lib /system/lib64 /system_ext/lib /system_ext/lib64 /vendor/lib /vendor/lib64 /vendor/bin /vendor/bin/hw /odm/lib /odm/lib64 /odm/bin /odm/bin/hw /product/lib /product/lib64 -type f \( \
        -name "libaudiopolicymanagerdefault.so" -o -name "libaudiopolicycomponents.so" -o \
        -name "libaudiopolicymanagerimpl.so" -o -iname "*audiopolicymanager*stub*.so" -o \
        -name "libaudioclient.so" -o -name "libaudiopolicyservice.so" -o \
        -name "libaudioflinger.so" -o -name "libaudioflingerimpl.so" -o \
        -name "libdev_usb.so" -o -name "libar-pal.so" -o \
        -iname "*audioplatformconverter*.so" -o -iname "*audiocorehal*.so" -o \
        -iname "audio.primary*.so" -o -iname "audio.usb*.so" -o \
        -iname "audio.bluetooth*.so" -o -iname "android.hardware.audio*.so" -o \
        -iname "android.hardware.audio*.service" -o -iname "audiohalservice*" \
        \) -print 2>/dev/null | sort -u'

    copy_list 'for d in /proc/[0-9]*; do
        cmd=$(tr "\000" " " < "$d/cmdline" 2>/dev/null)
        case "$cmd" in
            *audioserver*|*audiohal*|*hardware.audio*|*audio.service*|*vendor.audio*)
                readlink "$d/exe" 2>/dev/null
                sed -n "s/.* \(\/[^ ]*\)$/\1/p" "$d/maps" 2>/dev/null | grep -iE "/([^/]*audio[^/]*|libpal|libar-pal|libagm|libacdb|libdev_usb|libqahw|libtinyalsa|libalsautils|libaudioroute)[^/]*$" || true
                ;;
        esac
    done | sort -u'

    copy_list 'find /vendor/etc /odm/etc /system/etc /system_ext/etc /product/etc -type f \( \
        -iname "*audio*policy*.xml" -o -iname "*audio*engine*.xml" -o \
        -iname "audio_module_config*.xml" -o -iname "vendor_audio_interfaces.xml" -o \
        -iname "*audio*.conf" -o -iname "*mixer*paths*.xml" \
        \) -print 2>/dev/null | sort -u
        for f in $(find /vendor/etc/vintf /odm/etc/vintf /system/etc/vintf /system_ext/etc/vintf /product/etc/vintf /vendor/etc/init /odm/etc/init /system/etc/init /system_ext/etc/init /product/etc/init -type f 2>/dev/null); do
            grep -qiE "android.hardware.audio|audiohal|audioserver|audio.core|audio.effect|libaudio|libpal|libagm" "$f" && echo "$f"
        done | sort -u'
}

collect_issue_files() {
    save_text state/installed-module.txt '
        for d in /data/adb/modules/xiaomi-usb-dac-rate-follower /data/adb/modules_update/xiaomi-usb-dac-rate-follower; do
            [ -e "$d" ] || continue
            echo "=== $d ==="
            find "$d" -maxdepth 12 -print 2>/dev/null | sort
            printf "\n--- module.prop ---\n"
            cat "$d/module.prop" 2>/dev/null || true
            printf "\n--- flags ---\n"
            for flag in disable remove update skip_mount; do [ -e "$d/$flag" ] && echo "$flag=present" || echo "$flag=absent"; done
        done
    '

    copy_list 'for d in /data/adb/modules/xiaomi-usb-dac-rate-follower /data/adb/modules_update/xiaomi-usb-dac-rate-follower; do
        [ -d "$d" ] || continue
        find "$d" -type f \( -name module.prop -o -path "*/state/*" -o -path "*/system/*" -o -name "*.log" -o -name service.sh -o -name post-fs-data.sh -o -name action.sh \) -print 2>/dev/null
    done | sort -u'

    copy_list 'find /system/lib /system/lib64 /system_ext/lib /system_ext/lib64 /vendor/lib /vendor/lib64 /odm/lib /odm/lib64 -type f \( \
        -name "libaudiopolicymanagerdefault.so" -o -name "libaudioflinger.so" -o \
        -name "libaudioflingerimpl.so" -o -name "libdev_usb.so" -o \
        -name "libar-pal.so" -o -iname "*audiocorehal*.so" -o \
        -iname "audio.primary*.so" \
        \) -print 2>/dev/null | sort -u'
}

capture_transitions() {
    local step slug observation
    [[ -t 0 ]] || die "--capture-transitions requires an interactive terminal"
    printf '\nStarting one filtered log window. The device log buffer will not be cleared.\n'
    printf 'Keep one USB DAC connected and use the same player unless a step says otherwise.\n\n'
    adb_run exec-out logcat -b all -v threadtime -T 1 \
        | awk '{ line=tolower($0); if (line ~ /audio|audioserver|audioflinger|audiopolicy|audiocore|pal|agm|alsa|usb|hifi|sample.?rate|sampling_rate|tombstone|fatal|abort/) print; fflush(); }' \
        > "$OUT/logs/transition-live.txt" &
    LOG_PID=$!
    printf 'capture_started=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > "$OUT/state/transition-observations.txt"

    for step in \
        'Play a native 44.1 kHz track|44100' \
        'Switch to a native 48 kHz track|48000' \
        'Switch to a native 88.2 kHz track|88200' \
        'Switch to a native 96 kHz track|96000' \
        'Switch to a native 176.4 kHz track|176400' \
        'Switch to a native 192 kHz track|192000' \
        'Switch to a native 384 kHz track|384000' \
        'Switch back to the native 44.1 kHz track|44100-return' \
        'Stop playback completely and wait several seconds|stopped' \
        'Unplug and reconnect the DAC, then wait for enumeration|reconnected'; do
        slug=${step#*|}
        printf '%s, then press Enter.\n' "${step%%|*}"
        IFS= read -r _
        printf 'DAC display / observed result (blank is allowed): '
        IFS= read -r observation
        printf '%s=%s\n' "$slug" "$observation" \
            >> "$OUT/state/transition-observations.txt"
        save_text "state/transitions/$slug-audio-policy.txt" \
            'dumpsys media.audio_policy 2>&1'
        save_text "state/transitions/$slug-audio-flinger.txt" \
            'dumpsys media.audio_flinger 2>&1'
        save_text "state/transitions/$slug-alsa.txt" \
            'cat /proc/asound/cards 2>/dev/null; cat /proc/asound/pcm 2>/dev/null; for f in /proc/asound/card*/stream*; do [ -r "$f" ] && { echo "=== $f ==="; cat "$f"; }; done; true'
    done
    printf 'capture_finished=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        >> "$OUT/state/transition-observations.txt"
    kill "$LOG_PID" >/dev/null 2>&1 || true
    wait "$LOG_PID" >/dev/null 2>&1 || true
    LOG_PID=
    [[ -s "$OUT/logs/transition-live.txt" ]] \
        || warn "The live transition log was empty"
}

require_any() {
    local label=$1
    shift
    local pattern
    for pattern in "$@"; do
        if find "$OUT/files" -type f -path "$pattern" -print -quit \
                | grep -q .; then
            return 0
        fi
    done
    warn "Missing expected port input: $label"
}

build_metadata() {
    local file relative size hash
    local file_count=0
    local file_bytes=0
    : > "$OUT/state/file-manifest.sha256"
    while IFS= read -r file; do
        relative=${file#"$OUT/"}
        size=$(wc -c < "$file" | tr -d ' ')
        if command -v shasum >/dev/null 2>&1; then
            hash=$(shasum -a 256 "$file" | awk '{print $1}')
        else
            hash=$(sha256sum "$file" | awk '{print $1}')
        fi
        printf '%s  %s  %s\n' "$hash" "$size" "$relative" \
            >> "$OUT/state/file-manifest.sha256"
        file_count=$((file_count + 1))
        file_bytes=$((file_bytes + size))
    done < <(find "$OUT/files" -type f | LC_ALL=C sort)

    local readelf_bin
    readelf_bin=$(command -v llvm-readelf || command -v readelf || true)
    if [[ -n "$readelf_bin" ]]; then
        : > "$OUT/state/elf-metadata.txt"
        while IFS= read -r file; do
            case "$file" in
                *.so|*/bin/*|*/bin/hw/*)
                    printf '=== %s ===\n' "${file#"$OUT/files/"}" \
                        >> "$OUT/state/elf-metadata.txt"
                    "$readelf_bin" -h -d -n "$file" \
                        >> "$OUT/state/elf-metadata.txt" 2>/dev/null || true
                    ;;
            esac
        done < <(find "$OUT/files" -type f | LC_ALL=C sort)
    else
        warn "Host readelf was unavailable; ELF metadata was not generated"
    fi

    {
        echo "schema=$COLLECTOR_VERSION"
        echo "mode=$MODE"
        echo "device=$DEVICE"
        echo "collected_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "capture_transitions=$CAPTURE_TRANSITIONS"
        echo "copied_file_count=$file_count"
        echo "copied_file_bytes=$file_bytes"
    } > "$OUT/state/collection.conf"
}

write_notes() {
    cat > "$OUT/PRIVACY-REVIEW.txt" <<'EOF'
Review before upload:

- Build fingerprints and firmware identifiers are intentionally included.
- USB descriptors or logs may include a DAC serial number.
- Filtered logs may still include application package names or file metadata.
- Root metadata lists installed modules and may reveal their names.
- Remove any line or file you do not want to publish.

The collector intentionally excludes APKs, music, app-private directories,
partition images, the full process list, and unfiltered main/system logcat.
EOF

    if [[ "$MODE" == port ]]; then
        cat > "$OUT/README.txt" <<'EOF'
This is a NEW-DEVICE PORT archive collected from the unmodified system view.

It contains the stock audio ELF files at their original paths, active policy,
VINTF/init configuration, audio service maps, AudioPolicy/AudioFlinger state,
ALSA/USB state, and filtered health logs. Use transition-observations.txt and
transition-live.txt when --capture-transitions was selected.

This archive is input for offline adaptation. It is not proof that an existing
module ZIP is safe to install on this device.
EOF
    else
        cat > "$OUT/README.txt" <<'EOF'
This is an INSTALLED-MODULE ISSUE archive.

It contains the installed module metadata and overlay payload, current live
target libraries, AudioPolicy/AudioFlinger state, ALSA/USB state, process maps,
and filtered crash/health logs. It is intended to explain a failure after this
module was installed; it is not a clean stock baseline for adapting a device.

Describe the installed ZIP version, exact reproduction steps, expected result,
actual result, DAC model/display, player, track PCM format, and whether audio
recovers after disabling the module.
EOF
    fi
}

printf 'Collecting %s evidence from %s...\n' "$MODE" "$DEVICE"
collect_common_state
if [[ "$MODE" == port ]]; then
    collect_port_files
else
    collect_issue_files
fi
if ((CAPTURE_TRANSITIONS)); then
    capture_transitions
fi

if [[ "$MODE" == port ]]; then
    require_any AudioPolicyManager '*/libaudiopolicymanagerdefault.so'
    require_any AudioPolicyComponents '*/libaudiopolicycomponents.so'
    require_any Xiaomi-AudioPolicyImpl '*/libaudiopolicymanagerimpl.so' '*/*audiopolicymanager*stub*.so'
    require_any AudioFlinger '*/libaudioflinger.so' '*/libaudioflingerimpl.so'
    require_any Qualcomm-USB-PAL '*/libdev_usb.so' '*/libar-pal.so'
    require_any Qualcomm-primary-HAL '*/*audiocorehal*.so' '*/audio.primary*.so' '*/android.hardware.audio*.service'
fi

build_metadata
write_notes

if [[ ! -s "$WARNINGS" ]]; then
    printf 'none\n' > "$WARNINGS"
fi

if ((!CREATE_ARCHIVE)); then
    FINISHED=1
    printf 'Wrote directory: %s\n' "$OUT"
    exit 0
fi

tar -czf "$ARCHIVE.part" -C "$OUT_PARENT" "$OUT_BASE"
mv "$ARCHIVE.part" "$ARCHIVE"
if command -v shasum >/dev/null 2>&1; then
    ARCHIVE_HASH=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
else
    ARCHIVE_HASH=$(sha256sum "$ARCHIVE" | awk '{print $1}')
fi

if ((!KEEP_DIRECTORY)); then
    [[ -f "$OUT/.collector-created" ]] \
        || die "refusing to remove an output directory without the collector marker"
    rm -rf -- "$OUT"
fi

FINISHED=1
printf 'Wrote archive: %s\n' "$ARCHIVE"
printf 'SHA-256: %s\n' "$ARCHIVE_HASH"
if ((KEEP_DIRECTORY)); then
    printf 'Kept directory: %s\n' "$OUT"
fi
