#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/module/lib/target-selection.sh"

ui_print() {
    :
}

abort() {
    echo "$*" >&2
    exit 7
}

getevent() {
    printf '/dev/input/event0: EV_KEY KEY_VOLUMEUP DOWN\n'
}

confirm_theoretical_installation

if (
    unset -f getevent
    PATH=/nonexistent
    confirm_theoretical_installation
) >/dev/null 2>&1; then
    echo "theoretical confirmation test failed: missing getevent was accepted" >&2
    exit 1
fi

echo "theoretical confirmation model: PASS"
