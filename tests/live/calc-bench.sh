#!/usr/bin/env bash
# Tap-accuracy benchmark: drive the companion app through arithmetic on the
# iPhone Calculator and score the answers.
#
# Calculator is the ideal probe for input precision: the keypad is a dense grid
# of small targets, every answer is deterministic, the phone itself displays the
# result (so scoring needs no judgement), and nothing is installed or purchased.
# A wrong digit is a mis-landed tap, full stop.
#
# Usage: calc-bench.sh              run the full set (~1 min per case)
#        calc-bench.sh --quick      3-case smoke check
#        calc-bench.sh "12 times 12=144" ...   explicit cases
#        case format "expr=expected", e.g. "47 times 89=4,183"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Full set: every digit 0-9 is pressed at least once and all four operators are
# exercised, including results carrying a thousands separator (the comma in the
# display is an easy false negative when matching naively).
ALL_CASES=(
    "47 times 89=4,183"
    "128 plus 256=384"
    "96 divided by 8=12"
    "12 times 12=144"
    "365 plus 635=1,000"
    "500 minus 137=363"
    "144 divided by 12=12"
    "9 times 9=81"
    "70 minus 24=46"
    "8 times 125=1,000"
    "256 plus 744=1,000"
    "6 times 7=42"
    "81 divided by 3=27"
)
QUICK_CASES=("47 times 89=4,183" "365 plus 635=1,000" "70 minus 24=46")

CASES=("${ALL_CASES[@]}")
if [[ "${1:-}" == "--quick" ]]; then
    CASES=("${QUICK_CASES[@]}")
    shift
fi
(( $# > 0 )) && CASES=("$@")

panel() {
    osascript <<'AS'
tell application "System Events"
  tell process "iPhoneCompanion"
    if (count of windows) is 0 then return "none"
    set p to position of window 1
    set s to size of window 1
    return ((item 1 of p) as string) & "," & ((item 2 of p) as string) & "," & ¬
           ((item 1 of s) as string) & "," & ((item 2 of s) as string)
  end tell
end tell
AS
}

click() {
    osascript -l JavaScript -e "
ObjC.import('CoreGraphics'); ObjC.import('Foundation');
const p = {x: $1, y: $2};
\$.CGEventPost(\$.kCGHIDEventTap, \$.CGEventCreateMouseEvent(null, \$.kCGEventMouseMoved, p, 0));
\$.NSThread.sleepForTimeInterval(0.03);
\$.CGEventPost(\$.kCGHIDEventTap, \$.CGEventCreateMouseEvent(null, \$.kCGEventLeftMouseDown, p, \$.kCGMouseButtonLeft));
\$.NSThread.sleepForTimeInterval(0.05);
\$.CGEventPost(\$.kCGHIDEventTap, \$.CGEventCreateMouseEvent(null, \$.kCGEventLeftMouseUp, p, \$.kCGMouseButtonLeft));
'ok';" > /dev/null
}

paste_cmd() {
    osascript -l JavaScript -e "
ObjC.import('CoreGraphics'); ObjC.import('Foundation');
const src = \$.CGEventSourceCreate(\$.kCGEventSourceStateHIDSystemState);
const dn = \$.CGEventCreateKeyboardEvent(src, 9, true);
const up = \$.CGEventCreateKeyboardEvent(src, 9, false);
\$.CGEventSetFlags(dn, \$.kCGEventFlagMaskCommand);
\$.CGEventSetFlags(up, \$.kCGEventFlagMaskCommand);
\$.CGEventPost(\$.kCGHIDEventTap, dn);
\$.NSThread.sleepForTimeInterval(0.05);
\$.CGEventPost(\$.kCGHIDEventTap, up);
'ok';" > /dev/null
}

FRAME=$(panel)
if [[ "$FRAME" == "none" || -z "$FRAME" ]]; then
    echo "Error: iPhoneCompanion is not running." >&2
    exit 1
fi
IFS=',' read -r PX PY PW PH <<< "$FRAME"
CLEAR_X=$(( PX + PW - 59 )); TOOLBAR_Y=$(( PY + 24 ))
INPUT_X=$(( PX + PW / 2 ));  INPUT_Y=$(( PY + PH - 26 ))
SEND_X=$(( PX + PW - 28 ))

PASS=0; FAIL=0
printf 'Calculator benchmark: %d case(s). Hands off mouse/keyboard.\n\n' "${#CASES[@]}"

for case in "${CASES[@]}"; do
    expr="${case%%=*}"
    expected="${case##*=}"

    "$ROOT/iphone-control.sh" home > /dev/null 2>&1
    sleep 1.5
    click "$CLEAR_X" "$TOOLBAR_Y"      # clear chat, so each case starts fresh
    sleep 1

    printf '%s' "open the Calculator app, compute $expr, and tell me the result" | pbcopy
    click "$INPUT_X" "$INPUT_Y"
    sleep 0.5
    paste_cmd
    sleep 0.5
    click "$SEND_X" "$INPUT_Y"

    # Poll the phone for the expected answer rather than sleeping a fixed guess.
    found=false
    start=$SECONDS
    while (( SECONDS - start < 120 )); do
        sleep 8
        if "$ROOT/read.sh" --grep "$(printf '%s' "$expected" | sed 's/,/,\\?/g')" \
             > /dev/null 2>&1; then
            found=true
            break
        fi
    done

    if $found; then
        printf '  %-22s PASS  (%s)\n' "$expr" "$expected"
        PASS=$(( PASS + 1 ))
    else
        shown=$("$ROOT/read.sh" 2>/dev/null | awk '$2 ~ /^[0-9.,]+$/ {print $2}' | tail -1)
        printf '  %-22s FAIL  expected %s, display shows %s\n' \
               "$expr" "$expected" "${shown:-?}"
        FAIL=$(( FAIL + 1 ))
    fi
done

printf '\ntotal: %d pass, %d fail\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
