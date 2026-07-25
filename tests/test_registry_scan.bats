#!/usr/bin/env bats
# Tests for registry.sh scan command with mocked dependencies.

load test_helper

setup() {
    setup_temp
    export REAL_HOME="$HOME"
    export HOME="$TEST_TEMP_DIR"
}

teardown() {
    export HOME="$REAL_HOME"
    teardown_temp
}

# Helper: create a registry scan environment with mocked map-apps.sh
_create_registry_scan_env() {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    local apps_json="${1:-[{\"name\":\"Safari\",\"page\":1,\"x\":50,\"y\":100},{\"name\":\"Settings\",\"page\":2,\"x\":150,\"y\":200}]}"

    # Mock map-apps.sh - returns canned JSON array
    cat > "$mock_dir/map-apps.sh" << MOCK
#!/usr/bin/env bash
echo '${apps_json}'
MOCK
    chmod +x "$mock_dir/map-apps.sh"

    echo "$mock_dir"
}

# Helper: create a registry script that uses the mock directory
_create_registry_script() {
    local mock_dir="$1"

    cat > "$mock_dir/registry.sh" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$mock_dir"
source "\$SCRIPT_DIR/helpers/common.sh"
REGISTRY_DIR="\$HOME/.iphone-control"
REGISTRY_FILE="\$REGISTRY_DIR/app-registry.json"

cmd="\${1:-help}"
shift || true

case "\$cmd" in
    scan)
        max_pages="\${1:-\$DEFAULT_MAX_PAGES}"

        window_json=\$("\$SCRIPT_DIR/find-window.sh")
        parse_window_bounds "\$window_json"

        apps_json=\$("\$SCRIPT_DIR/map-apps.sh" "\$max_pages")
        scanned_at=\$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # Build registry JSON using pure bash (no osascript for tests)
        # Parse total_pages from apps_json
        max_page=0
        while [[ "\$apps_json" =~ \"page\":([0-9]+) ]]; do
            p="\${BASH_REMATCH[1]}"
            (( p > max_page )) && max_page=\$p
            apps_json="\${apps_json#*\"page\":\$p}"
        done
        # Re-read apps_json from map-apps
        apps_json=\$("\$SCRIPT_DIR/map-apps.sh" "\$max_pages")

        registry="{\"version\":2,\"scanned_at\":\"\${scanned_at}\",\"total_pages\":\${max_page},\"content_width\":\${CONTENT_W},\"content_height\":\${CONTENT_H},\"apps\":\${apps_json}}"

        mkdir -p "\$REGISTRY_DIR"
        echo "\$registry" > "\$REGISTRY_FILE"
        echo "\$registry"
        ;;
    *)
        echo "Unknown command: \$cmd" >&2
        exit 1
        ;;
esac
SCRIPT
    chmod +x "$mock_dir/registry.sh"
}

@test "registry scan: creates registry directory if missing" {
    local mock_dir
    mock_dir=$(_create_registry_scan_env)
    _create_registry_script "$mock_dir"

    # Ensure directory does not exist
    [ ! -d "$HOME/.iphone-control" ]

    run "$mock_dir/registry.sh" scan
    [ "$status" -eq 0 ]
    [ -d "$HOME/.iphone-control" ]
}

@test "registry scan: writes valid JSON to registry file" {
    local mock_dir
    mock_dir=$(_create_registry_scan_env)
    _create_registry_script "$mock_dir"

    run "$mock_dir/registry.sh" scan
    [ "$status" -eq 0 ]
    [ -f "$HOME/.iphone-control/app-registry.json" ]

    # File should contain valid JSON-like structure
    local content
    content=$(cat "$HOME/.iphone-control/app-registry.json")
    [[ "$content" == "{"* ]]
    [[ "$content" == *"}" ]]
}

@test "registry scan: registry contains version, scanned_at, apps fields" {
    local mock_dir
    mock_dir=$(_create_registry_scan_env)
    _create_registry_script "$mock_dir"

    run "$mock_dir/registry.sh" scan
    [ "$status" -eq 0 ]

    [[ "$output" == *'"version":2'* ]]
    [[ "$output" == *'"scanned_at":'* ]]
    [[ "$output" == *'"apps":'* ]]
    [[ "$output" == *'"content_width":'* ]]
    [[ "$output" == *'"content_height":'* ]]
    [[ "$output" == *"Safari"* ]]
    [[ "$output" == *"Settings"* ]]
}

@test "registry scan: respects max_pages argument" {
    local mock_dir
    mock_dir=$(_create_registry_scan_env)

    # Replace map-apps mock to verify max_pages is passed through
    cat > "$mock_dir/map-apps.sh" << 'MOCK'
#!/usr/bin/env bash
max_pages="${1:-10}"
echo "[{\"name\":\"TestApp\",\"page\":1,\"x\":50,\"y\":100,\"max_pages_received\":${max_pages}}]"
MOCK
    chmod +x "$mock_dir/map-apps.sh"
    _create_registry_script "$mock_dir"

    run "$mock_dir/registry.sh" scan 3
    [ "$status" -eq 0 ]
    [[ "$output" == *'"max_pages_received":3'* ]]
}
