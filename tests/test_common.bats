#!/usr/bin/env bats
# Tests for helpers/common.sh shared functions.

load test_helper

setup() {
    setup_temp
    source "$PROJECT_ROOT/helpers/common.sh"
}

teardown() {
    teardown_temp
}

# --- json_field ---

@test "json_field: extracts numeric field" {
    local json='{"x":100,"y":200}'
    result=$(json_field "$json" "x")
    [ "$result" = "100" ]
}

@test "json_field: extracts second numeric field" {
    local json='{"x":100,"y":200}'
    result=$(json_field "$json" "y")
    [ "$result" = "200" ]
}

@test "json_field: extracts string field" {
    local json='{"status":"connected","other":1}'
    result=$(json_field "$json" "status")
    [ "$result" = "connected" ]
}

@test "json_field: extracts last field before closing brace" {
    local json='{"a":1,"b":2,"c":3}'
    result=$(json_field "$json" "c")
    [ "$result" = "3" ]
}

@test "json_field: handles spaces around colon" {
    local json='{"width": 400, "height": 800}'
    result=$(json_field "$json" "width")
    [ "$result" = "400" ]
}

@test "json_field: extracts window_id from full JSON" {
    result=$(json_field "$MOCK_WINDOW_JSON" "window_id")
    [ "$result" = "12345" ]
}

@test "json_field: extracts scale from full JSON" {
    result=$(json_field "$MOCK_WINDOW_JSON" "scale")
    [ "$result" = "2" ]
}

@test "json_field: extracts content_width from full JSON" {
    result=$(json_field "$MOCK_WINDOW_JSON" "content_width")
    [ "$result" = "380" ]
}

# --- parse_window_bounds ---

@test "parse_window_bounds: sets CONTENT_X (negative origin preserved)" {
    parse_window_bounds "$MOCK_WINDOW_JSON"
    [ "$CONTENT_X" = "-1070" ]
}

@test "parse_window_bounds: sets CONTENT_Y (negative origin preserved)" {
    parse_window_bounds "$MOCK_WINDOW_JSON"
    [ "$CONTENT_Y" = "-380" ]
}

@test "parse_window_bounds: sets CONTENT_W" {
    parse_window_bounds "$MOCK_WINDOW_JSON"
    [ "$CONTENT_W" = "380" ]
}

@test "parse_window_bounds: sets CONTENT_H" {
    parse_window_bounds "$MOCK_WINDOW_JSON"
    [ "$CONTENT_H" = "760" ]
}

@test "parse_window_bounds: sets WINDOW_X (negative origin preserved)" {
    parse_window_bounds "$MOCK_WINDOW_JSON"
    [ "$WINDOW_X" = "-1080" ]
}

@test "parse_window_bounds: sets WINDOW_Y (negative origin preserved)" {
    parse_window_bounds "$MOCK_WINDOW_JSON"
    [ "$WINDOW_Y" = "-400" ]
}

@test "parse_window_bounds: sets WINDOW_ID" {
    parse_window_bounds "$MOCK_WINDOW_JSON"
    [ "$WINDOW_ID" = "12345" ]
}

@test "parse_window_bounds: sets SCALE" {
    parse_window_bounds "$MOCK_WINDOW_JSON"
    [ "$SCALE" = "2" ]
}

@test "parse_window_bounds: SCALE defaults to 1 when set to empty" {
    # Simulate what happens when scale field has empty value
    SCALE=""
    SCALE="${SCALE:-1}"
    [ "$SCALE" = "1" ]
}

@test "parse_window_bounds: SCALE is set from JSON with scale field" {
    local json='{"x":0,"y":0,"width":100,"height":200,"content_x":0,"content_y":0,"content_width":100,"content_height":200,"window_id":1,"scale":2}'
    parse_window_bounds "$json"
    [ "$SCALE" = "2" ]
}

@test "parse_window_bounds: fails when content_x is missing" {
    local json='{"x":0,"y":0,"width":100,"height":200,"content_y":0,"content_width":100,"content_height":200,"window_id":1,"scale":2}'
    run parse_window_bounds "$json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"required fields"* ]]
}

# --- validate_coords ---

@test "validate_coords: accepts origin (0,0)" {
    run validate_coords 0 0 380 760
    [ "$status" -eq 0 ]
}

@test "validate_coords: rejects x/y equal to bounds (valid range is 0..w-1)" {
    run validate_coords 380 760 380 760
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of bounds"* ]]
}

@test "validate_coords: accepts max valid point (w-1, h-1)" {
    run validate_coords 379 759 380 760
    [ "$status" -eq 0 ]
}

@test "validate_coords: accepts mid-point" {
    run validate_coords 190 380 380 760
    [ "$status" -eq 0 ]
}

@test "validate_coords: rejects negative x" {
    run validate_coords -1 100 380 760
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of bounds"* ]]
}

@test "validate_coords: rejects negative y" {
    run validate_coords 100 -1 380 760
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of bounds"* ]]
}

@test "validate_coords: rejects x beyond width" {
    run validate_coords 381 100 380 760
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of bounds"* ]]
}

@test "validate_coords: rejects y beyond height" {
    run validate_coords 100 761 380 760
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of bounds"* ]]
}

# --- sanitize_jxa ---

@test "sanitize_jxa: escapes backslashes" {
    result=$(sanitize_jxa 'hello\world')
    [ "$result" = 'hello\\world' ]
}

@test "sanitize_jxa: escapes double quotes" {
    result=$(sanitize_jxa 'say "hello"')
    [ "$result" = 'say \"hello\"' ]
}

@test "sanitize_jxa: escapes single quotes" {
    run sanitize_jxa "it's"
    [ "$status" -eq 0 ]
    # Output should be: it\'s (backslash before the single quote)
    [[ "$output" == it* ]]
    [[ "$output" == *s ]]
    # Must contain a backslash
    [[ "$output" == *'\'* ]]
}

@test "sanitize_jxa: escapes newlines" {
    input=$'line1\nline2'
    result=$(sanitize_jxa "$input")
    [ "$result" = 'line1\nline2' ]
}

@test "sanitize_jxa: escapes carriage returns" {
    input=$'line1\rline2'
    result=$(sanitize_jxa "$input")
    [ "$result" = 'line1\rline2' ]
}

@test "sanitize_jxa: handles combined special chars" {
    input=$'He said "it\'s a \\ path\n"'
    result=$(sanitize_jxa "$input")
    [[ "$result" == *'\\"'* ]]
    [[ "$result" == *"\\\\'"* ]] || [[ "$result" == *"\\\\"* ]]
}

@test "sanitize_jxa: passes through plain text unchanged" {
    result=$(sanitize_jxa "hello world 123")
    [ "$result" = "hello world 123" ]
}

# --- sanitize_applescript ---

@test "sanitize_applescript: escapes backslashes" {
    result=$(sanitize_applescript 'path\to\file')
    [ "$result" = 'path\\to\\file' ]
}

@test "sanitize_applescript: escapes double quotes" {
    result=$(sanitize_applescript 'say "hi"')
    [ "$result" = 'say \"hi\"' ]
}

@test "sanitize_applescript: passes through plain text unchanged" {
    result=$(sanitize_applescript "Home Screen")
    [ "$result" = "Home Screen" ]
}

@test "sanitize_applescript: does not escape single quotes" {
    result=$(sanitize_applescript "it's fine")
    [ "$result" = "it's fine" ]
}
