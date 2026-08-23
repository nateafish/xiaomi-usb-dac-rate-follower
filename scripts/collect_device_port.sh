#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/collect_device_port.sh [output-directory]

Collect a read-only diagnostic archive for a device-port request. The device
must be connected through adb and expose a working `su` command. The script
does not install anything, change properties, clear logs, or collect APKs or
audio files.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

ADB=${ADB:-adb}

if ! command -v "$ADB" >/dev/null 2>&1; then
    echo "adb is required" >&2
    exit 1
fi

if ! "$ADB" get-state >/dev/null 2>&1; then
    echo "No adb device is available" >&2
    exit 1
fi

ROOT_ID=$("$ADB" shell su -c id 2>/dev/null | tr -d '\r')
if [[ "$ROOT_ID" != *"uid=0"* ]]; then
    echo "A working root shell through adb shell su -c is required" >&2
    exit 1
fi

OUT=${1:-"xiaomi-usb-dac-port-$(date +%Y%m%d-%H%M%S)"}
mkdir -p "$OUT/files" "$OUT/state" "$OUT/logs"

remote() {
    "$ADB" shell su -c "$1" 2>/dev/null | tr -d '\r'
}

save_text() {
    local name=$1
    local command=$2
    remote "$command" > "$OUT/$name" || true
}

