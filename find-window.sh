#!/usr/bin/env bash
# Find the iPhone Mirroring window position and size.
# Uses window ID capture + alpha channel detection for 100% reliable content bounds.
# Returns JSON: {"x":N,"y":N,"width":N,"height":N,"content_x":N,"content_y":N,"content_width":N,"content_height":N,"window_id":N,"scale":N}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER="$SCRIPT_DIR/helpers/get-window-id"
HELPER_SRC="$HELPER.swift"
CACHE_FILE="/tmp/iphone-mirror-window.json"
CACHE_KEY_FILE="/tmp/iphone-mirror-window.key"
CACHE_TTL=30  # seconds

# Auto-compile helper if missing or outdated
if [[ ! -x "$HELPER" ]] || [[ "$HELPER_SRC" -nt "$HELPER" ]]; then
    swiftc -O "$HELPER_SRC" -o "$HELPER" 2>/dev/null || {
        echo '{"error":"Failed to compile get-window-id helper"}' >&2
        exit 1
    }
fi

# Get window info from compiled helper (fast - <10ms)
win_info=$("$HELPER" 2>/dev/null) || {
    echo '{"error":"iPhone Mirroring window not found. Is iPhone Mirroring open?"}' >&2
    exit 1
}

IFS='|' read -r window_id wx wy ww wh scale <<< "$win_info"
scale="${scale:-1}"  # default to 1 if missing (backward compat)

# Cache key = window ID + position + size + scale (invalidates on restart, move, resize, or display change)
cache_key="${window_id}|${wx}|${wy}|${ww}|${wh}|${scale}"

# Use cache if fresh enough and window hasn't moved
if [[ -f "$CACHE_FILE" && -f "$CACHE_KEY_FILE" ]]; then
    cache_age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE") ))
    stored_key=$(cat "$CACHE_KEY_FILE")
    if (( cache_age < CACHE_TTL )) && [[ "$stored_key" == "$cache_key" ]]; then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

# Capture just the window (alpha channel preserves rounded corners)
tmp_png="/tmp/iphone-mirror-bounds-$$.png"
screencapture -x -l "$window_id" -o "$tmp_png" 2>/dev/null || {
    echo '{"error":"screencapture failed. Check Screen Recording permission."}' >&2
    exit 1
}

# Scan alpha channel to find content bounds (alpha=255 = content, alpha=0 = rounded corners)
result=$(osascript -l JavaScript -e "
ObjC.import('AppKit');
const imgData = \$.NSData.dataWithContentsOfFile('$tmp_png');
const img = \$.NSBitmapImageRep.imageRepWithData(imgData);
const pw = img.pixelsWide;
const ph = img.pixelsHigh;

function alpha(px, py) {
    // colorAtXY is top-left origin, same as the scan loops - no flip
    const c = img.colorAtXY(px, py);
    // alphaComponent is color-space-independent - avoids null from colorUsingColorSpaceName on P3/wide-gamut displays
    return Math.round(ObjC.unwrap(c.alphaComponent) * 255);
}

const midX = Math.floor(pw / 2);
const midY = Math.floor(ph / 2);

// Scan from each edge to find first fully opaque pixel
let left = -1, right = -1, top = -1, bottom = -1;
for (let x = 0; x < pw; x++) { if (alpha(x, midY) === 255) { left = x; break; } }
for (let x = pw - 1; x >= 0; x--) { if (alpha(x, midY) === 255) { right = x; break; } }
for (let y = 0; y < ph; y++) { if (alpha(midX, y) === 255) { top = y; break; } }
for (let y = ph - 1; y >= 0; y--) { if (alpha(midX, y) === 255) { bottom = y; break; } }

// Validate scan found real content bounds
if (left < 0 || right < 0 || top < 0 || bottom < 0 || left >= right || top >= bottom) {
    throw new Error('Alpha scan found no opaque content region - midpoint row/column may be transparent');
}

// screencapture -l captures at the window's backing scale (2x on Retina).
// Measure scale from this capture: pixel width / window point width.
// Authoritative even when the window straddles displays or the arrangement has gaps.
// Requires -o (no shadow) on screencapture, or shadow pixels corrupt the ratio.
const m = Math.round(pw / ${ww});
const scale = (isFinite(m) && m >= 1) ? m : 1;
const cw = Math.round((right - left + 1) / scale);
const ch = Math.round((bottom - top + 1) / scale);
const cx = ${wx} + Math.round(left / scale);
const cy = ${wy} + Math.round(top / scale);

JSON.stringify({x:${wx},y:${wy},width:${ww},height:${wh},content_x:cx,content_y:cy,content_width:cw,content_height:ch,window_id:${window_id},scale:scale});
" 2>/dev/null) || true

rm -f "$tmp_png"

if [[ -z "$result" ]]; then
    echo '{"error":"Failed to detect content bounds from alpha channel"}' >&2
    exit 1
fi

# Write cache atomically - write key first so a reader that sees the key always has the file
tmp_cache="/tmp/iphone-mirror-window-$$.json"
printf '%s\n' "$result" > "$tmp_cache"
mv "$tmp_cache" "$CACHE_FILE"
printf '%s\n' "$cache_key" > "$CACHE_KEY_FILE"
echo "$result"
