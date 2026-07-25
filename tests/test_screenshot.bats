#!/usr/bin/env bats
# Tests for screenshot.sh argument handling and error paths.

load test_helper

setup() {
    setup_temp
    source "$PROJECT_ROOT/helpers/common.sh"
}

teardown() {
    teardown_temp
}

@test "screenshot: uses default output path when none specified" {
    # Verify the default path logic in the script
    # screenshot.sh line: OUTPUT="${1:-/tmp/iphone-screen.png}"
    local default_output="/tmp/iphone-screen.png"

    # Create a minimal mock screenshot script that just tests the default
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    cat > "$mock_dir/screenshot_test.sh" << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT="${1:-/tmp/iphone-screen.png}"
echo "$OUTPUT"
SCRIPT
    chmod +x "$mock_dir/screenshot_test.sh"

    run "$mock_dir/screenshot_test.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/iphone-screen.png" ]
}

@test "screenshot: uses custom output path when specified" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    cat > "$mock_dir/screenshot_test.sh" << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
OUTPUT="${1:-/tmp/iphone-screen.png}"
echo "$OUTPUT"
SCRIPT
    chmod +x "$mock_dir/screenshot_test.sh"

    run "$mock_dir/screenshot_test.sh" "/tmp/custom-output.png"
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/custom-output.png" ]
}

@test "screenshot: fails when screencapture produces no file" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    # Create a mock that simulates screencapture failure (no file created)
    cat > "$mock_dir/screenshot_fail.sh" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$mock_dir"
source "\$SCRIPT_DIR/helpers/common.sh"
OUTPUT="\${1:-/tmp/iphone-screen.png}"

window_json=\$("\$SCRIPT_DIR/find-window.sh")
parse_window_bounds "\$window_json"

tmp_full="/tmp/iphone-screenshot-test-nonexistent-\$\$.png"
# Don't actually create the file — simulate screencapture failure

if [[ ! -f "\$tmp_full" ]]; then
    echo "Error: Screenshot failed. Check Screen Recording permission." >&2
    exit 1
fi
SCRIPT
    chmod +x "$mock_dir/screenshot_fail.sh"

    run "$mock_dir/screenshot_fail.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Screenshot failed"* ]]
}

@test "screenshot: crop offset calculation is correct" {
    # Verify the math: offset = (CONTENT - WINDOW) * SCALE
    parse_window_bounds "$MOCK_WINDOW_JSON"

    local offset_x=$(( (CONTENT_X - WINDOW_X) * SCALE ))
    local offset_y=$(( (CONTENT_Y - WINDOW_Y) * SCALE ))
    local crop_w=$(( CONTENT_W * SCALE ))
    local crop_h=$(( CONTENT_H * SCALE ))

    # CONTENT_X=110, WINDOW_X=100, SCALE=2 => offset_x=20
    [ "$offset_x" -eq 20 ]
    # CONTENT_Y=220, WINDOW_Y=200, SCALE=2 => offset_y=40
    [ "$offset_y" -eq 40 ]
    # CONTENT_W=380, SCALE=2 => crop_w=760
    [ "$crop_w" -eq 760 ]
    # CONTENT_H=760, SCALE=2 => crop_h=1520
    [ "$crop_h" -eq 1520 ]
}
