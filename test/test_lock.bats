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

@test "acquire_local_lock fails if lock held by another process" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    LOCK_FILE="$CONFIG_DIR/.lock"
    # Hold the flock in a background subprocess
    (
        exec 9>"$LOCK_FILE"
        flock -n 9
        echo "$BASHPID" >&9
        sleep 10
    ) &
    local bg_pid=$!
    sleep 0.2  # let the subprocess grab the lock
    source ./claude-sync --source-only
    run acquire_local_lock
    [ "$status" -ne 0 ]
    [[ "$output" == *"already running"* ]]
    kill "$bg_pid" 2>/dev/null || true
    wait "$bg_pid" 2>/dev/null || true
}

@test "acquire_local_lock succeeds after previous holder exits" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    LOCK_FILE="$CONFIG_DIR/.lock"
    # Hold and release the flock in a subprocess
    (
        exec 9>"$LOCK_FILE"
        flock -n 9
        echo "old_pid" >&9
    )
    # Subprocess exited, flock is released — should succeed
    source ./claude-sync --source-only
    acquire_local_lock
    read -r pid _ < "$LOCK_FILE"
    [ "$pid" = "$$" ]
    release_local_lock
}
