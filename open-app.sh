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

    jxa_activate_and_run "
const proc = Application('System Events').processes.byName('${IPHONE_MIRRORING_PROCESS}');
proc.menuBars[0].menuBarItems.byName('View').menus[0].menuItems.byName('Spotlight').click();
\$.NSThread.sleepForTimeInterval(${SPOTLIGHT_DELAY});

const nameData = \$.NSData.dataWithContentsOfFile('${tmp_name}');
const appName = \$.NSString.alloc.initWithDataEncoding(nameData, \$.NSUTF8StringEncoding).js;
const se = Application('System Events');
// Clear any stale query first: iOS Spotlight restores the previous search, so
// typing would append to it and Return would fire on the wrong (old) result.
se.keystroke('a', { using: 'command down' });
\$.NSThread.sleepForTimeInterval(0.15);
se.keyCode(51);
\$.NSThread.sleepForTimeInterval(0.15);
se.keystroke(appName);
\$.NSThread.sleepForTimeInterval(${SPOTLIGHT_SEARCH_DELAY});
" || { rm -f "$tmp_name"; return 1; }
    rm -f "$tmp_name"

    # Open by tapping the app's own result ROW, never blind Return: Spotlight's
    # top hit can be a web/video/game suggestion, which sent runs into YouTube,
    # Safari and Apple Games. Rows sit below the search field (y > 160); the
    # field's own echo of the query is excluded by that threshold.
    local row
    row=$("$SCRIPT_DIR/read.sh" 2>/dev/null | awk -v name="$app_name" '
        BEGIN { lname = tolower(name) }
        {
            coord = $1
            $1 = ""
            sub(/^ +/, "")
            if (tolower($0) == lname) {
                split(coord, xy, ",")
                if (xy[2] + 0 > 160) { print xy[1], xy[2]; exit }
            }
        }')
    if [[ -z "$row" ]]; then
        echo "Error: \"$app_name\" not found in Spotlight results - is it installed?" >&2
        return 1
    fi
    # shellcheck disable=SC2086
    "$SCRIPT_DIR/tap.sh" $row > /dev/null 2>&1 || return 1
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

# VERIFY: registry coordinates go stale whenever icons move, and a missed tap
# used to still print success, leaving callers convinced an app was open while
# the phone sat on the home screen. The home screen always shows the Search
# pill, so if it is still there the launch did not happen - fall back and
# invalidate the stale registry.
"$SCRIPT_DIR/wait.sh" still --timeout 3 > /dev/null 2>&1 || true
if "$SCRIPT_DIR/read.sh" --grep '^Search$' > /dev/null 2>&1; then
    "$SCRIPT_DIR/registry.sh" invalidate > /dev/null 2>&1 || true
    _open_via_spotlight
    exit 0
fi

echo "Opened: $app_name (registry, page $app_page)"
