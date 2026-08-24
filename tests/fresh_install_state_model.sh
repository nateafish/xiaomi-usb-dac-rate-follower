#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/module/lib/install-state.sh"

ui_print() {
    :
}

fail() {
    echo "fresh-install-state test failed: $*" >&2
    exit 1
}

assert_equal() {
    [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"
}

TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rate-follower-fresh.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

RATE_FOLLOWER_ACTIVE_DIR=$TEST_DIR/modules/$RATE_FOLLOWER_MODULE_ID
mkdir -p "$RATE_FOLLOWER_ACTIVE_DIR" "$TEST_DIR/stock/system/lib64"
printf stock-policy > "$TEST_DIR/stock/system/lib64/policy.so"

require_fresh_install_state \
    || fail "an absent active module must be accepted as a fresh install"
assert_equal "$(patch_source_for "$TEST_DIR/stock/system/lib64/policy.so")" \
    "$TEST_DIR/stock/system/lib64/policy.so"

printf 'version=0.8.0-alpha\n' > "$RATE_FOLLOWER_ACTIVE_DIR/module.prop"
abort() {
    return 1
}
if require_fresh_install_state; then
    fail "every installed version must be rejected instead of upgraded in place"
fi

if declare -F active_payload_file >/dev/null; then
    fail "legacy active-payload upgrade support must not exist"
fi

echo "fresh-install-only state model: PASS"
