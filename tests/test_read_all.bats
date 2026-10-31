#!/usr/bin/env bats
# Tests for read-all.sh and the page stitcher (no phone required).

load test_helper

FIXTURES="$PROJECT_ROOT/tests/fixtures/read-all"

setup_file() {
    swiftc -O "$PROJECT_ROOT/helpers/stitch-pages.swift" -o "$BATS_FILE_TMPDIR/stitch-pages"
}

setup() {
    setup_temp
    STITCH="$BATS_FILE_TMPDIR/stitch-pages"
}

teardown() {
    teardown_temp
}

# Settings-like list: page1 scrolled 300pt, page2 a partial 150pt to the bottom.
three_pages() {
    cat "$FIXTURES/page0.json" "$FIXTURES/page1.json" "$FIXTURES/page2.json"
}

# Harness: a fake phone whose scroll position indexes into the fixture pages.
# scroll.sh moves one page per call (clamped at both ends) and logs every dy;
# read.sh prints the page at the current position.
create_read_all_harness() {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)
    cp "$PROJECT_ROOT/read-all.sh" "$mock_dir/read-all.sh"
    chmod +x "$mock_dir/read-all.sh"
    cp "$PROJECT_ROOT/helpers/stitch-pages.swift" "$mock_dir/helpers/"
    cp "$BATS_FILE_TMPDIR/stitch-pages" "$mock_dir/helpers/stitch-pages"
    touch "$mock_dir/helpers/stitch-pages"
    cp "$FIXTURES"/page*.json "$mock_dir/"
    echo "${START_POS:-0}" > "$mock_dir/pos"

    cat > "$mock_dir/scroll.sh" << 'MOCK'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
echo "$1" >> "$dir/scroll.log"
pos=$(cat "$dir/pos")
if (( $1 > 0 )); then pos=$(( pos + 1 )); else pos=$(( pos - 1 )); fi
(( pos < 0 )) && pos=0
(( pos > 2 )) && pos=2
echo "$pos" > "$dir/pos"
MOCK
    cat > "$mock_dir/read.sh" << 'MOCK'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
cat "$dir/page$(cat "$dir/pos").json"
MOCK
    cat > "$mock_dir/wait.sh" << 'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
    chmod +x "$mock_dir/scroll.sh" "$mock_dir/read.sh" "$mock_dir/wait.sh"
    echo "$mock_dir"
}

@test "stitch: measures the offset from shared text and dedupes the overlap" {
    run bash -c "$(declare -f three_pages); FIXTURES='$FIXTURES'; three_pages | '$STITCH' --json"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"text":"Privacy","x":100,"y_abs":700'* ]]
    [[ "$output" == *'"text":"Apps","x":100,"y_abs":1000'* ]]
    [[ "$output" == *'"text":"Developer","x":100,"y_abs":1100'* ]]
    # Overlap rows appear exactly once
    [ "$(grep -o '"text":"Battery"' <<< "$output" | wc -l | tr -d ' ')" -eq 1 ]
    [ "$(grep -o '"text":"Wallet"' <<< "$output" | wc -l | tr -d ' ')" -eq 1 ]
    echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

@test "stitch: chrome that does not scroll is emitted once and flagged fixed" {
    run bash -c "cat '$FIXTURES/page0.json' '$FIXTURES/page1.json' '$FIXTURES/page2.json' | '$STITCH' --json"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"text":"Settings","x":190,"y_abs":40,"page":0,"fixed":true'* ]]
    [ "$(grep -o '"text":"Settings"' <<< "$output" | wc -l | tr -d ' ')" -eq 1 ]
    [ "$(grep -o '"text":"9:41"' <<< "$output" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "stitch: the same text at two list positions is two rows" {
    run bash -c "cat '$FIXTURES/page0.json' '$FIXTURES/page1.json' | '$STITCH' --json"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"text":"On","x":300,"y_abs":300'* ]]
    [[ "$output" == *'"text":"On","x":300,"y_abs":700'* ]]
}

@test "stitch: curly and straight apostrophes are one row" {
    run bash -c "cat '$FIXTURES/page0.json' '$FIXTURES/page1.json' | '$STITCH'"
    [ "$status" -eq 0 ]
    [ "$(grep -ci 'Disturb' <<< "$output")" -eq 1 ]
}

@test "stitch: drops synthetic (button N) shapes" {
    run bash -c "cat '$FIXTURES/page0.json' '$FIXTURES/page1.json' | '$STITCH'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"(button"* ]]
}

@test "stitch: a page that did not scroll adds nothing, chrome included" {
    run bash -c "cat '$FIXTURES/page0.json' '$FIXTURES/page1.json' '$FIXTURES/page2.json' '$FIXTURES/page2.json' | '$STITCH' --count"
    [ "$status" -eq 0 ]
    [ "$output" -eq 12 ]
    run bash -c "cat '$FIXTURES/page0.json' '$FIXTURES/page1.json' '$FIXTURES/page2.json' '$FIXTURES/page2.json' | '$STITCH' --offset"
    [ "$output" -eq 450 ]
}

@test "stitch: a seam with no shared text falls back to --step and is flagged" {
    run bash -c "cat '$FIXTURES/noanchor0.json' '$FIXTURES/noanchor1.json' | '$STITCH' --json --step 250"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"text":"Part B","x":100,"y_abs":370,"page":1,"fixed":false,"seam_uncertain":true'* ]]
    [[ "$output" == *'"text":"Intro","x":100,"y_abs":100,"page":0,"fixed":false}'* ]]
}

@test "stitch: --grep filters after stitching" {
    run bash -c "cat '$FIXTURES/page0.json' '$FIXTURES/page1.json' | '$STITCH' --grep '^w'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Wi-Fi"* ]]
    [[ "$output" == *"Wallet"* ]]
    [[ "$output" != *"Battery"* ]]
}

@test "stitch: rejects a page that is not a JSON array" {
    run bash -c "echo 'Battery|1|2|3|4' | '$STITCH'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a read.sh --json array"* ]]
}

@test "read-all: rejects unknown option" {
    run "$PROJECT_ROOT/read-all.sh" --frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "read-all: rejects a missing option value instead of aborting silently" {
    run "$PROJECT_ROOT/read-all.sh" --max
    [ "$status" -eq 1 ]
    [[ "$output" == *"--max needs a value"* ]]
}

@test "read-all: scrolls to the bottom, stitches, then scrolls back by the measured offset" {
    local mock_dir
    mock_dir=$(create_read_all_harness)
    run "$mock_dir/read-all.sh" --step 300
    [ "$status" -eq 0 ]
    [[ "$output" == *"12 rows over 4 pages."* ]]
    [[ "$output" == *"Developer"* ]]
    [ "$(cat "$mock_dir/scroll.log" | tr '\n' ' ')" = "300 300 300 -450 " ]
}

@test "read-all: --stay does not scroll back" {
    local mock_dir
    mock_dir=$(create_read_all_harness)
    run "$mock_dir/read-all.sh" --step 300 --stay
    [ "$status" -eq 0 ]
    [ "$(cat "$mock_dir/scroll.log" | tr '\n' ' ')" = "300 300 300 " ]
}

@test "read-all: --max stops early and says so" {
    local mock_dir
    mock_dir=$(create_read_all_harness)
    run "$mock_dir/read-all.sh" --step 300 --max 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"stopped at --max 2 before the end"* ]]
    [[ "$output" != *"Developer"* ]]
}

@test "read-all: --from-top scrolls up until the screen stops changing" {
    local mock_dir
    START_POS=2 mock_dir=$(create_read_all_harness)
    run "$mock_dir/read-all.sh" --step 300 --from-top --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"text":"Wi-Fi"'* ]]
    [[ "$output" == *'"text":"Developer"'* ]]
    echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
}
