#!/usr/bin/env bash
# iPhone Mirroring Control — main entry point.
# Usage: iphone-control.sh <command> [args...]
#
# Commands:
#   find                         — Locate iPhone Mirroring window
#   screenshot [output_path]     — Capture iPhone screen
#   tap <x> <y>                  — Tap at coordinates
#   swipe <x1> <y1> <x2> <y2> [duration_ms] — Swipe gesture
#   type "text" [x y]            — Type text (optionally tap field first)
#   home                         — Go to home screen (via View menu)
#   app-switcher                 — Open app switcher (via View menu)
#   spotlight                    — Open Spotlight search (via View menu)
#   open-app "App Name" [--spotlight] — Open app (registry→Spotlight fallback)
#   status                       — Check connection state
#   map-apps [max_pages]         — Map apps on home screen (OCR, stdout only)
#   registry-scan [max_pages]    — Scan apps and save to persistent registry
#   registry-lookup <name>       — Look up app position from registry
#   registry-invalidate          — Delete registry (force rescan)
#   registry-list                — Show cached registry contents
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

cmd="${1:-help}"
shift || true

# Helper: click a View menu item in iPhone Mirroring
_view_menu_click() {
    local menu_item="$1"
    local safe_item
    safe_item=$(sanitize_applescript "$menu_item")
    osascript -e "
tell application \"System Events\"
    tell process \"${IPHONE_MIRRORING_PROCESS}\"
        set frontmost to true
        click menu item \"${safe_item}\" of menu 1 of menu bar item \"View\" of menu bar 1
    end tell
end tell" || {
        echo "Error: Failed to click View > ${menu_item}. Is iPhone Mirroring running?" >&2
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
        _view_menu_click "Home Screen"
        echo "Home screen activated"
        ;;
    app-switcher)
        _view_menu_click "App Switcher"
        echo "App switcher opened"
        ;;
    spotlight)
        _view_menu_click "Spotlight"
        echo "Spotlight opened"
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
