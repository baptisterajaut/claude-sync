#!/usr/bin/env bats

# Numbered 00 so it runs first — if the test suite ever fails with confusing
# errors elsewhere, look here first: a missing prereq is usually the cause.

@test "prereq: jq is installed (required by several plugin-related tests)" {
    if ! command -v jq >/dev/null 2>&1; then
        skip_msg="jq not found in PATH — install jq to run the full test suite (Arch: pacman -S jq, Debian/Ubuntu: apt install jq, macOS: brew install jq)"
        echo "$skip_msg" >&2
        false
    fi
}

@test "prereq: bats is installed (running it, so duh — but covers PATH sanity)" {
    command -v bats >/dev/null 2>&1
}

@test "prereq: rsync is installed (used by the rsync backend tests)" {
    command -v rsync >/dev/null 2>&1
}

@test "prereq: git is installed (used by the git backend tests)" {
    command -v git >/dev/null 2>&1
}
