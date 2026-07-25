#!/usr/bin/env bash
# Check iPhone Mirroring connection state.
# Output: JSON with status ("connected", "disconnected", or "not_running")
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

status_code=$(osascript -e "
tell application \"System Events\"
    if not (exists process \"${IPHONE_MIRRORING_PROCESS}\") then
        return \"not_running\"
    end if
    tell process \"${IPHONE_MIRRORING_PROCESS}\"
        if not (exists window 1) then
            return \"not_running\"
        end if
        try
            set g to group 1 of window 1
            set childCount to count of UI elements of g
            if childCount = 0 then
                return \"connected\"
            else
                return \"disconnected\"
            end if
        on error
            return \"disconnected\"
        end try
    end tell
end tell" 2>/dev/null) || true

echo "{\"status\":\"${status_code:-not_running}\"}"
