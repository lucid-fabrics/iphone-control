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
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cmd="${1:-help}"
shift || true

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
        echo ""
        echo "Prerequisites: brew install cliclick"
        ;;
    *)
        echo "Unknown command: $cmd" >&2
        echo "Run: iphone-control.sh help" >&2
        exit 1
        ;;
esac
