#!/usr/bin/env bats
# Tests for swipe.sh argument validation and defaults.

load test_helper

setup() {
    setup_temp
}

teardown() {
    teardown_temp
}

@test "swipe: rejects missing arguments (no args)" {
    run "$PROJECT_ROOT/swipe.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "swipe: rejects missing arguments (1 arg)" {
    run "$PROJECT_ROOT/swipe.sh" 10
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "swipe: rejects missing arguments (2 args)" {
    run "$PROJECT_ROOT/swipe.sh" 10 20
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "swipe: rejects missing arguments (3 args)" {
    run "$PROJECT_ROOT/swipe.sh" 10 20 30
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "swipe: rejects out-of-bounds start coordinates" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    cat > "$mock_dir/swipe_test.sh" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$mock_dir"
source "\$SCRIPT_DIR/helpers/common.sh"

if [[ \$# -lt 4 ]]; then
    echo "Usage: swipe.sh <x1> <y1> <x2> <y2> [duration_ms]" >&2
    exit 1
fi

rel_x1="\$1"; rel_y1="\$2"; rel_x2="\$3"; rel_y2="\$4"
duration_ms="\${5:-\$DEFAULT_SWIPE_DURATION}"

window_json=\$("\$SCRIPT_DIR/find-window.sh")
parse_window_bounds "\$window_json"
validate_coords "\$rel_x1" "\$rel_y1" "\$CONTENT_W" "\$CONTENT_H" || exit 1
validate_coords "\$rel_x2" "\$rel_y2" "\$CONTENT_W" "\$CONTENT_H" || exit 1
echo "Swiped (\$rel_x1,\$rel_y1) -> (\$rel_x2,\$rel_y2) in \${duration_ms}ms"
SCRIPT
    chmod +x "$mock_dir/swipe_test.sh"

    run "$mock_dir/swipe_test.sh" 500 100 200 300
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of bounds"* ]]
}

@test "swipe: rejects out-of-bounds end coordinates" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    cat > "$mock_dir/swipe_test.sh" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$mock_dir"
source "\$SCRIPT_DIR/helpers/common.sh"

if [[ \$# -lt 4 ]]; then
    echo "Usage: swipe.sh <x1> <y1> <x2> <y2> [duration_ms]" >&2
    exit 1
fi

rel_x1="\$1"; rel_y1="\$2"; rel_x2="\$3"; rel_y2="\$4"
duration_ms="\${5:-\$DEFAULT_SWIPE_DURATION}"

window_json=\$("\$SCRIPT_DIR/find-window.sh")
parse_window_bounds "\$window_json"
validate_coords "\$rel_x1" "\$rel_y1" "\$CONTENT_W" "\$CONTENT_H" || exit 1
validate_coords "\$rel_x2" "\$rel_y2" "\$CONTENT_W" "\$CONTENT_H" || exit 1
echo "Swiped"
SCRIPT
    chmod +x "$mock_dir/swipe_test.sh"

    run "$mock_dir/swipe_test.sh" 100 100 100 900
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of bounds"* ]]
}

@test "swipe: default duration is 300ms" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    cat > "$mock_dir/swipe_test.sh" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$mock_dir"
source "\$SCRIPT_DIR/helpers/common.sh"

if [[ \$# -lt 4 ]]; then
    echo "Usage: swipe.sh <x1> <y1> <x2> <y2> [duration_ms]" >&2
    exit 1
fi

rel_x1="\$1"; rel_y1="\$2"; rel_x2="\$3"; rel_y2="\$4"
duration_ms="\${5:-\$DEFAULT_SWIPE_DURATION}"

window_json=\$("\$SCRIPT_DIR/find-window.sh")
parse_window_bounds "\$window_json"
validate_coords "\$rel_x1" "\$rel_y1" "\$CONTENT_W" "\$CONTENT_H" || exit 1
validate_coords "\$rel_x2" "\$rel_y2" "\$CONTENT_W" "\$CONTENT_H" || exit 1
echo "Swiped (\$rel_x1,\$rel_y1) -> (\$rel_x2,\$rel_y2) in \${duration_ms}ms"
SCRIPT
    chmod +x "$mock_dir/swipe_test.sh"

    run "$mock_dir/swipe_test.sh" 100 100 200 200
    [ "$status" -eq 0 ]
    [[ "$output" == *"300ms"* ]]
}

@test "swipe: accepts custom duration" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    cat > "$mock_dir/swipe_test.sh" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$mock_dir"
source "\$SCRIPT_DIR/helpers/common.sh"

if [[ \$# -lt 4 ]]; then
    echo "Usage: swipe.sh <x1> <y1> <x2> <y2> [duration_ms]" >&2
    exit 1
fi

rel_x1="\$1"; rel_y1="\$2"; rel_x2="\$3"; rel_y2="\$4"
duration_ms="\${5:-\$DEFAULT_SWIPE_DURATION}"

window_json=\$("\$SCRIPT_DIR/find-window.sh")
parse_window_bounds "\$window_json"
validate_coords "\$rel_x1" "\$rel_y1" "\$CONTENT_W" "\$CONTENT_H" || exit 1
validate_coords "\$rel_x2" "\$rel_y2" "\$CONTENT_W" "\$CONTENT_H" || exit 1
echo "Swiped (\$rel_x1,\$rel_y1) -> (\$rel_x2,\$rel_y2) in \${duration_ms}ms"
SCRIPT
    chmod +x "$mock_dir/swipe_test.sh"

    run "$mock_dir/swipe_test.sh" 100 100 200 200 500
    [ "$status" -eq 0 ]
    [[ "$output" == *"500ms"* ]]
}
