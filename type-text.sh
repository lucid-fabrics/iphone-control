#!/usr/bin/env bash
# Type text into the iPhone Mirroring window.
# Usage: type-text.sh "text" [tap_x tap_y]
# If tap coordinates given, taps the field first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

if [[ $# -lt 1 ]]; then
    echo "Usage: type-text.sh \"text\" [tap_x tap_y]" >&2
    exit 1
fi

text="$1"
tap_x="${2:-}"
tap_y="${3:-}"

if [[ -z "$text" ]]; then
    echo "Error: text argument is empty" >&2
    exit 1
fi

# Both coordinates must be provided together or not at all
if [[ -n "$tap_x" && -z "$tap_y" ]] || [[ -z "$tap_x" && -n "$tap_y" ]]; then
    echo "Usage: type-text.sh \"text\" [tap_x tap_y]" >&2
    echo "Error: tap_x and tap_y must both be provided" >&2
    exit 1
fi

# Tap field first if coordinates provided
if [[ -n "$tap_x" && -n "$tap_y" ]]; then
    "$SCRIPT_DIR/tap.sh" "$tap_x" "$tap_y"
    sleep "$KEYBOARD_APPEAR_DELAY"
fi

# Write text to a temp file — avoids embedding user content in any bash string,
# eliminating $ expansion and backtick injection entirely.
tmp_text=$(mktemp /tmp/type-text-XXXXXX.txt)
printf '%s' "$text" > "$tmp_text"

jxa_activate_and_run "
const textData = \$.NSData.dataWithContentsOfFile('${tmp_text}');
const text = \$.NSString.alloc.initWithDataEncoding(textData, \$.NSUTF8StringEncoding).js;
const se = Application('System Events');
se.keystroke(text);
" || { rm -f "$tmp_text"; exit 1; }
rm -f "$tmp_text"

echo "Typed: $text"
