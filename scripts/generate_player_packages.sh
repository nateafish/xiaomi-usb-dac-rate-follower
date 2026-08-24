#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 MANIFEST OUTPUT" >&2
    exit 2
fi

MANIFEST=$1
OUTPUT=$2
[[ -r "$MANIFEST" ]] || {
    echo "missing player package manifest: $MANIFEST" >&2
    exit 1
}

temp_output=$(mktemp "${TMPDIR:-/tmp}/player-packages.XXXXXX")
trap 'rm -f "$temp_output"' EXIT

count=0
while IFS=$'\t' read -r package display_name validation extra; do
    [[ -n "$package" && ${package:0:1} != "#" ]] || continue
    [[ -z "${extra:-}" ]] || {
        echo "too many fields for player package: $package" >&2
        exit 1
    }
    [[ "$package" =~ ^[a-zA-Z0-9_]+([.][a-zA-Z0-9_]+)+$ ]] || {
        echo "invalid Android package name: $package" >&2
        exit 1
    }
    [[ -n "$display_name" ]] || {
        echo "missing display name for player package: $package" >&2
        exit 1
    }
    case "$validation" in
        hardware|pending) ;;
        *)
            echo "invalid validation state for player package: $package" >&2
            exit 1
            ;;
    esac
    grep -Fqx ".asciz \"$package\"" "$temp_output" 2>/dev/null && {
        echo "duplicate player package: $package" >&2
        exit 1
    }
    printf '.asciz "%s"\n' "$package" >> "$temp_output"
    count=$((count + 1))
done < "$MANIFEST"

[[ $count -gt 0 ]] || {
    echo "player package manifest is empty" >&2
    exit 1
}
printf '.byte 0\n' >> "$temp_output"
mv "$temp_output" "$OUTPUT"
