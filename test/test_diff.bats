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

@test "diff shows plugins.list three-way merge preview" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$REMOTE_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"
    printf "pluginA@market\npluginB@market\n" > "$BASE_DIR/plugins.list"
    printf "pluginA@market\npluginB@market\npluginC@market\n" > "$LOCAL_DIR/plugins.list"
    printf "pluginA@market\npluginB@market\npluginD@market\n" > "$REMOTE_DIR/plugins.list"
    run bash ./claude-sync diff
    [ "$status" -eq 0 ]
    [[ "$output" == *"plugins.list (mergeable)"* ]]
    [[ "$output" == *"added locally"* ]]
    [[ "$output" == *"pluginC@market"* ]]
    [[ "$output" == *"added remotely"* ]]
    [[ "$output" == *"pluginD@market"* ]]
    [[ "$output" == *"merge result"* ]]
}

@test "diff shows plugins.list removal preview" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$REMOTE_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"
    printf "pluginA@market\npluginB@market\n" > "$BASE_DIR/plugins.list"
    printf "pluginA@market\n" > "$LOCAL_DIR/plugins.list"
    printf "pluginA@market\npluginB@market\n" > "$REMOTE_DIR/plugins.list"
    run bash ./claude-sync diff
    [ "$status" -eq 0 ]
    [[ "$output" == *"plugins.list (mergeable)"* ]]
    [[ "$output" == *"removed locally"* ]]
    [[ "$output" == *"pluginB@market"* ]]
}

@test "diff hides plugins.list when clean" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$REMOTE_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"
    printf "pluginA@market\n" > "$LOCAL_DIR/plugins.list"
    printf "pluginA@market\n" > "$REMOTE_DIR/plugins.list"
    run bash ./claude-sync diff
    [ "$status" -eq 0 ]
    [[ "$output" != *"plugins.list"* ]]
}

@test "diff shows plugins.list no-base union preview" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$REMOTE_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"
    printf "pluginA@market\n" > "$LOCAL_DIR/plugins.list"
    printf "pluginB@market\n" > "$REMOTE_DIR/plugins.list"
    run bash ./claude-sync diff
    [ "$status" -eq 0 ]
    [[ "$output" == *"plugins.list (mergeable)"* ]]
    [[ "$output" == *"no base"* ]]
    [[ "$output" == *"local only"* ]]
    [[ "$output" == *"remote only"* ]]
}
