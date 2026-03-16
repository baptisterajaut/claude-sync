#!/usr/bin/env bash
set -euo pipefail

# Setup mocks
TEST_DIR=$(mktemp -d)
export CLAUDE_DIR="$TEST_DIR/local"
export LAST_SYNC_DIR="$TEST_DIR/base"
REMOTE_DIR="$TEST_DIR/remote"

mkdir -p "$CLAUDE_DIR" "$LAST_SYNC_DIR" "$REMOTE_DIR"

# Source the script functions
source ./claude-sync --source-only

# Setup test case: pluginB removed locally
printf "pluginA@market\npluginB@market\n" > "$LAST_SYNC_DIR/plugins.list"
printf "pluginA@market\n" > "$CLAUDE_DIR/plugins.list"
printf "pluginA@market\npluginB@market\n" > "$REMOTE_DIR/plugins.list"

echo "=== Testing merge_plugins_list ==="
remote_file="$REMOTE_DIR/plugins.list"

# Call the function and capture output
echo "Calling merge_plugins_list..."
merge_result=$(merge_plugins_list "$remote_file")
EXIT_CODE=$?

echo "Exit code: $EXIT_CODE"
echo "Output (merge_result): '$merge_result'"
echo "Output length: ${#merge_result}"

# Debug hex dump to see hidden chars
echo -n "$merge_result" | od -t x1

# Check if it matches 'conflict'
if [[ "$merge_result" == "conflict" ]]; then
    echo "MATCH: 'conflict'"
else
    echo "NO MATCH: 'conflict'"
fi

# Clean up
rm -rf "$TEST_DIR"
