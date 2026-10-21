#!/usr/bin/env bats
# Regression guard for issue #6: iPhone Mirroring must be identified by bundle ID,
# never by its localized name or its localized menu titles (Japanese macOS reports
# "iPhoneミラーリング" and "表示"). Only code is scanned: docs, tests, *.txt, plists
# and user-facing log/error text are out of scope by construction of the patterns.

load test_helper

# Source files only (no docs, tests, txt, plist, build output, node_modules).
scan() {
    grep -rnE "$1" "$PROJECT_ROOT" \
        --include='*.sh' --include='*.swift' --include='*.ts' --include='*.js' \
        --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=tests \
        --exclude-dir=docs --exclude-dir=build --exclude-dir=dist --exclude-dir=.build \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|#|\*|///)' || true
}

@test "no string comparison against the localized app name" {
    run scan '(==|!=|===|!==|isEqual|\.equals)[[:space:](]*"iPhone Mirroring"|"iPhone Mirroring"[[:space:]]*(==|!=|===|!==)'
    [ -z "$output" ] || { echo "$output"; false; }
}

@test "no process or application lookup by the localized app name" {
    run scan "(process|application|processes\.byName|byName|pgrep|killall|open -a)[[:space:](\\\\]*[\"']iPhone Mirroring[\"']"
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
    run scan "byName\\([\"'](View|Spotlight|Home Screen|App Switcher)[\"']\\)|title == \"View\"|title == itemName|whose name is \"(View|Spotlight)\""
    [ -z "$output" ] || { echo "$output"; false; }
}

@test "guard detects a violation (self-check)" {
    local f="$PROJECT_ROOT/zz_guard_probe.swift"
    echo 'let x = owner == "iPhone Mirroring"' > "$f"
    run scan '(==|!=|===|!==)[[:space:]]*"iPhone Mirroring"|"iPhone Mirroring"[[:space:]]*(==|!=)'
    rm -f "$f"
    [[ "$output" == *"zz_guard_probe.swift"* ]]
}
