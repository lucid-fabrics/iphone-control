#!/usr/bin/env bats
# Tests for tap.sh argument validation and error handling.

load test_helper

setup() {
    setup_temp
}

teardown() {
    teardown_temp
}

@test "tap: rejects missing arguments (no args)" {
    run "$PROJECT_ROOT/tap.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "tap: rejects missing y argument (one arg)" {
    run "$PROJECT_ROOT/tap.sh" 100
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "tap: rejects out-of-bounds coordinates" {
    # Create a tap.sh wrapper that uses our mock find-window.sh
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    # Create a tap script that sources common.sh and uses mock find-window
    cat > "$mock_dir/tap_test.sh" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$mock_dir"
source "\$SCRIPT_DIR/helpers/common.sh"

if [[ \$# -lt 2 ]]; then
    echo "Usage: tap.sh <x> <y>" >&2
    exit 1
fi

rel_x="\$1"
rel_y="\$2"

window_json=\$("\$SCRIPT_DIR/find-window.sh")
parse_window_bounds "\$window_json"
validate_coords "\$rel_x" "\$rel_y" "\$CONTENT_W" "\$CONTENT_H" || exit 1
echo "Tapped at (\$rel_x, \$rel_y)"
SCRIPT
    chmod +x "$mock_dir/tap_test.sh"

    # Out of bounds — content is 380x760
    run "$mock_dir/tap_test.sh" 500 100
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of bounds"* ]]
}

@test "tap: accepts valid coordinates with mock" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    cat > "$mock_dir/tap_test.sh" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$mock_dir"
source "\$SCRIPT_DIR/helpers/common.sh"

if [[ \$# -lt 2 ]]; then
    echo "Usage: tap.sh <x> <y>" >&2
    exit 1
fi

rel_x="\$1"
rel_y="\$2"

window_json=\$("\$SCRIPT_DIR/find-window.sh")
parse_window_bounds "\$window_json"
validate_coords "\$rel_x" "\$rel_y" "\$CONTENT_W" "\$CONTENT_H" || exit 1
echo "Tapped at (\$rel_x, \$rel_y)"
SCRIPT
    chmod +x "$mock_dir/tap_test.sh"

    run "$mock_dir/tap_test.sh" 190 380
    [ "$status" -eq 0 ]
    [[ "$output" == *"Tapped"* ]]
}

@test "tap: accepts origin coordinates (0,0)" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    cat > "$mock_dir/tap_test.sh" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$mock_dir"
source "\$SCRIPT_DIR/helpers/common.sh"

rel_x="\$1"; rel_y="\$2"
window_json=\$("\$SCRIPT_DIR/find-window.sh")
parse_window_bounds "\$window_json"
validate_coords "\$rel_x" "\$rel_y" "\$CONTENT_W" "\$CONTENT_H" || exit 1
echo "Tapped at (\$rel_x, \$rel_y)"
SCRIPT
    chmod +x "$mock_dir/tap_test.sh"

    run "$mock_dir/tap_test.sh" 0 0
    [ "$status" -eq 0 ]
}
