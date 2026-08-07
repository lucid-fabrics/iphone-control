#!/usr/bin/env bash
# Scroll until a piece of text is on screen, then stop.
# Replaces the manual "scroll, screenshot, guess, scroll again" loop.
# Usage: scroll-to.sh <text> [--up] [--max N] [--step N] [--tap]
#   --up      scroll upward instead of down
#   --max N   give up after N scrolls (default 12)
#   --step N  content points per scroll (default 250)
#   --tap     tap the text once found
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

if [[ $# -lt 1 ]]; then
    echo "Usage: scroll-to.sh <text> [--up] [--max N] [--step N] [--tap]" >&2
    exit 1
fi

needle="$1"; shift
direction=1
max_scrolls=12
step=250
do_tap=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --up) direction=-1; shift ;;
        --max) max_scrolls="${2:-}"; shift 2 ;;
        --step) step="${2:-}"; shift 2 ;;
        --tap) do_tap=true; shift ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
done
if ! [[ "$max_scrolls" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --max must be a positive integer, got: $max_scrolls" >&2
    exit 1
fi
if ! [[ "$step" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --step must be a positive integer, got: $step" >&2
    exit 1
fi

found_here() { "$SCRIPT_DIR/tap-text.sh" "$needle" --dry > /dev/null 2>&1; }

if found_here; then
    echo "Found \"$needle\" without scrolling"
    $do_tap && "$SCRIPT_DIR/tap-text.sh" "$needle"
    exit 0
fi

for (( i = 1; i <= max_scrolls; i++ )); do
    "$SCRIPT_DIR/scroll.sh" $(( direction * step )) > /dev/null
    # Let the scroll settle before reading, otherwise OCR catches motion blur
    "$SCRIPT_DIR/wait.sh" still --timeout 2 > /dev/null 2>&1 || true
    if found_here; then
        echo "Found \"$needle\" after $i scroll(s)"
        $do_tap && "$SCRIPT_DIR/tap-text.sh" "$needle"
        exit 0
    fi
done

echo "Error: \"$needle\" not found after $max_scrolls scroll(s)" >&2
exit 1
