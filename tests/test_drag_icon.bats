#!/usr/bin/env bats
# Tests for drag-icon.sh argument validation (no phone required).

load test_helper

setup() {
    setup_temp
}

teardown() {
    teardown_temp
}

create_drag_harness() {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    cat >> "$mock_dir/helpers/common.sh" << 'STUB'
jxa_activate_and_run() { printf '%s' "$1"; }
STUB
    cp "$PROJECT_ROOT/drag-icon.sh" "$mock_dir/drag-icon.sh"
    chmod +x "$mock_dir/drag-icon.sh"
    # Stub tap-text (Done tap) so the harness never OCRs
    cat > "$mock_dir/tap-text.sh" << 'MOCK'
#!/usr/bin/env bash
echo "Matched \"Done\" at (0, 0)"
MOCK
    chmod +x "$mock_dir/tap-text.sh"
    echo "$mock_dir"
}

@test "drag-icon: rejects missing arguments" {
    run "$PROJECT_ROOT/drag-icon.sh" 10 10
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "drag-icon: rejects bad hover value" {
    local mock_dir
    mock_dir=$(create_drag_harness)
    run "$mock_dir/drag-icon.sh" 10 10 100 100 --hover abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"--hover"* ]]
}

@test "drag-icon: rejects unknown option" {
    local mock_dir
    mock_dir=$(create_drag_harness)
    run "$mock_dir/drag-icon.sh" 10 10 100 100 --frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "drag-icon: rejects out-of-bounds source" {
    local mock_dir
    mock_dir=$(create_drag_harness)
    run "$mock_dir/drag-icon.sh" 500 10 100 100
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of bounds"* ]]
}

@test "drag-icon: accepts valid drag with keep-jiggle" {
    local mock_dir
    mock_dir=$(create_drag_harness)
    run "$mock_dir/drag-icon.sh" 10 10 100 100 --keep-jiggle
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dragged icon (10,10) -> (100,100)"* ]]
}

@test "drag-icon: jiggle entry uses wallpaper margin, not the icon" {
    local mock_dir
    mock_dir=$(create_drag_harness)
    # Body is echoed by the stub; the first press must NOT be at the icon's abs coords.
    # Icon (100,100) -> abs (-970,-280) with the mock window; margin press is at x=-1064.
    run "$mock_dir/drag-icon.sh" 100 100 200 200 --keep-jiggle
    [ "$status" -eq 0 ]
    [[ "$output" == *"x: -1064"* ]]
}
