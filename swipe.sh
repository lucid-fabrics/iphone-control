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

jxa_activate_and_run "
const steps = ${SWIPE_STEPS};
const stepDelay = ${duration_ms} / 1000 / steps;
const startPt = {x: ${abs_x1}, y: ${abs_y1}};
const endPt   = {x: ${abs_x2}, y: ${abs_y2}};
const dx = ${abs_x2} - ${abs_x1};
const dy = ${abs_y2} - ${abs_y1};

// mouseDown at start point
const dn = \$.CGEventCreateMouseEvent(null, \$.kCGEventLeftMouseDown, startPt, \$.kCGMouseButtonLeft);
\$.CGEventPost(\$.kCGHIDEventTap, dn);

// IMMEDIATELY send first drag at ${SWIPE_KICK_FACTOR} distance — zero delay after mouseDown.
// iOS decides drag-vs-longpress within ~50ms. If cursor moves >10px in that window,
// it's recognized as a drag.
const kickPt = {x: ${abs_x1} + dx * ${SWIPE_KICK_FACTOR}, y: ${abs_y1} + dy * ${SWIPE_KICK_FACTOR}};
const kick = \$.CGEventCreateMouseEvent(null, \$.kCGEventLeftMouseDragged, kickPt, \$.kCGMouseButtonLeft);
\$.CGEventPost(\$.kCGHIDEventTap, kick);

// Interpolate remaining distance over the duration
const remaining = 1.0 - ${SWIPE_KICK_FACTOR};
for (let i = 1; i <= steps; i++) {
    \$.NSThread.sleepForTimeInterval(stepDelay);
    const f = ${SWIPE_KICK_FACTOR} + remaining * (i / steps);
    const mid = {x: ${abs_x1} + dx * f, y: ${abs_y1} + dy * f};
    const drag = \$.CGEventCreateMouseEvent(null, \$.kCGEventLeftMouseDragged, mid, \$.kCGMouseButtonLeft);
    \$.CGEventPost(\$.kCGHIDEventTap, drag);
}

const up = \$.CGEventCreateMouseEvent(null, \$.kCGEventLeftMouseUp, endPt, \$.kCGMouseButtonLeft);
\$.CGEventPost(\$.kCGHIDEventTap, up);
"

echo "Swiped ($rel_x1,$rel_y1) -> ($rel_x2,$rel_y2) in ${duration_ms}ms"
