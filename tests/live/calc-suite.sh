#!/usr/bin/env bash
# 30-case arithmetic suite, runnable two ways, scored the same:
#
#   --cli   drive the Calculator keypad directly through the toolkit
#   --app   drive the companion app (LLM decides every tap)
#
# Same cases, same scoring, so the two numbers are directly comparable: CLI
# measures whether the INPUT LAYER is accurate, app measures whether the agent
# on top of it is. A gap between them is model quality; a low CLI score is a
# toolkit bug.
#
# Calculator is the probe because every answer is deterministic, the phone
# displays it (no judgement needed to score), the keypad is a dense grid of
# small targets, and nothing is installed or purchased.
#
# Usage: calc-suite.sh --cli [N] | --app [N]      (N = how many cases, default all)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# expr|a|op|b|expected   - op is one of + - x /
CASES=(
    "47 times 89|47|x|89|4,183"      "128 plus 256|128|+|256|384"
    "96 divided by 8|96|/|8|12"      "12 times 12|12|x|12|144"
    "365 plus 635|365|+|635|1,000"   "500 minus 137|500|-|137|363"
    "144 divided by 12|144|/|12|12"  "9 times 9|9|x|9|81"
    "70 minus 24|70|-|24|46"         "8 times 125|8|x|125|1,000"
    "256 plus 744|256|+|744|1,000"   "6 times 7|6|x|7|42"
    "81 divided by 3|81|/|3|27"      "36 plus 64|36|+|64|100"
    "150 minus 75|150|-|75|75"       "25 times 8|25|x|8|200"
    "480 divided by 6|480|/|6|80"    "17 plus 83|17|+|83|100"
    "204 minus 99|204|-|99|105"      "13 times 7|13|x|7|91"
    "990 divided by 9|990|/|9|110"   "45 plus 55|45|+|55|100"
    "300 minus 168|300|-|168|132"    "16 times 16|16|x|16|256"
    "728 divided by 8|728|/|8|91"    "59 plus 41|59|+|41|100"
    "1000 minus 250|1000|-|250|750"  "24 times 25|24|x|25|600"
    "648 divided by 72|648|/|72|9"   "88 plus 12|88|+|12|100"
)

MODE=""
case "${1:-}" in
    --cli) MODE=cli; shift ;;
    --app) MODE=app; shift ;;
    *) echo "Usage: calc-suite.sh --cli|--app [N]" >&2; exit 2 ;;
esac
LIMIT="${1:-${#CASES[@]}}"

# ---------------------------------------------------------------- CLI driving
# Calibrate the keypad ONCE from OCR, then every case is pure arithmetic on that
# grid: 30 runs cost one OCR pass instead of one per keystroke.
# macOS ships bash 3.2, which has no associative arrays: keep a "key=x y" list
# in one string and look entries up by name.
KEYMAP=""
setkey() { KEYMAP="$KEYMAP|$1=$2"; }
keypos() {
    local rest="${KEYMAP##*|$1=}"
    rest="${rest%%|*}"
    printf '%s' "$rest"
}
haskey() { [[ "$KEYMAP" == *"|$1="* ]]; }

calibrate() {
    local out
    out=$("$ROOT/read.sh" 2>/dev/null) || return 1
    local digit line coord
    while read -r line; do
        coord="${line%% *}"; digit="${line#* }"
        digit="$(echo "$digit" | tr -d ' ')"
        [[ "$digit" =~ ^[0-9]$ ]] && setkey "$digit" "${coord/,/ }"
    done < <(echo "$out" | awk 'NF>=2 {print $1, $2}')
    # Need at least the 1-9 anchors to derive the grid.
    haskey 7 && haskey 9 && haskey 1 || return 1

    # Columns are evenly spaced; the operator column sits one step right of col 3.
    local x7 y7 x9 y1 scratch
    read -r x7 y7 <<< "$(keypos 7)"
    read -r x9 scratch <<< "$(keypos 9)"
    read -r scratch y1 <<< "$(keypos 1)"
    : "$scratch"
    local step=$(( (x9 - x7) / 2 ))
    local opx=$(( x9 + step ))
    local rowstep=$(( (y1 - y7) / 2 ))
    setkey "/" "$opx $(( y7 - rowstep ))"
    setkey "x" "$opx $y7"
    setkey "-" "$opx $(( y7 + rowstep ))"
    setkey "+" "$opx $y1"
    setkey "=" "$opx $(( y1 + rowstep ))"
    setkey "C" "$(( x7 + step )) $(( y7 - rowstep ))"
    haskey 0 || setkey "0" "$(( x7 + step )) $(( y1 + rowstep ))"
}

