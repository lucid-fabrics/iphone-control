#!/usr/bin/env bash
# App Registry Manager - persistent storage for home screen app positions.
# Usage: registry.sh <command> [args...]
#
# Commands:
#   scan [max_pages]   - Scan home screen, write registry file
#   lookup <name>      - Find app by name (case-insensitive), output JSON entry
#   invalidate         - Delete registry file
#   list               - Output registry file contents
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"
REGISTRY_DIR="$HOME/.iphone-control"
REGISTRY_FILE="$REGISTRY_DIR/app-registry.json"

cmd="${1:-help}"
shift || true

case "$cmd" in
    scan)
        max_pages="${1:-$DEFAULT_MAX_PAGES}"

        # Get current content dimensions
        window_json=$("$SCRIPT_DIR/find-window.sh")
        parse_window_bounds "$window_json"

        # Run map-apps.sh to get app list
        apps_json=$("$SCRIPT_DIR/map-apps.sh" "$max_pages")

        # Build registry JSON - sanitize apps_json for safe JXA embedding
        # apps_json comes from our own map-apps.sh output, but we validate it's valid JSON
        scanned_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # Use a temp file to avoid shell interpolation issues with large JSON
        tmp_apps="/tmp/iphone-registry-apps-$$.json"
        printf '%s\n' "$apps_json" > "$tmp_apps"

        registry=$(osascript -l JavaScript -e "
            ObjC.import('Foundation');
            const data = \$.NSData.dataWithContentsOfFile('${tmp_apps}');
            const str = \$.NSString.alloc.initWithDataEncoding(data, \$.NSUTF8StringEncoding).js;
            const apps = JSON.parse(str);
            let max = 0;
            for (const a of apps) { if (a.page > max) max = a.page; }
            JSON.stringify({
                version: 2,
                scanned_at: '${scanned_at}',
                total_pages: max,
                content_width: ${CONTENT_W},
                content_height: ${CONTENT_H},
                apps: apps
            }, null, 2);
        ") || {
            rm -f "$tmp_apps"
            echo '{"error":"Failed to build registry JSON"}' >&2
            exit 1
        }
        rm -f "$tmp_apps"

        if [[ -z "$registry" ]]; then
            echo '{"error":"Registry scan returned empty output"}' >&2
            exit 1
        fi

        # Write to file atomically - temp file + mv prevents partial writes on interrupt
        mkdir -p "$REGISTRY_DIR"
        tmp_reg="/tmp/iphone-registry-$$.json"
        printf '%s\n' "$registry" > "$tmp_reg"
        mv "$tmp_reg" "$REGISTRY_FILE"
        echo "$registry"
        ;;

    lookup)
        if [[ $# -lt 1 ]]; then
            echo '{"error":"Usage: registry.sh lookup <app_name>"}' >&2
            exit 1
        fi
        search_name="$1"

        if [[ ! -f "$REGISTRY_FILE" ]]; then
            echo '{"error":"No registry found. Run: registry.sh scan"}' >&2
            exit 1
        fi

        # Write search name to a temp file - avoids embedding user content in any bash string,
        # preventing $ expansion and backtick injection in the osascript -e argument.
        tmp_search=$(mktemp /tmp/registry-search-XXXXXX.txt)
        printf '%s' "$search_name" > "$tmp_search"

        # Case-insensitive lookup: exact match first, then substring
        result=$(osascript -l JavaScript -e "
            ObjC.import('Foundation');
            const regData = \$.NSData.dataWithContentsOfFile('${REGISTRY_FILE}');
            const str = \$.NSString.alloc.initWithDataEncoding(regData, \$.NSUTF8StringEncoding).js;
            const registry = JSON.parse(str);
            // v1 registries stored pixel-space coords; v2 stores content points.
            // Reject stale versions so open-app falls back to Spotlight instead of mis-tapping.
            if (registry.version !== 2) throw new Error('stale registry version: rescan needed');
            const apps = registry.apps;
            const searchData = \$.NSData.dataWithContentsOfFile('${tmp_search}');
            const search = \$.NSString.alloc.initWithDataEncoding(searchData, \$.NSUTF8StringEncoding).js;
            const lower = search.toLowerCase();

            // Exact match (case-insensitive)
            let match = apps.find(a => a.name.toLowerCase() === lower);

            // Substring fallback
            if (!match) {
                match = apps.find(a => a.name.toLowerCase().includes(lower));
            }

            if (match) {
                JSON.stringify({
                    name: match.name,
                    page: match.page,
                    x: match.x,
                    y: match.y,
                    content_width: registry.content_width,
                    content_height: registry.content_height
                });
            } else {
                '';
            }
        ") || {
            rm -f "$tmp_search"
            echo "{\"error\":\"Registry lookup failed\"}" >&2
            exit 1
        }
        rm -f "$tmp_search"

        if [[ -z "$result" ]]; then
            safe_err="${search_name//\\/\\\\}"
            safe_err="${safe_err//\"/\\\"}"
            echo "{\"error\":\"App not found: $safe_err\"}" >&2
            exit 1
        fi
        echo "$result"
        ;;

    invalidate)
        if [[ -f "$REGISTRY_FILE" ]]; then
            rm -f "$REGISTRY_FILE"
            echo "Registry invalidated"
        else
            echo "No registry to invalidate"
        fi
        ;;

    list)
        if [[ ! -f "$REGISTRY_FILE" ]]; then
            echo '{"error":"No registry found. Run: registry.sh scan"}' >&2
            exit 1
        fi
        cat "$REGISTRY_FILE"
        ;;

    help|--help|-h)
        echo "App Registry Manager"
        echo ""
        echo "Usage: registry.sh <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  scan [max_pages]   Scan home screen, write registry file"
        echo "  lookup <name>      Find app by name (case-insensitive)"
        echo "  invalidate         Delete registry file"
        echo "  list               Output registry file contents"
        ;;

    *)
        echo "Unknown command: $cmd" >&2
        echo "Run: registry.sh help" >&2
        exit 1
        ;;
esac
