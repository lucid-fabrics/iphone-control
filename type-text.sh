#!/usr/bin/env bash
# Type text into the iPhone Mirroring window.
# Usage: type-text.sh "text" [tap_x tap_y]
# If tap coordinates given, taps the field first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: type-text.sh \"text\" [tap_x tap_y]" >&2
    exit 1
fi

text="$1"
tap_x="${2:-}"
tap_y="${3:-}"

if ! command -v cliclick &>/dev/null; then
    echo "Error: cliclick not found. Install with: brew install cliclick" >&2
    exit 1
fi

# Tap field first if coordinates provided
if [[ -n "$tap_x" && -n "$tap_y" ]]; then
    "$SCRIPT_DIR/tap.sh" "$tap_x" "$tap_y"
    sleep 0.3  # Wait for keyboard to appear
fi

# Type the text
cliclick t:"$text"
echo "Typed: $text"
