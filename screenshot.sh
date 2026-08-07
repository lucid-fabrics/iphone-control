#!/usr/bin/env bash
# Capture a screenshot of the iPhone Mirroring window (content area only).
# Uses window ID capture - no desktop bleed, works with overlapping windows.
# Usage: screenshot.sh [--native] [output_path]
#   Default output is normalized to POINT dimensions (content_width x content_height),
#   so image pixels map 1:1 onto tap/swipe coordinates on any display, any Retina scale.
#   --native keeps the display's native pixel resolution (2x on Retina), for OCR.
# Output: path to the saved PNG
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"
NATIVE=0
if [[ "${1:-}" == "--native" ]]; then
    NATIVE=1
    shift
fi
OUTPUT="${1:-/tmp/iphone-screen.png}"

# The daemon writes from ITS working directory - relative paths must be
# absolutized here, in the caller's cwd, before crossing the socket.
case "$OUTPUT" in
    /*) ;;
    *) OUTPUT="$PWD/$OUTPUT" ;;
esac

# Fast path: resident daemon captures natively via ScreenCaptureKit (~150ms vs
# ~270ms) with identical crop/normalize geometry. Fallback: screencapture+sips.
if [[ -z "${ICTL_NO_DAEMON:-}" ]]; then
    engine=$(input_engine "$SCRIPT_DIR/helpers" 2>/dev/null) || engine=""
    if [[ -n "$engine" ]]; then
        mode="norm"
        (( NATIVE )) && mode="native"
        if "$engine" send shot "$OUTPUT" "$mode" > /dev/null 2>&1; then
            echo "$OUTPUT"
            exit 0
        fi
    fi
fi

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

# Crop to content area (remove bezel/rounded corners).
# NOTE: crop and resample must stay in SEPARATE sips invocations. Combining them
# does not apply in command-line order - sips computes resample factors against
# the ORIGINAL image and applies them to the cropped rect, yielding the wrong
# size. This only shows up at scale > 1, so a 1x display will not reveal it.
cp "$tmp_full" "$OUTPUT"
rm -f "$tmp_full"
sips --cropToHeightWidth "$crop_h" "$crop_w" --cropOffset "$offset_y" "$offset_x" "$OUTPUT" >/dev/null || {
    echo "Error: Failed to crop screenshot (sips failed)" >&2
    rm -f "$OUTPUT"
    exit 1
}

# Normalize to point dimensions: one coordinate space for screenshots, OCR,
# registry and taps. Exact 1/SCALE resample, so no aspect drift.
if (( ! NATIVE && SCALE > 1 )); then
    sips --resampleHeightWidth "$CONTENT_H" "$CONTENT_W" "$OUTPUT" >/dev/null || {
        echo "Error: Failed to resample screenshot (sips failed)" >&2
        rm -f "$OUTPUT"
        exit 1
    }
fi

echo "$OUTPUT"
