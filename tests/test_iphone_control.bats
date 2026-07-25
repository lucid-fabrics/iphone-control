#!/usr/bin/env bats
# Tests for iphone-control.sh main entry point.

load test_helper

setup() {
    setup_temp
}

teardown() {
    teardown_temp
}

@test "iphone-control: help command outputs usage" {
    run "$PROJECT_ROOT/iphone-control.sh" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"iPhone Mirroring Control"* ]]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"Commands"* ]]
}

@test "iphone-control: --help flag works" {
    run "$PROJECT_ROOT/iphone-control.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"iPhone Mirroring Control"* ]]
}

@test "iphone-control: -h flag works" {
    run "$PROJECT_ROOT/iphone-control.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"iPhone Mirroring Control"* ]]
}

@test "iphone-control: no args shows help" {
    run "$PROJECT_ROOT/iphone-control.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"iPhone Mirroring Control"* ]]
}

@test "iphone-control: unknown command exits with error" {
    run "$PROJECT_ROOT/iphone-control.sh" nonexistent-cmd
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}

@test "iphone-control: unknown command suggests help" {
    run "$PROJECT_ROOT/iphone-control.sh" badcmd
    [ "$status" -eq 1 ]
    [[ "$output" == *"help"* ]]
}

@test "iphone-control: help lists all expected commands" {
    run "$PROJECT_ROOT/iphone-control.sh" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"find"* ]]
    [[ "$output" == *"screenshot"* ]]
    [[ "$output" == *"tap"* ]]
    [[ "$output" == *"swipe"* ]]
    [[ "$output" == *"type"* ]]
    [[ "$output" == *"home"* ]]
    [[ "$output" == *"app-switcher"* ]]
    [[ "$output" == *"spotlight"* ]]
    [[ "$output" == *"open-app"* ]]
    [[ "$output" == *"status"* ]]
    [[ "$output" == *"registry-scan"* ]]
    [[ "$output" == *"registry-lookup"* ]]
    [[ "$output" == *"registry-invalidate"* ]]
    [[ "$output" == *"registry-list"* ]]
}

@test "iphone-control: tap without coords shows usage error" {
    # tap.sh should fail with usage message when called without args
    run "$PROJECT_ROOT/iphone-control.sh" tap
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "iphone-control: swipe without coords shows usage error" {
    run "$PROJECT_ROOT/iphone-control.sh" swipe
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "iphone-control: type without text shows usage error" {
    run "$PROJECT_ROOT/iphone-control.sh" type
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "iphone-control: routes registry-list to registry.sh" {
    # Override HOME to avoid finding a real registry
    export HOME="$TEST_TEMP_DIR"
    run "$PROJECT_ROOT/iphone-control.sh" registry-list
    # Should fail gracefully (no registry file in temp HOME)
    [ "$status" -eq 1 ]
    [[ "$output" == *"No registry found"* ]]
}

@test "iphone-control: routes registry-invalidate to registry.sh" {
    export HOME="$TEST_TEMP_DIR"
    run "$PROJECT_ROOT/iphone-control.sh" registry-invalidate
    [ "$status" -eq 0 ]
    [[ "$output" == *"No registry to invalidate"* ]]
}
