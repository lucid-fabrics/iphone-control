#!/usr/bin/env bash
# Shared functions for iphone-control scripts.
# Source this file: source "$SCRIPT_DIR/helpers/common.sh"
set -euo pipefail

# --- Constants ---
IPHONE_MIRRORING_BUNDLE_ID="com.apple.ScreenContinuity"
IPHONE_MIRRORING_PROCESS="iPhone Mirroring"

# Timing constants (seconds)
ACTIVATION_DELAY=0.05
TAP_DELAY=0.02
KEYBOARD_APPEAR_DELAY=0.3
SPOTLIGHT_DELAY=0.4
SPOTLIGHT_SEARCH_DELAY=1.0
PAGE_SWIPE_DELAY=0.3
HOME_SETTLE_DELAY=0.5

# Swipe physics
SWIPE_STEPS=20
SWIPE_KICK_FACTOR=0.3

# App grid detection zones (pixels from content edge)
APP_ZONE_TOP=80
APP_ZONE_BOTTOM_MARGIN=100
APP_LABEL_MIN_LEN=2
APP_LABEL_MAX_LEN=25
APP_ICON_ABOVE_LABEL=20

# Page navigation
SWIPE_EDGE_MARGIN=30
DEFAULT_MAX_PAGES=10
DEFAULT_SWIPE_DURATION=300

# --- JSON Parsing (pure bash, no jq) ---
# Usage: json_field "$json_string" "field_name"
# Returns the value of a top-level JSON field (numbers and simple strings only)
json_field() {
    local json="$1" field="$2"
    # Absent field must yield empty (not the unstripped remainder) so callers' -z checks work
    [[ "$json" == *"\"${field}\":"* ]] || { echo ""; return 0; }
    local val="${json#*\"${field}\":}"
    # Strip leading whitespace
    val="${val#"${val%%[! ]*}"}"
    # Handle string vs number
    if [[ "$val" == \"* ]]; then
        val="${val#\"}"
        val="${val%%\"*}"
    else
        val="${val%%[,\}]*}"
    fi
    echo "$val"
}

# Parse all content bounds from find-window.sh JSON output
# Sets: CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H, WINDOW_X, WINDOW_Y, WINDOW_ID, SCALE
parse_window_bounds() {
    local json="$1"
    WINDOW_X=$(json_field "$json" "x")
    WINDOW_Y=$(json_field "$json" "y")
    CONTENT_X=$(json_field "$json" "content_x")
    CONTENT_Y=$(json_field "$json" "content_y")
    CONTENT_W=$(json_field "$json" "content_width")
    CONTENT_H=$(json_field "$json" "content_height")
    WINDOW_ID=$(json_field "$json" "window_id")
    SCALE=$(json_field "$json" "scale")
    SCALE="${SCALE:-1}"
    SCALE="${SCALE%%.*}"  # strip decimal - bash arithmetic requires integers
    # Guard against 0 or non-integer scale (e.g. empty string from malformed JSON)
    if ! [[ "$SCALE" =~ ^[1-9][0-9]*$ ]]; then
        SCALE=1
    fi

    # All coordinate fields are required: an empty value would silently become 0 in
    # bash arithmetic and taps would land relative to the primary display's origin.
    if [[ -z "$CONTENT_X" || -z "$CONTENT_Y" || -z "$CONTENT_W" || -z "$CONTENT_H" ||
          -z "$WINDOW_X" || -z "$WINDOW_Y" || -z "$WINDOW_ID" ]]; then
        echo "Error: Failed to parse required fields from window JSON" >&2
        return 1
    fi
}

# Validate coordinates are within content bounds
# Usage: validate_coords <x> <y> <content_w> <content_h>
validate_coords() {
    local x="$1" y="$2" w="$3" h="$4"
    if ! [[ "$x" =~ ^-?[0-9]+$ ]] || ! [[ "$y" =~ ^-?[0-9]+$ ]]; then
        echo "Error: Coordinates must be integers, got: ($x, $y)" >&2
        return 1
    fi
    if (( x < 0 || x >= w || y < 0 || y >= h )); then
        echo "Error: Coordinates ($x, $y) out of bounds (${w}x${h})" >&2
        return 1
    fi
}

# --- Input Sanitization ---
# Sanitize a string for safe embedding in JXA (JavaScript for Automation) string literals.
# Escapes characters that are dangerous in bash double-quoted strings or JXA string literals.
sanitize_jxa() {
    local input="$1"
    # Escape backslashes first (must be first to avoid double-escaping)
    input="${input//\\/\\\\}"
    # Escape dollar signs (prevent bash variable expansion in double-quoted embedding)
    input="${input//\$/\\\$}"
    # Escape backticks (prevent bash command substitution in double-quoted embedding)
    input="${input//\`/\\\`}"
    # Escape single quotes
    input="${input//\'/\\\'}"
    # Escape double quotes
    input="${input//\"/\\\"}"
    # Escape newlines
    input="${input//$'\n'/\\n}"
    # Escape carriage returns
    input="${input//$'\r'/\\r}"
    echo "$input"
}

# Sanitize a string for safe embedding in AppleScript string literals (double-quoted).
# AppleScript uses backslash-escaping for quotes and backslashes.
sanitize_applescript() {
    local input="$1"
    # Escape backslashes first (must be first to avoid double-escaping)
    input="${input//\\/\\\\}"
    # Escape dollar signs (prevent bash variable expansion in double-quoted embedding)
    input="${input//\$/\\\$}"
    # Escape backticks (prevent bash command substitution in double-quoted embedding)
    input="${input//\`/\\\`}"
    # Escape double quotes
    input="${input//\"/\\\"}"
    # Escape newlines and carriage returns
    input="${input//$'\n'/\\n}"
    input="${input//$'\r'/\\r}"
    echo "$input"
}

# --- JXA Boilerplate ---
# Generate JXA code to activate iPhone Mirroring and save/restore cursor.
# Usage: jxa_activate_and_run "<jxa_body_code>"
# Writes script to a temp file to prevent double bash expansion of ${body} contents.
# The body code can use 'saved' (saved cursor position) and assumes ObjC imports are available.
jxa_activate_and_run() {
    local body="$1"
    local tmp_jxa
    tmp_jxa=$(mktemp /tmp/jxa-XXXXXX.js)
    # Write preamble - unquoted heredoc expands shell vars; \$ writes literal $ for ObjC bridge
    cat > "$tmp_jxa" << JXAEOF
ObjC.import('AppKit');
ObjC.import('CoreGraphics');
ObjC.import('Foundation');

// Save cursor
const saved = \$.CGEventGetLocation(\$.CGEventCreate(null));

// Activate iPhone Mirroring
const apps = \$.NSWorkspace.sharedWorkspace.runningApplications.js;
const im = apps.find(a => ObjC.unwrap(a.bundleIdentifier) === '${IPHONE_MIRRORING_BUNDLE_ID}');
if (im) im.activateWithOptions(\$.NSApplicationActivateIgnoringOtherApps);
\$.NSThread.sleepForTimeInterval(${ACTIVATION_DELAY});

JXAEOF
    # Append body with printf - no further shell expansion of body content
    printf '%s\n' "$body" >> "$tmp_jxa"
    # Append postamble - printf prevents $ expansion
    printf '\n$.CGWarpMouseCursorPosition(saved);\n' >> "$tmp_jxa"
    osascript -l JavaScript "$tmp_jxa" > /dev/null || { rm -f "$tmp_jxa"; return 1; }
    rm -f "$tmp_jxa"
}
