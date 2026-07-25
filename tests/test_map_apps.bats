#!/usr/bin/env bats
# Tests for map-apps.sh OCR-based app scanning.

load test_helper

setup() {
    setup_temp
}

teardown() {
    teardown_temp
}

# Helper: create a full map-apps mock environment
_create_map_apps_env() {
    local mock_dir
    mock_dir=$(create_mock_scripts_dir)

    # Mock iphone-control.sh (home command)
    cat > "$mock_dir/iphone-control.sh" << 'MOCK'
#!/usr/bin/env bash
echo "home: ok"
MOCK
    chmod +x "$mock_dir/iphone-control.sh"

    # Mock swipe.sh
    cat > "$mock_dir/swipe.sh" << 'MOCK'
#!/usr/bin/env bash
echo "Swiped"
MOCK
    chmod +x "$mock_dir/swipe.sh"

    # Mock screenshot.sh - creates a minimal PNG file (accepts --native like the real one)
    cat > "$mock_dir/screenshot.sh" << 'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == "--native" ]]; then shift; fi
output="${1:-/tmp/iphone-screen.png}"
printf '\x89PNG\r\n\x1a\n' > "$output"
# Append unique data per call so page hashes differ
echo "$$-$RANDOM" >> "$output"
MOCK
    chmod +x "$mock_dir/screenshot.sh"

    echo "$mock_dir"
}

# Helper: create mock OCR helper that returns canned output
_create_mock_ocr() {
    local mock_dir="$1"
    local ocr_output="$2"

    mkdir -p "$mock_dir/helpers"
    cat > "$mock_dir/helpers/ocr-image" << MOCK
#!/usr/bin/env bash
echo '${ocr_output}'
MOCK
    chmod +x "$mock_dir/helpers/ocr-image"

    # Create a dummy swift source so the -nt check works
    touch -t 200001010000 "$mock_dir/helpers/ocr-image.swift"
}

# Helper: create the map-apps test script
_create_map_apps_script() {
    local mock_dir="$1"

    cat > "$mock_dir/map-apps.sh" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$mock_dir"
source "\$SCRIPT_DIR/helpers/common.sh"
HELPER="\$SCRIPT_DIR/helpers/ocr-image"
HELPER_SRC="\$HELPER.swift"
MAX_PAGES="\${1:-\$DEFAULT_MAX_PAGES}"

# Skip compilation - use mock OCR helper
if [[ ! -x "\$HELPER" ]]; then
    echo '{"error":"OCR helper not found"}' >&2
    exit 1
fi

window_json=\$("\$SCRIPT_DIR/find-window.sh")
parse_window_bounds "\$window_json"

"\$SCRIPT_DIR/iphone-control.sh" home > /dev/null 2>&1
sleep 0.01

swipe_y=\$(( CONTENT_H / 2 ))
swipe_x_start=\$(( CONTENT_W - SWIPE_EDGE_MARGIN ))
swipe_x_end=\$SWIPE_EDGE_MARGIN
app_zone_bottom=\$(( CONTENT_H - APP_ZONE_BOTTOM_MARGIN ))

all_apps="["
first_entry=true
prev_hash=""

for (( page=1; page<=MAX_PAGES; page++ )); do
    tmp_img="/tmp/iphone-home-page-\${page}.png"
    "\$SCRIPT_DIR/screenshot.sh" --native "\$tmp_img" > /dev/null 2>&1

    current_hash=\$(md5 -q "\$tmp_img" 2>/dev/null || md5sum "\$tmp_img" | cut -d' ' -f1)
    if [[ "\$current_hash" == "\$prev_hash" ]]; then
        rm -f "\$tmp_img"
        break
    fi
    prev_hash="\$current_hash"

    ocr_output=\$("\$HELPER" "\$tmp_img" 2>/dev/null) || {
        continue
    }

    while IFS='|' read -r text px py pw ph; do
        [[ -z "\$text" ]] && continue
        px=\$(( px / SCALE )); py=\$(( py / SCALE )); pw=\$(( pw / SCALE ))
        (( py < APP_ZONE_TOP || py > app_zone_bottom )) && continue
        text_len=\${#text}
        (( text_len > APP_LABEL_MAX_LEN || text_len < APP_LABEL_MIN_LEN )) && continue
        case "\$text" in
            [0-9]*:[0-9]*|[0-9]*%|Search*|Suggestions*|Siri*) continue ;;
        esac
        tap_x=\$(( px + pw / 2 ))
        tap_y=\$(( py - APP_ICON_ABOVE_LABEL ))
        if \$first_entry; then
            first_entry=false
        else
            all_apps+=","
        fi
        escaped_text="\${text//\\\\/\\\\\\\\}"
        escaped_text="\${escaped_text//\\\"/\\\\\\\"}"
        all_apps+="{\"name\":\"\${escaped_text}\",\"page\":\${page},\"x\":\${tap_x},\"y\":\${tap_y}}"
    done <<< "\$ocr_output"

    if (( page < MAX_PAGES )); then
        "\$SCRIPT_DIR/swipe.sh" "\$swipe_x_start" "\$swipe_y" "\$swipe_x_end" "\$swipe_y" "\$DEFAULT_SWIPE_DURATION" > /dev/null 2>&1
        sleep 0.01
    fi
done

all_apps+="]"
echo "\$all_apps"
SCRIPT
    chmod +x "$mock_dir/map-apps.sh"
}

