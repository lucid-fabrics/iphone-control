#!/usr/bin/env bash
# Check iPhone Mirroring connection state.
# Output: JSON with status ("connected", "disconnected", or "not_running")
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

status_code=$(osascript -e "
tell application \"System Events\"
    set procs to every process whose bundle identifier is \"${IPHONE_MIRRORING_BUNDLE_ID}\"
    if (count of procs) = 0 then
        return \"not_running\"
    end if
    tell item 1 of procs
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
