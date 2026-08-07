#!/usr/bin/env bash
# iPhone Mirroring Control - main entry point.
# Usage: iphone-control.sh <command> [args...]
#
# Commands:
#   find                         - Locate iPhone Mirroring window
#   screenshot [output_path]     - Capture iPhone screen
#   tap <x> <y>                  - Tap at coordinates
#   tap-text <text> [--index N]  - OCR the screen and tap matching text
#   press <x> <y> [hold_ms]      - Long press (context menu, edit mode, selection)
#   double-tap <x> <y>           - Double tap (zoom toggle, word select)
#   read [--grep p] [--at x y]   - Read on-screen text with tappable coordinates
#   wait <text|gone|still> ...   - Wait for a screen condition (not a fixed sleep)
#   back                         - Navigate back (edge swipe)
#   key <key> [--cmd ...]        - Send a key press
#   copy | paste | select-all    - Clipboard actions
#   clear-text                   - Select all and delete in the focused field
#   scroll <dy> [x y]            - Scroll content (dy>0 down, dy<0 up)
#   scroll-to <text> [--max N]   - Scroll until text is visible
#   drag-icon <x1> <y1> <x2> <y2> [--hover ms] - Move icon / drop onto icon (folder)
#   batch "<action>" ...         - Run tap/swipe/scroll/sleep actions in one session
#   swipe <x1> <y1> <x2> <y2> [duration_ms] - Swipe gesture
#   type "text" [x y]            - Type text (optionally tap field first)
#   home                         - Go to home screen (via View menu)
#   app-switcher                 - Open app switcher (via View menu)
#   spotlight                    - Open Spotlight search (via View menu)
#   open-app "App Name" [--spotlight] - Open app (registry→Spotlight fallback)
#   status                       - Check connection state
#   map-apps [max_pages]         - Map apps on home screen (OCR, stdout only)
#   registry-scan [max_pages]    - Scan apps and save to persistent registry
#   registry-lookup <name>       - Look up app position from registry
#   registry-invalidate          - Delete registry (force rescan)
#   registry-list                - Show cached registry contents
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

cmd="${1:-help}"
shift || true

# Helper: trigger a View menu action by its keyboard shortcut (Cmd+1/2/3).
# ~2.4x faster than opening the menu and clicking the item, and it goes through
# jxa_activate_and_run so focus and cursor are restored afterwards.
# Resolves the digit via the active keyboard layout (not a fixed US-QWERTY
# table) so this works when the Mac's layout is AZERTY/QWERTZ/etc, falling
# back to the static table if the native engine cannot be built.
_view_menu_key() {
    local key="$1" code="" engine keyfor_out flags_expr='$.kCGEventFlagMaskCommand'
    engine=$(input_engine "$SCRIPT_DIR/helpers" 2>/dev/null) || engine=""
    if [[ -n "$engine" ]]; then
        keyfor_out=$("$engine" keyfor "$key" 2>/dev/null) || keyfor_out=""
        if [[ -n "$keyfor_out" ]]; then
            code="${keyfor_out%% *}"
            base_flags="${keyfor_out##* }"
            [[ "$base_flags" != "0" ]] && flags_expr="${base_flags} | ${flags_expr}"
        fi
    fi
    if [[ -z "$code" ]]; then
        code=$(keycode_for "$key") || { echo "Error: bad view shortcut key: $key" >&2; return 1; }
    fi
    jxa_activate_and_run "$(jxa_key_body "$code" "$flags_expr")" || {
        echo "Error: Failed to send Cmd+${key}. Is iPhone Mirroring running?" >&2
        return 1
    }
}

