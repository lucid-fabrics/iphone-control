#!/usr/bin/env bash
# Drive the running iPhoneCompanion app end to end and print what it did.
#
# Sends a prompt into the app's input field, waits for the agent loop to go
# quiet, then reads the conversation back through the app's own "Copy chat"
# button (clipboard), so the transcript is exactly what the user sees.
#
# Usage: drive-companion.sh "<prompt>" [timeout_seconds]
#
# Text is pasted (Cmd+V), never typed character by character: synthetic unicode
# keystrokes get mangled by the panel and land as garbage glyphs.
set -euo pipefail

PROMPT="${1:?Usage: drive-companion.sh \"<prompt>\" [timeout_seconds]}"
TIMEOUT="${2:-180}"

panel_frame() {
    osascript <<'AS'
tell application "System Events"
  tell process "iPhoneCompanion"
    if (count of windows) is 0 then return "none"
    set p to position of window 1
    set s to size of window 1
    return ((item 1 of p) as string) & "," & ((item 2 of p) as string) & "," & ¬
           ((item 1 of s) as string) & "," & ((item 2 of s) as string)
  end tell
end tell
AS
}

click_at() {  # click_at <x> <y>
    osascript -l JavaScript -e "
ObjC.import('CoreGraphics'); ObjC.import('Foundation');
const p = {x: $1, y: $2};
\$.CGEventPost(\$.kCGHIDEventTap, \$.CGEventCreateMouseEvent(null, \$.kCGEventMouseMoved, p, 0));
\$.NSThread.sleepForTimeInterval(0.03);
\$.CGEventPost(\$.kCGHIDEventTap, \$.CGEventCreateMouseEvent(null, \$.kCGEventLeftMouseDown, p, \$.kCGMouseButtonLeft));
\$.NSThread.sleepForTimeInterval(0.05);
\$.CGEventPost(\$.kCGHIDEventTap, \$.CGEventCreateMouseEvent(null, \$.kCGEventLeftMouseUp, p, \$.kCGMouseButtonLeft));
'ok';" > /dev/null
}

key_code() {  # key_code <code> [cmd|cmd_shift]
    local code="$1" mods="${2:-none}" flags="0"
    case "$mods" in
        cmd) flags='$.kCGEventFlagMaskCommand' ;;
        cmd_shift) flags='$.kCGEventFlagMaskCommand | $.kCGEventFlagMaskShift' ;;
    esac
    osascript -l JavaScript -e "
ObjC.import('CoreGraphics'); ObjC.import('Foundation');
const src = \$.CGEventSourceCreate(\$.kCGEventSourceStateHIDSystemState);
const dn = \$.CGEventCreateKeyboardEvent(src, $code, true);
const up = \$.CGEventCreateKeyboardEvent(src, $code, false);
const f = $flags; if (f) { dn.flags = f; up.flags = f; }
\$.CGEventPost(\$.kCGHIDEventTap, dn);
\$.NSThread.sleepForTimeInterval(0.04);
\$.CGEventPost(\$.kCGHIDEventTap, up);
'ok';" > /dev/null
}

FRAME=$(panel_frame)
if [[ "$FRAME" == "none" || -z "$FRAME" ]]; then
    echo "Error: iPhoneCompanion is not running (no window found)." >&2
    exit 1
fi
IFS=',' read -r PX PY PW PH <<< "$FRAME"

# Toolbar controls are right-aligned: gear, trash, copy, dock (28px pitch).
COPY_X=$(( PX + PW - 89 )); COPY_Y=$(( PY + 24 ))
INPUT_X=$(( PX + PW / 2 ));  INPUT_Y=$(( PY + PH - 26 ))

read_transcript() {
    click_at "$COPY_X" "$COPY_Y"
    sleep 0.4
    pbpaste
}

# Send the prompt: focus the field, paste, submit.
printf '%s' "$PROMPT" | pbcopy
click_at "$INPUT_X" "$INPUT_Y"
sleep 0.4
key_code 9 cmd      # Cmd+V
sleep 0.3
key_code 36         # Return
echo "Sent: $PROMPT" >&2

# Wait for the agent loop to settle: transcript unchanged across two polls.
deadline=$(( SECONDS + TIMEOUT ))
prev=""; stable=0
while (( SECONDS < deadline )); do
    sleep 6
    current=$(read_transcript)
    if [[ "$current" == "$prev" && -n "$current" ]]; then
        stable=$(( stable + 1 ))
        (( stable >= 2 )) && break
    else
        stable=0
    fi
    prev="$current"
done

echo "----- transcript -----"
read_transcript
