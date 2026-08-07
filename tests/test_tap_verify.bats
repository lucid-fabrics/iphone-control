#!/usr/bin/env bats
# Tests for tap-verify.sh argument validation (no phone required).

load test_helper

setup() {
    setup_temp
}

teardown() {
    teardown_temp
}

@test "tap-verify: rejects missing coordinates" {
    run "$PROJECT_ROOT/tap-verify.sh" 100
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "tap-verify: rejects unknown option" {
    run "$PROJECT_ROOT/tap-verify.sh" 100 100 --frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "tap-verify: rejects --expect without text" {
    run "$PROJECT_ROOT/tap-verify.sh" 100 100 --expect
    [ "$status" -eq 1 ]
    [[ "$output" == *"needs a text argument"* ]]
}

@test "tap-verify: rejects --gone without text" {
    run "$PROJECT_ROOT/tap-verify.sh" 100 100 --gone
    [ "$status" -eq 1 ]
    [[ "$output" == *"needs a text argument"* ]]
}

@test "tap-verify: rejects non-integer retries" {
    run "$PROJECT_ROOT/tap-verify.sh" 100 100 --retries abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"--retries"* ]]
}

@test "tap-verify: rejects non-numeric timeout" {
    run "$PROJECT_ROOT/tap-verify.sh" 100 100 --timeout abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"--timeout"* ]]
}
