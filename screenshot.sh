#!/usr/bin/env bash
# Capture a screenshot of the iPhone Mirroring window.
# Output: path to the saved PNG
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="${1:-/tmp/iphone-screen.png}"

# Get window info
window_json=$("$SCRIPT_DIR/find-window.sh")

x=$(echo "$window_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['x'])")
y=$(echo "$window_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['y'])")
w=$(echo "$window_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['width'])")
h=$(echo "$window_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['height'])")

# Capture the region
screencapture -R "${x},${y},${w},${h}" "$OUTPUT" 2>/dev/null

if [[ ! -f "$OUTPUT" ]]; then
    echo "Error: Screenshot failed. Check Screen Recording permission." >&2
    exit 1
fi

echo "$OUTPUT"
