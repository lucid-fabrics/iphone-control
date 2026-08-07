#!/usr/bin/env bash
# Wait for a screen condition instead of sleeping a guessed duration.
#
# Fixed sleeps are the main source of both slowness (over-waiting on fast
# transitions) and flakiness (under-waiting on slow ones). Every sleep in a flow
# that has an observable end state should be one of these instead.
#
# Usage:
#   wait.sh text <string> [--timeout N]   until <string> is on screen
#   wait.sh gone <string> [--timeout N]   until <string> is NOT on screen
#   wait.sh still [--timeout N]           until the screen stops changing
#
# Exits 0 when the condition holds (prints how long it took), 1 on timeout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

if [[ $# -lt 1 ]]; then
    echo "Usage: wait.sh <text|gone|still> [string] [--timeout N]" >&2
    exit 1
fi

mode="$1"; shift
needle=""
case "$mode" in
    text|gone)
        [[ $# -ge 1 ]] || { echo "Usage: wait.sh $mode <string> [--timeout N]" >&2; exit 1; }
        needle="$1"; shift
        ;;
    still) ;;
    *) echo "Error: mode must be text, gone, or still" >&2; exit 1 ;;
esac

timeout="$WAIT_DEFAULT_TIMEOUT"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout) timeout="${2:-}"; shift 2 ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
done
if ! [[ "$timeout" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Error: --timeout must be a number, got: $timeout" >&2
    exit 1
fi

start=$(python3 -c 'import time; print(time.time())')
elapsed() { python3 -c "import time; print(f'{time.time() - $start:.2f}')"; }
expired() { python3 -c "import time; print(1 if time.time() - $start >= $timeout else 0)"; }

# Mirroring delivers a live video stream, so two captures of a frozen screen are
# never byte-identical and hashing never converges. Downscaling hard collapses
# the codec noise; frames are then compared with a tolerance.
snap_frame() {
    local out="$1" tmp
    tmp=$(mktemp /tmp/wait-frame-XXXXXX)
    screencapture -x -l "$WINDOW_ID" -o "$tmp.png" 2>/dev/null || { rm -f "$tmp" "$tmp.png"; return 1; }
    sips -Z "$WAIT_STILL_SIZE" -s format bmp "$tmp.png" --out "$out" >/dev/null 2>&1 || {
        rm -f "$tmp" "$tmp.png"; return 1
    }
    rm -f "$tmp" "$tmp.png"
}

# Mean absolute pixel difference between two BMPs; prints 1 if under tolerance.
frames_match() {
    python3 - "$1" "$2" "$WAIT_STILL_TOLERANCE" << 'PYEOF'
import sys
def pixels(path):
    d = open(path, 'rb').read()
    return d[int.from_bytes(d[10:14], 'little'):]
a, b = pixels(sys.argv[1]), pixels(sys.argv[2])
n = min(len(a), len(b))
if n == 0:
    print(0)
else:
    mad = sum(abs(a[i] - b[i]) for i in range(n)) / n
    print(1 if mad <= float(sys.argv[3]) else 0)
PYEOF
}

if [[ "$mode" == "still" ]]; then
    window_json=$("$SCRIPT_DIR/find-window.sh")
    parse_window_bounds "$window_json"
    prev="/tmp/wait-prev-$$.bmp"
    cur="/tmp/wait-cur-$$.bmp"
    trap 'rm -f "$prev" "$cur"' EXIT
    # A transition triggered a moment ago may not have started rendering yet, so
    # a single matching pair proves nothing. Require the frame to hold steady
    # across several consecutive comparisons before calling it settled.
    sleep "$WAIT_STILL_LEADIN"
    snap_frame "$prev" || { echo "Error: capture failed" >&2; exit 1; }
    steady=0
    while true; do
        sleep "$WAIT_STILL_INTERVAL"
        snap_frame "$cur" || { echo "Error: capture failed" >&2; exit 1; }
        if [[ "$(frames_match "$prev" "$cur")" == "1" ]]; then
            steady=$(( steady + 1 ))
            if (( steady >= WAIT_STILL_CONFIRMATIONS )); then
                echo "still after $(elapsed)s"
                exit 0
            fi
        else
            steady=0
        fi
        mv "$cur" "$prev"
        if [[ "$(expired)" == "1" ]]; then
            echo "Timeout: screen still changing after ${timeout}s" >&2
            exit 1
        fi
    done
fi

while true; do
    if "$SCRIPT_DIR/tap-text.sh" "$needle" --dry > /dev/null 2>&1; then
        found=true
    else
        found=false
    fi
    if [[ "$mode" == "text" && "$found" == true ]]; then
        echo "found \"$needle\" after $(elapsed)s"
        exit 0
    fi
    if [[ "$mode" == "gone" && "$found" == false ]]; then
        echo "\"$needle\" gone after $(elapsed)s"
        exit 0
    fi
    if [[ "$(expired)" == "1" ]]; then
        if [[ "$mode" == "text" ]]; then
            echo "Timeout: \"$needle\" not on screen after ${timeout}s" >&2
        else
            echo "Timeout: \"$needle\" still on screen after ${timeout}s" >&2
        fi
        exit 1
    fi
    sleep "$WAIT_POLL_INTERVAL"
done
