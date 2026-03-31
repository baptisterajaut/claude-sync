#!/usr/bin/env bash

setup_test_env() {
    export TEST_DIR
    TEST_DIR="$(mktemp -d)"
    export LOCAL_DIR="$TEST_DIR/local"
    export REMOTE_DIR="$TEST_DIR/remote"
    export CONFIG_DIR="$TEST_DIR/config"
    export BASE_DIR="$CONFIG_DIR/last-sync"
    export BACKUP_DIR="$CONFIG_DIR/backups"
    mkdir -p "$LOCAL_DIR" "$BASE_DIR" "$REMOTE_DIR" "$CONFIG_DIR" "$BACKUP_DIR"

    cat > "$CONFIG_DIR/config" <<EOF
REMOTE_HOST=
REMOTE_PATH=$REMOTE_DIR
CLAUDE_DIR=$LOCAL_DIR
EOF
}

teardown_test_env() {
    rm -rf "$TEST_DIR"
}
