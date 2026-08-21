#!/system/bin/sh

MODDIR=${0%/*}
LOGDIR=/data/adb/xiaomi17-bitperfect
LOGFILE=$LOGDIR/daemon.log
PIDFILE=$LOGDIR/daemon.pid

mkdir -p "$LOGDIR"
chmod 0700 "$LOGDIR"

if [ -r "$PIDFILE" ]; then
    old_pid=$(cat "$PIDFILE" 2>/dev/null)
    case "$old_pid" in
        ''|*[!0-9]*) ;;
        *) kill "$old_pid" 2>/dev/null || true ;;
    esac
fi

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done

until [ "$(getprop init.svc.vendor.audio-hal-aidl)" = "running" ] \
        && [ "$(getprop init.svc.audioserver)" = "running" ]; do
    sleep 2
done

echo "[service] starting BitPerfectDaemon" >> "$LOGFILE"
/system/bin/app_process64 \
    -Djava.class.path="$MODDIR/bitperfect-daemon.dex" \
    /system/bin BitPerfectDaemon "$LOGFILE" >> "$LOGFILE" 2>&1 &
echo $! > "$PIDFILE"