case "$cmd" in
    find)
        "$SCRIPT_DIR/find-window.sh"
        ;;
    screenshot)
        "$SCRIPT_DIR/screenshot.sh" "$@"
        ;;
    tap)
        "$SCRIPT_DIR/tap.sh" "$@"
        ;;
    tap-text)
        "$SCRIPT_DIR/tap-text.sh" "$@"
        ;;
    press|long-press)
        [[ $# -ge 2 ]] || { echo "Usage: iphone-control.sh press <x> <y> [hold_ms]" >&2; exit 1; }
        ENGINE=$(input_engine "$SCRIPT_DIR/helpers") || exit 1
        "$ENGINE" longpress "$@"
        echo "Long pressed ($1, $2)"
        ;;
    double-tap)
        [[ $# -ge 2 ]] || { echo "Usage: iphone-control.sh double-tap <x> <y>" >&2; exit 1; }
        ENGINE=$(input_engine "$SCRIPT_DIR/helpers") || exit 1
        "$ENGINE" doubletap "$@"
        echo "Double tapped ($1, $2)"
        ;;
    read)
        "$SCRIPT_DIR/read.sh" "$@"
        ;;
    wait)
        "$SCRIPT_DIR/wait.sh" "$@"
        ;;
    back)
        "$SCRIPT_DIR/back.sh" "$@"
        ;;
    scroll-to)
        "$SCRIPT_DIR/scroll-to.sh" "$@"
        ;;
    clear-text)
        # Select all, then delete: the only reliable way to empty a field whose
        # current contents are unknown.
        "$SCRIPT_DIR/key.sh" a --cmd > /dev/null
        "$SCRIPT_DIR/key.sh" delete > /dev/null
        echo "Cleared focused text field"
        ;;
    scroll)
        "$SCRIPT_DIR/scroll.sh" "$@"
        ;;
    drag-icon)
        "$SCRIPT_DIR/drag-icon.sh" "$@"
        ;;
    batch)
        "$SCRIPT_DIR/batch.sh" "$@"
        ;;
    swipe)
        "$SCRIPT_DIR/swipe.sh" "$@"
        ;;
    type)
        "$SCRIPT_DIR/type-text.sh" "$@"
        ;;
    open-app)
        "$SCRIPT_DIR/open-app.sh" "$@"
        ;;
    home)
        _view_menu_key 1
        echo "Home screen activated"
        ;;
    app-switcher)
        _view_menu_key 2
        echo "App switcher opened"
        ;;
    spotlight)
        _view_menu_key 3
        echo "Spotlight opened"
        ;;
    key)
        "$SCRIPT_DIR/key.sh" "$@"
        ;;
    copy)
        "$SCRIPT_DIR/key.sh" c --cmd
        ;;
    paste)
        "$SCRIPT_DIR/key.sh" v --cmd
        ;;
    select-all)
        "$SCRIPT_DIR/key.sh" a --cmd
        ;;
    map-apps)
        "$SCRIPT_DIR/map-apps.sh" "$@"
        ;;
    registry-scan)
        "$SCRIPT_DIR/registry.sh" scan "$@"
        ;;
    registry-lookup)
        "$SCRIPT_DIR/registry.sh" lookup "$@"
        ;;
    registry-invalidate)
        "$SCRIPT_DIR/registry.sh" invalidate
        ;;
    registry-list)
        "$SCRIPT_DIR/registry.sh" list
        ;;
    status)
        "$SCRIPT_DIR/status.sh"
        ;;
    help|--help|-h)
        echo "iPhone Mirroring Control"
        echo ""
        echo "Usage: iphone-control.sh <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  find                              Locate iPhone Mirroring window"
        echo "  screenshot [output_path]          Capture iPhone screen"
        echo "  tap <x> <y>                       Tap at coordinates"
        echo "  tap-text <text> [--index N]       OCR the screen, tap matching text"
        echo "  press <x> <y> [hold_ms]           Long press (context menu, edit mode)"
        echo "  double-tap <x> <y>                Double tap (zoom toggle, word select)"
        echo "  read [--grep p] [--at x y] [--json]  Read on-screen text + coordinates"
        echo "  wait text|gone <s> | still        Wait for a condition, not a fixed sleep"
        echo "  back [--swipe]                    Navigate back"
        echo "  key <key> [--cmd --shift ...]     Send a key press"
        echo "  copy | paste | select-all         Clipboard actions"
        echo "  clear-text                        Empty the focused text field"
        echo "  scroll <dy> [x y]                 Scroll content (dy>0 down, dy<0 up)"
        echo "  scroll-to <text> [--tap] [--up]   Scroll until text is visible"
        echo "  drag-icon <x1> <y1> <x2> <y2>     Move icon; --hover 1200 drops into folder"
        echo "  batch \"<action>\" ...              tap/swipe/scroll/sleep, one session"
        echo "  swipe <x1> <y1> <x2> <y2> [ms]   Swipe gesture"
        echo "  type \"text\" [x y]                 Type text"
        echo "  home                              Go to home screen"
        echo "  app-switcher                      Open app switcher"
        echo "  spotlight                         Open Spotlight search"
        echo "  open-app \"App Name\" [--spotlight]  Open app (registry→Spotlight)"
        echo "  map-apps [max_pages]              Map apps on home screen (OCR)"
        echo "  registry-scan [max_pages]         Scan apps, save to registry"
        echo "  registry-lookup <name>            Look up app from registry"
        echo "  registry-invalidate               Delete registry"
        echo "  registry-list                     Show registry contents"
        echo "  status                            Check connection state"
        echo ""
        echo "No external dependencies required."
        ;;
    *)
        echo "Unknown command: $cmd" >&2
        echo "Run: iphone-control.sh help" >&2
        exit 1
        ;;
esac
