#!/usr/bin/env bash
# Navigate back in the current iOS app.
# Prefers the on-screen Back control (reliable), falls back to the left-edge
# swipe gesture. iOS edge-swipe through mirroring is unreliable, so the visible
# control is tried first rather than last.
# Usage: back.sh [--swipe]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

force_swipe=false
if [[ "${1:-}" == "--swipe" ]]; then
    force_swipe=true
fi

window_json=$("$SCRIPT_DIR/find-window.sh")
parse_window_bounds "$window_json"

if ! $force_swipe; then
    # Exact match only: a substring match happily taps "Background App Refresh"
    # or "Backup" and reports it as a successful back navigation.
    back_hit=$("$SCRIPT_DIR/read.sh" --grep '^Back$' 2>/dev/null | head -1)
    if [[ -n "$back_hit" ]]; then
        bx=${back_hit%%,*}
        by=${back_hit#*,}; by=${by%% *}
        if "$SCRIPT_DIR/tap.sh" "${bx// /}" "${by// /}" > /dev/null 2>&1; then
            echo "Back (tapped Back control)"
            exit 0
        fi
    fi

    # iOS usually labels the back control with the PREVIOUS page's title, not
    # "Back", so the text match above misses it. The chevron itself always sits
    # in the nav bar's top-left corner; tap that region directly (verified to
    # pop a Settings subpage where the edge swipe below failed).
    if "$SCRIPT_DIR/tap.sh" 30 70 > /dev/null 2>&1; then
        echo "Back (tapped top-left chevron)"
        exit 0
    fi
fi

mid_y=$(( CONTENT_H / 2 ))
end_x=$(( CONTENT_W * 6 / 10 ))
ENGINE=$(input_engine "$SCRIPT_DIR/helpers") || exit 1
"$ENGINE" swipe 2 "$mid_y" "$end_x" "$mid_y" 250 || {
    echo "Error: back swipe failed" >&2
    exit 1
}
echo "Back (edge swipe)"
