#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "sync: local-only changes propagate to remote" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$LOCAL_DIR/CLAUDE.md"
    echo "original" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "modified locally" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "modified locally" ]
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "modified locally" ]
}

@test "sync: remote-only changes propagate to local" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$LOCAL_DIR/CLAUDE.md"
    echo "original" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "modified remotely" > "$REMOTE_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "modified remotely" ]
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "modified remotely" ]
}

@test "sync: pull creates backup before modifying local" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "local original" > "$LOCAL_DIR/CLAUDE.md"
    echo "local original" > "$BASE_DIR/CLAUDE.md"
    echo "remote modified" > "$REMOTE_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    local backup
    backup=$(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)
    [ -n "$backup" ]
    mkdir -p "$TEST_DIR/restore"
    tar -xzf "$backup" -C "$TEST_DIR/restore"
    [ "$(cat "$TEST_DIR/restore/CLAUDE.md")" = "local original" ]
}

@test "sync: conflict exits non-zero and does not modify files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$LOCAL_DIR/CLAUDE.md"
    echo "original" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "local change" > "$LOCAL_DIR/CLAUDE.md"
    echo "remote change" > "$REMOTE_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -ne 0 ]
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "local change" ]
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "remote change" ]
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "original" ]
    [[ "$output" == *"CONFLICT"* ]]
}

@test "sync: new local file propagates to remote" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "new file" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "new file" ]
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "new file" ]
}

@test "sync: new remote file propagates to local" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "from remote" > "$REMOTE_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "from remote" ]
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "from remote" ]
}

@test "sync: dry-run does not modify files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$LOCAL_DIR/CLAUDE.md"
    echo "original" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "modified" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync --dry-run sync
    [ "$status" -eq 0 ]
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "original" ]
    [[ "$output" == *"push"* ]]
}

@test "sync: deletion propagates when one side unchanged" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ ! -f "$REMOTE_DIR/CLAUDE.md" ]
    [ ! -f "$BASE_DIR/CLAUDE.md" ]
}

@test "sync: everything clean → exit 0" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$REMOTE_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"Everything in sync"* ]]
}

@test "sync: push-only does not create backup" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$LOCAL_DIR/CLAUDE.md"
    echo "original" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "modified" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    local count
    count=$(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)
    [ "$count" -eq 0 ]
}
