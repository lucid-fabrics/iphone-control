#!/usr/bin/env bash
# Live integration suite + benchmark for iphone-control.
# Drives the REAL iPhone Mirroring window - do not touch mouse/keyboard while it runs.
# Every test is a no-op for phone state: it must leave the screen exactly as found.
#
# Usage: run-live.sh [--bench N]
#   (no args)   run the suite once, print pass/fail + per-test duration
#   --bench N   run the suite N times, print per-test success rate and
#               min/median/max duration; raw results saved as JSONL
# shellcheck disable=SC2329  # test functions are invoked indirectly via run_test
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"

ITERATIONS=1
if [[ "${1:-}" == "--bench" ]]; then
    ITERATIONS="${2:-5}"
    [[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]] || { echo "Error: --bench needs a positive integer" >&2; exit 1; }
fi

RUN_ID=$(date +%Y%m%d-%H%M%S)
RESULTS_FILE="$RESULTS_DIR/bench-$RUN_ID.jsonl"
TMP="$(mktemp -d /tmp/iphone-live-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# --- helpers ---------------------------------------------------------------

now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

# OCR a screenshot into a normalized, sorted line set (volatile tokens dropped:
# clock, battery, temperatures, bare numbers - they change between captures).
ocr_lines() {
    "$ROOT/helpers/ocr-image" "$1" 2>/dev/null \
        | awk -F'|' '{print $1}' \
        | grep -Ev '^([0-9]{1,2}:[0-9]{2}|[0-9]+%?|SOS.*|.{0,1}|[-+]?[0-9]+°.*|H:.*|L:.*)$' \
        | sort
}

# Screens equal if their normalized OCR line sets differ by at most 3 lines
# (widgets refresh: weather, calendar). $1, $2: png paths.
screens_match() {
    ocr_lines "$1" > "$TMP/a.txt"
    ocr_lines "$2" > "$TMP/b.txt"
    local diffs
    diffs=$(comm -3 "$TMP/a.txt" "$TMP/b.txt" | wc -l | tr -d ' ')
    [[ "$diffs" -le 3 ]]
}

cursor_pos() {
    osascript -l JavaScript -e 'ObjC.import("CoreGraphics"); const l=$.CGEventGetLocation($.CGEventCreate(null)); Math.round(l.x)+","+Math.round(l.y)' 2>/dev/null
}

frontmost() {
    osascript -l JavaScript -e 'ObjC.import("AppKit"); ObjC.unwrap($.NSWorkspace.sharedWorkspace.frontmostApplication.localizedName)' 2>/dev/null
}

PASS=0
FAIL=0
report() { # name status duration_ms detail
    local mark="PASS"
    [[ "$2" == "pass" ]] && PASS=$((PASS+1)) || { mark="FAIL"; FAIL=$((FAIL+1)); }
    printf '  %-18s %s  %5sms  %s\n' "$1" "$mark" "$3" "${4:-}"
    printf '{"iter":%d,"test":"%s","status":"%s","ms":%s,"detail":"%s"}\n' \
        "$ITER" "$1" "$2" "$3" "${4:-}" >> "$RESULTS_FILE"
}

run_test() { # name function
    local name="$1" fn="$2" t0 t1 detail
    t0=$(now_ms)
    if detail=$("$fn" 2>&1); then
        t1=$(now_ms)
        report "$name" pass $((t1-t0)) ""
    else
        t1=$(now_ms)
        report "$name" fail $((t1-t0)) "$(echo "$detail" | tail -1 | tr '"' "'")"
    fi
}

# --- tests (each must be a phone-state no-op) ------------------------------

t_find_window() {
    local json
    json=$("$ROOT/find-window.sh") || return 1
    [[ "$json" == *'"content_width"'* && "$json" == *'"window_id"'* ]] || return 1
}

t_screenshot_dims() {
    local json w h img dims
    json=$("$ROOT/find-window.sh") || return 1
    w=$(echo "$json" | sed -E 's/.*"content_width":([0-9]+).*/\1/')
    h=$(echo "$json" | sed -E 's/.*"content_height":([0-9]+).*/\1/')
    img="$TMP/dims.png"
    "$ROOT/screenshot.sh" "$img" > /dev/null || return 1
    dims=$(sips -g pixelWidth -g pixelHeight "$img" | awk '/pixel/{print $2}' | paste -sd x -)
    [[ "$dims" == "${w}x${h}" ]] || { echo "expected ${w}x${h} got ${dims}"; return 1; }
}

