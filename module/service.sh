#!/system/bin/sh

MODDIR=${0%/*}
LOGDIR=/data/adb/xiaomi17-bitperfect
LOGFILE=$LOGDIR/rate-follower.log
PIDFILE=$LOGDIR/rate-follower.pid
HELPER=$MODDIR/bin/set-audio-parameters
PACKAGES=$MODDIR/config/packages.list

mkdir -p "$LOGDIR"
chmod 0700 "$LOGDIR"

if [ -r "$PIDFILE" ]; then
    old_pid=$(cat "$PIDFILE" 2>/dev/null)
    case "$old_pid" in
        ''|*[!0-9]*) ;;
        *) kill "$old_pid" 2>/dev/null || true ;;
    esac
fi
echo $$ > "$PIDFILE"

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
until [ "$(getprop init.svc.audioserver)" = "running" ]; do sleep 2; done

if [ "$(getprop ro.vendor.audio.hifi.config)" != "15" ]; then
    echo "[follower] Feature 8 inactive; hifi.config=$(getprop ro.vendor.audio.hifi.config)" \
        >> "$LOGFILE"
    exit 1
fi
if [ ! -x "$HELPER" ] || [ ! -r "$PACKAGES" ]; then
    echo "[follower] helper or package list missing" >> "$LOGFILE"
    exit 1
fi

target_uids=""
while IFS= read -r package_name; do
    case "$package_name" in ''|'#'*) continue ;; esac
    package_uid=$(cmd package list packages -U "$package_name" 2>/dev/null \
        | sed -n 's/.* uid://p' | head -n 1)
    case "$package_uid" in
        ''|*[!0-9]*) echo "[follower] package not installed: $package_name" >> "$LOGFILE" ;;
        *) target_uids="$target_uids $package_uid";
           echo "[follower] target $package_name uid=$package_uid" >> "$LOGFILE" ;;
    esac
done < "$PACKAGES"

if [ -z "$target_uids" ]; then
    echo "[follower] no installed target packages" >> "$LOGFILE"
    exit 0
fi

follower_active=0
while true; do
    flinger_dump=$(dumpsys media.audio_flinger 2>/dev/null)
    target_active=0
    if echo "$flinger_dump" | grep -q 'AUDIO_DEVICE_OUT_USB'; then
        for target_uid in $target_uids; do
            if echo "$flinger_dump" \
                    | grep -Eq "yes[[:space:]]+[0-9]+/[[:space:]]*${target_uid}[[:space:]]"; then
                target_active=1
                break
            fi
        done
    fi

    if [ "$target_active" -ne "$follower_active" ]; then
        if [ "$target_active" -eq 1 ]; then
            "$HELPER" activeEffect=none >> "$LOGFILE" 2>&1
            echo "[follower] whitelist active; source-rate following enabled" >> "$LOGFILE"
        else
            "$HELPER" activeEffect=rate_follow_off >> "$LOGFILE" 2>&1
            echo "[follower] whitelist idle; restoring default 48 kHz policy" >> "$LOGFILE"
        fi
        follower_active=$target_active
    fi
    sleep 0.5
done
