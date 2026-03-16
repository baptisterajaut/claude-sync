#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "e2e: first machine bootstrap (empty remote)" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md
skills/" > "$CONFIG_DIR/synclist"
    echo "my config" > "$LOCAL_DIR/CLAUDE.md"
    mkdir -p "$LOCAL_DIR/skills/grimoire"
    echo "spell" > "$LOCAL_DIR/skills/grimoire/SKILL.md"

    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "my config" ]
    [ "$(cat "$REMOTE_DIR/skills/grimoire/SKILL.md")" = "spell" ]
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "my config" ]
}

@test "e2e: second machine joins (has local config, remote exists)" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md
skills/" > "$CONFIG_DIR/synclist"
    # Remote already has config from first machine
    echo "first machine config" > "$REMOTE_DIR/CLAUDE.md"
    mkdir -p "$REMOTE_DIR/skills/grimoire"
    echo "spell" > "$REMOTE_DIR/skills/grimoire/SKILL.md"
    # Local has its own skill but no CLAUDE.md
    mkdir -p "$LOCAL_DIR/skills/necronomicon"
    echo "dark spell" > "$LOCAL_DIR/skills/necronomicon/SKILL.md"

    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    # Local should get remote's CLAUDE.md and grimoire
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "first machine config" ]
    [ "$(cat "$LOCAL_DIR/skills/grimoire/SKILL.md")" = "spell" ]
    # Remote should get local's necronomicon
    [ "$(cat "$REMOTE_DIR/skills/necronomicon/SKILL.md")" = "dark spell" ]
}

@test "e2e: normal workflow — modify, sync, modify other side, sync" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    # Start in sync
    echo "v1" > "$LOCAL_DIR/CLAUDE.md"
    echo "v1" > "$REMOTE_DIR/CLAUDE.md"
    echo "v1" > "$BASE_DIR/CLAUDE.md"

    # Local modifies
    echo "v2 local" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "v2 local" ]

    # Now remote modifies (simulating another machine syncing)
    echo "v3 remote" > "$REMOTE_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "v3 remote" ]
}

@test "e2e: conflict detected and non-conflicting files still sync" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md
skills/" > "$CONFIG_DIR/synclist"
    # In sync for skills, conflict on CLAUDE.md
    echo "base" > "$BASE_DIR/CLAUDE.md"
    echo "local edit" > "$LOCAL_DIR/CLAUDE.md"
    echo "remote edit" > "$REMOTE_DIR/CLAUDE.md"
    # Skills: remote changed, local didn't
    mkdir -p "$LOCAL_DIR/skills/new" "$BASE_DIR/skills/new" "$REMOTE_DIR/skills/new"
    echo "v1" > "$LOCAL_DIR/skills/new/SKILL.md"
    echo "v1" > "$BASE_DIR/skills/new/SKILL.md"
    echo "v2" > "$REMOTE_DIR/skills/new/SKILL.md"

    run bash ./claude-sync sync
    # Should exit non-zero due to conflicts
    [ "$status" -ne 0 ]
    # CLAUDE.md untouched on both sides
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "local edit" ]
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "remote edit" ]
    # But skills/new/SKILL.md should have been pulled (only remote changed)
    [ "$(cat "$LOCAL_DIR/skills/new/SKILL.md")" = "v2" ]
}

@test "e2e: deletion propagates correctly" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "skills/" > "$CONFIG_DIR/synclist"
    # Start with a skill on all three
    mkdir -p "$LOCAL_DIR/skills/old" "$REMOTE_DIR/skills/old" "$BASE_DIR/skills/old"
    echo "content" > "$LOCAL_DIR/skills/old/SKILL.md"
    echo "content" > "$REMOTE_DIR/skills/old/SKILL.md"
    echo "content" > "$BASE_DIR/skills/old/SKILL.md"

    # Delete locally
    rm -rf "$LOCAL_DIR/skills/old"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    # Should be gone from remote and base
    [ ! -f "$REMOTE_DIR/skills/old/SKILL.md" ]
    [ ! -f "$BASE_DIR/skills/old/SKILL.md" ]
}
