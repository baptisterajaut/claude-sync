#!/usr/bin/env bats

load helpers

setup() {
    setup_test_env
    # Set up a local bare repo as "remote" for git tests
    export GIT_BARE="$TEST_DIR/bare.git"
    export GIT_CLONE="$TEST_DIR/repo"
    export GIT_SUBDIR="claude-sync-data"
    git init --bare "$GIT_BARE" >/dev/null 2>&1
    git clone "$GIT_BARE" "$GIT_CLONE" >/dev/null 2>&1
    mkdir -p "$GIT_CLONE/$GIT_SUBDIR"
    # Initial commit so origin/main exists
    touch "$GIT_CLONE/$GIT_SUBDIR/.gitkeep"
    git -C "$GIT_CLONE" add . >/dev/null 2>&1
    git -C "$GIT_CLONE" commit -m "init" >/dev/null 2>&1
    git -C "$GIT_CLONE" push >/dev/null 2>&1

    # Rewrite config for git backend
    cat > "$CONFIG_DIR/config" <<EOF
BACKEND=git
GIT_REPO=$GIT_CLONE
GIT_SUBDIR=$GIT_SUBDIR
CLAUDE_DIR=$LOCAL_DIR
EOF
}

teardown() { teardown_test_env; }

@test "git: load_config sets REMOTE_PATH from GIT_REPO+GIT_SUBDIR" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    [ "$REMOTE_PATH" = "$GIT_CLONE/$GIT_SUBDIR" ]
    [ "$REMOTE_HOST" = "" ]
    [ "$BACKEND" = "git" ]
}

@test "git: git_pre_sync fetches and checks out subdir" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    # Simulate a remote change: clone again, push a file
    local other="$TEST_DIR/other"
    git clone "$GIT_BARE" "$other" >/dev/null 2>&1
    echo "remote content" > "$other/$GIT_SUBDIR/CLAUDE.md"
    git -C "$other" add . >/dev/null 2>&1
    git -C "$other" commit -m "add file" >/dev/null 2>&1
    git -C "$other" push >/dev/null 2>&1
    # Our clone doesn't have it yet
    [ ! -f "$GIT_CLONE/$GIT_SUBDIR/CLAUDE.md" ]
    # After pre_sync, it should
    git_pre_sync
    [ -f "$GIT_CLONE/$GIT_SUBDIR/CLAUDE.md" ]
    [ "$(cat "$GIT_CLONE/$GIT_SUBDIR/CLAUDE.md")" = "remote content" ]
}

@test "git: git_pre_sync fails on dirty working tree" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "dirty" > "$GIT_CLONE/$GIT_SUBDIR/dirty.txt"
    run git_pre_sync
    [ "$status" -ne 0 ]
    [[ "$output" == *"uncommitted changes"* ]]
}

@test "git: git_post_sync commits and pushes changes" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "new file" > "$GIT_CLONE/$GIT_SUBDIR/test.md"
    git_post_sync
    # Verify it was pushed: clone fresh and check
    local verify="$TEST_DIR/verify"
    git clone "$GIT_BARE" "$verify" >/dev/null 2>&1
    [ "$(cat "$verify/$GIT_SUBDIR/test.md")" = "new file" ]
}

@test "git: git_post_sync does nothing when no changes" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    local before
    before=$(git -C "$GIT_CLONE" rev-parse HEAD)
    git_post_sync
    local after
    after=$(git -C "$GIT_CLONE" rev-parse HEAD)
    [ "$before" = "$after" ]
}

@test "git: full sync pushes local changes to git repo" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "my config" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    # Verify pushed to bare repo
    local verify="$TEST_DIR/verify"
    git clone "$GIT_BARE" "$verify" >/dev/null 2>&1
    [ "$(cat "$verify/$GIT_SUBDIR/CLAUDE.md")" = "my config" ]
    # Base should be updated
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "my config" ]
}

@test "git: full sync pulls remote changes" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    # Push a file from another "machine"
    local other="$TEST_DIR/other"
    git clone "$GIT_BARE" "$other" >/dev/null 2>&1
    echo "from other" > "$other/$GIT_SUBDIR/CLAUDE.md"
    git -C "$other" add . >/dev/null 2>&1
    git -C "$other" commit -m "add" >/dev/null 2>&1
    git -C "$other" push >/dev/null 2>&1
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "from other" ]
}

