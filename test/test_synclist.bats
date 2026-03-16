#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "load_synclist returns defaults when no synclist file" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    result=$(load_synclist)
    [[ "$result" == *"CLAUDE.md"* ]]
    [[ "$result" == *"settings.json"* ]]
    [[ "$result" == *"skills/"* ]]
}

@test "load_synclist reads custom synclist file" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    cat > "$CONFIG_DIR/synclist" <<EOF
# custom list
CLAUDE.md
my-custom-file.txt
EOF
    source ./claude-sync --source-only
    result=$(load_synclist)
    [[ "$result" == *"CLAUDE.md"* ]]
    [[ "$result" == *"my-custom-file.txt"* ]]
    [[ "$result" != *"settings.json"* ]]
}

@test "enumerate_files expands directories to individual files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    mkdir -p "$LOCAL_DIR/skills/grimoire"
    echo "test" > "$LOCAL_DIR/CLAUDE.md"
    echo "test" > "$LOCAL_DIR/skills/grimoire/SKILL.md"
    result=$(enumerate_files "$LOCAL_DIR" "CLAUDE.md
skills/")
    [[ "$result" == *"CLAUDE.md"* ]]
    [[ "$result" == *"skills/grimoire/SKILL.md"* ]]
}

@test "enumerate_files excludes claude-sync skills" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    mkdir -p "$LOCAL_DIR/skills/claude-sync" "$LOCAL_DIR/skills/grimoire"
    echo "test" > "$LOCAL_DIR/skills/claude-sync/init.md"
    echo "test" > "$LOCAL_DIR/skills/grimoire/SKILL.md"
    result=$(enumerate_files "$LOCAL_DIR" "skills/")
    [[ "$result" != *"skills/claude-sync/"* ]]
    [[ "$result" == *"skills/grimoire/SKILL.md"* ]]
}
