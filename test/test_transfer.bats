#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "batch_push copies listed files to remote" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "content1" > "$LOCAL_DIR/CLAUDE.md"
    mkdir -p "$LOCAL_DIR/skills/grimoire"
    echo "content2" > "$LOCAL_DIR/skills/grimoire/SKILL.md"
    local list_file
    list_file=$(mktemp)
    printf "CLAUDE.md\nskills/grimoire/SKILL.md\n" > "$list_file"
    batch_push "$list_file"
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "content1" ]
    [ "$(cat "$REMOTE_DIR/skills/grimoire/SKILL.md")" = "content2" ]
    rm -f "$list_file"
}

@test "batch_pull copies listed files from remote" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "remote content" > "$REMOTE_DIR/CLAUDE.md"
    local list_file
    list_file=$(mktemp)
    echo "CLAUDE.md" > "$list_file"
    batch_pull "$list_file"
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "remote content" ]
    rm -f "$list_file"
}

@test "batch_delete_remote removes listed files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "to delete" > "$REMOTE_DIR/CLAUDE.md"
    batch_delete_remote "CLAUDE.md"
    [ ! -f "$REMOTE_DIR/CLAUDE.md" ]
}

@test "batch_delete_local removes listed files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "to delete" > "$LOCAL_DIR/CLAUDE.md"
    batch_delete_local "CLAUDE.md"
    [ ! -f "$LOCAL_DIR/CLAUDE.md" ]
}

@test "update_base copies file to last-sync" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "content" > "$LOCAL_DIR/CLAUDE.md"
    update_base_from_local "CLAUDE.md"
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "content" ]
}

@test "create_local_backup creates tar of synced files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "backup me" > "$LOCAL_DIR/CLAUDE.md"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    create_local_backup
    local latest
    latest=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)
    [ -n "$latest" ]
    tar -tzf "$latest" | grep -q "CLAUDE.md"
}
