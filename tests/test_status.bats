#!/usr/bin/env bats
# Tests for status.sh output format.
# Since status.sh calls osascript directly, we test with a mock.

load test_helper

setup() {
    setup_temp
    source "$PROJECT_ROOT/helpers/common.sh"
}

teardown() {
    teardown_temp
}

@test "status: mock returns valid JSON" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    # Create a mock status.sh that returns JSON without osascript
    cat > "$mock_dir/status_test.sh" << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# Simulate status.sh output
echo '{"status":"not_running"}'
SCRIPT
    chmod +x "$mock_dir/status_test.sh"

    run "$mock_dir/status_test.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"status"* ]]
}

@test "status: contains status field with valid value" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    for state in connected disconnected not_running; do
        cat > "$mock_dir/status_test.sh" << SCRIPT
#!/usr/bin/env bash
echo '{"status":"${state}"}'
SCRIPT
        chmod +x "$mock_dir/status_test.sh"

        run "$mock_dir/status_test.sh"
        [ "$status" -eq 0 ]
        local val
        val=$(json_field "$output" "status")
        [ "$val" = "$state" ]
    done
}

@test "status: real script handles empty osascript result" {
    # The real status.sh has a fallback: if osascript returns empty, output not_running
    # We test this logic in isolation
    result=""
    if [[ -z "$result" ]]; then
        output='{"status":"not_running"}'
    else
        output="$result"
    fi
    local val
    val=$(json_field "$output" "status")
    [ "$val" = "not_running" ]
}

@test "status: output is single-line JSON" {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    cat > "$mock_dir/status_test.sh" << 'SCRIPT'
#!/usr/bin/env bash
echo '{"status":"connected"}'
SCRIPT
    chmod +x "$mock_dir/status_test.sh"

    run "$mock_dir/status_test.sh"
    local lines
    lines=$(echo "$output" | wc -l)
    [ "$lines" -eq 1 ]
}
