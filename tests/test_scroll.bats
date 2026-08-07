#!/usr/bin/env bats
# Tests for scroll.sh argument validation (no phone required).

load test_helper

setup() {
    setup_temp
}

teardown() {
    teardown_temp
}

create_scroll_harness() {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    cat >> "$mock_dir/helpers/common.sh" << 'STUB'
jxa_activate_and_run() { printf '%s' "$1"; }
STUB
    cp "$PROJECT_ROOT/scroll.sh" "$mock_dir/scroll.sh"
    chmod +x "$mock_dir/scroll.sh"
    echo "$mock_dir"
}

@test "scroll: rejects missing dy" {
    run "$PROJECT_ROOT/scroll.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "scroll: rejects zero dy" {
    local mock_dir
    mock_dir=$(create_scroll_harness)
    run "$mock_dir/scroll.sh" 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"non-zero"* ]]
}

@test "scroll: rejects non-integer dy" {
    local mock_dir
    mock_dir=$(create_scroll_harness)
    run "$mock_dir/scroll.sh" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"non-zero integer"* ]]
}

@test "scroll: accepts positive dy with default position" {
    local mock_dir
    mock_dir=$(create_scroll_harness)
    run "$mock_dir/scroll.sh" 300
    [ "$status" -eq 0 ]
    [[ "$output" == *"Scrolled dy=300"* ]]
}

@test "scroll: accepts negative dy with explicit position" {
    local mock_dir
    mock_dir=$(create_scroll_harness)
    run "$mock_dir/scroll.sh" -200 100 400
    [ "$status" -eq 0 ]
    [[ "$output" == *"Scrolled dy=-200 at (100, 400)"* ]]
}

@test "scroll: rejects out-of-bounds position" {
    local mock_dir
    mock_dir=$(create_scroll_harness)
    run "$mock_dir/scroll.sh" 300 500 100
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of bounds"* ]]
}
