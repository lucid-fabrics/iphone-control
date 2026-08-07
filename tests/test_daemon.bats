#!/usr/bin/env bats
# Tests that the input daemon survives bad commands instead of exiting.
# These need the compiled engine but NOT iPhone Mirroring: every command here
# fails validation before it would touch the phone, which is the whole point -
# a recoverable error must come back as ERR with the daemon still alive.

load test_helper

ENGINE="$PROJECT_ROOT/helpers/input"
SOCK="/tmp/iphone-control-daemon.sock"

setup() {
    [ -x "$ENGINE" ] || skip "native engine not built"
}

teardown() {
    pkill -f "helpers/input serve" 2>/dev/null || true
    rm -f "$SOCK"
}

daemon_pid() {
    pgrep -f "helpers/input serve" | head -1
}

@test "daemon: socket is owner-only (0600)" {
    pkill -f "helpers/input serve" 2>/dev/null || true
    rm -f "$SOCK"
    run "$ENGINE" send ping
    [ "$status" -eq 0 ]
    [[ "$output" == *"pong"* ]]
    # bind + chmod: no other user may connect and drive the phone
    local perms
    perms=$(stat -f '%Sp' "$SOCK")
    [ "$perms" = "srw-------" ]
}

@test "daemon: survives a coordinate validation error" {
    # With Mirroring open this errors "out of bounds"; on a headless CI runner
    # it errors "window not found". Both are recoverable, so assert the daemon
    # LIVES rather than the specific message - keeps the test environment-neutral.
    "$ENGINE" send ping > /dev/null
    local before after
    before=$(daemon_pid)
    [ -n "$before" ]
    run "$ENGINE" send tap 99999 99999
    [ "$status" -ne 0 ]
    after=$(daemon_pid)
    [ "$before" = "$after" ]
}

@test "daemon: survives a non-numeric argument" {
    "$ENGINE" send ping > /dev/null
    local before after
    before=$(daemon_pid)
    run "$ENGINE" send tap abc def
    [ "$status" -ne 0 ]
    after=$(daemon_pid)
    [ "$before" = "$after" ]
}

@test "daemon: survives an unknown verb" {
    "$ENGINE" send ping > /dev/null
    local before after
    before=$(daemon_pid)
    run "$ENGINE" send frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown verb"* ]]
    after=$(daemon_pid)
    [ "$before" = "$after" ]
}

@test "daemon: still answers after a burst of bad commands" {
    "$ENGINE" send ping > /dev/null
    local before after
    before=$(daemon_pid)
    "$ENGINE" send tap 99999 99999 || true
    "$ENGINE" send tap abc def || true
    "$ENGINE" send frobnicate || true
    run "$ENGINE" send ping
    [ "$status" -eq 0 ]
    [[ "$output" == *"pong"* ]]
    after=$(daemon_pid)
    [ "$before" = "$after" ]
}
