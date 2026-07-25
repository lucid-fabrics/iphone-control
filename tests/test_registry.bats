#!/usr/bin/env bats
# Tests for registry.sh command routing and error handling.

load test_helper

setup() {
    setup_temp
    # Override HOME so registry operations don't touch real files
    export REAL_HOME="$HOME"
    export HOME="$TEST_TEMP_DIR"
}

teardown() {
    export HOME="$REAL_HOME"
    teardown_temp
}

@test "registry: help command works" {
    run "$PROJECT_ROOT/registry.sh" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"App Registry Manager"* ]]
    [[ "$output" == *"scan"* ]]
    [[ "$output" == *"lookup"* ]]
    [[ "$output" == *"invalidate"* ]]
    [[ "$output" == *"list"* ]]
}

@test "registry: --help flag works" {
    run "$PROJECT_ROOT/registry.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"App Registry Manager"* ]]
}

@test "registry: unknown command exits with error" {
    run "$PROJECT_ROOT/registry.sh" foobar
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}

@test "registry: lookup fails gracefully when no registry exists" {
    run "$PROJECT_ROOT/registry.sh" lookup "Safari"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No registry found"* ]]
}

@test "registry: lookup requires app name argument" {
    run "$PROJECT_ROOT/registry.sh" lookup
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"error"* ]]
}

@test "registry: invalidate works on non-existent file" {
    run "$PROJECT_ROOT/registry.sh" invalidate
    [ "$status" -eq 0 ]
    [[ "$output" == *"No registry to invalidate"* ]]
}

@test "registry: invalidate removes existing registry" {
    # Create a fake registry
    mkdir -p "$HOME/.iphone-control"
    echo '{"version":1}' > "$HOME/.iphone-control/app-registry.json"
    [ -f "$HOME/.iphone-control/app-registry.json" ]

    run "$PROJECT_ROOT/registry.sh" invalidate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Registry invalidated"* ]]
    [ ! -f "$HOME/.iphone-control/app-registry.json" ]
}

@test "registry: lookup rejects stale v1 registry (pixel-space coords)" {
    mkdir -p "$HOME/.iphone-control"
    echo '{"version":1,"content_width":380,"content_height":760,"apps":[{"name":"Safari","page":1,"x":50,"y":100}]}' > "$HOME/.iphone-control/app-registry.json"

    run "$PROJECT_ROOT/registry.sh" lookup "Safari"
    [ "$status" -eq 1 ]
    [[ "$output" == *"lookup failed"* ]]
}

@test "registry: lookup finds app in v2 registry" {
    mkdir -p "$HOME/.iphone-control"
    echo '{"version":2,"content_width":380,"content_height":760,"apps":[{"name":"Safari","page":1,"x":50,"y":100}]}' > "$HOME/.iphone-control/app-registry.json"

    run "$PROJECT_ROOT/registry.sh" lookup "Safari"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"name":"Safari"'* ]]
    [[ "$output" == *'"x":50'* ]]
}

@test "registry: list fails gracefully when no registry exists" {
    run "$PROJECT_ROOT/registry.sh" list
    [ "$status" -eq 1 ]
    [[ "$output" == *"No registry found"* ]]
}

@test "registry: list outputs registry contents when file exists" {
    mkdir -p "$HOME/.iphone-control"
    local registry='{"version":1,"apps":[{"name":"Safari","page":1,"x":50,"y":100}]}'
    echo "$registry" > "$HOME/.iphone-control/app-registry.json"

    run "$PROJECT_ROOT/registry.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Safari"* ]]
    [[ "$output" == *"version"* ]]
}
