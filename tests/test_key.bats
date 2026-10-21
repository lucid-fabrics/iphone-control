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

# --- Keypad-first resolution (parity with iphone-control.sh on main) ---
# The live-verified calculator baseline types digits and operators through the
# number pad: keypad keys give the same character on every phone layout, with no
# modifier. INPUT_LAYOUT_ID selects an installed layout for the query only; system
# settings are not touched. The engine is compiled from source into a temp dir so
# these tests never skip on a fresh clone and never use a stale binary.

build_engine() {
    ENGINE_UNDER_TEST="${ENGINE_SRC_DIR:-$PROJECT_ROOT/helpers/input-src}"
    ENGINE_BIN="$BATS_FILE_TMPDIR/input-$(basename "$(dirname "$ENGINE_UNDER_TEST")")"
    [ -x "$ENGINE_BIN" ] || swiftc -O "$ENGINE_UNDER_TEST"/*.swift -o "$ENGINE_BIN" 2>/dev/null
    [ -x "$ENGINE_BIN" ]
}

@test "native keyfor: + and * resolve to the keypad with no modifier (US layout)" {
    build_engine
    export INPUT_LAYOUT_ID="com.apple.keylayout.US"
    run "$ENGINE_BIN" keyfor "+"
    [ "$status" -eq 0 ]
    [ "$output" = "69 0" ]
    run "$ENGINE_BIN" keyfor "*"
    [ "$status" -eq 0 ]
    [ "$output" = "67 0" ]
}

@test "native keyfor: + and * on the current layout never need Shift on the keypad" {
    build_engine
    unset INPUT_LAYOUT_ID
    run "$ENGINE_BIN" keyfor "+"
    [ "$status" -eq 0 ]
    [ "$output" = "69 0" ]
    run "$ENGINE_BIN" keyfor "*"
    [ "$status" -eq 0 ]
    [ "$output" = "67 0" ]
}

@test "native keyfor: French layout digits resolve with no modifiers" {
    build_engine
    export INPUT_LAYOUT_ID="com.apple.keylayout.French"
    local d out
    for d in 0 1 2 3 4 5 6 7 8 9; do
        out=$("$ENGINE_BIN" keyfor "$d") || { echo "keyfor $d failed"; false; }
        [ "${out##* }" = "0" ] || { echo "digit $d needs a modifier: $out"; false; }
    done
}

@test "native keyfor: an unknown INPUT_LAYOUT_ID falls back to the active layout" {
    build_engine
    unset INPUT_LAYOUT_ID
    local expected
    expected=$("$ENGINE_BIN" keyfor "a")
    export INPUT_LAYOUT_ID="com.example.no-such-layout"
    run "$ENGINE_BIN" keyfor "a"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}

@test "view shortcut: companion ViewShortcut and the engine agree on Cmd+1/2/3" {
    build_engine
    local probe="$BATS_FILE_TMPDIR/viewshortcut"
    cat > "$BATS_FILE_TMPDIR/stub.swift" <<'SWIFT'
import CoreGraphics
import Foundation
enum Constants { static let keystrokeDelay: TimeInterval = 0 }
SWIFT
    cat > "$BATS_FILE_TMPDIR/main.swift" <<'SWIFT'
import CoreGraphics
for n in 1...3 {
    let k = ViewShortcut(rawValue: n)!.keyStroke()
    print(n, k.code, k.flags.contains(.maskShift) ? 1 : 0)
}
SWIFT
    swiftc "$PROJECT_ROOT/companion/iPhoneCompanion/Utilities/ViewShortcut.swift" \
        "$BATS_FILE_TMPDIR/stub.swift" "$BATS_FILE_TMPDIR/main.swift" -o "$probe" 2>/dev/null \
        || skip "cannot compile ViewShortcut"
    # ViewShortcut has no layout override hook, so compare on the active layout.
    local n code shift out ecode eflags
    while read -r n code shift; do
        out=$(INPUT_LAYOUT_ID="" "$ENGINE_BIN" keyfor "$n")
        ecode="${out%% *}"; eflags="${out##* }"
        [ "$code" = "$ecode" ] || { echo "Cmd+$n: companion $code vs engine $ecode"; false; }
        [ "$shift" = "$(( (eflags & 131072) ? 1 : 0 ))" ] || { echo "Cmd+$n shift mismatch"; false; }
    done < <("$probe")
}

@test "view_shortcut_body follows the engine keyfor result" {
    build_engine
    local out
    out=$(INPUT_LAYOUT_ID="" "$ENGINE_BIN" keyfor 1)
    local code="${out%% *}"
    run bash -c 'SCRIPT_DIR="$1"; source "$1/helpers/common.sh"; view_shortcut_body 1' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CGEventCreateKeyboardEvent(kSrc, ${code}"* ]]
}
