#!/usr/bin/env bash
# Tap at coordinates relative to the iPhone Mirroring window.
# Usage: tap.sh <x> <y>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -lt 2 ]]; then
    echo "Usage: tap.sh <x> <y>" >&2
    exit 1
fi

rel_x="$1"
rel_y="$2"

# Check cliclick
if ! command -v cliclick &>/dev/null; then
    echo "Error: cliclick not found. Install with: brew install cliclick" >&2
    exit 1
fi

# Get window position
window_json=$("$SCRIPT_DIR/find-window.sh")

win_x=$(echo "$window_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['x'])")
win_y=$(echo "$window_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['y'])")
win_w=$(echo "$window_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['width'])")
win_h=$(echo "$window_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['height'])")

# Validate coordinates are within bounds
if (( rel_x < 0 || rel_x > win_w || rel_y < 0 || rel_y > win_h )); then
    echo "Error: Coordinates ($rel_x, $rel_y) out of bounds (${win_w}x${win_h})" >&2
    exit 1
fi

# Convert to absolute screen coordinates
abs_x=$(( win_x + rel_x ))
abs_y=$(( win_y + rel_y ))

# Click
cliclick c:"${abs_x},${abs_y}"
echo "Tapped at ($rel_x, $rel_y) -> screen ($abs_x, $abs_y)"
