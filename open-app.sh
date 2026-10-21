#!/usr/bin/env bash
# Open an app on the iPhone by name.
# Strategy: registry lookup → page navigation + tap (fast), Spotlight fallback (reliable).
# Usage: open-app.sh <app name> [--spotlight]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

if [[ $# -lt 1 ]]; then
    echo "Usage: open-app.sh <app name> [--spotlight]" >&2
    exit 1
fi

app_name="$1"
force_spotlight=false
if [[ "${2:-}" == "--spotlight" ]]; then
    force_spotlight=true
fi

# --- Spotlight launcher (fallback) ---
_open_via_spotlight() {
    # Write app name to a temp file - avoids embedding user content in any bash string,
    # preventing $ expansion and backtick injection (same pattern as type-text.sh).
    local tmp_name
    tmp_name=$(mktemp /tmp/open-app-XXXXXX.txt)
    printf '%s' "$app_name" > "$tmp_name"

    local spotlight_body
    spotlight_body=$(view_shortcut_body 3) || { rm -f "$tmp_name"; return 1; }

    jxa_activate_and_run "
${spotlight_body}
\$.NSThread.sleepForTimeInterval(${SPOTLIGHT_DELAY});

const nameData = \$.NSData.dataWithContentsOfFile('${tmp_name}');
const appName = \$.NSString.alloc.initWithDataEncoding(nameData, \$.NSUTF8StringEncoding).js;
const se = Application('System Events');
se.keystroke(appName);
\$.NSThread.sleepForTimeInterval(${SPOTLIGHT_SEARCH_DELAY});

se.keyCode(36);
" || { rm -f "$tmp_name"; return 1; }
    rm -f "$tmp_name"
    echo "Opened: $app_name (spotlight)"
}

# --- Force Spotlight if requested ---
if $force_spotlight; then
    _open_via_spotlight
    exit 0
fi

# --- Try registry lookup ---
lookup_result=$("$SCRIPT_DIR/registry.sh" lookup "$app_name" 2>/dev/null) || lookup_result=""

if [[ -z "$lookup_result" ]]; then
    _open_via_spotlight
    exit 0
fi

# Parse lookup result using shared JSON parser
app_page=$(json_field "$lookup_result" "page")
app_x=$(json_field "$lookup_result" "x")
app_y=$(json_field "$lookup_result" "y")
reg_width=$(json_field "$lookup_result" "content_width")
reg_height=$(json_field "$lookup_result" "content_height")

# Validate we got all values
if [[ -z "$app_page" || -z "$app_x" || -z "$app_y" || -z "$reg_width" || -z "$reg_height" ]]; then
    _open_via_spotlight
    exit 0
fi

# Check content dimensions match current window
window_json=$("$SCRIPT_DIR/find-window.sh")
parse_window_bounds "$window_json"

if [[ "$CONTENT_W" != "$reg_width" || "$CONTENT_H" != "$reg_height" ]]; then
    # Dimensions changed - invalidate registry, fall back to Spotlight
    "$SCRIPT_DIR/registry.sh" invalidate > /dev/null
    _open_via_spotlight
    exit 0
fi

# --- Navigate via registry: go home, swipe to page, tap ---

# Go to home screen (guaranteed page 1)
"$SCRIPT_DIR/iphone-control.sh" home > /dev/null
sleep "$HOME_SETTLE_DELAY"

# Swipe to target page (each swipe = one page forward)
if (( app_page > 1 )); then
    swipe_y=$(( CONTENT_H / 2 ))
    swipe_x_start=$(( CONTENT_W - SWIPE_EDGE_MARGIN ))
    swipe_x_end=$SWIPE_EDGE_MARGIN
    for (( i=1; i<app_page; i++ )); do
        "$SCRIPT_DIR/swipe.sh" "$swipe_x_start" "$swipe_y" "$swipe_x_end" "$swipe_y" "$DEFAULT_SWIPE_DURATION" > /dev/null
        sleep "$PAGE_SWIPE_DELAY"
    done
fi

# Tap the app
"$SCRIPT_DIR/tap.sh" "$app_x" "$app_y" > /dev/null

echo "Opened: $app_name (registry, page $app_page)"
