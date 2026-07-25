#!/usr/bin/env bash
# Shared test helpers for iphone-control bats tests.
# Source this in setup() of each test file.

# Canonical mock JSON matching find-window.sh output.
# Negative origin on purpose: simulates a window on a 2x display left of / above
# the primary (global coordinates are negative there). Deltas content-window = (10, 20).
MOCK_WINDOW_JSON='{"x":-1080,"y":-400,"width":400,"height":800,"content_x":-1070,"content_y":-380,"content_width":380,"content_height":760,"window_id":12345,"scale":2}'

# Create a temp directory for each test
setup_temp() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
}

# Clean up temp directory
teardown_temp() {
    if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Create a mock scripts directory with a fake find-window.sh
# that returns canned JSON without requiring iPhone Mirroring.
create_mock_scripts_dir() {
    local mock_dir="$TEST_TEMP_DIR/mock_scripts"
    mkdir -p "$mock_dir/helpers"

    # Copy real common.sh so sourced functions work
    cp "$PROJECT_ROOT/helpers/common.sh" "$mock_dir/helpers/common.sh"

    # Mock find-window.sh - outputs the canonical fixture (expanded at generation time)
    cat > "$mock_dir/find-window.sh" << MOCK
#!/usr/bin/env bash
echo '${MOCK_WINDOW_JSON}'
MOCK
    chmod +x "$mock_dir/find-window.sh"

    # Mock screencapture - creates a 1x1 PNG
    cat > "$mock_dir/screencapture" << 'MOCK'
#!/usr/bin/env bash
# Create a minimal valid PNG (1x1 pixel, red)
printf '\x89PNG\r\n\x1a\n' > "${@: -1}" 2>/dev/null || true
MOCK
    chmod +x "$mock_dir/screencapture"

    echo "$mock_dir"
}

# Create a mock find-window.sh that fails (simulates iPhone Mirroring not running)
create_failing_find_window() {
    local mock_dir="$1"
    cat > "$mock_dir/find-window.sh" << 'MOCK'
#!/usr/bin/env bash
echo '{"error":"iPhone Mirroring window not found. Is iPhone Mirroring open?"}' >&2
exit 1
MOCK
    chmod +x "$mock_dir/find-window.sh"
}

# Project root (one level up from tests/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT
