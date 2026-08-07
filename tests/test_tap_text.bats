#!/usr/bin/env bats
# Tests for tap-text.sh argument validation and matching logic (no phone required).

load test_helper

setup() {
    setup_temp
}

teardown() {
    teardown_temp
}

# Harness: mock find-window, screenshot, ocr-image, and tap so matching logic
# runs against a canned OCR fixture.
create_tap_text_harness() {
    local ocr_fixture="$1"
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    cp "$PROJECT_ROOT/tap-text.sh" "$mock_dir/tap-text.sh"
    chmod +x "$mock_dir/tap-text.sh"

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
${ocr_fixture}
FIXTURE
MOCK
    chmod +x "$mock_dir/helpers/ocr-image"

    cat > "$mock_dir/tap.sh" << 'MOCK'
#!/usr/bin/env bash
echo "Tapped at ($1, $2)"
MOCK
    chmod +x "$mock_dir/tap.sh"
    echo "$mock_dir"
}

@test "tap-text: rejects missing query" {
    run "$PROJECT_ROOT/tap-text.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "tap-text: rejects bad index" {
    run "$PROJECT_ROOT/tap-text.sh" "Foo" --index 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"--index"* ]]
}

@test "tap-text: exact match wins over substring, coords scaled by 2x" {
    local mock_dir
    # Battery at pixel (100,200) 80x40 -> center (140,220) -> points (70,110)
    mock_dir=$(create_tap_text_harness 'Battery Saver|10|10|50|20
Battery|100|200|80|40')
    run "$mock_dir/tap-text.sh" "battery"
    [ "$status" -eq 0 ]
    [[ "$output" == *'Matched "Battery" at (70, 110)'* ]]
    [[ "$output" == *"Tapped at (70, 110)"* ]]
}

@test "tap-text: substring match used when no exact match" {
    local mock_dir
    mock_dir=$(create_tap_text_harness 'Battery Saver|10|10|50|20')
    run "$mock_dir/tap-text.sh" "battery"
    [ "$status" -eq 0 ]
    [[ "$output" == *'Matched "Battery Saver"'* ]]
}

@test "tap-text: --index picks Nth match top-to-bottom" {
    local mock_dir
    mock_dir=$(create_tap_text_harness 'Wi-Fi|10|400|60|20
Wi-Fi|10|100|60|20')
    run "$mock_dir/tap-text.sh" "Wi-Fi" --index 2
    [ "$status" -eq 0 ]
    # Second from the top = the y=400 one -> center (40,410) -> points (20,205)
    [[ "$output" == *"(20, 205)"* ]]
}

@test "tap-text: --dry locates without tapping" {
    local mock_dir
    mock_dir=$(create_tap_text_harness 'Settings|100|200|80|40')
    run "$mock_dir/tap-text.sh" "Settings" --dry
    [ "$status" -eq 0 ]
    [[ "$output" == *'Matched "Settings"'* ]]
    [[ "$output" != *"Tapped"* ]]
}

@test "tap-text: no match lists what was seen and fails" {
    local mock_dir
    mock_dir=$(create_tap_text_harness 'Wallet|10|10|50|20')
    run "$mock_dir/tap-text.sh" "Nonexistent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no on-screen text matches"* ]]
    [[ "$output" == *"Wallet"* ]]
}
