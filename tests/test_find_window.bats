#!/usr/bin/env bats
# Tests for find-window.sh output format.
# These tests use mocked helpers to avoid requiring iPhone Mirroring.

load test_helper

setup() {
    setup_temp
    source "$PROJECT_ROOT/helpers/common.sh"
}

teardown() {
    teardown_temp
}

@test "find-window: mock returns valid JSON with all expected fields" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    run "$mock_dir/find-window.sh"
    [ "$status" -eq 0 ]

    # Parse and verify all expected fields exist
    local json="$output"
    [ "$(json_field "$json" "x")" != "" ]
    [ "$(json_field "$json" "y")" != "" ]
    [ "$(json_field "$json" "width")" != "" ]
    [ "$(json_field "$json" "height")" != "" ]
    [ "$(json_field "$json" "content_x")" != "" ]
    [ "$(json_field "$json" "content_y")" != "" ]
    [ "$(json_field "$json" "content_width")" != "" ]
    [ "$(json_field "$json" "content_height")" != "" ]
    [ "$(json_field "$json" "window_id")" != "" ]
    [ "$(json_field "$json" "scale")" != "" ]
}

@test "find-window: JSON contains numeric x field (negative allowed on secondary displays)" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    run "$mock_dir/find-window.sh"
    local val
    val=$(json_field "$output" "x")
    [[ "$val" =~ ^-?[0-9]+$ ]]
}

@test "find-window: JSON contains numeric content_width" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    run "$mock_dir/find-window.sh"
    local val
    val=$(json_field "$output" "content_width")
    [[ "$val" =~ ^[0-9]+$ ]]
}

@test "find-window: JSON contains numeric window_id" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    run "$mock_dir/find-window.sh"
    local val
    val=$(json_field "$output" "window_id")
    [[ "$val" =~ ^[0-9]+$ ]]
}

@test "find-window: JSON contains numeric scale" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    run "$mock_dir/find-window.sh"
    local val
    val=$(json_field "$output" "scale")
    [[ "$val" =~ ^[0-9]+$ ]]
}

@test "find-window: exits with error when iPhone Mirroring not running" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    create_failing_find_window "$mock_dir"
    run "$mock_dir/find-window.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"error"* ]]
}

@test "find-window: content bounds are within window bounds" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    run "$mock_dir/find-window.sh"
    local json="$output"

    local wx wy ww wh cx cy cw ch
    wx=$(json_field "$json" "x")
    wy=$(json_field "$json" "y")
    ww=$(json_field "$json" "width")
    wh=$(json_field "$json" "height")
    cx=$(json_field "$json" "content_x")
    cy=$(json_field "$json" "content_y")
    cw=$(json_field "$json" "content_width")
    ch=$(json_field "$json" "content_height")

    # Content origin >= window origin
    [ "$cx" -ge "$wx" ]
    [ "$cy" -ge "$wy" ]
    # Content fits within window
    [ "$(( cx + cw ))" -le "$(( wx + ww ))" ]
    [ "$(( cy + ch ))" -le "$(( wy + wh ))" ]
}
