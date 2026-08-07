#!/usr/bin/env bats
# Tests for batch.sh argument validation (no phone required).

load test_helper

setup() {
    setup_temp
}

teardown() {
    teardown_temp
}

# Build a batch harness that parses actions with the real common.sh + mock window,
# but stubs out jxa_activate_and_run so no events are posted.
create_batch_harness() {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    # Stub the JXA runner: print the body instead of executing it
    cat >> "$mock_dir/helpers/common.sh" << 'STUB'
jxa_activate_and_run() { printf '%s' "$1"; }
STUB
    cp "$PROJECT_ROOT/batch.sh" "$mock_dir/batch.sh"
    chmod +x "$mock_dir/batch.sh"
    echo "$mock_dir"
}

@test "batch: rejects no actions" {
    local mock_dir
    mock_dir=$(create_batch_harness)
    run "$mock_dir/batch.sh" < /dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "batch: rejects unknown action" {
    local mock_dir
    mock_dir=$(create_batch_harness)
    run "$mock_dir/batch.sh" "frobnicate 1 2"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown batch action"* ]]
}

@test "batch: rejects tap with wrong arity" {
    local mock_dir
    mock_dir=$(create_batch_harness)
    run "$mock_dir/batch.sh" "tap 100"
    [ "$status" -eq 1 ]
    [[ "$output" == *"tap needs"* ]]
}

@test "batch: rejects out-of-bounds tap" {
    local mock_dir
    mock_dir=$(create_batch_harness)
    run "$mock_dir/batch.sh" "tap 500 100"
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of bounds"* ]]
}

@test "batch: rejects bad swipe duration" {
    local mock_dir
    mock_dir=$(create_batch_harness)
    run "$mock_dir/batch.sh" "swipe 10 10 100 100 abc"
    [ "$status" -eq 1 ]
    [[ "$output" == *"duration_ms"* ]]
}

@test "batch: rejects bad sleep value" {
    local mock_dir
    mock_dir=$(create_batch_harness)
    run "$mock_dir/batch.sh" "sleep abc"
    [ "$status" -eq 1 ]
    [[ "$output" == *"sleep needs"* ]]
}

@test "batch: accepts valid tap+swipe+scroll+sleep mix" {
    local mock_dir
    mock_dir=$(create_batch_harness)
    run "$mock_dir/batch.sh" "tap 100 100" "swipe 10 10 100 100" "scroll 200" "sleep 0.5"
    [ "$status" -eq 0 ]
    [[ "$output" == *"4 action(s) done"* ]]
}

@test "batch: reads actions from stdin" {
    local mock_dir
    mock_dir=$(create_batch_harness)
    run bash -c "printf 'tap 100 100\n# comment\n\ntap 50 50\n' | '$mock_dir/batch.sh'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 action(s) done"* ]]
}
