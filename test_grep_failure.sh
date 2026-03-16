#!/usr/bin/env bash
set -euo pipefail

# Setup mocks
TEST_DIR=$(mktemp -d)
CONFIG_DIR="$TEST_DIR/config"
mkdir -p "$CONFIG_DIR"
export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
export CONFIG_FILE="$CONFIG_DIR/config"

# Create a config file to satisfy load_config check
touch "$CONFIG_FILE"

# Mock the script functions by sourcing
# We need to temporarily disable the 'main' execution at the bottom of claude-sync
# but since we can't easily modify it, we'll just source it and hope the "if --source-only" works.
# The script has `if [[ "${1:-}" == "--source-only" ]]; then return 0 ...` so we use that.

source ./claude-sync --source-only

# Create a synclist with only comments
echo "# This is a comment" > "$CONFIG_DIR/synclist"
echo "" >> "$CONFIG_DIR/synclist"

echo "Testing load_synclist with only comments..."
if output=$(load_synclist); then
    echo "Success. Output: '$output'"
else
    echo "Failed (exit code $?)"
fi

# Create empty synclist
echo -n "" > "$CONFIG_DIR/synclist"
echo "Testing load_synclist with empty file..."
if output=$(load_synclist); then
     echo "Success. Output: '$output'"
else
     echo "Failed (exit code $?)"
fi

rm -rf "$TEST_DIR"
