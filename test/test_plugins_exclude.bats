#!/usr/bin/env bats

load helpers

setup() {
    setup_test_env
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$REMOTE_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"

    # Create installed_plugins.json so generate_plugins_list() runs
    mkdir -p "$LOCAL_DIR/plugins"
}

teardown() { teardown_test_env; }

# --- generate_plugins_list with exclude ---

@test "plugins exclude: excluded plugin not in plugins.list" {
    cat > "$LOCAL_DIR/plugins/installed_plugins.json" <<'EOF'
[{"name": "pluginA@market"}, {"name": "pluginB@market"}, {"name": "pluginC@market"}]
EOF
    echo "pluginB@market" > "$CONFIG_DIR/plugins.exclude"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    grep -q "pluginA@market" "$LOCAL_DIR/plugins.list"
    grep -q "pluginC@market" "$LOCAL_DIR/plugins.list"
    ! grep -q "pluginB@market" "$LOCAL_DIR/plugins.list"
}

@test "plugins exclude: multiple plugins excluded" {
    cat > "$LOCAL_DIR/plugins/installed_plugins.json" <<'EOF'
[{"name": "pluginA@market"}, {"name": "pluginB@market"}, {"name": "pluginC@market"}]
EOF
    printf "pluginA@market\npluginC@market\n" > "$CONFIG_DIR/plugins.exclude"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    grep -q "pluginB@market" "$LOCAL_DIR/plugins.list"
    ! grep -q "pluginA@market" "$LOCAL_DIR/plugins.list"
    ! grep -q "pluginC@market" "$LOCAL_DIR/plugins.list"
}

@test "plugins exclude: comments and blank lines ignored" {
    cat > "$LOCAL_DIR/plugins/installed_plugins.json" <<'EOF'
[{"name": "pluginA@market"}, {"name": "pluginB@market"}]
EOF
    printf "# this is a comment\n\npluginB@market\n\n# another comment\n" > "$CONFIG_DIR/plugins.exclude"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    grep -q "pluginA@market" "$LOCAL_DIR/plugins.list"
    ! grep -q "pluginB@market" "$LOCAL_DIR/plugins.list"
}

@test "plugins exclude: no exclude file — all plugins in list" {
    cat > "$LOCAL_DIR/plugins/installed_plugins.json" <<'EOF'
[{"name": "pluginA@market"}, {"name": "pluginB@market"}]
EOF
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    grep -q "pluginA@market" "$LOCAL_DIR/plugins.list"
    grep -q "pluginB@market" "$LOCAL_DIR/plugins.list"
}

@test "plugins exclude: empty exclude file — all plugins in list" {
    cat > "$LOCAL_DIR/plugins/installed_plugins.json" <<'EOF'
[{"name": "pluginA@market"}, {"name": "pluginB@market"}]
EOF
    touch "$CONFIG_DIR/plugins.exclude"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    grep -q "pluginA@market" "$LOCAL_DIR/plugins.list"
    grep -q "pluginB@market" "$LOCAL_DIR/plugins.list"
}

# --- exclude + sync interaction ---

@test "plugins exclude: excluded plugin not pushed to remote" {
    cat > "$LOCAL_DIR/plugins/installed_plugins.json" <<'EOF'
[{"name": "pluginA@market"}, {"name": "pluginB@market"}]
EOF
    echo "pluginB@market" > "$CONFIG_DIR/plugins.exclude"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    # Remote should only have pluginA
    grep -q "pluginA@market" "$REMOTE_DIR/plugins.list"
    ! grep -q "pluginB@market" "$REMOTE_DIR/plugins.list"
}

@test "plugins exclude: remote plugin pulled even with local exclude" {
    cat > "$LOCAL_DIR/plugins/installed_plugins.json" <<'EOF'
[{"name": "pluginA@market"}]
EOF
    echo "pluginA@market" > "$CONFIG_DIR/plugins.exclude"
    # Remote has pluginB
    printf "pluginB@market\n" > "$REMOTE_DIR/plugins.list"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    # pluginB from remote should be in local list (not excluded)
    grep -q "pluginB@market" "$LOCAL_DIR/plugins.list"
    # pluginA is excluded from generation, should not appear
    ! grep -q "pluginA@market" "$LOCAL_DIR/plugins.list"
}

# --- install-local command ---

@test "install-local: adds plugin to exclude file and installs" {
    # Mock claude CLI
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/bin/bash
echo "mock-installed: $*"
MOCK
    chmod +x "$TEST_DIR/bin/claude"
    export PATH="$TEST_DIR/bin:$PATH"

    run bash ./claude-sync install-local "my-plugin@marketplace"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Excluded from sync"* ]]
    [[ "$output" == *"mock-installed"* ]]
    grep -qFx "my-plugin@marketplace" "$CONFIG_DIR/plugins.exclude"
}

@test "install-local: does not duplicate in exclude file" {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/bin/bash
echo "mock-installed: $*"
MOCK
    chmod +x "$TEST_DIR/bin/claude"
    export PATH="$TEST_DIR/bin:$PATH"

    echo "my-plugin@marketplace" > "$CONFIG_DIR/plugins.exclude"
    run bash ./claude-sync install-local "my-plugin@marketplace"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already excluded"* ]]
    # Should still only have one line
    [ "$(grep -cFx "my-plugin@marketplace" "$CONFIG_DIR/plugins.exclude")" -eq 1 ]
}

@test "install-local: fails without argument" {
    run bash ./claude-sync install-local
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage"* ]]
}

@test "install-local: fails without claude CLI" {
    # Ensure claude is not in PATH
    export PATH="/usr/bin:/bin"
    run bash ./claude-sync install-local "my-plugin@marketplace"
    [ "$status" -ne 0 ]
    [[ "$output" == *"claude CLI not found"* ]]
    # But exclude file should still have been written
    grep -qFx "my-plugin@marketplace" "$CONFIG_DIR/plugins.exclude"
}
