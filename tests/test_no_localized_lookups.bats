#!/usr/bin/env bats
# Regression guard for issue #6: iPhone Mirroring must be identified by bundle ID,
# never by its localized name or its localized menu titles (Japanese macOS reports
# "iPhoneミラーリング" and "表示"). Only code is scanned: docs, tests, *.txt, plists
# and user-facing log/error text are out of scope by construction of the patterns.
#
# All patterns run through `grep -iE` (case-insensitive) and allow an optional
# backslash before a quote, because AppleScript embedded in a shell string is
# written as: tell application \"iPhone Mirroring\"

load test_helper

APP='iPhone[[:space:]]+Mirroring'
# Optional backslash, then a double or single quote.
Q="\\\\?[\"']"

PAT_COMPARE="(==|!=|===|!==|isEqual|\\.equals)[[:space:](]*${Q}${APP}${Q}|${Q}${APP}${Q}[[:space:]]*(==|!=|===|!==)"
PAT_LOOKUP="(process|application|app|byName|pgrep|killall|launchApplication|launchApp|open -a)[[:space:](\\\\]*${Q}${APP}"
PAT_MENU="byName\\(${Q}(View|Spotlight|Home Screen|App Switcher)${Q}\\)|title == \"View\"|title == itemName|whose name is ${Q}(View|Spotlight)${Q}"

# Source files only (no docs, tests, txt, plist, build output, node_modules).
# Optional second argument is the directory to scan (default: the project).
scan() {
    grep -rniE "$1" "${2:-$PROJECT_ROOT}" \
        --include='*.sh' --include='*.swift' --include='*.ts' --include='*.js' \
        --include='*.py' --include='*.applescript' --include='*.scpt' \
        --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=tests \
        --exclude-dir=docs --exclude-dir=build --exclude-dir=dist --exclude-dir=.build \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|#|\*|///)' || true
}

@test "no string comparison against the localized app name" {
    run scan "$PAT_COMPARE"
    [ -z "$output" ] || { echo "$output"; false; }
}

@test "no process or application lookup by the localized app name" {
    run scan "$PAT_LOOKUP"
    [ -z "$output" ] || { echo "$output"; false; }
}

@test "IPHONE_MIRRORING_PROCESS is gone" {
    run scan 'IPHONE_MIRRORING_PROCESS'
    [ -z "$output" ] || { echo "$output"; false; }
}

@test "no kCGWindowOwnerName equality check" {
    run scan 'kCGWindowOwnerName'
    [ -z "$output" ] || { echo "$output"; false; }
}

@test "no localizedName comparison" {
    run scan 'localizedName\)?[[:space:]]*(==|!=)'
    [ -z "$output" ] || { echo "$output"; false; }
}

@test "no menu matching by localized title" {
    run scan "$PAT_MENU"
    [ -z "$output" ] || { echo "$output"; false; }
}

# --- Self-check: the REAL patterns must catch every seeded bad form ---
# The probe files live in a temp dir (not tests/), so scan() sees them.

seed() { # seed <file> <line>
    printf '%s\n' "$2" > "$TEST_TEMP_DIR/$1"
}

assert_caught() { # assert_caught <pattern> <file>
    run scan "$1" "$TEST_TEMP_DIR"
    [[ "$output" == *"$2:"* ]] || { echo "pattern missed $2: $(cat "$TEST_TEMP_DIR/$2")"; false; }
}

@test "guard catches every seeded lookup and comparison form (self-check)" {
    setup_temp
    # Backslash-escaped quotes, exactly how the old status.sh embedded AppleScript.
    seed bad1.sh   'osascript -e "tell application \"iPhone Mirroring\" to activate"'
    seed bad2.swift 'let a = Application("iPhone Mirroring")'
    seed bad3.sh   "osascript -e 'tell app \"iPhone Mirroring\" to quit'"
    seed bad4.swift 'NSWorkspace.shared.launchApplication("iPhone Mirroring")'
    seed bad5.js   "const a = Application('iPhone Mirroring')"
    seed bad6.py   'run(["open", "-a", "iPhone Mirroring"]); os.system("open -a \"iPhone Mirroring\"")'
    seed bad7.applescript 'tell application "iPhone Mirroring" to activate'
    seed bad8.swift 'if owner == "iPhone Mirroring" { }'
    seed bad9.ts   "if (name === 'iPhone Mirroring') {}"
    seed bad10.sh  'pgrep -x "iPhone Mirroring"; killall "iPhone Mirroring"'
    seed bad11.sh  'tell APPLICATION \"IPHONE MIRRORING\"'
    seed bad12.swift 'let m = menu.byName("View")'
    assert_caught "$PAT_LOOKUP" bad1.sh
    assert_caught "$PAT_LOOKUP" bad2.swift
    assert_caught "$PAT_LOOKUP" bad3.sh
    assert_caught "$PAT_LOOKUP" bad4.swift
    assert_caught "$PAT_LOOKUP" bad5.js
    assert_caught "$PAT_LOOKUP" bad6.py
    assert_caught "$PAT_LOOKUP" bad7.applescript
    assert_caught "$PAT_COMPARE" bad8.swift
    assert_caught "$PAT_COMPARE" bad9.ts
    assert_caught "$PAT_LOOKUP" bad10.sh
    assert_caught "$PAT_LOOKUP" bad11.sh
    assert_caught "$PAT_MENU" bad12.swift
    teardown_temp
}

@test "guard ignores legitimate log and error text (self-check)" {
    setup_temp
    seed ok1.sh    'echo "Error: iPhone Mirroring window not found" >&2'
    seed ok2.swift 'throw CommandError(message: "iPhone Mirroring is not running")'
    seed ok3.sh    'log "Open the iPhone Mirroring app first"'
    seed ok4.ts    "console.log('Waiting for iPhone Mirroring to connect')"
    seed ok5.sh    '# tell application "iPhone Mirroring" is forbidden here'
    local pat
    for pat in "$PAT_LOOKUP" "$PAT_COMPARE" "$PAT_MENU"; do
        run scan "$pat" "$TEST_TEMP_DIR"
        [ -z "$output" ] || { echo "false positive: $output"; false; }
    done
    teardown_temp
}
