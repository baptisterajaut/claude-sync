#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "acquire_local_lock creates lock file with PID and timestamp" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    LOCK_FILE="$CONFIG_DIR/.lock"
    acquire_local_lock
    [ -f "$LOCK_FILE" ]
    read -r pid ts < "$LOCK_FILE"
    [ "$pid" = "$$" ]
    [ -n "$ts" ]
    release_local_lock
}

@test "acquire_local_lock fails if lock held by running process" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    LOCK_FILE="$CONFIG_DIR/.lock"
    echo "$$ $(date +%s)" > "$LOCK_FILE"
    run acquire_local_lock
    [ "$status" -ne 0 ]
    [[ "$output" == *"already running"* ]]
}

@test "acquire_local_lock reclaims stale lock from dead PID" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    LOCK_FILE="$CONFIG_DIR/.lock"
    echo "99999 $(date +%s)" > "$LOCK_FILE"
    acquire_local_lock
    read -r pid _ < "$LOCK_FILE"
    [ "$pid" = "$$" ]
    release_local_lock
}
