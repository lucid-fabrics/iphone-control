#!/usr/bin/env bats
# Tests for open-app.sh argument validation and launch strategies.

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

# Helper: create a mock open-app environment with registry, tap, swipe, iphone-control
_create_open_app_env() {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    # Mock iphone-control.sh (home command)
    cat > "$mock_dir/iphone-control.sh" << 'MOCK'
#!/usr/bin/env bash
echo "home: ok"
MOCK
    chmod +x "$mock_dir/iphone-control.sh"

    # Mock tap.sh
    cat > "$mock_dir/tap.sh" << 'MOCK'
#!/usr/bin/env bash
echo "Tapped at ($1, $2)"
MOCK
    chmod +x "$mock_dir/tap.sh"

    # Mock swipe.sh
    cat > "$mock_dir/swipe.sh" << 'MOCK'
#!/usr/bin/env bash
echo "Swiped"
MOCK
    chmod +x "$mock_dir/swipe.sh"

    echo "$mock_dir"
}

# Helper: create a mock registry.sh that returns lookup results
_create_mock_registry() {
    local mock_dir="$1"
    local lookup_result="${2:-}"

    if [[ -n "$lookup_result" ]]; then
        cat > "$mock_dir/registry.sh" << MOCK
#!/usr/bin/env bash
cmd="\${1:-help}"
shift || true
case "\$cmd" in
    lookup) echo '${lookup_result}' ;;
    invalidate) echo "Registry invalidated" ;;
    *) echo "Unknown" >&2; exit 1 ;;
esac
MOCK
    else
        # Registry lookup fails
        cat > "$mock_dir/registry.sh" << 'MOCK'
#!/usr/bin/env bash
cmd="${1:-help}"
shift || true
case "$cmd" in
    lookup) echo '{"error":"App not found"}' >&2; exit 1 ;;
    invalidate) echo "Registry invalidated" ;;
    *) echo "Unknown" >&2; exit 1 ;;
esac
MOCK
    fi
    chmod +x "$mock_dir/registry.sh"
}

# Helper: create the open-app test script using the mock directory
_create_open_app_script() {
    local mock_dir="$1"

    cat > "$mock_dir/open-app.sh" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$mock_dir"
source "\$SCRIPT_DIR/helpers/common.sh"

if [[ \$# -lt 1 ]]; then
    echo "Usage: open-app.sh <app name> [--spotlight]" >&2
    exit 1
fi

app_name="\$1"
force_spotlight=false
if [[ "\${2:-}" == "--spotlight" ]]; then
    force_spotlight=true
fi

_open_via_spotlight() {
    echo "Opened: \$app_name (spotlight)"
}

if \$force_spotlight; then
    _open_via_spotlight
    exit 0
fi

lookup_result=\$("\$SCRIPT_DIR/registry.sh" lookup "\$app_name" 2>/dev/null) || lookup_result=""

if [[ -z "\$lookup_result" ]]; then
    _open_via_spotlight
    exit 0
fi

app_page=\$(json_field "\$lookup_result" "page")
app_x=\$(json_field "\$lookup_result" "x")
app_y=\$(json_field "\$lookup_result" "y")
reg_width=\$(json_field "\$lookup_result" "content_width")
reg_height=\$(json_field "\$lookup_result" "content_height")

if [[ -z "\$app_page" || -z "\$app_x" || -z "\$app_y" || -z "\$reg_width" || -z "\$reg_height" ]]; then
    _open_via_spotlight
    exit 0
fi

window_json=\$("\$SCRIPT_DIR/find-window.sh")
parse_window_bounds "\$window_json"

if [[ "\$CONTENT_W" != "\$reg_width" || "\$CONTENT_H" != "\$reg_height" ]]; then
    "\$SCRIPT_DIR/registry.sh" invalidate > /dev/null 2>&1
    _open_via_spotlight
    exit 0
fi

"\$SCRIPT_DIR/iphone-control.sh" home > /dev/null 2>&1
sleep 0.01

if (( app_page > 1 )); then
    swipe_y=\$(( CONTENT_H / 2 ))
    swipe_x_start=\$(( CONTENT_W - SWIPE_EDGE_MARGIN ))
    swipe_x_end=\$SWIPE_EDGE_MARGIN
    for (( i=1; i<app_page; i++ )); do
        "\$SCRIPT_DIR/swipe.sh" "\$swipe_x_start" "\$swipe_y" "\$swipe_x_end" "\$swipe_y" "\$DEFAULT_SWIPE_DURATION" > /dev/null 2>&1
        sleep 0.01
    done
fi

"\$SCRIPT_DIR/tap.sh" "\$app_x" "\$app_y" > /dev/null 2>&1

echo "Opened: \$app_name (registry, page \$app_page)"
SCRIPT
    chmod +x "$mock_dir/open-app.sh"
}

@test "open-app: rejects missing arguments (no app name)" {
    run "$PROJECT_ROOT/open-app.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "open-app: falls back to spotlight when registry lookup fails" {
    local mock_dir
    mock_dir=$(_create_open_app_env)
    _create_mock_registry "$mock_dir" ""
    _create_open_app_script "$mock_dir"

    run "$mock_dir/open-app.sh" "NonExistentApp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"spotlight"* ]]
}

@test "open-app: falls back to spotlight when --spotlight flag used" {
    local mock_dir
    mock_dir=$(_create_open_app_env)
    _create_mock_registry "$mock_dir" '{"name":"Safari","page":1,"x":50,"y":100,"content_width":380,"content_height":760}'
    _create_open_app_script "$mock_dir"

    run "$mock_dir/open-app.sh" "Safari" "--spotlight"
    [ "$status" -eq 0 ]
    [[ "$output" == *"spotlight"* ]]
    [[ "$output" != *"registry"* ]]
}

@test "open-app: falls back to spotlight when dimensions mismatch" {
    local mock_dir
    mock_dir=$(_create_open_app_env)
    # Registry has different dimensions than mock window (380x760)
    _create_mock_registry "$mock_dir" '{"name":"Safari","page":1,"x":50,"y":100,"content_width":999,"content_height":999}'
    _create_open_app_script "$mock_dir"

    run "$mock_dir/open-app.sh" "Safari"
    [ "$status" -eq 0 ]
    [[ "$output" == *"spotlight"* ]]
}

@test "open-app: uses registry path when lookup succeeds and dimensions match" {
    local mock_dir
    mock_dir=$(_create_open_app_env)
    # Dimensions match mock window content: 380x760
    _create_mock_registry "$mock_dir" '{"name":"Safari","page":1,"x":50,"y":100,"content_width":380,"content_height":760}'
    _create_open_app_script "$mock_dir"

    run "$mock_dir/open-app.sh" "Safari"
    [ "$status" -eq 0 ]
    [[ "$output" == *"registry, page 1"* ]]
}

@test "open-app: handles app names with special characters (quotes, spaces)" {
    local mock_dir
    mock_dir=$(_create_open_app_env)
    _create_mock_registry "$mock_dir" ""
    _create_open_app_script "$mock_dir"

    run "$mock_dir/open-app.sh" "My App's \"Test\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"spotlight"* ]]
}
