#!/usr/bin/env bash
# Run multiple actions in ONE input session: one idle-wait, one activation,
# one cursor/focus restore for the whole sequence.
# Usage: batch.sh "tap <x> <y>" "swipe <x1> <y1> <x2> <y2> [ms]" "sleep <seconds>" ...
#        With no arguments, reads one action per line from stdin
#        (blank lines and lines starting with # are skipped).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

actions=("$@")
if [[ ${#actions[@]} -eq 0 ]]; then
    while IFS= read -r line; do
        line="${line%%#*}"
        [[ -n "${line//[[:space:]]/}" ]] && actions+=("$line")
    done
fi

if [[ ${#actions[@]} -eq 0 ]]; then
    echo "Usage: batch.sh \"tap <x> <y>\" [\"swipe <x1> <y1> <x2> <y2> [ms]\"] [\"sleep <s>\"] ..." >&2
    exit 1
fi

# Parse content bounds once for the whole batch
window_json=$("$SCRIPT_DIR/find-window.sh")
parse_window_bounds "$window_json"

body=""
count=0
for action in "${actions[@]}"; do
    # shellcheck disable=SC2086  # intentional word splitting of the action string
    set -- $action
    cmd="$1"; shift
    case "$cmd" in
        tap)
            [[ $# -eq 2 ]] || { echo "Error: tap needs <x> <y>, got: $action" >&2; exit 1; }
            validate_coords "$1" "$2" "$CONTENT_W" "$CONTENT_H" || exit 1
            body+="$(jxa_tap_body $(( CONTENT_X + $1 )) $(( CONTENT_Y + $2 )))"$'\n'
            ;;
        swipe)
            [[ $# -eq 4 || $# -eq 5 ]] || { echo "Error: swipe needs <x1> <y1> <x2> <y2> [ms], got: $action" >&2; exit 1; }
            dur="${5:-$DEFAULT_SWIPE_DURATION}"
            if ! [[ "$dur" =~ ^[0-9]+$ ]] || (( dur <= 0 )); then
                echo "Error: duration_ms must be a positive integer, got: $dur" >&2
                exit 1
            fi
            validate_coords "$1" "$2" "$CONTENT_W" "$CONTENT_H" || exit 1
            validate_coords "$3" "$4" "$CONTENT_W" "$CONTENT_H" || exit 1
            body+="$(jxa_swipe_body $(( CONTENT_X + $1 )) $(( CONTENT_Y + $2 )) $(( CONTENT_X + $3 )) $(( CONTENT_Y + $4 )) "$dur")"$'\n'
            ;;
        scroll)
            [[ $# -eq 1 || $# -eq 3 ]] || { echo "Error: scroll needs <dy> [x y], got: $action" >&2; exit 1; }
            if ! [[ "$1" =~ ^-?[0-9]+$ ]] || [[ "$1" == "0" ]]; then
                echo "Error: scroll dy must be a non-zero integer, got: $1" >&2
                exit 1
            fi
            sx="${2:-$(( CONTENT_W / 2 ))}"
            sy="${3:-$(( CONTENT_H / 2 ))}"
            validate_coords "$sx" "$sy" "$CONTENT_W" "$CONTENT_H" || exit 1
            body+="$(jxa_scroll_body $(( CONTENT_X + sx )) $(( CONTENT_Y + sy )) "$1")"$'\n'
            ;;
        sleep)
            [[ $# -eq 1 && "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "Error: sleep needs <seconds>, got: $action" >&2; exit 1; }
            body+="\$.NSThread.sleepForTimeInterval($1);"$'\n'
            ;;
        *)
            echo "Error: unknown batch action: $cmd (want tap|swipe|scroll|sleep)" >&2
            exit 1
            ;;
    esac
    body+="\$.NSThread.sleepForTimeInterval(${BATCH_ACTION_DELAY});"$'\n'
    count=$(( count + 1 ))
done

jxa_activate_and_run "$body"

echo "Batch: $count action(s) done"
