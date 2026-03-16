#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "status shows clean when all in sync" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "hello" > "$LOCAL_DIR/CLAUDE.md"
    echo "hello" > "$REMOTE_DIR/CLAUDE.md"
    echo "hello" > "$BASE_DIR/CLAUDE.md"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    run bash ./claude-sync status
    [ "$status" -eq 0 ]
    [[ "$output" == *"clean"* ]]
    [[ "$output" == *"CLAUDE.md"* ]]
}

@test "status shows local-> when local changed" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "modified" > "$LOCAL_DIR/CLAUDE.md"
    echo "original" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    run bash ./claude-sync status
    [ "$status" -eq 0 ]
    [[ "$output" == *"local→"* ]]
}

@test "status shows CONFLICT when both changed differently" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "local version" > "$LOCAL_DIR/CLAUDE.md"
    echo "remote version" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    run bash ./claude-sync status
    [ "$status" -eq 0 ]
    [[ "$output" == *"CONFLICT"* ]]
}

@test "status shows new-local for new local file" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "new" > "$LOCAL_DIR/CLAUDE.md"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    run bash ./claude-sync status
    [ "$status" -eq 0 ]
    [[ "$output" == *"new-local"* ]]
}
