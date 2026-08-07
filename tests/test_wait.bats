#!/usr/bin/env bats
# Tests for wait.sh argument handling (no phone required).

load test_helper

setup() {
    setup_temp
}

teardown() {
    teardown_temp
}

@test "wait: rejects missing mode" {
    run "$PROJECT_ROOT/wait.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "wait: rejects unknown mode" {
    run "$PROJECT_ROOT/wait.sh" frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"text, gone, or still"* ]]
}

@test "wait: text mode requires a string" {
    run "$PROJECT_ROOT/wait.sh" text
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "wait: gone mode requires a string" {
    run "$PROJECT_ROOT/wait.sh" gone
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "wait: rejects non-numeric timeout" {
    run "$PROJECT_ROOT/wait.sh" text "Foo" --timeout abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"--timeout must be a number"* ]]
}

@test "wait: rejects unknown option" {
    run "$PROJECT_ROOT/wait.sh" text "Foo" --frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "wait: still-mode tuning constants are defined and sane" {
    source "$PROJECT_ROOT/helpers/common.sh"
    # Mirroring is a video stream, so exact frame equality never happens:
    # the tolerance must be non-zero and confirmations must exceed one.
    [ -n "$WAIT_STILL_TOLERANCE" ]
    [ -n "$WAIT_STILL_SIZE" ]
    [ "$WAIT_STILL_CONFIRMATIONS" -ge 2 ]
    [ "$WAIT_DEFAULT_TIMEOUT" -gt 0 ]
}
