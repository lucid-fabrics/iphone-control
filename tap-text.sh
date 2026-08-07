#!/usr/bin/env bash
# Tap on-screen text found by OCR: no pixel-guessing, coordinates come from Vision.
# Case-insensitive; an exact match wins over a substring match.
# Usage: tap-text.sh <text> [--index N] [--dry] [--cached]
#   --index N   when several matches, tap the Nth counting from the top (default 1)
#   --dry       locate and print the match, do not tap
#   --cached    reuse the last OCR'd position for this query+window size (skip
#               screenshot+OCR entirely) - for stable chrome like the Done button
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

if [[ $# -lt 1 ]]; then
    echo "Usage: tap-text.sh <text> [--index N]" >&2
    exit 1
fi

query="$1"; shift
index=1
dry=false
cached=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --index) index="${2:-}"; shift 2 ;;
        --dry) dry=true; shift ;;
        --cached) cached=true; shift ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
done
if ! [[ "$index" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --index must be a positive integer, got: $index" >&2
    exit 1
fi

# Auto-compile OCR helper if missing or outdated (same pattern as find-window.sh)
HELPER="$SCRIPT_DIR/helpers/ocr-image"
HELPER_SRC="$HELPER.swift"
if [[ ! -x "$HELPER" ]] || [[ "$HELPER_SRC" -nt "$HELPER" ]]; then
    swiftc -O "$HELPER_SRC" -o "$HELPER" 2>/dev/null || {
        echo "Error: Failed to compile ocr-image helper" >&2
        exit 1
    }
fi

# SCALE converts native-capture pixel coords to content points
window_json=$("$SCRIPT_DIR/find-window.sh")
parse_window_bounds "$window_json"

# Cached fast path: reuse the last OCR'd position for this query at this
# content size (chrome like Done/Edit is position-stable). Cache line format:
# query_lc|content_w|content_h|index|cx|cy
CACHE_FILE="/tmp/iphone-tap-text-cache"
query_lc=$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')
cache_key="${query_lc}|${CONTENT_W}|${CONTENT_H}|${index}"
if $cached && [[ -f "$CACHE_FILE" ]]; then
    hit=$(grep -F "${cache_key}|" "$CACHE_FILE" 2>/dev/null | head -1 || true)
    if [[ -n "$hit" ]]; then
        IFS='|' read -r _ _ _ _ cx cy <<< "$hit"
        echo "Matched \"$query\" at ($cx, $cy) [cached]"
        if ! $dry; then
            "$SCRIPT_DIR/tap.sh" "$cx" "$cy"
        fi
        exit 0
    fi
fi

img=$(mktemp /tmp/tap-text-XXXXXX.png)
trap 'rm -f "$img"' EXIT
"$SCRIPT_DIR/screenshot.sh" --native "$img" > /dev/null

ocr_output=$("$HELPER" "$img" 2>/dev/null) || {
    echo "Error: OCR failed" >&2
    exit 1
}

exact=()
partial=()
seen=()
while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    # Take the 4 numeric fields from the right - the OCR text itself may contain '|'
    IFS='|' read -r -a f <<< "$line"
    n=${#f[@]}
    (( n >= 5 )) || continue
    x="${f[n-4]}"; y="${f[n-3]}"; w="${f[n-2]}"; h="${f[n-1]}"
    text="${f[0]}"
    for (( i = 1; i < n - 4; i++ )); do text+="|${f[i]}"; done
    seen+=("$text")
    text_lc=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')
    cx=$(( (x + w / 2) / SCALE ))
    cy=$(( (y + h / 2) / SCALE ))
    entry="${cy}|${cx}|${text}"
    if [[ "$text_lc" == "$query_lc" ]]; then
        exact+=("$entry")
    elif [[ "$text_lc" == *"$query_lc"* ]]; then
        partial+=("$entry")
    fi
done <<< "$ocr_output"

if (( ${#exact[@]} > 0 )); then
    matches=("${exact[@]}")
elif (( ${#partial[@]} > 0 )); then
    matches=("${partial[@]}")
else
    echo "Error: no on-screen text matches '$query'" >&2
    if (( ${#seen[@]} > 0 )); then
        echo "On screen:" >&2
        printf '  %s\n' "${seen[@]}" >&2
    fi
    exit 1
fi

# Top-to-bottom order, pick the Nth
selected=$(printf '%s\n' "${matches[@]}" | sort -t'|' -k1,1n | sed -n "${index}p")
if [[ -z "$selected" ]]; then
    echo "Error: --index $index out of range (${#matches[@]} match(es) for '$query')" >&2
    exit 1
fi

IFS='|' read -r cy cx matched_text <<< "$selected"
echo "Matched \"$matched_text\" at ($cx, $cy)"
if $cached; then
    # Refresh this key's entry
    tmp_cache=$(mktemp /tmp/tap-text-cache-XXXXXX)
    [[ -f "$CACHE_FILE" ]] && grep -vF "${cache_key}|" "$CACHE_FILE" > "$tmp_cache" || true
    printf '%s|%s|%s\n' "$cache_key" "$cx" "$cy" >> "$tmp_cache"
    mv "$tmp_cache" "$CACHE_FILE"
fi
if ! $dry; then
    "$SCRIPT_DIR/tap.sh" "$cx" "$cy"
fi