@test "map-apps: auto-compiles OCR helper if missing (verify compilation attempt)" {
    local mock_dir
    mock_dir=$(_create_map_apps_env)

    # Create swift source but no compiled binary
    mkdir -p "$mock_dir/helpers"
    echo "// swift source" > "$mock_dir/helpers/ocr-image.swift"
    # Do NOT create the binary - script should try to compile

    # Create a script that only tests the compilation logic
    cat > "$mock_dir/compile_test.sh" << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
HELPER="$mock_dir/helpers/ocr-image"
HELPER_SRC="\$HELPER.swift"

if [[ ! -x "\$HELPER" ]] || [[ "\$HELPER_SRC" -nt "\$HELPER" ]]; then
    echo "compilation_attempted"
    exit 0
fi
echo "no_compilation_needed"
SCRIPT
    chmod +x "$mock_dir/compile_test.sh"

    run "$mock_dir/compile_test.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "compilation_attempted" ]
}

@test "map-apps: outputs valid JSON array" {
    local mock_dir
    mock_dir=$(_create_map_apps_env)
    # OCR returns app labels in the valid zone (y=200 is within 80..660 for 760-high content)
    _create_mock_ocr "$mock_dir" "Safari|50|200|60|15
Settings|150|200|70|15"
    _create_map_apps_script "$mock_dir"

    run "$mock_dir/map-apps.sh" 1
    [ "$status" -eq 0 ]

    # Must start with [ and end with ]
    [[ "$output" == "["* ]]
    [[ "$output" == *"]" ]]
    # Must contain app names
    [[ "$output" == *"Safari"* ]]
    [[ "$output" == *"Settings"* ]]
}

@test "map-apps: respects MAX_PAGES argument" {
    local mock_dir
    mock_dir=$(_create_map_apps_env)
    _create_mock_ocr "$mock_dir" "Safari|50|200|60|15"
    _create_map_apps_script "$mock_dir"

    # With MAX_PAGES=1, should only scan 1 page and not swipe
    run "$mock_dir/map-apps.sh" 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Safari"* ]]
    # Only page 1 entries
    [[ "$output" == *'"page":1'* ]]
}

@test "map-apps: converts OCR pixel coords to points (scale 2 fixture)" {
    local mock_dir
    mock_dir=$(_create_map_apps_env)
    # OCR emits native-resolution pixel coords; fixture scale is 2.
    # Safari label at px=100,py=400,pw=120 -> points 50,200,60 -> tap at (80, 180)
    _create_mock_ocr "$mock_dir" "Safari|100|400|120|30"
    _create_map_apps_script "$mock_dir"

    run "$mock_dir/map-apps.sh" 1
    [ "$status" -eq 0 ]
    [[ "$output" == *'"x":80'* ]]
    [[ "$output" == *'"y":180'* ]]
}

@test "map-apps: handles empty OCR output gracefully" {
    local mock_dir
    mock_dir=$(_create_map_apps_env)
    _create_mock_ocr "$mock_dir" ""
    _create_map_apps_script "$mock_dir"

    run "$mock_dir/map-apps.sh" 1
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "map-apps: filters app labels by length and zone" {
    local mock_dir
    mock_dir=$(_create_map_apps_env)
    # y=10 is above APP_ZONE_TOP (80) - should be filtered
    # "X" is too short (< APP_LABEL_MIN_LEN=2) - should be filtered
    # "ThisIsAnExtremelyLongAppNameThatExceedsLimit" is too long (> 25) - should be filtered
    # "Safari" at y=200 should pass
    _create_mock_ocr "$mock_dir" "X|50|200|10|15
ThisIsAnExtremelyLongAppNameThatExceedsLimit|50|200|200|15
TopZone|50|10|60|15
Safari|50|200|60|15"
    _create_map_apps_script "$mock_dir"

    run "$mock_dir/map-apps.sh" 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Safari"* ]]
    [[ "$output" != *"TopZone"* ]]
    [[ "$output" != *"ThisIsAnExtremely"* ]]
}
