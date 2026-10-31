#!/usr/bin/env bash
# Read a whole scrolling list in one call: scroll through it, OCR every step,
# stitch the overlapping pages into one de-duplicated top-to-bottom list, then
# scroll back to where it started.
#
# Replaces the agent loop "scroll, read, scroll, read, merge by hand", which
# costs a round trip per page and double-counts or drops rows at page seams.
#
# Usage: read-all.sh [--max N] [--step N] [--from-top] [--stay] [--json] [--grep P]
#   --max N      stop after N pages even if the list continues (default 15)
#   --step N     content points per scroll (default 60% of the screen, so pages overlap)
#   --from-top   scroll to the top of the list first
#   --stay       leave the list where the read ended instead of scrolling back
#   --json       JSON array of {text, x, y_abs, page, fixed[, seam_uncertain]}
#   --grep P     only rows whose text matches P (case-insensitive regex)
#
# y_abs is the row's position in the whole list, NOT a tap coordinate. To act
# on a row, use: scroll-to.sh "<text>" --tap
set -euo pipefail

# Piping into head/grep -q closes stdout early; that is normal usage, not an error.
trap '' PIPE

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

max_pages=15
step=""
from_top=false
stay=false
as_json=false
pattern=""

need_value() {
    [[ $# -ge 2 && -n "$2" ]] || { echo "Error: $1 needs a value" >&2; exit 1; }
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --max) need_value "$@"; max_pages="$2"; shift 2 ;;
        --step) need_value "$@"; step="$2"; shift 2 ;;
        --grep) need_value "$@"; pattern="$2"; shift 2 ;;
        --from-top) from_top=true; shift ;;
        --stay) stay=true; shift ;;
        --json) as_json=true; shift ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
done
if ! [[ "$max_pages" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --max must be a positive integer, got: $max_pages" >&2
    exit 1
fi
if [[ -n "$step" ]] && ! [[ "$step" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --step must be a positive integer, got: $step" >&2
    exit 1
fi

# Compile the stitcher on demand, like the other Swift helpers.
STITCH="$SCRIPT_DIR/helpers/stitch-pages"
if [[ ! -x "$STITCH" ]] || [[ "$STITCH.swift" -nt "$STITCH" ]]; then
    swiftc -O "$STITCH.swift" -o "$STITCH" 2>/dev/null || {
        echo "Error: Failed to compile stitch-pages helper (need Xcode command line tools)" >&2
        exit 1
    }
fi

window_json=$("$SCRIPT_DIR/find-window.sh")
parse_window_bounds "$window_json"
[[ -n "$step" ]] || step=$(( CONTENT_H * 60 / 100 ))

pages_file=$(mktemp /tmp/read-all-XXXXXX)
trap 'rm -f "$pages_file"' EXIT

read_page() { "$SCRIPT_DIR/read.sh" --json | tr -d '\n'; echo; }
settle() { "$SCRIPT_DIR/wait.sh" still --timeout 2 > /dev/null 2>&1 || true; }
# Text-only signature: OCR boxes jitter by a point between captures of a still
# screen, the strings do not.
signature() { grep -o '"text":"[^"]*"' <<< "$1" || true; }
stitch() { "$STITCH" --step "$step" "$@" < "$pages_file"; }

if $from_top; then
    previous=$(signature "$(read_page)")
    for (( i = 0; i < max_pages; i++ )); do
        "$SCRIPT_DIR/scroll.sh" $(( -2 * step )) > /dev/null
        settle
        current=$(signature "$(read_page)")
        [[ "$current" == "$previous" ]] && break
        previous="$current"
    done
fi

read_page >> "$pages_file"
pages=1
rows=$(stitch --count)
truncated=true
while (( pages < max_pages )); do
    "$SCRIPT_DIR/scroll.sh" "$step" > /dev/null
    settle
    read_page >> "$pages_file"
    pages=$(( pages + 1 ))
    now=$(stitch --count)
    # A page that adds nothing new means the scroll hit the bottom.
    if (( now <= rows )); then
        truncated=false
        break
    fi
    rows="$now"
done

if ! $stay; then
    offset=$(stitch --offset)
    if (( offset > 0 )); then
        "$SCRIPT_DIR/scroll.sh" "-$offset" > /dev/null
        settle
    fi
fi

grep_args=()
[[ -n "$pattern" ]] && grep_args=(--grep "$pattern")

if $as_json; then
    stitch --json ${grep_args[@]+"${grep_args[@]}"}
else
    note=""
    $truncated && note=", stopped at --max $max_pages before the end"
    echo "# $rows rows over $pages pages$note. y_abs is list position, not a tap point: act with scroll-to \"<text>\" --tap"
    stitch ${grep_args[@]+"${grep_args[@]}"}
fi