t_tap_noop() {
    local c0 f0 c1 f1
    "$ROOT/screenshot.sh" "$TMP/tap-before.png" > /dev/null || return 1
    c0=$(cursor_pos); f0=$(frontmost)
    "$ROOT/tap.sh" 180 620 > /dev/null || return 1   # dead wallpaper between grid and search
    sleep 0.5
    "$ROOT/screenshot.sh" "$TMP/tap-after.png" > /dev/null || return 1
    c1=$(cursor_pos); f1=$(frontmost)
    screens_match "$TMP/tap-before.png" "$TMP/tap-after.png" || { echo "screen changed"; return 1; }
    [[ "$f0" == "$f1" ]] || { echo "focus leaked: $f0 -> $f1"; return 1; }
    # Warp restore rounds to integers: allow 2px
    local dx dy
    dx=$(( ${c0%%,*} - ${c1%%,*} )); dy=$(( ${c0##*,} - ${c1##*,} ))
    (( dx < 0 )) && dx=$(( -dx )); (( dy < 0 )) && dy=$(( -dy ))
    (( dx <= 2 && dy <= 2 )) || { echo "cursor moved: $c0 -> $c1"; return 1; }
}

t_ocr_find() {
    "$ROOT/tap-text.sh" "Search" --dry > /dev/null 2>&1 || { echo "'Search' not found on home"; return 1; }
}

t_native_bounds() {
    # The native engine must agree with find-window.sh or taps land elsewhere.
    local a b
    a=$("$ROOT/helpers/input" bounds) || return 1
    b=$("$ROOT/find-window.sh") || return 1
    for field in content_x content_y content_width content_height scale; do
        local va vb
        va=$(printf '%s' "$a" | sed -E "s/.*\"$field\":(-?[0-9]+).*/\1/")
        vb=$(printf '%s' "$b" | sed -E "s/.*\"$field\":(-?[0-9]+).*/\1/")
        [[ "$va" == "$vb" ]] || { echo "$field: native=$va shell=$vb"; return 1; }
    done
}

t_read_screen() {
    local n
    n=$("$ROOT/read.sh" | wc -l | tr -d ' ')
    (( n >= 5 )) || { echo "read returned only $n lines on the home screen"; return 1; }
    # Coordinates must be tappable content points, not raw pixels
    "$ROOT/read.sh" --json | grep -q '"cx":' || { echo "no cx in json output"; return 1; }
}

t_wait_still() {
    "$ROOT/wait.sh" still --timeout 6 > /dev/null || { echo "screen never settled"; return 1; }
}

t_wait_text() {
    "$ROOT/wait.sh" text "Search" --timeout 6 > /dev/null || { echo "wait text failed"; return 1; }
    # A string that is not present must time out rather than falsely succeed
    if "$ROOT/wait.sh" text "ZZQXNOTHERE" --timeout 2 > /dev/null 2>&1; then
        echo "wait text falsely matched a missing string"; return 1
    fi
}

t_long_press() {
    # Long-press an app icon -> iOS context menu -> Escape. Net phone state: unchanged.
    "$ROOT/screenshot.sh" "$TMP/lp-before.png" > /dev/null || return 1
    "$ROOT/iphone-control.sh" press 306 555 800 > /dev/null 2>&1 || return 1
    "$ROOT/wait.sh" still --timeout 4 > /dev/null 2>&1 || true
    # Capture rather than pipe: a pipe to grep -q closes early, SIGPIPEs read.sh,
    # and pipefail then reports a failure that never happened.
    local menu
    menu=$("$ROOT/read.sh" --grep 'Remove App|Edit Home|Share' 2>/dev/null)
    dismiss_overlay
    if [[ -z "$menu" ]]; then
        echo "context menu did not appear"; return 1
    fi
    "$ROOT/screenshot.sh" "$TMP/lp-after.png" > /dev/null || return 1
    screens_match "$TMP/lp-before.png" "$TMP/lp-after.png" || { echo "menu not dismissed"; return 1; }
}

t_double_tap() {
    # On dead wallpaper: exercises the double-click event pair with no side effect.
    "$ROOT/screenshot.sh" "$TMP/dt-before.png" > /dev/null || return 1
    "$ROOT/iphone-control.sh" double-tap 180 620 > /dev/null 2>&1 || return 1
    sleep 0.6
    "$ROOT/screenshot.sh" "$TMP/dt-after.png" > /dev/null || return 1
    screens_match "$TMP/dt-before.png" "$TMP/dt-after.png" || { echo "screen changed"; return 1; }
}

t_tap_verify_negative() {
    # A dead-space tap changes nothing; tap-verify must SAY so rather than
    # claiming success. (The positive case is exercised implicitly by every
    # tap-based test; the negative is the one that catches a lying verifier.)
    if "$ROOT/tap-verify.sh" 180 620 --retries 0 > /dev/null 2>&1; then
        echo "verified a no-op tap as a screen change"; return 1
    fi
    return 0
}

t_key_event() {
    # Escape on the home screen is a no-op, but proves key delivery + restore.
    local f0 f1
    f0=$(frontmost)
    "$ROOT/iphone-control.sh" key escape > /dev/null 2>&1 || return 1
    sleep 0.4
    f1=$(frontmost)
    [[ "$f0" == "$f1" ]] || { echo "focus leaked: $f0 -> $f1"; return 1; }
}

t_page_swipe() {
    # Establish a known page before baselining: a previous test may have drifted,
    # and Today View sits to the LEFT of page 1 so a stray swipe strands us there.
    "$ROOT/iphone-control.sh" home > /dev/null 2>&1
    # Waits on the settle condition rather than a guessed sleep: faster when the
    # animation is quick, and correct when it is slow.
    "$ROOT/wait.sh" still --timeout 4 > /dev/null 2>&1 || true
    "$ROOT/screenshot.sh" "$TMP/pg-base.png" > /dev/null || return 1
    "$ROOT/swipe.sh" 300 400 60 400 > /dev/null || return 1
    "$ROOT/wait.sh" still --timeout 4 > /dev/null 2>&1 || true
    "$ROOT/screenshot.sh" "$TMP/pg-2.png" > /dev/null || return 1
    if screens_match "$TMP/pg-base.png" "$TMP/pg-2.png"; then
        echo "page did not change"; "$ROOT/swipe.sh" 60 400 300 400 > /dev/null; return 1
    fi
    "$ROOT/swipe.sh" 60 400 300 400 > /dev/null || return 1
    "$ROOT/wait.sh" still --timeout 4 > /dev/null 2>&1 || true
    "$ROOT/screenshot.sh" "$TMP/pg-back.png" > /dev/null || return 1
    if ! screens_match "$TMP/pg-base.png" "$TMP/pg-back.png"; then
        # Deterministic recovery - never re-swipe blindly (overshoots into Today View)
        "$ROOT/iphone-control.sh" home > /dev/null 2>&1
        "$ROOT/wait.sh" still --timeout 4 > /dev/null 2>&1 || true
        "$ROOT/screenshot.sh" "$TMP/pg-back.png" > /dev/null || return 1
        screens_match "$TMP/pg-base.png" "$TMP/pg-back.png" || { echo "did not return to page 1"; return 1; }
    fi
}

t_icon_drag_lift() {
    # Lift the row-5 slot-1 icon, tour it through the dock zone, and margin-drop it
    # back at slot 1: full lift/track/drop cycle, zero layout change.
    # (A drop-in-place without a waypoint is a long-press and opens the context menu.)
    "$ROOT/screenshot.sh" "$TMP/drag-before.png" > /dev/null || return 1
    "$ROOT/drag-icon.sh" 54 555 25 555 --via 180 680 --hover 250 > /dev/null 2>&1 || return 1
    # Jiggle mode must be fully exited before comparing, or the Edit/Done chrome
    # reads as a layout change. Wait for the condition rather than guessing.
    if "$ROOT/tap-text.sh" "Done" --dry > /dev/null 2>&1; then
        "$ROOT/tap-text.sh" "Done" > /dev/null 2>&1
    fi
    "$ROOT/wait.sh" gone "Done" --timeout 4 > /dev/null 2>&1 || true
    "$ROOT/wait.sh" still --timeout 4 > /dev/null 2>&1 || true
    "$ROOT/screenshot.sh" "$TMP/drag-after.png" > /dev/null || return 1
    screens_match "$TMP/drag-before.png" "$TMP/drag-after.png" || { echo "layout changed"; return 1; }
}

# Dismiss an iOS context menu / popover. The Escape key does NOT close these -
# only a tap outside the menu does. Called by any test that may open one.
dismiss_overlay() {
    "$ROOT/tap.sh" 180 640 > /dev/null 2>&1
    "$ROOT/wait.sh" still --timeout 3 > /dev/null 2>&1 || true
}

# Whole-list read on the Settings root list: both ends present, more than one
# page stitched, no duplicate rows, and the scroll-back restores the start view.
t_read_all() {
    "$ROOT/open-app.sh" "Settings" > /dev/null 2>&1 || { echo "could not open Settings"; return 1; }
    "$ROOT/wait.sh" still --timeout 4 > /dev/null 2>&1 || true
    # Settings reopens on its last subpage; walk back to the root list.
    local i
    for (( i = 0; i < 3; i++ )); do
        "$ROOT/tap-text.sh" "General" --dry > /dev/null 2>&1 && break
        "$ROOT/back.sh" > /dev/null 2>&1
        "$ROOT/wait.sh" still --timeout 3 > /dev/null 2>&1 || true
    done

    local json rc=0
    json=$("$ROOT/read-all.sh" --from-top --json) || { echo "read-all failed"; rc=1; }
    "$ROOT/screenshot.sh" "$TMP/ra-top.png" > /dev/null
    if (( rc == 0 )); then
        local verdict
        verdict=$(python3 - "$json" << 'PYEOF'
import json, sys
rows = json.loads(sys.argv[1])
content = [r for r in rows if not r["fixed"]]
problems = []
if not any(r["text"].startswith("General") for r in content):
    problems.append("no General row")
if not any("Privacy" in r["text"] for r in content):
    problems.append("no Privacy row (bottom of list not reached)")
if max((r["page"] for r in content), default=0) < 1:
    problems.append("only one page stitched")
for i, a in enumerate(content):
    for b in content[i + 1:]:
        if a["text"].lower() == b["text"].lower() and abs(a["y_abs"] - b["y_abs"]) <= 8:
            problems.append(f"duplicate row {a['text']!r}")
print("; ".join(problems) if problems else "ok")
PYEOF
)
        [[ "$verdict" == "ok" ]] || { echo "$verdict"; rc=1; }
    fi
    # Second pass starting at the top without --from-top: it must scroll back
    # to the exact view it started from.
    if (( rc == 0 )); then
        "$ROOT/read-all.sh" > /dev/null || { echo "second read-all failed"; rc=1; }
        "$ROOT/screenshot.sh" "$TMP/ra-after.png" > /dev/null
        screens_match "$TMP/ra-top.png" "$TMP/ra-after.png" || { echo "scroll-back did not restore the start view"; rc=1; }
    fi
    "$ROOT/iphone-control.sh" home > /dev/null 2>&1
    "$ROOT/wait.sh" still --timeout 4 > /dev/null 2>&1 || true
    return "$rc"
}

# Reset leaked UI state so one failing test cannot cascade: dismiss any context
# menu, exit jiggle mode if Edit/Done chrome is up, and force the home screen to
# page 1 (a stray swipe can strand us on Today View, which is left of page 1).
hygiene() {
    dismiss_overlay
    if "$ROOT/tap-text.sh" "Done" --dry > /dev/null 2>&1; then
        "$ROOT/tap-text.sh" "Done" > /dev/null 2>&1
        sleep 0.5
    fi
    "$ROOT/iphone-control.sh" home > /dev/null 2>&1
    "$ROOT/wait.sh" still --timeout 4 > /dev/null 2>&1 || true
}

# --- preflight -------------------------------------------------------------

"$ROOT/find-window.sh" > /dev/null || {
    echo "ABORT: iPhone Mirroring window not found." >&2
    exit 1
}
echo "Live suite: $ITERATIONS iteration(s). Hands off mouse/keyboard."
echo "Preconditions: phone on HOME SCREEN PAGE 1, portrait, unlocked."
echo ""

for (( ITER = 1; ITER <= ITERATIONS; ITER++ )); do
    echo "iteration $ITER/$ITERATIONS"
    hygiene
    run_test find-window     t_find_window
    run_test native-bounds   t_native_bounds
    run_test screenshot-dims t_screenshot_dims
    run_test tap-noop        t_tap_noop
    run_test tap-verify-neg  t_tap_verify_negative
    run_test key-event       t_key_event
    run_test double-tap      t_double_tap
    run_test ocr-find        t_ocr_find
    run_test read-screen     t_read_screen
    run_test read-all        t_read_all
    run_test wait-still      t_wait_still
    run_test wait-text       t_wait_text
    run_test long-press      t_long_press
    run_test page-swipe      t_page_swipe
    run_test icon-drag-lift  t_icon_drag_lift
done

echo ""
echo "total: $PASS pass, $FAIL fail  ->  $RESULTS_FILE"

if (( ITERATIONS > 1 )); then
    echo ""
    python3 - "$RESULTS_FILE" << 'PYEOF'
import json, sys, statistics
rows = [json.loads(l) for l in open(sys.argv[1])]
tests = []
for r in rows:
    if r['test'] not in tests:
        tests.append(r['test'])
print(f"{'test':<18} {'ok':>5} {'min':>7} {'median':>7} {'max':>7}")
for t in tests:
    sub = [r for r in rows if r['test'] == t]
    ok = sum(1 for r in sub if r['status'] == 'pass')
    ms = [r['ms'] for r in sub]
    print(f"{t:<18} {ok}/{len(sub):<3} {min(ms):>6}ms {int(statistics.median(ms)):>6}ms {max(ms):>6}ms")
PYEOF
fi

exit $(( FAIL > 0 ? 1 : 0 ))
