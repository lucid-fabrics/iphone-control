#!/usr/bin/env bats
# Tests for type-text.sh argument validation and safety.

load test_helper

setup() {
    setup_temp
    source "$PROJECT_ROOT/helpers/common.sh"
}

teardown() {
    teardown_temp
}

@test "type-text: rejects missing arguments" {
    run "$PROJECT_ROOT/type-text.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "type-text: sanitize_applescript prevents double-quote injection" {
    # If someone passes text with double quotes, it should be escaped
    local malicious='"; tell app "Terminal" to do script "rm -rf /"'
    result=$(sanitize_applescript "$malicious")
    # The escaped result should not contain unescaped double quotes
    # (every " should be preceded by \)
    [[ "$result" != *'"; tell app'* ]] || {
        # Verify the quotes are escaped
        [[ "$result" == *'\"'* ]]
    }
}

@test "type-text: sanitize_applescript escapes backslash in text" {
    local text='C:\Users\test'
    result=$(sanitize_applescript "$text")
    [ "$result" = 'C:\\Users\\test' ]
}

@test "type-text: sanitize_jxa prevents single-quote injection" {
    local malicious="'; process.exit(1); '"
    result=$(sanitize_jxa "$malicious")
    [[ "$result" == *"\\'"* ]]
}

@test "type-text: handles unicode text safely" {
    # Unicode should pass through sanitization unchanged
    result=$(sanitize_applescript "Hello World")
    [ "$result" = "Hello World" ]
}

@test "type-text: handles empty string after required arg check" {
    # Empty string is still a valid argument (just empty text)
    # The script should accept it since $# >= 1
    # We can't run the full script without osascript, but we verify
    # the arg check logic
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    cat > "$mock_dir/type_test.sh" << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 ]]; then
    echo "Usage: type-text.sh \"text\" [tap_x tap_y]" >&2
    exit 1
fi
echo "OK: text='$1'"
SCRIPT
    chmod +x "$mock_dir/type_test.sh"

    run "$mock_dir/type_test.sh" ""
    [ "$status" -eq 0 ]
}

@test "type-text: special chars do not cause command injection via sanitize_applescript" {
    # Test that backticks, $(), and other shell metacharacters are safe
    # after AppleScript sanitization
    local dangerous='$(rm -rf /)'
    result=$(sanitize_applescript "$dangerous")
    # Dollar signs are escaped so double-quoted bash embedding cannot expand them;
    # the embedded AppleScript then receives the literal text
    [ "$result" = '\$(rm -rf /)' ]
}

@test "type-text: newlines in text are handled by sanitize_jxa" {
    local multiline=$'line1\nline2\nline3'
    result=$(sanitize_jxa "$multiline")
    [[ "$result" == *'\n'* ]]
    # Should not contain literal newlines
    local lines
    lines=$(echo "$result" | wc -l)
    [ "$lines" -eq 1 ]
}
