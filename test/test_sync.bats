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

@test "resolve: pushes local version for conflicting files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "local merge" > "$LOCAL_DIR/CLAUDE.md"
    echo "remote version" > "$REMOTE_DIR/CLAUDE.md"
    # Verify it's a conflict
    run bash ./claude-sync sync
    [ "$status" -ne 0 ]
    [[ "$output" == *"CONFLICT"* ]]
    # Resolve: local wins
    run bash ./claude-sync resolve
    [ "$status" -eq 0 ]
    [[ "$output" == *"resolved"* ]]
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "local merge" ]
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "local merge" ]
    # Sync should now be clean
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"Everything in sync"* ]]
}

@test "resolve: does nothing when no conflicts" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$REMOTE_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"
    run bash ./claude-sync resolve
    [ "$status" -eq 0 ]
    [[ "$output" == *"No conflicts"* ]]
}

@test "resolve: only affects conflicting files, not clean ones" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md
settings.json" > "$CONFIG_DIR/synclist"
    # CLAUDE.md: conflict
    echo "base" > "$BASE_DIR/CLAUDE.md"
    echo "local" > "$LOCAL_DIR/CLAUDE.md"
    echo "remote" > "$REMOTE_DIR/CLAUDE.md"
    # settings.json: clean
    echo "clean" > "$BASE_DIR/settings.json"
    echo "clean" > "$LOCAL_DIR/settings.json"
    echo "clean" > "$REMOTE_DIR/settings.json"
    run bash ./claude-sync resolve
    [ "$status" -eq 0 ]
    # CLAUDE.md resolved
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "local" ]
    # settings.json untouched
    [ "$(cat "$REMOTE_DIR/settings.json")" = "clean" ]
}

@test "resolve: only resolves specified files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md
settings.json" > "$CONFIG_DIR/synclist"
    # Both in conflict
    echo "base1" > "$BASE_DIR/CLAUDE.md"
    echo "local1" > "$LOCAL_DIR/CLAUDE.md"
    echo "remote1" > "$REMOTE_DIR/CLAUDE.md"
    echo "base2" > "$BASE_DIR/settings.json"
    echo "local2" > "$LOCAL_DIR/settings.json"
    echo "remote2" > "$REMOTE_DIR/settings.json"
    # Resolve only CLAUDE.md
    run bash ./claude-sync resolve CLAUDE.md
    [ "$status" -eq 0 ]
    # CLAUDE.md resolved
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "local1" ]
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "local1" ]
    # settings.json still in conflict (remote untouched)
    [ "$(cat "$REMOTE_DIR/settings.json")" = "remote2" ]
    [ "$(cat "$BASE_DIR/settings.json")" = "base2" ]
}

@test "resolve: errors when specified file not in conflict" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$REMOTE_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"
    run bash ./claude-sync resolve CLAUDE.md
    [ "$status" -ne 0 ]
    [[ "$output" == *"not in conflict"* ]]
}

@test "sync: plugins.list auto-merges union of both sides" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$REMOTE_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"
    # Local has plugin A, remote has plugin B, base has neither
    printf "pluginA@market\n" > "$LOCAL_DIR/plugins.list"
    printf "pluginB@market\n" > "$REMOTE_DIR/plugins.list"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    # Local should have both
    grep -q "pluginA@market" "$LOCAL_DIR/plugins.list"
    grep -q "pluginB@market" "$LOCAL_DIR/plugins.list"
    # Remote should have both
    grep -q "pluginA@market" "$REMOTE_DIR/plugins.list"
    grep -q "pluginB@market" "$REMOTE_DIR/plugins.list"
}

@test "sync: plugins.list pushes local when remote empty" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$REMOTE_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"
    printf "pluginA@market\n" > "$LOCAL_DIR/plugins.list"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$REMOTE_DIR/plugins.list")" = "pluginA@market" ]
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
