#!/usr/bin/env bash
# Tap and CONFIRM it worked, retrying once if it did not.
# Silent missed taps are the top failure mode of agent-driven flows; this makes
# every tap self-checking for ~0.3s of overhead (daemon-accelerated).
#
# Usage: tap-verify.sh <x> <y> [--expect <text>] [--gone <text>] [--retries N] [--timeout S]
#   (default)        verify the screen CHANGED after the tap
#   --expect <text>  verify <text> is on screen after the tap
#   --gone <text>    verify <text> left the screen after the tap
#   --retries N      re-tap up to N times on failure (default 1)
#   --timeout S      per-attempt wait for the expect/gone condition (default 4)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

if [[ $# -lt 2 ]]; then
    echo "Usage: tap-verify.sh <x> <y> [--expect <text>] [--gone <text>] [--retries N] [--timeout S]" >&2
    exit 1
fi

x="$1"; y="$2"; shift 2
mode="changed"
needle=""
retries=1
timeout=4
# shift 2 aborts silently under set -e when the value is missing; shift by what
# is actually present and let the validation below report the real problem.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --expect) mode="expect"; needle="${2:-}"; shift; [[ $# -gt 0 ]] && shift || true ;;
        --gone)   mode="gone";   needle="${2:-}"; shift; [[ $# -gt 0 ]] && shift || true ;;
        --retries) retries="${2:-}"; shift; [[ $# -gt 0 ]] && shift || true ;;
        --timeout) timeout="${2:-}"; shift; [[ $# -gt 0 ]] && shift || true ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
done
if [[ "$mode" != "changed" && -z "$needle" ]]; then
    echo "Error: --$mode needs a text argument" >&2
    exit 1
fi
if ! [[ "$retries" =~ ^[0-9]+$ ]]; then
    echo "Error: --retries must be a non-negative integer, got: $retries" >&2
    exit 1
fi
if ! [[ "$timeout" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Error: --timeout must be a number, got: $timeout" >&2
    exit 1
fi

before=""
if [[ "$mode" == "changed" ]]; then
    before=$(mktemp /tmp/tap-verify-before-XXXXXX.png)
    trap 'rm -f "$before" /tmp/tap-verify-after-$$.png' EXIT
    "$SCRIPT_DIR/screenshot.sh" "$before" > /dev/null
fi

# Compare two screenshots after collapsing them to thumbnails: mirroring's
# video-stream noise vanishes at that size, so any remaining difference is a
# real screen change. Same tolerance as wait.sh stillness.
screens_differ() {
    local a="$1" b="$2" ta tb result
    ta=$(mktemp /tmp/tv-a-XXXXXX); tb=$(mktemp /tmp/tv-b-XXXXXX)
    sips -Z "$WAIT_STILL_SIZE" -s format bmp "$a" --out "$ta.bmp" >/dev/null 2>&1
    sips -Z "$WAIT_STILL_SIZE" -s format bmp "$b" --out "$tb.bmp" >/dev/null 2>&1
    result=$(python3 - "$ta.bmp" "$tb.bmp" "$WAIT_STILL_TOLERANCE" << 'PYEOF'
import sys
def px(p):
    d = open(p, 'rb').read()
    return d[int.from_bytes(d[10:14], 'little'):]
a, b = px(sys.argv[1]), px(sys.argv[2])
n = min(len(a), len(b))
mad = sum(abs(a[i] - b[i]) for i in range(n)) / n if n else 0
print(1 if mad > float(sys.argv[3]) else 0)
PYEOF
)
    rm -f "$ta" "$tb" "$ta.bmp" "$tb.bmp"
    [[ "$result" == "1" ]]
}

verify() {
    case "$mode" in
        changed)
            "$SCRIPT_DIR/wait.sh" still --timeout "$timeout" > /dev/null 2>&1 || true
            local after="/tmp/tap-verify-after-$$.png"
            "$SCRIPT_DIR/screenshot.sh" "$after" > /dev/null
            screens_differ "$before" "$after"
            ;;
        expect)
            "$SCRIPT_DIR/wait.sh" text "$needle" --timeout "$timeout" > /dev/null 2>&1
            ;;
        gone)
            "$SCRIPT_DIR/wait.sh" gone "$needle" --timeout "$timeout" > /dev/null 2>&1
            ;;
    esac
}

attempt=0
while true; do
    attempt=$(( attempt + 1 ))
    "$SCRIPT_DIR/tap.sh" "$x" "$y" > /dev/null
    if verify; then
        case "$mode" in
            changed) echo "Tap ($x, $y) verified: screen changed" ;;
            expect)  echo "Tap ($x, $y) verified: \"$needle\" on screen" ;;
            gone)    echo "Tap ($x, $y) verified: \"$needle\" gone" ;;
        esac
        [[ $attempt -gt 1 ]] && echo "(succeeded on attempt $attempt)"
        exit 0
    fi
    if (( attempt > retries )); then
        case "$mode" in
            changed) echo "Error: tap ($x, $y) produced no screen change after $attempt attempt(s)" >&2 ;;
            expect)  echo "Error: \"$needle\" did not appear after $attempt attempt(s)" >&2 ;;
            gone)    echo "Error: \"$needle\" still on screen after $attempt attempt(s)" >&2 ;;
        esac
        exit 1
    fi
done
