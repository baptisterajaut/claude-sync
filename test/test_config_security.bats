#!/usr/bin/env bats

load helpers

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "config parser loads standard key=value pairs" {
    cat > "$CONFIG_DIR/config" <<EOF
CLAUDE_DIR=$LOCAL_DIR
REMOTE_HOST=
REMOTE_PATH=$REMOTE_DIR
SSH_PORT=2222
EOF
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    [ "$CLAUDE_DIR" = "$LOCAL_DIR" ]
    [ "$REMOTE_HOST" = "" ]
    [ "$REMOTE_PATH" = "$REMOTE_DIR" ]
    [ "$SSH_PORT" = "2222" ]
}

@test "config parser handles quoted values" {
    cat > "$CONFIG_DIR/config" <<EOF
CLAUDE_DIR="$LOCAL_DIR"
REMOTE_HOST=""
REMOTE_PATH="$REMOTE_DIR"
EOF
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    [ "$CLAUDE_DIR" = "$LOCAL_DIR" ]
    [ "$REMOTE_PATH" = "$REMOTE_DIR" ]
}

@test "config parser ignores comments and blank lines" {
    cat > "$CONFIG_DIR/config" <<EOF
# This is a comment
CLAUDE_DIR=$LOCAL_DIR

REMOTE_HOST=
# Another comment
REMOTE_PATH=$REMOTE_DIR
EOF
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    [ "$CLAUDE_DIR" = "$LOCAL_DIR" ]
}

@test "config parser rejects unknown keys" {
    cat > "$CONFIG_DIR/config" <<EOF
CLAUDE_DIR=$LOCAL_DIR
REMOTE_HOST=
REMOTE_PATH=$REMOTE_DIR
MALICIOUS_KEY=pwned
EOF
    run bash -c "CLAUDE_SYNC_CONFIG_DIR='$CONFIG_DIR' source ./claude-sync --source-only && load_config"
    [[ "$output" == *"unknown config key"* ]]
}

@test "config parser does not execute shell commands in values" {
    # This is the critical security test
    local marker="/tmp/claude-sync-rce-test-$$"
    cat > "$CONFIG_DIR/config" <<HEREDOC
CLAUDE_DIR=$LOCAL_DIR
REMOTE_HOST=
REMOTE_PATH=$REMOTE_DIR
CLAUDE_DIR=\$(touch $marker)
HEREDOC
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config 2>/dev/null || true
    # The marker file must NOT exist — command was not executed
    [ ! -f "$marker" ]
}

@test "config parser handles tilde expansion in CLAUDE_DIR" {
    cat > "$CONFIG_DIR/config" <<EOF
CLAUDE_DIR=~/test-dir
REMOTE_HOST=
REMOTE_PATH=$REMOTE_DIR
EOF
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    [ "$CLAUDE_DIR" = "$HOME/test-dir" ]
}
