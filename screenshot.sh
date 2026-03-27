#!/usr/bin/env bash
# Capture a screenshot of the iPhone Mirroring window (content area only).
# Uses window ID capture — no desktop bleed, works with overlapping windows.
# Output: path to the saved PNG
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"
OUTPUT="${1:-/tmp/iphone-screen.png}"

# Get window info (includes content bounds and window_id)
window_json=$("$SCRIPT_DIR/find-window.sh")
parse_window_bounds "$window_json"

# Offsets for sips must be in pixel space (captured image is at native resolution)
offset_x=$(( (CONTENT_X - WINDOW_X) * SCALE ))
offset_y=$(( (CONTENT_Y - WINDOW_Y) * SCALE ))
crop_w=$(( CONTENT_W * SCALE ))
crop_h=$(( CONTENT_H * SCALE ))

# Capture just the window (no desktop, no overlap from other windows)
tmp_full="/tmp/iphone-screenshot-full-$$.png"
screencapture -x -l "$WINDOW_ID" -o "$tmp_full" 2>/dev/null || {
    echo "Error: Screenshot failed. Check Screen Recording permission." >&2
    exit 1
}

# Crop to content area (remove bezel/rounded corners)
cp "$tmp_full" "$OUTPUT"
rm -f "$tmp_full"
sips --cropToHeightWidth "$crop_h" "$crop_w" --cropOffset "$offset_y" "$offset_x" "$OUTPUT" >/dev/null || {
    echo "Error: Failed to crop screenshot (sips failed)" >&2
    rm -f "$OUTPUT"
    exit 1
}

echo "$OUTPUT"
