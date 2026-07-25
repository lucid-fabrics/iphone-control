#!/usr/bin/env bash
# Map all apps on the iPhone home screen.
# Navigates through each home screen page, screenshots, and uses OCR to detect app labels.
# Output: JSON array of {name, page, x, y} for each detected app.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"
HELPER="$SCRIPT_DIR/helpers/ocr-image"
HELPER_SRC="$HELPER.swift"
MAX_PAGES="${1:-$DEFAULT_MAX_PAGES}"

# Auto-compile OCR helper if missing or outdated
if [[ ! -x "$HELPER" ]] || [[ "$HELPER_SRC" -nt "$HELPER" ]]; then
    swiftc -O "$HELPER_SRC" -o "$HELPER" 2>/dev/null || {
        echo '{"error":"Failed to compile ocr-image helper"}' >&2
        exit 1
    }
fi

# Get content dimensions
window_json=$("$SCRIPT_DIR/find-window.sh")
parse_window_bounds "$window_json"

# Go to home screen first
"$SCRIPT_DIR/iphone-control.sh" home > /dev/null
sleep "$HOME_SETTLE_DELAY"

# Swipe parameters - horizontal swipe across middle of screen
swipe_y=$(( CONTENT_H / 2 ))
if (( CONTENT_W <= SWIPE_EDGE_MARGIN * 2 )); then
    echo "Error: Content width ($CONTENT_W) too small for swipe margin ($SWIPE_EDGE_MARGIN)" >&2
    exit 1
fi
swipe_x_start=$(( CONTENT_W - SWIPE_EDGE_MARGIN ))
swipe_x_end=$SWIPE_EDGE_MARGIN

# App icon grid zone
app_zone_bottom=$(( CONTENT_H - APP_ZONE_BOTTOM_MARGIN ))

all_apps="["
first_entry=true
prev_hash=""

for (( page=1; page<=MAX_PAGES; page++ )); do
    # Screenshot current page
    tmp_img="/tmp/iphone-home-page-$$-${page}.png"
    "$SCRIPT_DIR/screenshot.sh" --native "$tmp_img" > /dev/null

    # Check if this page is identical to previous (end of pages)
    current_hash=$(md5 -q "$tmp_img" 2>/dev/null || md5sum "$tmp_img" | cut -d' ' -f1)
    if [[ "$current_hash" == "$prev_hash" ]]; then
        rm -f "$tmp_img"
        break
    fi
    prev_hash="$current_hash"

    # OCR the screenshot
    ocr_output=$("$HELPER" "$tmp_img" 2>/dev/null) || {
        echo "Warning: OCR failed for page $page, skipping" >&2
        rm -f "$tmp_img"
        continue
    }
    rm -f "$tmp_img"

    # Filter for app labels: short text in the app grid zone
    while IFS='|' read -r text px py pw ph; do
        [[ -z "$text" ]] && continue

        # OCR ran on the native-resolution capture; convert pixel coords to points
        # so stored tap targets are display- and Retina-scale-independent
        px=$(( px / SCALE )); py=$(( py / SCALE )); pw=$(( pw / SCALE ))

        # Skip if outside app grid zone
        (( py < APP_ZONE_TOP || py > app_zone_bottom )) && continue

        # App labels are typically 1-2 words, within length bounds, not all-caps system text
        text_len=${#text}
        (( text_len > APP_LABEL_MAX_LEN || text_len < APP_LABEL_MIN_LEN )) && continue

        # Skip common non-app-label patterns
        case "$text" in
            [0-9]*:[0-9]*|[0-9]*%|Search*|Suggestions*|Siri*) continue ;;
        esac

        # Center of the label = approximate tap target for the app icon above it
        tap_x=$(( px + pw / 2 ))
        tap_y=$(( py - APP_ICON_ABOVE_LABEL ))
        (( tap_y < 0 )) && continue  # skip labels too close to top edge

        if $first_entry; then
            first_entry=false
        else
            all_apps+=","
        fi
        # Escape text for JSON: strip control chars (\\x00-\\x1f), then escape \\ and "
        escaped_text=$(printf '%s' "$text" | tr -d '\000-\037')
        escaped_text="${escaped_text//\\/\\\\}"
        escaped_text="${escaped_text//\"/\\\"}"
        all_apps+="{\"name\":\"${escaped_text}\",\"page\":${page},\"x\":${tap_x},\"y\":${tap_y}}"
    done <<< "$ocr_output"

    # Swipe to next page (skip on last iteration)
    if (( page < MAX_PAGES )); then
        "$SCRIPT_DIR/swipe.sh" "$swipe_x_start" "$swipe_y" "$swipe_x_end" "$swipe_y" "$DEFAULT_SWIPE_DURATION" > /dev/null
        sleep "$HOME_SETTLE_DELAY"
    fi
done

all_apps+="]"
echo "$all_apps"
