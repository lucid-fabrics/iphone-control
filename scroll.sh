#!/usr/bin/env bash
# Scroll the iPhone content using scroll-wheel events (drag-swipes do not scroll
# iOS lists through mirroring; wheel events do).
# Usage: scroll.sh <dy> [x y]
#   dy > 0 scrolls down (reveals lower content), dy < 0 scrolls up.
#   x y: content point to scroll at (default: content center).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

if [[ $# -lt 1 ]]; then
    echo "Usage: scroll.sh <dy> [x y]" >&2
    exit 1
fi

dy="$1"
rel_x="${2:-}"
rel_y="${3:-}"

if ! [[ "$dy" =~ ^-?[0-9]+$ ]] || [[ "$dy" == "0" ]]; then
    echo "Error: dy must be a non-zero integer, got: $dy" >&2
    exit 1
fi

# Parse content bounds
window_json=$("$SCRIPT_DIR/find-window.sh")
parse_window_bounds "$window_json"

if [[ -z "$rel_x" ]]; then rel_x=$(( CONTENT_W / 2 )); fi
if [[ -z "$rel_y" ]]; then rel_y=$(( CONTENT_H / 2 )); fi
validate_coords "$rel_x" "$rel_y" "$CONTENT_W" "$CONTENT_H" || exit 1

abs_x=$(( CONTENT_X + rel_x ))
abs_y=$(( CONTENT_Y + rel_y ))

jxa_activate_and_run "$(jxa_scroll_body "$abs_x" "$abs_y" "$dy")"

echo "Scrolled dy=$dy at ($rel_x, $rel_y)"
