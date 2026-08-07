#!/usr/bin/env bats
# Tests for key.sh and the keycode_for lookup (no phone required).

load test_helper

setup() {
    setup_temp
}

teardown() {
    teardown_temp
}

create_key_harness() {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    cat >> "$mock_dir/helpers/common.sh" << 'STUB'
jxa_activate_and_run() { printf '%s' "$1"; }
STUB
    cp "$PROJECT_ROOT/key.sh" "$mock_dir/key.sh"
    chmod +x "$mock_dir/key.sh"
    echo "$mock_dir"
}

@test "key: rejects missing argument" {
    run "$PROJECT_ROOT/key.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "key: rejects unknown key name" {
    local mock_dir
    mock_dir=$(create_key_harness)
    run "$mock_dir/key.sh" "notakey"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown key"* ]]
}

@test "key: rejects unknown modifier flag" {
    local mock_dir
    mock_dir=$(create_key_harness)
    run "$mock_dir/key.sh" a --frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "key: named keys resolve to correct keycodes" {
    source "$PROJECT_ROOT/helpers/common.sh"
    [ "$(keycode_for return)" -eq 36 ]
    [ "$(keycode_for escape)" -eq 53 ]
    [ "$(keycode_for delete)" -eq 51 ]
    [ "$(keycode_for space)" -eq 49 ]
    [ "$(keycode_for tab)" -eq 48 ]
    [ "$(keycode_for up)" -eq 126 ]
    [ "$(keycode_for down)" -eq 125 ]
}

@test "key: letters and digits resolve, case-insensitively" {
    source "$PROJECT_ROOT/helpers/common.sh"
    [ "$(keycode_for a)" -eq 0 ]
    [ "$(keycode_for A)" -eq 0 ]
    [ "$(keycode_for c)" -eq 8 ]
    [ "$(keycode_for v)" -eq 9 ]
    [ "$(keycode_for 1)" -eq 18 ]
    [ "$(keycode_for 3)" -eq 20 ]
}

@test "key: keycode_for fails on unknown input" {
    source "$PROJECT_ROOT/helpers/common.sh"
    run keycode_for "nope"
    [ "$status" -ne 0 ]
}

@test "key: single key emits a body with no modifier flags" {
    local mock_dir
    mock_dir=$(create_key_harness)
    run "$mock_dir/key.sh" return
    [ "$status" -eq 0 ]
    [[ "$output" == *"CGEventCreateKeyboardEvent"* ]]
    [[ "$output" == *"Key: return"* ]]
}

@test "key: cmd modifier is applied" {
    local mock_dir
    mock_dir=$(create_key_harness)
    run "$mock_dir/key.sh" c --cmd
    [ "$status" -eq 0 ]
    [[ "$output" == *"kCGEventFlagMaskCommand"* ]]
    [[ "$output" == *"Key: cmd+c"* ]]
}

@test "key: multiple modifiers are combined" {
    local mock_dir
    mock_dir=$(create_key_harness)
    run "$mock_dir/key.sh" a --cmd --shift
    [ "$status" -eq 0 ]
    [[ "$output" == *"kCGEventFlagMaskCommand"* ]]
    [[ "$output" == *"kCGEventFlagMaskShift"* ]]
}

# --- Native layout resolution (real compiled engine, not the mock harness) ---
# These fix non-US keyboard layouts: keycode_for is a fixed US-QWERTY position
# table, wrong on AZERTY/QWERTZ/etc. keyfor asks the ACTUAL active layout via
# UCKeyTranslate, so it is correct on any layout by construction. It is a pure
# macOS API query - no phone interaction, no window resolution.

@test "native keyfor: resolves a lowercase letter with no modifier" {
    local engine="$PROJECT_ROOT/helpers/input"
    [ -x "$engine" ] || skip "native engine not built"
    run "$engine" keyfor a
    [ "$status" -eq 0 ]
    read -r code flags <<< "$output"
    [[ "$code" =~ ^[0-9]+$ ]]
    [ "$flags" -eq 0 ]
}

@test "native keyfor: uppercase requires a modifier on any layout" {
    local engine="$PROJECT_ROOT/helpers/input"
    [ -x "$engine" ] || skip "native engine not built"
    run "$engine" keyfor A
    [ "$status" -eq 0 ]
    read -r code flags <<< "$output"
    [ "$flags" -ne 0 ]
}

@test "native keyfor: rejects multi-character input" {
    local engine="$PROJECT_ROOT/helpers/input"
    [ -x "$engine" ] || skip "native engine not built"
    run "$engine" keyfor ab
    [ "$status" -eq 1 ]
}

@test "native keyfor: works without iPhone Mirroring (pure layout query)" {
    local engine="$PROJECT_ROOT/helpers/input"
    [ -x "$engine" ] || skip "native engine not built"
    run "$engine" keyfor z
    [ "$status" -eq 0 ]
    [[ "$output" != *"window"* ]]
}

@test "key.sh: end-to-end uses the native engine when available" {
    local engine="$PROJECT_ROOT/helpers/input"
    [ -x "$engine" ] || skip "native engine not built"
    local mock_dir
    mock_dir=$(create_key_harness)
    # Point the mock at the real compiled engine: symlink sources so
    # input_engine() finds them, copy the binary, and backdate its mtime so
    # the staleness check does not force a recompile.
    ln -s "$PROJECT_ROOT/helpers/input-src" "$mock_dir/helpers/input-src"
    cp "$PROJECT_ROOT/helpers/input" "$mock_dir/helpers/input"
    touch -t 203001010000 "$mock_dir/helpers/input"

    expected=$("$engine" keyfor A)
    exp_code="${expected%% *}"

    run "$mock_dir/key.sh" A --cmd
    [ "$status" -eq 0 ]
    [[ "$output" == *"CGEventCreateKeyboardEvent(kSrc, ${exp_code}"* ]]
    [[ "$output" == *"kCGEventFlagMaskCommand"* ]]
}