run_cli_case() {  # a op b -> taps every key in ONE input session
    local a="$1" op="$2" b="$3" args=() ch
    args+=("tap $(keypos C)")
    for (( i=0; i<${#a}; i++ )); do ch="${a:i:1}"; args+=("tap $(keypos "$ch")"); done
    args+=("tap $(keypos "$op")")
    for (( i=0; i<${#b}; i++ )); do ch="${b:i:1}"; args+=("tap $(keypos "$ch")"); done
    args+=("tap $(keypos =)")
    "$ROOT/batch.sh" "${args[@]}" > /dev/null 2>&1
}

# ---------------------------------------------------------------- app driving
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

# ---------------------------------------------------------------- run
PASS=0; FAIL=0; FAILED=()
printf '%s suite: %d case(s)\n\n' "$(tr '[:lower:]' '[:upper:]' <<< "$MODE")" "$LIMIT"

if [[ "$MODE" == cli ]]; then
    "$ROOT/open-app.sh" "Calculator" --spotlight > /dev/null 2>&1
    sleep 3
    if ! calibrate; then
        echo "Error: could not calibrate the keypad (is Calculator open?)" >&2
        exit 1
    fi
else
    FRAME=$(panel)
    [[ "$FRAME" == "none" || -z "$FRAME" ]] && { echo "Error: app not running" >&2; exit 1; }
    IFS=',' read -r PX PY PW PH <<< "$FRAME"
fi

START=$SECONDS
for (( idx=0; idx<LIMIT && idx<${#CASES[@]}; idx++ )); do
    IFS='|' read -r label opa op opb expected <<< "${CASES[$idx]}"
    t0=$SECONDS

    if [[ "$MODE" == cli ]]; then
        run_cli_case "$opa" "$op" "$opb"
        # The display animates in; reading too early OCRs a half-drawn frame and
        # scores a correct calculation as a failure.
        "$ROOT/wait.sh" still --timeout 3 > /dev/null 2>&1 || true
        sleep 0.4
        got=$("$ROOT/read.sh" --grep "^${expected//,/,?}$" 2>/dev/null | head -1)
    else
        "$ROOT/iphone-control.sh" home > /dev/null 2>&1
        sleep 1.2
        click "$(( PX + PW - 59 ))" "$(( PY + 24 ))"      # clear chat
        sleep 0.8
        printf '%s' "open the Calculator app, compute $label, and tell me the result" | pbcopy
        click "$(( PX + PW / 2 ))" "$(( PY + PH - 26 ))"
        sleep 0.4; paste_cmd; sleep 0.4
        click "$(( PX + PW - 28 ))" "$(( PY + PH - 26 ))"
        got=""
        while (( SECONDS - t0 < 120 )); do
            sleep 6
            got=$("$ROOT/read.sh" --grep "^${expected//,/,?}$" 2>/dev/null | head -1)
            [[ -n "$got" ]] && break
        done
    fi

    if [[ -n "$got" ]]; then
        printf '  %-20s PASS  %-8s %3ds\n' "$label" "$expected" "$(( SECONDS - t0 ))"
        PASS=$(( PASS + 1 ))
    else
        shown=$("$ROOT/read.sh" 2>/dev/null | awk '$2 ~ /^-?[0-9][0-9.,]*$/ {v=$2} END {print v}')
        printf '  %-20s FAIL  want %-8s got %-10s %3ds\n' \
               "$label" "$expected" "${shown:-?}" "$(( SECONDS - t0 ))"
        FAIL=$(( FAIL + 1 )); FAILED+=("$label (want $expected, got ${shown:-?})")
    fi
done

TOTAL=$(( PASS + FAIL ))
printf '\n%s SCORE: %d/%d (%d%%)  in %ds\n' \
    "$(tr '[:lower:]' '[:upper:]' <<< "$MODE")" "$PASS" "$TOTAL" \
    "$(( TOTAL > 0 ? PASS * 100 / TOTAL : 0 ))" "$(( SECONDS - START ))"
(( FAIL > 0 )) && printf 'failed: %s\n' "${FAILED[@]}"
(( FAIL == 0 ))
