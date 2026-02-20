#!/usr/bin/env bash
# Swipe from (x1,y1) to (x2,y2) on the iPhone Mirroring window.
# Usage: swipe.sh <x1> <y1> <x2> <y2> [duration_ms]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -lt 4 ]]; then
    echo "Usage: swipe.sh <x1> <y1> <x2> <y2> [duration_ms]" >&2
    exit 1
fi

rel_x1="$1"
rel_y1="$2"
rel_x2="$3"
rel_y2="$4"
duration_ms="${5:-300}"

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

# Validate coordinates
for coord_pair in "$rel_x1,$rel_y1" "$rel_x2,$rel_y2"; do
    cx="${coord_pair%,*}"
    cy="${coord_pair#*,}"
    if (( cx < 0 || cx > win_w || cy < 0 || cy > win_h )); then
        echo "Error: Coordinates ($cx, $cy) out of bounds (${win_w}x${win_h})" >&2
        exit 1
    fi
done

# Convert to absolute
abs_x1=$(( win_x + rel_x1 ))
abs_y1=$(( win_y + rel_y1 ))
abs_x2=$(( win_x + rel_x2 ))
abs_y2=$(( win_y + rel_y2 ))

# Calculate intermediate steps for smooth swipe
steps=10
sleep_per_step=$(echo "scale=4; $duration_ms / 1000 / $steps" | bc)

# Mouse down at start, drag through intermediate points, mouse up at end
cliclick dd:"${abs_x1},${abs_y1}"

for (( i = 1; i <= steps; i++ )); do
    frac=$(echo "scale=4; $i / $steps" | bc)
    ix=$(echo "$abs_x1 + ($abs_x2 - $abs_x1) * $frac" | bc | cut -d. -f1)
    iy=$(echo "$abs_y1 + ($abs_y2 - $abs_y1) * $frac" | bc | cut -d. -f1)
    cliclick m:"${ix},${iy}"
    sleep "$sleep_per_step"
done

cliclick du:"${abs_x2},${abs_y2}"

echo "Swiped ($rel_x1,$rel_y1) -> ($rel_x2,$rel_y2) in ${duration_ms}ms"
