#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "exits with error when config file missing" {
    rm "$CONFIG_DIR/config"
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    run bash ./claude-sync sync
    [ "$status" -ne 0 ]
    [[ "$output" == *"config not found"* ]]
}

@test "loads config from CLAUDE_SYNC_CONFIG_DIR" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    run bash ./claude-sync --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"0.1.0"* ]]
}

@test "shows usage on no command" {
    run bash ./claude-sync
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "shows usage on --help" {
    run bash ./claude-sync --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "rejects unknown command" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    run bash ./claude-sync foobar
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown command"* ]]
}
