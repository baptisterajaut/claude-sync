#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "diff shows unified diff for changed files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$LOCAL_DIR/CLAUDE.md"
    echo "modified" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    run bash ./claude-sync diff
    [ "$status" -eq 0 ]
    [[ "$output" == *"---"* ]]
    [[ "$output" == *"+++"* ]]
    [[ "$output" == *"CLAUDE.md"* ]]
}

@test "diff shows nothing when all clean" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$REMOTE_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"
    run bash ./claude-sync diff
    [ "$status" -eq 0 ]
    [[ "$output" == *"No differences"* ]]
}

@test "diff shows absent files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "only remote" > "$REMOTE_DIR/CLAUDE.md"
    run bash ./claude-sync diff
    [ "$status" -eq 0 ]
    [[ "$output" == *"absent"* ]]
}
