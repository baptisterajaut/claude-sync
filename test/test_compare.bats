#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "decide_action: all same -> clean" {
    source ./claude-sync --source-only
    result=$(decide_action "abc123" "abc123" "abc123")
    [ "$result" = "clean" ]
}

@test "decide_action: local changed, remote same as base -> push" {
    source ./claude-sync --source-only
    result=$(decide_action "new111" "abc123" "abc123")
    [ "$result" = "push" ]
}

@test "decide_action: remote changed, local same as base -> pull" {
    source ./claude-sync --source-only
    result=$(decide_action "abc123" "abc123" "new222")
    [ "$result" = "pull" ]
}

@test "decide_action: both changed same way -> update-base" {
    source ./claude-sync --source-only
    result=$(decide_action "new111" "abc123" "new111")
    [ "$result" = "update-base" ]
}

@test "decide_action: both changed differently -> conflict" {
    source ./claude-sync --source-only
    result=$(decide_action "new111" "abc123" "new222")
    [ "$result" = "conflict" ]
}

@test "decide_action: local deleted, remote same -> delete-remote" {
    source ./claude-sync --source-only
    result=$(decide_action "ABSENT" "abc123" "abc123")
    [ "$result" = "delete-remote" ]
}

@test "decide_action: remote deleted, local same -> delete-local" {
    source ./claude-sync --source-only
    result=$(decide_action "abc123" "abc123" "ABSENT")
    [ "$result" = "delete-local" ]
}

@test "decide_action: both deleted -> delete-base" {
    source ./claude-sync --source-only
    result=$(decide_action "ABSENT" "abc123" "ABSENT")
    [ "$result" = "delete-base" ]
}

@test "decide_action: local deleted, remote changed -> conflict" {
    source ./claude-sync --source-only
    result=$(decide_action "ABSENT" "abc123" "new222")
    [ "$result" = "conflict" ]
}

@test "decide_action: remote deleted, local changed -> conflict" {
    source ./claude-sync --source-only
    result=$(decide_action "new111" "abc123" "ABSENT")
    [ "$result" = "conflict" ]
}

@test "decide_action: new local, no base, no remote -> push-new" {
    source ./claude-sync --source-only
    result=$(decide_action "new111" "ABSENT" "ABSENT")
    [ "$result" = "push-new" ]
}

@test "decide_action: no local, no base, new remote -> pull-new" {
    source ./claude-sync --source-only
    result=$(decide_action "ABSENT" "ABSENT" "new222")
    [ "$result" = "pull-new" ]
}

@test "decide_action: new on both sides, same content -> create-base" {
    source ./claude-sync --source-only
    result=$(decide_action "same11" "ABSENT" "same11")
    [ "$result" = "create-base" ]
}

@test "decide_action: new on both sides, different content -> conflict" {
    source ./claude-sync --source-only
    result=$(decide_action "new111" "ABSENT" "new222")
    [ "$result" = "conflict" ]
}

@test "decide_action: all absent -> clean" {
    source ./claude-sync --source-only
    result=$(decide_action "ABSENT" "ABSENT" "ABSENT")
    [ "$result" = "clean" ]
}
