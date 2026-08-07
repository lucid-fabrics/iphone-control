#!/usr/bin/env bash
# Read all text currently on the iPhone screen, with tappable coordinates.
# This is the inspection channel: OCR is the only way to query iOS state through
# mirroring (there is no accessibility tree across the link).
#
# Usage: read.sh [--grep <pattern>] [--at <x> <y>] [--json]
#   --grep <pattern>   only lines whose text matches (case-insensitive regex)
#   --at <x> <y>       only the text whose box contains that content point
#   --json             JSON array (default is aligned text: "x,y  text")
#
# Coordinates are content points: the center of the text, ready to pass to tap.
set -euo pipefail

# Piping into head/grep -q closes stdout early; that is normal usage, not an error.
trap '' PIPE

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

pattern=""
at_x=""; at_y=""
as_json=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --grep) pattern="${2:-}"; shift 2 ;;
        --at)   at_x="${2:-}"; at_y="${3:-}"; shift 3 ;;
        --json) as_json=true; shift ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
done

HELPER="$SCRIPT_DIR/helpers/ocr-image"
HELPER_SRC="$HELPER.swift"
if [[ ! -x "$HELPER" ]] || [[ "$HELPER_SRC" -nt "$HELPER" ]]; then
    swiftc -O "$HELPER_SRC" -o "$HELPER" 2>/dev/null || {
        echo "Error: Failed to compile ocr-image helper" >&2
        exit 1
    }
fi

window_json=$("$SCRIPT_DIR/find-window.sh")
parse_window_bounds "$window_json"

img=$(mktemp /tmp/read-XXXXXX.png)
trap 'rm -f "$img"' EXIT
"$SCRIPT_DIR/screenshot.sh" --native "$img" > /dev/null

ocr=$("$HELPER" "$img" 2>/dev/null) || {
    echo "Error: OCR failed" >&2
    exit 1
}

first=true
$as_json && printf '['
while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    # The 4 geometry fields are the last 4; OCR text itself may contain '|'
    IFS='|' read -r -a f <<< "$line"
    n=${#f[@]}
    (( n >= 5 )) || continue
    px="${f[n-4]}"; py="${f[n-3]}"; pw="${f[n-2]}"; ph="${f[n-1]}"
    text="${f[0]}"
    for (( i = 1; i < n - 4; i++ )); do text+="|${f[i]}"; done

    # Native capture pixels -> content points
    x=$(( px / SCALE )); y=$(( py / SCALE ))
    w=$(( pw / SCALE )); h=$(( ph / SCALE ))
    cx=$(( x + w / 2 )); cy=$(( y + h / 2 ))

    if [[ -n "$pattern" ]] && ! printf '%s' "$text" | grep -qiE "$pattern"; then
        continue
    fi
    if [[ -n "$at_x" ]]; then
        (( at_x >= x && at_x < x + w && at_y >= y && at_y < y + h )) || continue
    fi

    if $as_json; then
        $first || printf ','
        first=false
        esc=${text//\\/\\\\}; esc=${esc//\"/\\\"}
        printf '{"text":"%s","x":%d,"y":%d,"w":%d,"h":%d,"cx":%d,"cy":%d}' \
            "$esc" "$x" "$y" "$w" "$h" "$cx" "$cy" || exit 0
    else
        printf '%4d,%-4d  %s\n' "$cx" "$cy" "$text" || exit 0
    fi
done <<< "$ocr"
$as_json && printf ']\n'
exit 0
