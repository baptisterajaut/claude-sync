#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

# --- Fix 1: Path validation ---

@test "validate_filepath rejects path with .." {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    run validate_filepath "../../.bashrc"
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing unsafe path"* ]]
}

@test "validate_filepath rejects absolute path" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    run validate_filepath "/etc/passwd"
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing unsafe path"* ]]
}

@test "validate_filepath accepts normal paths" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    run validate_filepath "CLAUDE.md"
    [ "$status" -eq 0 ]
    run validate_filepath "skills/foo/bar.md"
    [ "$status" -eq 0 ]
}

@test "batch_pull rejects traversal path" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config

    # We need REMOTE_PATH and CLAUDE_DIR in different subtrees so that
    # $REMOTE_PATH/../../payload exists but $CLAUDE_DIR/../../payload does not.
    # Restructure: put remote under $TEST_DIR/deep/nested/remote
    local deep_remote="$TEST_DIR/deep/nested/remote"
    mkdir -p "$deep_remote"
    # Update REMOTE_PATH for this test
    REMOTE_PATH="$deep_remote"

    # Place a file so that $REMOTE_PATH/../../payload = $TEST_DIR/deep/payload
    echo "malicious payload" > "$TEST_DIR/deep/payload"

    # The canary: if batch_pull copies it, it writes to $CLAUDE_DIR/../../payload
    # CLAUDE_DIR is $TEST_DIR/local, so that's $TEST_DIR/../payload — different path
    # Make sure the canary doesn't exist
    local canary_path
    canary_path="$(cd "$LOCAL_DIR/.." && pwd)/payload"
    rm -f "$canary_path"

    # Create a pull list with a traversal path
    local list_file
    list_file=$(mktemp)
    echo "../../payload" > "$list_file"

    # batch_pull should skip the traversal path (stderr may contain warning)
    batch_pull "$list_file" 2>/dev/null || true
    rm -f "$list_file"

    # The file must NOT have appeared at the traversal destination relative to CLAUDE_DIR
    [ ! -f "$canary_path" ]
}

@test "build_file_union excludes traversal paths" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config

    # Create a normal file in REMOTE_DIR
    echo "normal" > "$REMOTE_DIR/CLAUDE.md"

    # Create a file that would appear as a traversal path via enumerate_files
    # We create a directory named ".." inside REMOTE_DIR to simulate
    mkdir -p "$REMOTE_DIR/../traversal"
    echo "evil" > "$REMOTE_DIR/../traversal/file.txt"

    # Also plant a file that would look like an absolute path if the enum were broken
    # We test that build_file_union output contains no paths with ..
    local synclist="CLAUDE.md"
    local union
    union=$(build_file_union "$synclist")

    # The union should not contain any paths with ..
    if echo "$union" | grep -q '\.\.'; then
        echo "FAIL: union contains traversal path"
        echo "$union"
        return 1
    fi
}

# --- Fix 2: Filename escaping in remote_finalize ---

@test "remote_finalize local mode handles filenames with special chars" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config

    # Create a file with spaces in the name
    echo "hello world" > "$REMOTE_DIR/file with spaces.md"

    # Write the filename to a verify file
    local verify_file
    verify_file=$(mktemp)
    echo "file with spaces.md" > "$verify_file"

    # remote_finalize should return md5sum output for the file
    local output
    output=$(remote_finalize "$verify_file" "")
    rm -f "$verify_file"

    # Verify it contains the filename and a valid md5sum
    [[ "$output" == *"file with spaces.md"* ]]
    # The md5sum should be a 32-char hex string
    local hash
    hash=$(echo "$output" | grep "file with spaces.md" | awk '{print $1}')
    [ "${#hash}" -eq 32 ]
}

@test "remote_finalize local mode handles quoted filenames" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config

    # Create a file with a quote in the name
    local fname='file'\''quote.md'
    echo "quoted content" > "$REMOTE_DIR/$fname"

    # Write the filename to a verify file
    local verify_file
    verify_file=$(mktemp)
    echo "$fname" > "$verify_file"

    # remote_finalize should return md5sum output for the file
    local output
    output=$(remote_finalize "$verify_file" "")
    rm -f "$verify_file"

    # Verify it contains the filename and a valid md5sum
    [[ "$output" == *"$fname"* ]]
}

@test "batch_delete_local rejects traversal path" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config

    # Create a file that $CLAUDE_DIR/../../important.txt would resolve to
    local resolved_target
    resolved_target="$(cd "$LOCAL_DIR/../.." && pwd)/important.txt"
    echo "important file" > "$resolved_target"

    # Try to delete via traversal
    batch_delete_local "../../important.txt" 2>/dev/null || true

    # The file outside CLAUDE_DIR must still exist
    [ -f "$resolved_target" ]
    rm -f "$resolved_target"
}
