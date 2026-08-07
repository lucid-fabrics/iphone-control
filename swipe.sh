#!/usr/bin/env bash
# Swipe from (x1,y1) to (x2,y2) on the iPhone iOS content area.
# Usage: swipe.sh <x1> <y1> <x2> <y2> [duration_ms]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

if [[ $# -lt 4 ]]; then
    echo "Usage: swipe.sh <x1> <y1> <x2> <y2> [duration_ms]" >&2
    exit 1
fi

rel_x1="$1"; rel_y1="$2"; rel_x2="$3"; rel_y2="$4"
duration_ms="${5:-$DEFAULT_SWIPE_DURATION}"

if ! [[ "$duration_ms" =~ ^[0-9]+$ ]] || (( duration_ms <= 0 )); then
    echo "Error: duration_ms must be a positive integer, got: $duration_ms" >&2
    exit 1
fi

# Parse content bounds
window_json=$("$SCRIPT_DIR/find-window.sh")
parse_window_bounds "$window_json"

validate_coords "$rel_x1" "$rel_y1" "$CONTENT_W" "$CONTENT_H" || exit 1
validate_coords "$rel_x2" "$rel_y2" "$CONTENT_W" "$CONTENT_H" || exit 1

abs_x1=$(( CONTENT_X + rel_x1 )); abs_y1=$(( CONTENT_Y + rel_y1 ))
abs_x2=$(( CONTENT_X + rel_x2 )); abs_y2=$(( CONTENT_Y + rel_y2 ))

jxa_activate_and_run "$(jxa_swipe_body "$abs_x1" "$abs_y1" "$abs_x2" "$abs_y2" "$duration_ms")"

echo "Swiped ($rel_x1,$rel_y1) -> ($rel_x2,$rel_y2) in ${duration_ms}ms"
