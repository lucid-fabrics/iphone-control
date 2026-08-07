#!/usr/bin/env bash
# Tap at coordinates relative to the iPhone iOS content area.
# Usage: tap.sh <x> <y>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

if [[ $# -lt 2 ]]; then
    echo "Usage: tap.sh <x> <y>" >&2
    exit 1
fi

rel_x="$1"
rel_y="$2"

# Parse content bounds
window_json=$("$SCRIPT_DIR/find-window.sh")
parse_window_bounds "$window_json"

validate_coords "$rel_x" "$rel_y" "$CONTENT_W" "$CONTENT_H" || exit 1

abs_x=$(( CONTENT_X + rel_x ))
abs_y=$(( CONTENT_Y + rel_y ))

# Activate + click, saving and restoring cursor/focus
jxa_activate_and_run "$(jxa_tap_body "$abs_x" "$abs_y")"

echo "Tapped at ($rel_x, $rel_y) -> screen ($abs_x, $abs_y)"