@test "git: sync detects conflict same as rsync mode" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "base" > "$LOCAL_DIR/CLAUDE.md"
    echo "base" > "$BASE_DIR/CLAUDE.md"
    # Push different version from another machine
    echo "base" > "$GIT_CLONE/$GIT_SUBDIR/CLAUDE.md"
    git -C "$GIT_CLONE" add . >/dev/null 2>&1
    git -C "$GIT_CLONE" commit -m "base" >/dev/null 2>&1
    git -C "$GIT_CLONE" push >/dev/null 2>&1
    local other="$TEST_DIR/other"
    git clone "$GIT_BARE" "$other" >/dev/null 2>&1
    echo "remote change" > "$other/$GIT_SUBDIR/CLAUDE.md"
    git -C "$other" add . >/dev/null 2>&1
    git -C "$other" commit -m "change" >/dev/null 2>&1
    git -C "$other" push >/dev/null 2>&1
    # Local also changed
    echo "local change" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -ne 0 ]
    [[ "$output" == *"CONFLICT"* ]]
    # Both sides untouched
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "local change" ]
}

@test "git: resolve pushes resolved files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "base" > "$LOCAL_DIR/CLAUDE.md"
    echo "base" > "$BASE_DIR/CLAUDE.md"
    echo "base" > "$GIT_CLONE/$GIT_SUBDIR/CLAUDE.md"
    git -C "$GIT_CLONE" add . >/dev/null 2>&1
    git -C "$GIT_CLONE" commit -m "base" >/dev/null 2>&1
    git -C "$GIT_CLONE" push >/dev/null 2>&1
    local other="$TEST_DIR/other"
    git clone "$GIT_BARE" "$other" >/dev/null 2>&1
    echo "remote" > "$other/$GIT_SUBDIR/CLAUDE.md"
    git -C "$other" add . >/dev/null 2>&1
    git -C "$other" commit -m "change" >/dev/null 2>&1
    git -C "$other" push >/dev/null 2>&1
    echo "merged" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync resolve CLAUDE.md
    [ "$status" -eq 0 ]
    # Verify resolved version in git
    local verify="$TEST_DIR/verify"
    git clone "$GIT_BARE" "$verify" >/dev/null 2>&1
    [ "$(cat "$verify/$GIT_SUBDIR/CLAUDE.md")" = "merged" ]
}

@test "git: deletion propagates to remote repo" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    # Setup: file exists on both sides + base
    mkdir -p "$LOCAL_DIR" "$BASE_DIR"
    echo "content" > "$GIT_CLONE/$GIT_SUBDIR/to-delete.md"
    echo "content" > "$LOCAL_DIR/to-delete.md"
    echo "content" > "$BASE_DIR/to-delete.md"
    # Also have a file that stays (so there's always something to sync)
    echo "stays" > "$GIT_CLONE/$GIT_SUBDIR/CLAUDE.md"
    echo "stays" > "$LOCAL_DIR/CLAUDE.md"
    echo "stays" > "$BASE_DIR/CLAUDE.md"
    # Commit initial state to git
    git -C "$GIT_CLONE" add . >/dev/null 2>&1
    git -C "$GIT_CLONE" commit -m "initial" >/dev/null 2>&1
    git -C "$GIT_CLONE" push >/dev/null 2>&1
    # Delete locally
    rm "$LOCAL_DIR/to-delete.md"
    # Add to-delete.md to synclist
    echo "to-delete.md" > "$CONFIG_DIR/synclist"
    echo "CLAUDE.md" >> "$CONFIG_DIR/synclist"
    # Sync
    run bash ./claude-sync sync
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deleted remote"* ]]
    # Verify file is gone from remote/working tree
    [ ! -f "$GIT_CLONE/$GIT_SUBDIR/to-delete.md" ]
    # Verify file is gone from git history (committed)
    local git_files
    git_files=$(git -C "$GIT_CLONE" ls-files "$GIT_SUBDIR")
    [[ "$git_files" != *"to-delete.md"* ]]
}

@test "git: status does not fetch (read-only)" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"
    echo "same" > "$GIT_CLONE/$GIT_SUBDIR/CLAUDE.md"
    git -C "$GIT_CLONE" add . >/dev/null 2>&1
    git -C "$GIT_CLONE" commit -m "same" >/dev/null 2>&1
    git -C "$GIT_CLONE" push >/dev/null 2>&1
    # Push a change from another machine
    local other="$TEST_DIR/other"
    git clone "$GIT_BARE" "$other" >/dev/null 2>&1
    echo "changed" > "$other/$GIT_SUBDIR/CLAUDE.md"
    git -C "$other" add . >/dev/null 2>&1
    git -C "$other" commit -m "change" >/dev/null 2>&1
    git -C "$other" push >/dev/null 2>&1
    # Status should still show clean (no fetch)
    run bash ./claude-sync status
    [ "$status" -eq 0 ]
    [[ "$output" == *"clean"* ]]
}