copy_root_file() {
    local source=$1
    local relative=${source#/}
    local destination="$OUT/files/$relative"
    mkdir -p "$(dirname "$destination")"
    if "$ADB" exec-out su -c "test -r '$source' && cat '$source'" > "$destination" 2>/dev/null; then
        if [[ ! -s "$destination" ]]; then
            rm -f "$destination"
        fi
    else
        rm -f "$destination"
    fi
}

save_text state/build.txt \
    'getprop; printf "\\n=== uname ===\\n"; uname -a; printf "\\n=== id ===\\n"; id; printf "\\n=== root tools ===\\n"; command -v su; su -V 2>/dev/null || true; magisk -V 2>/dev/null || true; ksud -V 2>/dev/null || true'
save_text state/services.txt \
    'service list; printf "\\n=== binder audio services ===\\n"; dumpsys -l | grep -iE "audio|sound" || true; printf "\\n=== lshal audio ===\\n"; lshal 2>/dev/null | grep -iE "audio|effect" || true'
save_text state/processes.txt \
    'ps -A -o USER,PID,NAME,ARGS 2>/dev/null || ps -A; printf "\\n=== audio process contexts ===\\n"; ps -AZ 2>/dev/null | grep -iE "audio|agm|pal|audioserver" || true'
save_text state/root-overlay.txt \
    'mount; printf "\\n=== modules ===\\n"; find /data/adb/modules /data/adb/modules_update -mindepth 1 -maxdepth 2 -type f -name module.prop -print -exec cat {} \; 2>/dev/null || true; printf "\\n=== metamodule ===\\n"; ls -la /data/adb/metamodule 2>/dev/null || true'
save_text state/properties.txt \
    'getprop | grep -iE "audio|sound|usb|vendor|sku|product" || true'
save_text state/vintf.txt \
    'find /vendor/etc/vintf /odm/etc/vintf /system/etc/vintf -maxdepth 4 -type f -print -exec grep -HniE "audio|effect" {} \; 2>/dev/null || true'
save_text state/init-audio.txt \
    'find /vendor/etc/init /odm/etc/init /system/etc/init -maxdepth 3 -type f -print -exec grep -HniE "audio|agm|pal" {} \; 2>/dev/null || true'
save_text state/library-inventory.txt \
    'find /system/lib64 /system_ext/lib64 /vendor/lib64 /odm/lib64 /product/lib64 -type f \( -iname "*audio*" -o -iname "*pal*" -o -iname "*agm*" -o -iname "*acdb*" -o -iname "*sndcard*" \) -print 2>/dev/null | sort -u'
save_text state/audio-policy.txt 'dumpsys media.audio_policy'
save_text state/audio-flinger.txt 'dumpsys media.audio_flinger'
save_text state/alsa.txt \
    'cat /proc/asound/cards 2>/dev/null; printf "\\n=== pcm ===\\n"; cat /proc/asound/pcm 2>/dev/null; printf "\\n=== card streams ===\\n"; find /proc/asound \( -name stream0 -o -name stream1 \) -print | sort | while read -r f; do echo "=== $f ==="; cat "$f"; done'
save_text state/usb.txt \
    'dumpsys usb; printf "\\n=== sysfs sound ===\\n"; find /sys/class/sound -maxdepth 3 -type f -print -exec sh -c "echo === \$1; cat \"\$1\" 2>/dev/null" sh {} \; 2>/dev/null || true'
save_text logs/logcat-recent.txt \
    'logcat -d -b all -v threadtime -t 2500 2>/dev/null | grep -iE "audio|audioserver|audioflinger|audiopolicy|audiocore|pal|agm|usb|alsa|hifi|sample.rate|sampling_rate" || true'

save_text state/audio-process-maps.txt \
    'for d in /proc/[0-9]*; do p=${d##*/}; cmd=$(tr "\\000" " " < "$d/cmdline" 2>/dev/null); case "$cmd" in *audioserver*|*audiohal*|*hardware.audio*|*audio.service*) echo "=== PID $p: $cmd ==="; cat "$d/maps" 2>/dev/null;; esac; done'

# Copy the libraries and service/configuration files needed for both the
# current AIDL path and a possible legacy HIDL comparison.
while IFS= read -r path; do
    [[ -n "$path" ]] && copy_root_file "$path"
done < <(remote 'find /system/lib /system/lib64 /system_ext/lib /system_ext/lib64 /vendor/lib /vendor/lib64 /vendor/bin /vendor/bin/hw /odm/lib /odm/lib64 /odm/bin /odm/bin/hw /product/lib /product/lib64 -type f \( \
    -name "libaudiopolicymanagerdefault.so" -o -name "libaudiopolicycomponents.so" -o \
    -name "libaudiopolicymanagerimpl.so" -o -iname "*audiopolicymanager*stub*.so" -o \
    -name "libaudioclient.so" -o -name "libaudiopolicyservice.so" -o \
    -name "libaudioflinger.so" -o -name "libdev_usb.so" -o \
    -iname "*audioplatformconverter*.so" -o -iname "*audiocorehal*.so" -o \
    -iname "*audioaidl*.so" -o -iname "*audiohal*.so" -o \
    -iname "audio.primary*.so" -o -iname "audio.usb*.so" -o \
    -iname "audio.bluetooth*.so" -o -iname "android.hardware.audio*.so" -o \
    -iname "android.hardware.audio*.service" -o -iname "*pal*.so" -o -iname "*agm*.so" -o \
    -iname "*acdb*.so" -o -iname "*qahw*.so" -o -iname "*tinyalsa*.so" -o \
    -iname "*alsautils*.so" -o -iname "*audioroute*.so" \
    \) -print 2>/dev/null | sort -u')

# Keep the complete policy/configuration inputs, not only their grep summary.
while IFS= read -r path; do
    [[ -n "$path" ]] && copy_root_file "$path"
done < <(remote 'find /vendor/etc /odm/etc /system/etc /system_ext/etc /product/etc -type f \( \
    -iname "*audio*policy*.xml" -o -iname "audio_module_config*.xml" -o \
    -iname "vendor_audio_interfaces.xml" -o -iname "*audio*.conf" -o \
    -iname "*mixer*paths*.xml" \) -print 2>/dev/null | sort -u; \
    for f in $(find /vendor/etc/vintf /odm/etc/vintf /system/etc/vintf /system_ext/etc/vintf /product/etc/vintf /vendor/etc/init /odm/etc/init /system/etc/init /system_ext/etc/init /product/etc/init -type f 2>/dev/null); do \
        grep -qiE "android.hardware.audio|audiohal|audioserver|audio.core|audio.effect|libaudio|libpal|libagm" "$f" && echo "$f"; \
    done | sort -u')

# Record the libraries actually mapped by audio services. This catches vendor
# renames and libraries hidden behind an otherwise generic service binary.
while IFS= read -r path; do
    [[ -n "$path" && "$path" == /* && "$path" != *" (deleted)"* ]] || continue
    copy_root_file "${path% (deleted)}"
done < <(remote 'for d in /proc/[0-9]*; do p=${d##*/}; cmd=$(tr "\\000" " " < "$d/cmdline" 2>/dev/null); case "$cmd" in *audioserver*|*audiohal*|*hardware.audio*|*audio.service*) readlink "$d/exe" 2>/dev/null; sed -n "s/.* \\(\\/[^ ]*\\)$/\\1/p" "$d/maps" 2>/dev/null | grep -iE "/([^/]*audio[^/]*|libpal|libagm|libacdb|libdev_usb|libqahw|libtinyalsa|libalsautils|libaudioroute)[^/]*$" || true;; esac; done | sort -u')

while IFS= read -r file; do
    relative=${file#"$OUT/"}
    size=$(wc -c < "$file" | tr -d ' ')
    hash=$(shasum -a 256 "$file" | awk '{print $1}')
    printf '%s  %s  %s\n' "$hash" "$size" "$relative"
done < <(find "$OUT/files" -type f | LC_ALL=C sort) > "$OUT/state/file-manifest.sha256"

READELF=$(command -v llvm-readelf || command -v readelf || true)
if [[ -n "$READELF" ]]; then
    while IFS= read -r file; do
        case "$file" in *.so|*/bin/*|*/bin/hw/*)
            echo "=== ${file#"$OUT/files/"} ==="
            "$READELF" -h -d -n "$file" 2>/dev/null || true
            ;;
        esac
    done < <(find "$OUT/files" -type f | LC_ALL=C sort) \
        > "$OUT/state/elf-metadata.txt"
fi

cat > "$OUT/README.txt" <<'EOF'
This archive was produced by scripts/collect_device_port.sh.

It contains read-only device metadata, audio state, relevant system/vendor
libraries, configuration files, and recent filtered logcat output. It does not
contain APKs, music, or application-private data. Review and remove personal
information before publishing it in an Issue.

For transition analysis, reproduce 44.1 -> 48 -> 96 -> 44.1 kHz, stop
playback, and reconnect the DAC while separately recording logcat. A recent
snapshot alone cannot prove the rate-transition behavior.
EOF

ARCHIVE="${OUT%/}.tar.gz"
tar -czf "$ARCHIVE" -C "$(dirname "$OUT")" "$(basename "$OUT")"
echo "Wrote $ARCHIVE"
