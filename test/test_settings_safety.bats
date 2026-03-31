#!/usr/bin/env bats

load helpers

setup() {
    setup_test_env
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    # Add plugins.exclude
    echo "local-only-plugin@marketplace" > "$CONFIG_DIR/plugins.exclude"
    # synclist must include settings.json
    echo "settings.json" > "$CONFIG_DIR/synclist"
}

teardown() {
    teardown_test_env
}

@test "settings.json is never modified during push" {
    # Setup: local settings.json has an excluded plugin + a new setting (triggers push)
    cat > "$LOCAL_DIR/settings.json" <<'SETTINGS'
{
  "enabledPlugins": {
    "shared-plugin@marketplace": {"enabled": true},
    "local-only-plugin@marketplace": {"enabled": true}
  },
  "otherSetting": "new-value"
}
SETTINGS
    # Base has old value (so local differs from base = push scenario)
    cat > "$BASE_DIR/settings.json" <<'BASESETTINGS'
{
  "enabledPlugins": {
    "shared-plugin@marketplace": {"enabled": true}
  },
  "otherSetting": "old-value"
}
BASESETTINGS
    # Remote matches base (no remote changes)
    cp "$BASE_DIR/settings.json" "$REMOTE_DIR/settings.json"

    # Record the original content
    local original
    original=$(cat "$LOCAL_DIR/settings.json")

    run bash ./claude-sync sync
    echo "$output"
    [ "$status" -eq 0 ]

    # The LOCAL settings.json must still have the excluded plugin
    local after
    after=$(cat "$LOCAL_DIR/settings.json")
    [ "$original" = "$after" ]

    # The REMOTE settings.json should NOT have the excluded plugin
    if command -v jq >/dev/null 2>&1; then
        local remote_keys
        remote_keys=$(jq -r '.enabledPlugins | keys[]' "$REMOTE_DIR/settings.json" 2>/dev/null)
        [[ "$remote_keys" != *"local-only-plugin"* ]]
        [[ "$remote_keys" == *"shared-plugin"* ]]
    fi
}

@test "settings.json survives interrupted push" {
    # This test verifies that even if batch_push fails,
    # settings.json is not left in a filtered state
    cat > "$LOCAL_DIR/settings.json" <<'SETTINGS'
{
  "enabledPlugins": {
    "shared-plugin@marketplace": {"enabled": true},
    "local-only-plugin@marketplace": {"enabled": true}
  },
  "otherSetting": "new-value"
}
SETTINGS
    # Base has old value so local differs => push
    cat > "$BASE_DIR/settings.json" <<'BASESETTINGS'
{
  "enabledPlugins": {
    "shared-plugin@marketplace": {"enabled": true}
  },
  "otherSetting": "old-value"
}
BASESETTINGS
    cp "$BASE_DIR/settings.json" "$REMOTE_DIR/settings.json"

    local original
    original=$(cat "$LOCAL_DIR/settings.json")

    # Make remote settings.json read-only to force cp failure during push
    chmod 444 "$REMOTE_DIR/settings.json"

    run bash ./claude-sync sync
    # Sync may fail, that's expected

    # Restore permissions for cleanup
    chmod 644 "$REMOTE_DIR/settings.json"

    # The critical assertion: local settings.json must be UNCHANGED
    local after
    after=$(cat "$LOCAL_DIR/settings.json")
    [ "$original" = "$after" ]
}
