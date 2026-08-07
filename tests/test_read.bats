#!/usr/bin/env bats
# Tests for read.sh OCR parsing, coordinate scaling and filters (no phone required).

load test_helper

setup() {
    setup_temp
}

teardown() {
    teardown_temp
}

# Harness: stub screenshot + ocr-image so the parsing/scaling logic runs against
# a canned OCR fixture. MOCK_WINDOW_JSON has scale=2, so pixel coords halve.
create_read_harness() {
    local fixture="$1"
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    cp "$PROJECT_ROOT/read.sh" "$mock_dir/read.sh"
    chmod +x "$mock_dir/read.sh"

    cat > "$mock_dir/screenshot.sh" << 'MOCK'
#!/usr/bin/env bash
[[ "$1" == "--native" ]] && shift
touch "${1:-/tmp/mock.png}"
echo "${1:-/tmp/mock.png}"
MOCK
    chmod +x "$mock_dir/screenshot.sh"

    cat > "$mock_dir/helpers/ocr-image" << MOCK
#!/usr/bin/env bash
cat << 'FIXTURE'
${fixture}
FIXTURE
MOCK
    chmod +x "$mock_dir/helpers/ocr-image"
    echo "$mock_dir"
}

@test "read: rejects unknown option" {
    run "$PROJECT_ROOT/read.sh" --frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "read: scales pixel coords to content points and centers them" {
    local mock_dir
    # box at pixel (100,200) 80x40 with scale 2 -> point (50,100) 40x20, center (70,110)
    mock_dir=$(create_read_harness 'Battery|100|200|80|40')
    run "$mock_dir/read.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"70,110"* ]]
    [[ "$output" == *"Battery"* ]]
}

@test "read: --grep filters case-insensitively" {
    local mock_dir
    mock_dir=$(create_read_harness 'Battery|10|10|40|20
Wallet|10|100|40|20')
    run "$mock_dir/read.sh" --grep "battery"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Battery"* ]]
    [[ "$output" != *"Wallet"* ]]
}

@test "read: --json emits parseable objects with cx/cy" {
    local mock_dir
    mock_dir=$(create_read_harness 'Settings|100|200|80|40')
    run "$mock_dir/read.sh" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"text":"Settings"'* ]]
    [[ "$output" == *'"cx":70'* ]]
    [[ "$output" == *'"cy":110'* ]]
    echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

@test "read: --at selects only text whose box contains the point" {
    local mock_dir
    # points: box1 = (5,5)-(25,15), box2 = (5,50)-(25,60)
    mock_dir=$(create_read_harness 'First|10|10|40|20
Second|10|100|40|20')
    run "$mock_dir/read.sh" --at 10 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"First"* ]]
    [[ "$output" != *"Second"* ]]
}

@test "read: OCR text containing a pipe is preserved" {
    local mock_dir
    mock_dir=$(create_read_harness 'a|b|10|10|40|20')
    run "$mock_dir/read.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"a|b"* ]]
}

@test "read: empty OCR output yields no rows and still succeeds" {
    local mock_dir
    mock_dir=$(create_read_harness '')
    run "$mock_dir/read.sh"
    [ "$status" -eq 0 ]
}
