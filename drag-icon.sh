#!/usr/bin/env bash
# Drag a home-screen icon from one position to another (reorder, or drop onto
# another icon to create/extend a folder).
# Enters jiggle mode with a long-press first, replays real-hardware drag
# dynamics (see jxa_icon_drag_body), then taps Done unless told otherwise.
# Usage: drag-icon.sh <x1> <y1> <x2> <y2> [--hover ms] [--via x y] [--keep-jiggle]
#   --hover ms     hold over the target before release: ~300 for reorder (default),
#                  ~1200 to drop INTO an icon and create/extend a folder
#   --via x y      route the drag through a waypoint with a brief pause there
#                  (folder-exit drags, or a no-op tour back to the same slot)
#   --keep-jiggle  stay in jiggle mode after the drag (for chained drags)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

if [[ $# -lt 4 ]]; then
    echo "Usage: drag-icon.sh <x1> <y1> <x2> <y2> [--hover ms] [--keep-jiggle]" >&2
    exit 1
fi

rel_x1="$1"; rel_y1="$2"; rel_x2="$3"; rel_y2="$4"
shift 4
hover_ms=300
keep_jiggle=false
via_x=""; via_y=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --hover) hover_ms="${2:-}"; shift 2 ;;
        --via) via_x="${2:-}"; via_y="${3:-}"; shift 3 ;;
        --keep-jiggle) keep_jiggle=true; shift ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
done
if ! [[ "$hover_ms" =~ ^[0-9]+$ ]]; then
    echo "Error: --hover must be a non-negative integer (ms), got: $hover_ms" >&2
    exit 1
fi

# Parse content bounds
window_json=$("$SCRIPT_DIR/find-window.sh")
parse_window_bounds "$window_json"

validate_coords "$rel_x1" "$rel_y1" "$CONTENT_W" "$CONTENT_H" || exit 1
validate_coords "$rel_x2" "$rel_y2" "$CONTENT_W" "$CONTENT_H" || exit 1
if [[ -n "$via_x" ]]; then
    validate_coords "$via_x" "$via_y" "$CONTENT_W" "$CONTENT_H" || exit 1
fi

# A zero-distance "drag" with no waypoint is a long-press (opens the context
# menu), never what the caller wants.
if [[ "$rel_x1" == "$rel_x2" && "$rel_y1" == "$rel_y2" && -z "$via_x" ]]; then
    echo "Error: source and target are the same point; use --via for a no-op tour" >&2
    exit 1
fi

abs_x1=$(( CONTENT_X + rel_x1 )); abs_y1=$(( CONTENT_Y + rel_y1 ))
abs_x2=$(( CONTENT_X + rel_x2 )); abs_y2=$(( CONTENT_Y + rel_y2 ))

# One session: enter jiggle by long-pressing the LEFT MARGIN wallpaper - never the
# icon itself. Releasing a long-press on an app opens its context menu, and on
# iOS 26 the size row there converts the app into a widget if a later press or
# release lands on it.
jiggle_x=$(( CONTENT_X + 6 ))
jiggle_y=$(( CONTENT_Y + CONTENT_H - 140 ))
body="{
const src0 = \$.CGEventSourceCreate(\$.kCGEventSourceStateHIDSystemState);
const p0 = {x: ${jiggle_x}, y: ${jiggle_y}};
const mv0 = \$.CGEventCreateMouseEvent(src0, \$.kCGEventMouseMoved, p0, \$.kCGMouseButtonLeft);
\$.CGEventPost(\$.kCGHIDEventTap, mv0);
\$.NSThread.sleepForTimeInterval(0.1);
const dn0 = \$.CGEventCreateMouseEvent(src0, \$.kCGEventLeftMouseDown, p0, \$.kCGMouseButtonLeft);
\$.CGEventPost(\$.kCGHIDEventTap, dn0);
\$.NSThread.sleepForTimeInterval(0.7);
const up0 = \$.CGEventCreateMouseEvent(src0, \$.kCGEventLeftMouseUp, p0, \$.kCGMouseButtonLeft);
\$.CGEventPost(\$.kCGHIDEventTap, up0);
\$.NSThread.sleepForTimeInterval(0.7);
}
$(if [[ -n "$via_x" ]]; then
    jxa_icon_drag_body "$abs_x1" "$abs_y1" "$abs_x2" "$abs_y2" "$hover_ms" \
        "$(( CONTENT_X + via_x ))" "$(( CONTENT_Y + via_y ))"
else
    jxa_icon_drag_body "$abs_x1" "$abs_y1" "$abs_x2" "$abs_y2" "$hover_ms"
fi)"

jxa_activate_and_run "$body"

echo "Dragged icon ($rel_x1,$rel_y1) -> ($rel_x2,$rel_y2) hover=${hover_ms}ms"

if ! $keep_jiggle; then
    sleep 0.6
    "$SCRIPT_DIR/tap-text.sh" "Done" --cached || echo "Warning: could not find Done button; still in jiggle mode?" >&2
fi
