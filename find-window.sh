#!/usr/bin/env bash
# Find the iPhone Mirroring window position and size.
# Returns JSON: {"id": N, "x": N, "y": N, "width": N, "height": N}
set -euo pipefail

CACHE_FILE="/tmp/iphone-mirror-window.json"
CACHE_TTL=30  # seconds

# Use cache if fresh enough
if [[ -f "$CACHE_FILE" ]]; then
    cache_age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE") ))
    if (( cache_age < CACHE_TTL )); then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

# Query window info via JXA
result=$(osascript -l JavaScript -e '
ObjC.import("CoreGraphics");

const windows = $.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, $.kCGNullWindowID);
const count = ObjC.unwrap(windows).length;
let found = null;

for (let i = 0; i < count; i++) {
    const win = ObjC.unwrap(ObjC.unwrap(windows)[i]);
    const owner = ObjC.unwrap(win.kCGWindowOwnerName || "");
    const name = ObjC.unwrap(win.kCGWindowName || "");

    if (owner === "iPhone Mirroring" && name !== "") {
        const bounds = win.kCGWindowBounds;
        const x = ObjC.unwrap(bounds.X);
        const y = ObjC.unwrap(bounds.Y);
        const w = ObjC.unwrap(bounds.Width);
        const h = ObjC.unwrap(bounds.Height);
        const id = ObjC.unwrap(win.kCGWindowNumber);
        found = JSON.stringify({id: id, x: x, y: y, width: w, height: h});
        break;
    }
}

if (found) {
    found;
} else {
    "null";
}
' 2>/dev/null)

if [[ "$result" == "null" || -z "$result" ]]; then
    echo '{"error": "iPhone Mirroring window not found. Is iPhone Mirroring open?"}' >&2
    exit 1
fi

echo "$result" > "$CACHE_FILE"
echo "$result"
