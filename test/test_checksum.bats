#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "compute_checksums returns md5 for existing files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    echo "hello" > "$LOCAL_DIR/CLAUDE.md"
    result=$(compute_local_checksums "$LOCAL_DIR" "CLAUDE.md")
    [[ "$result" == *"CLAUDE.md"* ]]
    hash=$(echo "$result" | awk '{print $1}')
    [ "${#hash}" -eq 32 ]
}

@test "compute_checksums returns ABSENT for missing files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    result=$(compute_local_checksums "$LOCAL_DIR" "CLAUDE.md")
    [[ "$result" == *"ABSENT"* ]]
    [[ "$result" == *"CLAUDE.md"* ]]
}

@test "fetch_remote_checksums_readonly populates REMOTE_CHECKSUMS array" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "world" > "$REMOTE_DIR/CLAUDE.md"
    mkdir -p "$REMOTE_DIR/skills/test"
    echo "skill" > "$REMOTE_DIR/skills/test/SKILL.md"
    fetch_remote_checksums_readonly
    [ "${#REMOTE_CHECKSUMS[CLAUDE.md]}" -eq 32 ]
    [ "${#REMOTE_CHECKSUMS[skills/test/SKILL.md]}" -eq 32 ]
    [ -z "${REMOTE_CHECKSUMS[nonexistent.md]+x}" ]
}
