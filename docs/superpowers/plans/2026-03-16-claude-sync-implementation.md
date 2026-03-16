# claude-sync Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a bash script that safely syncs Claude Code config files across machines via rsync over SSH, with three-way conflict detection.

**Architecture:** Single bash script (`claude-sync`) with commands `sync`, `status`, `diff`, `update`. Config in `~/.config/claude-sync/`. Three-way comparison using a `last-sync/` snapshot as base. Claude Code skills for init and conflict resolution.

**Tech Stack:** Bash (>= 4.0), rsync, ssh, md5sum, bats-core (testing)

**Spec:** `docs/superpowers/specs/2026-03-16-claude-sync-design.md`

---

## Chunk 1: Script Foundation + Test Harness

### Task 1: Test harness and repo setup

**Files:**
- Create: `test/helpers.bash`
- Create: `test/test_config.bats`
- Create: `claude-sync`

The test harness creates fake local/base/remote dirs in `/tmp` to simulate the full sync environment without SSH. All tests use these temp dirs.

- [ ] **Step 1: Init git repo**

```bash
cd ~/claude-syncer
git init
```

- [ ] **Step 2: Create test helper**

Create `test/helpers.bash` — sets up temp directories simulating the three-way environment:

```bash
#!/usr/bin/env bash

# Called by bats setup/teardown

setup_test_env() {
    export TEST_DIR
    TEST_DIR="$(mktemp -d)"
    export LOCAL_DIR="$TEST_DIR/local"      # simulates ~/.claude
    export REMOTE_DIR="$TEST_DIR/remote"    # simulates remote server
    export CONFIG_DIR="$TEST_DIR/config"    # simulates ~/.config/claude-sync
    export BASE_DIR="$CONFIG_DIR/last-sync" # must match LAST_SYNC_DIR in the script
    mkdir -p "$LOCAL_DIR" "$BASE_DIR" "$REMOTE_DIR" "$CONFIG_DIR"

    # Write config that points to local dirs (no SSH needed)
    cat > "$CONFIG_DIR/config" <<EOF
REMOTE_HOST=""
REMOTE_PATH="$REMOTE_DIR"
CLAUDE_DIR="$LOCAL_DIR"
REPO_DIR="$TEST_DIR/repo"
EOF
}

teardown_test_env() {
    rm -rf "$TEST_DIR"
}
```

- [ ] **Step 3: Create script skeleton**

Create `claude-sync` with shebang, `set -euo pipefail`, version, usage, config loading, and command dispatch:

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
CONFIG_DIR="${CLAUDE_SYNC_CONFIG_DIR:-$HOME/.config/claude-sync}"
CONFIG_FILE="$CONFIG_DIR/config"
LOCK_FILE="$CONFIG_DIR/.lock"
LAST_SYNC_DIR="$CONFIG_DIR/last-sync"
BACKUP_DIR="$CONFIG_DIR/backups"

# Default synclist (overridable by $CONFIG_DIR/synclist)
DEFAULT_SYNCLIST="CLAUDE.md
settings.json
skills/
agents/
plugins/installed_plugins.json
plugins/known_marketplaces.json"

# Excluded from sync even if inside a synced directory
EXCLUDE_PATTERNS="skills/claude-sync/"

DRY_RUN=false

usage() {
    cat <<EOF
claude-sync $VERSION — sync Claude Code config across machines

Usage: claude-sync <command> [options]

Commands:
    sync      Bidirectional safe sync with conflict detection
    status    Show per-file sync status
    diff      Show diff between local and remote
    update    Self-update from git repo

Options:
    -n, --dry-run   Preview actions without applying (sync, update)
    -h, --help      Show this help
    -v, --version   Show version
EOF
}

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "error: config not found at $CONFIG_FILE" >&2
        echo "Run /claude-sync:init to set up." >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    # Validate required vars
    : "${REMOTE_PATH:?REMOTE_PATH not set in $CONFIG_FILE}"
    : "${CLAUDE_DIR:?CLAUDE_DIR not set in $CONFIG_FILE}"
}

load_synclist() {
    local synclist_file="$CONFIG_DIR/synclist"
    if [[ -f "$synclist_file" ]]; then
        grep -v '^#' "$synclist_file" | grep -v '^$'
    else
        echo "$DEFAULT_SYNCLIST"
    fi
}

# Parse global options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        -v|--version) echo "claude-sync $VERSION"; exit 0 ;;
        -*) echo "error: unknown option $1" >&2; exit 1 ;;
        *) break ;;
    esac
done

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
    sync)   load_config; cmd_sync "$@" ;;
    status) load_config; cmd_status "$@" ;;
    diff)   load_config; cmd_diff "$@" ;;
    update) load_config; cmd_update "$@" ;;
    "")     usage; exit 1 ;;
    *)      echo "error: unknown command '$COMMAND'" >&2; exit 1 ;;
esac
```

- [ ] **Step 4: Write config loading tests**

Create `test/test_config.bats`:

```bash
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
    # sync will fail later (no cmd_sync yet) but config should load
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
```

- [ ] **Step 5: Install bats-core if needed and run tests**

```bash
# Check if bats is available
which bats || sudo apt-get install -y bats
bats test/test_config.bats
```

Expected: tests for `--version`, `--help`, missing config, unknown command pass. Tests calling `sync` fail (function not defined yet — that's expected, those tests aren't written yet).

- [ ] **Step 6: Commit**

```bash
git add claude-sync test/
git commit -m "feat: script skeleton with arg parsing, config loading, test harness"
```

---

### Task 2: Lock mechanism

**Files:**
- Modify: `claude-sync`
- Create: `test/test_lock.bats`

- [ ] **Step 1: Write lock tests**

Create `test/test_lock.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "acquire_local_lock creates lock file with PID and timestamp" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    LOCK_FILE="$CONFIG_DIR/.lock"
    acquire_local_lock
    [ -f "$LOCK_FILE" ]
    # lock file contains PID and timestamp
    read -r pid ts < "$LOCK_FILE"
    [ "$pid" = "$$" ]
    [ -n "$ts" ]
    release_local_lock
}

@test "acquire_local_lock fails if lock held by running process" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    LOCK_FILE="$CONFIG_DIR/.lock"
    # Create a lock with our own PID (simulates held lock)
    echo "$$ $(date +%s)" > "$LOCK_FILE"
    run acquire_local_lock
    [ "$status" -ne 0 ]
    [[ "$output" == *"already running"* ]]
}

@test "acquire_local_lock reclaims stale lock from dead PID" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    LOCK_FILE="$CONFIG_DIR/.lock"
    # PID 99999 is almost certainly not running
    echo "99999 $(date +%s)" > "$LOCK_FILE"
    acquire_local_lock
    read -r pid _ < "$LOCK_FILE"
    [ "$pid" = "$$" ]
    release_local_lock
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bats test/test_lock.bats
```

Expected: FAIL (functions not defined).

- [ ] **Step 3: Implement lock functions**

Add to `claude-sync`, before the argument parsing section:

```bash
# --- Locking ---

acquire_local_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        read -r existing_pid _ < "$LOCK_FILE"
        if kill -0 "$existing_pid" 2>/dev/null; then
            echo "error: claude-sync already running (PID $existing_pid)" >&2
            return 1
        fi
        echo "warning: reclaiming stale lock from PID $existing_pid" >&2
        rm -f "$LOCK_FILE"
    fi
    echo "$$ $(date +%s)" > "$LOCK_FILE"
    trap release_local_lock EXIT
}

release_local_lock() {
    rm -f "$LOCK_FILE"
}

# Remote lock is handled by remote_init() (SSH call 1) and
# remote_finalize() (SSH call 3). See Task 7 for implementation.
# release_remote_lock() is only used for error cleanup paths.

release_remote_lock() {
    if [[ -z "$REMOTE_HOST" ]]; then
        rm -f "$REMOTE_PATH/.claude-sync.lock"
    else
        ssh "$REMOTE_HOST" "rm -f \"$REMOTE_PATH/.claude-sync.lock\""
    fi
}
```

Also add `--source-only` support at the top of the argument parsing section for testing:

```bash
# Allow sourcing for tests
if [[ "${1:-}" == "--source-only" ]]; then
    return 0 2>/dev/null || exit 0
fi
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
bats test/test_lock.bats
```

Expected: all 3 pass.

- [ ] **Step 5: Commit**

```bash
git add claude-sync test/test_lock.bats
git commit -m "feat: local and remote lock mechanism with stale detection"
```

---

### Task 3: Synclist loading and file enumeration

**Files:**
- Modify: `claude-sync`
- Create: `test/test_synclist.bats`

- [ ] **Step 1: Write synclist tests**

Create `test/test_synclist.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "load_synclist returns defaults when no synclist file" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    result=$(load_synclist)
    [[ "$result" == *"CLAUDE.md"* ]]
    [[ "$result" == *"settings.json"* ]]
    [[ "$result" == *"skills/"* ]]
}

@test "load_synclist reads custom synclist file" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    cat > "$CONFIG_DIR/synclist" <<EOF
# custom list
CLAUDE.md
my-custom-file.txt
EOF
    source ./claude-sync --source-only
    result=$(load_synclist)
    [[ "$result" == *"CLAUDE.md"* ]]
    [[ "$result" == *"my-custom-file.txt"* ]]
    [[ "$result" != *"settings.json"* ]]
}

@test "enumerate_files expands directories to individual files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    # Create some files in LOCAL_DIR
    mkdir -p "$LOCAL_DIR/skills/grimoire"
    echo "test" > "$LOCAL_DIR/CLAUDE.md"
    echo "test" > "$LOCAL_DIR/skills/grimoire/SKILL.md"
    result=$(enumerate_files "$LOCAL_DIR" "CLAUDE.md
skills/")
    [[ "$result" == *"CLAUDE.md"* ]]
    [[ "$result" == *"skills/grimoire/SKILL.md"* ]]
}

@test "enumerate_files excludes claude-sync skills" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    mkdir -p "$LOCAL_DIR/skills/claude-sync" "$LOCAL_DIR/skills/grimoire"
    echo "test" > "$LOCAL_DIR/skills/claude-sync/init.md"
    echo "test" > "$LOCAL_DIR/skills/grimoire/SKILL.md"
    result=$(enumerate_files "$LOCAL_DIR" "skills/")
    [[ "$result" != *"skills/claude-sync/"* ]]
    [[ "$result" == *"skills/grimoire/SKILL.md"* ]]
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bats test/test_synclist.bats
```

- [ ] **Step 3: Implement enumerate_files**

Add to `claude-sync`:

```bash
# --- File enumeration ---

# Given a root dir and a synclist, expand directories to individual file paths.
# Filters out EXCLUDE_PATTERNS. Returns one relative path per line.
enumerate_files() {
    local root_dir="$1"
    local synclist="$2"

    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        local full_path="$root_dir/$entry"
        if [[ "$entry" == */ ]]; then
            # Directory entry — enumerate files inside
            if [[ -d "$full_path" ]]; then
                (cd "$root_dir" && find "$entry" -type f 2>/dev/null) | while IFS= read -r f; do
                    if ! is_excluded "$f"; then
                        echo "$f"
                    fi
                done
            fi
        else
            # Single file
            if [[ -f "$full_path" ]] && ! is_excluded "$entry"; then
                echo "$entry"
            fi
        fi
    done <<< "$synclist"
}

is_excluded() {
    local path="$1"
    local pattern
    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue
        if [[ "$path" == "$pattern"* ]]; then
            return 0
        fi
    done <<< "$EXCLUDE_PATTERNS"
    return 1
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
bats test/test_synclist.bats
```

- [ ] **Step 5: Commit**

```bash
git add claude-sync test/test_synclist.bats
git commit -m "feat: synclist loading and file enumeration with exclude patterns"
```

---

## Chunk 2: Three-Way Comparison Engine

### Task 4: Checksum computation

**Files:**
- Modify: `claude-sync`
- Create: `test/test_checksum.bats`

- [ ] **Step 1: Write checksum tests**

Create `test/test_checksum.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "compute_checksums returns md5 for existing files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    echo "hello" > "$LOCAL_DIR/CLAUDE.md"
    result=$(compute_local_checksums "$LOCAL_DIR" "CLAUDE.md")
    [[ "$result" == *"CLAUDE.md"* ]]
    # Should contain a 32-char hex hash
    hash=$(echo "$result" | awk '{print $1}')
    [ "${#hash}" -eq 32 ]
}

@test "compute_checksums returns ABSENT for missing files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    result=$(compute_local_checksums "$LOCAL_DIR" "CLAUDE.md")
    [[ "$result" == *"ABSENT"* ]]
    [[ "$result" == *"CLAUDE.md"* ]]
}

@test "fetch_all_remote_checksums fetches in one call and get_remote_checksum retrieves" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "world" > "$REMOTE_DIR/CLAUDE.md"
    mkdir -p "$REMOTE_DIR/skills/test"
    echo "skill" > "$REMOTE_DIR/skills/test/SKILL.md"
    fetch_all_remote_checksums
    # Should find both files
    result=$(get_remote_checksum "CLAUDE.md")
    hash=$(echo "$result" | awk '{print $1}')
    [ "${#hash}" -eq 32 ]
    result2=$(get_remote_checksum "skills/test/SKILL.md")
    hash2=$(echo "$result2" | awk '{print $1}')
    [ "${#hash2}" -eq 32 ]
    # Missing file should return ABSENT
    result3=$(get_remote_checksum "nonexistent.md")
    [[ "$result3" == "ABSENT"* ]]
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bats test/test_checksum.bats
```

- [ ] **Step 3: Implement checksum functions**

Add to `claude-sync`:

```bash
# --- Checksums ---

# Compute checksums for all files in a directory that match the synclist.
# Returns "HASH FILEPATH" per line, or "ABSENT FILEPATH" for files in
# the expected list but missing from disk.
# Usage: compute_local_checksums <root_dir> <expected_files_newline_separated>
compute_local_checksums() {
    local root_dir="$1"
    shift
    local files="$*"

    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue
        if [[ -f "$root_dir/$filepath" ]]; then
            local hash
            hash=$(md5sum "$root_dir/$filepath" | awk '{print $1}')
            echo "$hash $filepath"
        else
            echo "ABSENT $filepath"
        fi
    done <<< "$files"
}

# Remote checksum cache — populated by remote_init() (sync) or
# fetch_remote_checksums_readonly() (status, diff).
REMOTE_CHECKSUMS_CACHE=""

# Fetch remote checksums without locking (for read-only commands: status, diff).
# Single SSH call, no lock acquired.
fetch_remote_checksums_readonly() {
    if [[ -z "${REMOTE_HOST:-}" ]]; then
        REMOTE_CHECKSUMS_CACHE=$(cd "$REMOTE_PATH" 2>/dev/null && find . -type f -not -name ".claude-sync.lock" -exec md5sum {} + 2>/dev/null | sed 's| \./| |' || true)
    else
        REMOTE_CHECKSUMS_CACHE=$(ssh "$REMOTE_HOST" "cd \"$REMOTE_PATH\" 2>/dev/null && find . -type f -not -name \".claude-sync.lock\" -exec md5sum {} + 2>/dev/null | sed 's| \./| |'" || true)
    fi
}

# Look up a single file's checksum from the cached remote checksums.
# Returns "HASH FILEPATH" or "ABSENT FILEPATH".
get_remote_checksum() {
    local filepath="$1"
    local line
    line=$(echo "$REMOTE_CHECKSUMS_CACHE" | grep -F " $filepath" | head -1)
    if [[ -n "$line" ]]; then
        echo "$line"
    else
        echo "ABSENT $filepath"
    fi
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
bats test/test_checksum.bats
```

- [ ] **Step 5: Commit**

```bash
git add claude-sync test/test_checksum.bats
git commit -m "feat: checksum computation for local, base, and remote files"
```

---

### Task 5: Three-way comparison logic

**Files:**
- Modify: `claude-sync`
- Create: `test/test_compare.bats`

This is the core algorithm. For each file, given its 3 checksums, decide the action.

- [ ] **Step 1: Write comparison tests**

Create `test/test_compare.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "decide_action: all same → clean" {
    source ./claude-sync --source-only
    result=$(decide_action "abc123" "abc123" "abc123")
    [ "$result" = "clean" ]
}

@test "decide_action: local changed, remote same as base → push" {
    source ./claude-sync --source-only
    result=$(decide_action "new111" "abc123" "abc123")
    [ "$result" = "push" ]
}

@test "decide_action: remote changed, local same as base → pull" {
    source ./claude-sync --source-only
    result=$(decide_action "abc123" "abc123" "new222")
    [ "$result" = "pull" ]
}

@test "decide_action: both changed same way → update-base" {
    source ./claude-sync --source-only
    result=$(decide_action "new111" "abc123" "new111")
    [ "$result" = "update-base" ]
}

@test "decide_action: both changed differently → conflict" {
    source ./claude-sync --source-only
    result=$(decide_action "new111" "abc123" "new222")
    [ "$result" = "conflict" ]
}

@test "decide_action: local deleted, remote same → delete-remote" {
    source ./claude-sync --source-only
    result=$(decide_action "ABSENT" "abc123" "abc123")
    [ "$result" = "delete-remote" ]
}

@test "decide_action: remote deleted, local same → delete-local" {
    source ./claude-sync --source-only
    result=$(decide_action "abc123" "abc123" "ABSENT")
    [ "$result" = "delete-local" ]
}

@test "decide_action: both deleted → delete-base" {
    source ./claude-sync --source-only
    result=$(decide_action "ABSENT" "abc123" "ABSENT")
    [ "$result" = "delete-base" ]
}

@test "decide_action: local deleted, remote changed → conflict" {
    source ./claude-sync --source-only
    result=$(decide_action "ABSENT" "abc123" "new222")
    [ "$result" = "conflict" ]
}

@test "decide_action: remote deleted, local changed → conflict" {
    source ./claude-sync --source-only
    result=$(decide_action "new111" "abc123" "ABSENT")
    [ "$result" = "conflict" ]
}

@test "decide_action: new local, no base, no remote → push-new" {
    source ./claude-sync --source-only
    result=$(decide_action "new111" "ABSENT" "ABSENT")
    [ "$result" = "push-new" ]
}

@test "decide_action: no local, no base, new remote → pull-new" {
    source ./claude-sync --source-only
    result=$(decide_action "ABSENT" "ABSENT" "new222")
    [ "$result" = "pull-new" ]
}

@test "decide_action: new on both sides, same content → create-base" {
    source ./claude-sync --source-only
    result=$(decide_action "same11" "ABSENT" "same11")
    [ "$result" = "create-base" ]
}

@test "decide_action: new on both sides, different content → conflict" {
    source ./claude-sync --source-only
    result=$(decide_action "new111" "ABSENT" "new222")
    [ "$result" = "conflict" ]
}

@test "decide_action: all absent → clean" {
    source ./claude-sync --source-only
    result=$(decide_action "ABSENT" "ABSENT" "ABSENT")
    [ "$result" = "clean" ]
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bats test/test_compare.bats
```

- [ ] **Step 3: Implement decide_action**

Add to `claude-sync`:

```bash
# --- Three-way comparison ---

# decide_action LOCAL_HASH BASE_HASH REMOTE_HASH
# Returns one of: clean, push, pull, update-base, conflict,
#   delete-remote, delete-local, delete-base,
#   push-new, pull-new, create-base
decide_action() {
    local local_hash="$1" base_hash="$2" remote_hash="$3"

    # All absent — nothing to do
    if [[ "$local_hash" == "ABSENT" && "$base_hash" == "ABSENT" && "$remote_hash" == "ABSENT" ]]; then
        echo "clean"
        return
    fi

    # No base entry (new file cases)
    if [[ "$base_hash" == "ABSENT" ]]; then
        if [[ "$local_hash" != "ABSENT" && "$remote_hash" == "ABSENT" ]]; then
            echo "push-new"
        elif [[ "$local_hash" == "ABSENT" && "$remote_hash" != "ABSENT" ]]; then
            echo "pull-new"
        elif [[ "$local_hash" == "$remote_hash" ]]; then
            echo "create-base"
        else
            echo "conflict"
        fi
        return
    fi

    # Base exists — standard three-way
    local local_changed=false remote_changed=false
    [[ "$local_hash" != "$base_hash" ]] && local_changed=true
    [[ "$remote_hash" != "$base_hash" ]] && remote_changed=true

    if ! $local_changed && ! $remote_changed; then
        echo "clean"
    elif $local_changed && ! $remote_changed; then
        if [[ "$local_hash" == "ABSENT" ]]; then
            echo "delete-remote"
        else
            echo "push"
        fi
    elif ! $local_changed && $remote_changed; then
        if [[ "$remote_hash" == "ABSENT" ]]; then
            echo "delete-local"
        else
            echo "pull"
        fi
    else
        # Both changed
        if [[ "$local_hash" == "$remote_hash" ]]; then
            echo "update-base"
        else
            echo "conflict"
        fi
    fi
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
bats test/test_compare.bats
```

Expected: all 15 tests pass.

- [ ] **Step 5: Commit**

```bash
git add claude-sync test/test_compare.bats
git commit -m "feat: three-way comparison logic with all edge cases"
```

---

### Task 6: Status command

**Files:**
- Modify: `claude-sync`
- Create: `test/test_status.bats`

`status` ties together synclist → enumerate → checksums → decide. Read-only, no writes.

- [ ] **Step 1: Write status tests**

Create `test/test_status.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "status shows clean when all in sync" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "hello" > "$LOCAL_DIR/CLAUDE.md"
    echo "hello" > "$REMOTE_DIR/CLAUDE.md"
    echo "hello" > "$BASE_DIR/CLAUDE.md"
    # Minimal synclist for test
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    run bash ./claude-sync status
    [ "$status" -eq 0 ]
    [[ "$output" == *"clean"* ]]
    [[ "$output" == *"CLAUDE.md"* ]]
}

@test "status shows local→ when local changed" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "modified" > "$LOCAL_DIR/CLAUDE.md"
    echo "original" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    run bash ./claude-sync status
    [ "$status" -eq 0 ]
    [[ "$output" == *"local→"* ]]
}

@test "status shows CONFLICT when both changed differently" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "local version" > "$LOCAL_DIR/CLAUDE.md"
    echo "remote version" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    run bash ./claude-sync status
    [ "$status" -eq 0 ]
    [[ "$output" == *"CONFLICT"* ]]
}

@test "status shows new-local for new local file" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "new" > "$LOCAL_DIR/CLAUDE.md"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    run bash ./claude-sync status
    [ "$status" -eq 0 ]
    [[ "$output" == *"new-local"* ]]
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bats test/test_status.bats
```

- [ ] **Step 3: Implement cmd_status**

Add to `claude-sync`:

```bash
# --- Status command ---

# Map decide_action output to human-readable labels
action_label() {
    case "$1" in
        clean)          echo "clean" ;;
        push|push-new)  echo "local→" ;;
        pull|pull-new)  echo "←remote" ;;
        update-base|create-base) echo "clean" ;;
        delete-remote)  echo "local→(del)" ;;
        delete-local)   echo "←remote(del)" ;;
        delete-base)    echo "clean" ;;
        conflict)       echo "CONFLICT" ;;
    esac
}

# Build the full file list (union of local, base, remote) for the synclist entries
build_file_union() {
    local synclist="$1"
    {
        enumerate_files "$CLAUDE_DIR" "$synclist"
        enumerate_files "$LAST_SYNC_DIR" "$synclist"
        if [[ -z "${REMOTE_HOST:-}" ]]; then
            enumerate_files "$REMOTE_PATH" "$synclist"
        else
            ssh "$REMOTE_HOST" "cd \"$REMOTE_PATH\" 2>/dev/null && find . -type f 2>/dev/null | sed 's|^\./||'" | while IFS= read -r f; do
                if ! is_excluded "$f"; then
                    # Check if file falls under a synclist entry
                    while IFS= read -r entry; do
                        [[ -z "$entry" ]] && continue
                        if [[ "$entry" == */ && "$f" == "$entry"* ]] || [[ "$f" == "$entry" ]]; then
                            echo "$f"
                            break
                        fi
                    done <<< "$synclist"
                fi
            done
        fi
    } | sort -u
}

cmd_status() {
    fetch_remote_checksums_readonly
    local synclist
    synclist=$(load_synclist)
    local all_files
    all_files=$(build_file_union "$synclist")

    if [[ -z "$all_files" ]]; then
        echo "No files to sync."
        return 0
    fi

    local has_conflict=false
    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue
        local local_hash base_hash remote_hash
        local_hash=$(compute_local_checksums "$CLAUDE_DIR" "$filepath" | awk '{print $1}')
        base_hash=$(compute_local_checksums "$LAST_SYNC_DIR" "$filepath" | awk '{print $1}')
        remote_hash=$(get_remote_checksum "$filepath" | awk '{print $1}')

        local action
        action=$(decide_action "$local_hash" "$base_hash" "$remote_hash")
        local label
        label=$(action_label "$action")

        printf "%-15s %s\n" "$label" "$filepath"
        [[ "$action" == "conflict" ]] && has_conflict=true
    done <<< "$all_files"

    if $has_conflict; then
        echo ""
        echo "Run /claude-sync:fix to resolve conflicts." >&2
    fi
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
bats test/test_status.bats
```

- [ ] **Step 5: Commit**

```bash
git add claude-sync test/test_status.bats
git commit -m "feat: status command with three-way comparison output"
```

---

## Chunk 3: Batch Transfer + Sync + Diff Commands

### Task 7: SSH operations and batch transfer

**Files:**
- Modify: `claude-sync`
- Create: `test/test_transfer.bats`

Batch operations: rsync with `--files-from` for push/pull, local file operations for base and deletes. In local-only mode (no REMOTE_HOST, for testing), use `cp`/`rm` instead of SSH/rsync.

- [ ] **Step 1: Write transfer tests**

Create `test/test_transfer.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "batch_push copies listed files to remote" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "content1" > "$LOCAL_DIR/CLAUDE.md"
    mkdir -p "$LOCAL_DIR/skills/grimoire"
    echo "content2" > "$LOCAL_DIR/skills/grimoire/SKILL.md"
    local list_file
    list_file=$(mktemp)
    printf "CLAUDE.md\nskills/grimoire/SKILL.md\n" > "$list_file"
    batch_push "$list_file"
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "content1" ]
    [ "$(cat "$REMOTE_DIR/skills/grimoire/SKILL.md")" = "content2" ]
    rm -f "$list_file"
}

@test "batch_pull copies listed files from remote" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "remote content" > "$REMOTE_DIR/CLAUDE.md"
    local list_file
    list_file=$(mktemp)
    echo "CLAUDE.md" > "$list_file"
    batch_pull "$list_file"
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "remote content" ]
    rm -f "$list_file"
}

@test "batch_delete_remote removes listed files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "to delete" > "$REMOTE_DIR/CLAUDE.md"
    batch_delete_remote "CLAUDE.md"
    [ ! -f "$REMOTE_DIR/CLAUDE.md" ]
}

@test "batch_delete_local removes listed files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "to delete" > "$LOCAL_DIR/CLAUDE.md"
    batch_delete_local "CLAUDE.md"
    [ ! -f "$LOCAL_DIR/CLAUDE.md" ]
}

@test "update_base copies file to last-sync" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "content" > "$LOCAL_DIR/CLAUDE.md"
    update_base_from_local "CLAUDE.md"
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "content" ]
}

@test "create_local_backup creates tar of synced files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "backup me" > "$LOCAL_DIR/CLAUDE.md"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    create_local_backup
    local latest
    latest=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)
    [ -n "$latest" ]
    # Verify content
    tar -tzf "$latest" | grep -q "CLAUDE.md"
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bats test/test_transfer.bats
```

- [ ] **Step 3: Implement batch transfer and backup functions**

Add to `claude-sync`:

```bash
# --- Batch file transfers ---
# All remote operations are batched to minimize SSH connections.
# In local-only mode (REMOTE_HOST=""), use cp/rm directly.

batch_push() {
    local files_from="$1"
    if [[ -z "${REMOTE_HOST:-}" ]]; then
        # Local mode: copy files preserving directory structure
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            mkdir -p "$(dirname "$REMOTE_PATH/$f")"
            cp "$CLAUDE_DIR/$f" "$REMOTE_PATH/$f"
        done < "$files_from"
    else
        rsync -a --files-from="$files_from" "$CLAUDE_DIR/" "$REMOTE_HOST:$REMOTE_PATH/"
    fi
}

batch_pull() {
    local files_from="$1"
    if [[ -z "${REMOTE_HOST:-}" ]]; then
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            mkdir -p "$(dirname "$CLAUDE_DIR/$f")"
            cp "$REMOTE_PATH/$f" "$CLAUDE_DIR/$f"
        done < "$files_from"
    else
        rsync -a --files-from="$files_from" "$REMOTE_HOST:$REMOTE_PATH/" "$CLAUDE_DIR/"
    fi
}

batch_delete_remote() {
    local files="$1"  # newline-separated file list
    if [[ -z "${REMOTE_HOST:-}" ]]; then
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            rm -f "$REMOTE_PATH/$f"
        done <<< "$files"
    else
        # Batched into SSH call 3 (see cmd_sync)
        :  # handled by remote_finalize
    fi
}

batch_delete_local() {
    local files="$1"  # newline-separated file list
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        rm -f "$CLAUDE_DIR/$f"
    done <<< "$files"
}

update_base_from_local() {
    local filepath="$1"
    mkdir -p "$(dirname "$LAST_SYNC_DIR/$filepath")"
    cp "$CLAUDE_DIR/$filepath" "$LAST_SYNC_DIR/$filepath"
}

remove_from_base() {
    local filepath="$1"
    rm -f "$LAST_SYNC_DIR/$filepath"
}

# --- Backups ---

create_local_backup() {
    mkdir -p "$BACKUP_DIR"
    local synclist
    synclist=$(load_synclist)
    local files
    files=$(enumerate_files "$CLAUDE_DIR" "$synclist")
    if [[ -n "$files" ]]; then
        local backup_file="$BACKUP_DIR/$(date -Iseconds).tar.gz"
        tar -czf "$backup_file" -C "$CLAUDE_DIR" $files 2>/dev/null || true
    fi
}

prune_old_backups() {
    if [[ -d "$BACKUP_DIR" ]]; then
        find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -mtime +30 -delete 2>/dev/null || true
    fi
}

# --- Remote combined operations ---
# SSH call 1: lock + bootstrap + checksums
# Returns checksums on stdout. Exits non-zero if lock held.

remote_init() {
    if [[ -z "${REMOTE_HOST:-}" ]]; then
        mkdir -p "$REMOTE_PATH"
        ( cd "$REMOTE_PATH" && find . -type f -not -name ".claude-sync.lock" -exec md5sum {} + 2>/dev/null | sed 's| \./| |' ) || true
    else
        ssh "$REMOTE_HOST" '
            set -e
            # Lock
            set -C
            echo "'"'$HOSTNAME'"'" > "'"$REMOTE_PATH"'/.claude-sync.lock" 2>/dev/null || {
                age=$(( $(date +%s) - $(stat -c %Y "'"$REMOTE_PATH"'/.claude-sync.lock" 2>/dev/null || echo 0) ))
                if [ "$age" -gt 300 ]; then
                    rm -f "'"$REMOTE_PATH"'/.claude-sync.lock"
                    echo "'"'$HOSTNAME'"'" > "'"$REMOTE_PATH"'/.claude-sync.lock"
                else
                    echo "LOCKED_BY $(cat "'"$REMOTE_PATH"'/.claude-sync.lock" 2>/dev/null)" >&2
                    exit 1
                fi
            }
            set +C
            # Bootstrap
            mkdir -p "'"$REMOTE_PATH"'"
            # Checksums
            cd "'"$REMOTE_PATH"'" && find . -type f -not -name ".claude-sync.lock" -exec md5sum {} + 2>/dev/null | sed "s| \./| |"
        '
    fi
}

# SSH call 3: verify pushed files + delete remote files + release lock
# Args: verify_list (file), delete_list (string)
# Returns verification checksums on stdout.

remote_finalize() {
    local verify_file="$1"
    local delete_files="$2"
    if [[ -z "${REMOTE_HOST:-}" ]]; then
        # Verify
        if [[ -s "$verify_file" ]]; then
            while IFS= read -r f; do
                [[ -z "$f" ]] && continue
                md5sum "$REMOTE_PATH/$f" | sed "s|$REMOTE_PATH/||"
            done < "$verify_file"
        fi
        # Delete
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            rm -f "$REMOTE_PATH/$f"
        done <<< "$delete_files"
        # Unlock
        rm -f "$REMOTE_PATH/.claude-sync.lock"
    else
        local script='cd "'"$REMOTE_PATH"'"; '
        # Verify
        if [[ -s "$verify_file" ]]; then
            while IFS= read -r f; do
                [[ -z "$f" ]] && continue
                script+="md5sum \"$f\"; "
            done < "$verify_file"
        fi
        # Delete
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            script+="rm -f \"$f\"; "
        done <<< "$delete_files"
        # Unlock
        script+='rm -f .claude-sync.lock'
        ssh "$REMOTE_HOST" "$script"
    fi
}

release_remote_lock() {
    if [[ -z "${REMOTE_HOST:-}" ]]; then
        rm -f "$REMOTE_PATH/.claude-sync.lock"
    else
        ssh "$REMOTE_HOST" "rm -f \"$REMOTE_PATH/.claude-sync.lock\""
    fi
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
bats test/test_transfer.bats
```

- [ ] **Step 5: Commit**

```bash
git add claude-sync test/test_transfer.bats
git commit -m "feat: batch transfer, backup, and combined SSH operations"
```

---

### Task 8: Sync command

**Files:**
- Modify: `claude-sync`
- Create: `test/test_sync.bats`

Phase-based orchestrator: lock+checksums → decide → backup → batch transfer → verify+delete+unlock → update base.

- [ ] **Step 1: Write sync integration tests**

Create `test/test_sync.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "sync: local-only changes propagate to remote" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$LOCAL_DIR/CLAUDE.md"
    echo "original" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "modified locally" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "modified locally" ]
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "modified locally" ]
}

@test "sync: remote-only changes propagate to local" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$LOCAL_DIR/CLAUDE.md"
    echo "original" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "modified remotely" > "$REMOTE_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "modified remotely" ]
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "modified remotely" ]
}

@test "sync: pull creates backup before modifying local" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "local original" > "$LOCAL_DIR/CLAUDE.md"
    echo "local original" > "$BASE_DIR/CLAUDE.md"
    echo "remote modified" > "$REMOTE_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    # Backup should exist
    local backup
    backup=$(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)
    [ -n "$backup" ]
    # Backup should contain old local version
    tar -xzf "$backup" -C "$TEST_DIR/restore" 2>/dev/null || { mkdir -p "$TEST_DIR/restore" && tar -xzf "$backup" -C "$TEST_DIR/restore"; }
    [ "$(cat "$TEST_DIR/restore/CLAUDE.md")" = "local original" ]
}

@test "sync: conflict exits non-zero and does not modify files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$LOCAL_DIR/CLAUDE.md"
    echo "original" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "local change" > "$LOCAL_DIR/CLAUDE.md"
    echo "remote change" > "$REMOTE_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -ne 0 ]
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "local change" ]
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "remote change" ]
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "original" ]
    [[ "$output" == *"CONFLICT"* ]]
}

@test "sync: new local file propagates to remote" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "new file" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "new file" ]
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "new file" ]
}

@test "sync: new remote file propagates to local" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "from remote" > "$REMOTE_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "from remote" ]
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "from remote" ]
}

@test "sync: dry-run does not modify files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$LOCAL_DIR/CLAUDE.md"
    echo "original" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "modified" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync --dry-run sync
    [ "$status" -eq 0 ]
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "original" ]
    [[ "$output" == *"push"* ]]
}

@test "sync: deletion propagates when one side unchanged" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ ! -f "$REMOTE_DIR/CLAUDE.md" ]
    [ ! -f "$BASE_DIR/CLAUDE.md" ]
}

@test "sync: everything clean → exit 0, no changes" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$REMOTE_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"Everything in sync"* ]]
}

@test "sync: push-only does not create backup" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$LOCAL_DIR/CLAUDE.md"
    echo "original" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    echo "modified" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    # No backup needed (only pushing, not modifying local)
    local count
    count=$(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)
    [ "$count" -eq 0 ]
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bats test/test_sync.bats
```

- [ ] **Step 3: Implement cmd_sync**

Add to `claude-sync`:

```bash
# --- Sync command ---

cmd_sync() {
    acquire_local_lock

    # Phase 1: Lock + bootstrap + fetch remote checksums (single SSH call)
    local remote_checksums
    if ! remote_checksums=$(remote_init); then
        echo "error: could not connect to remote (locked or unreachable)" >&2
        return 1
    fi
    REMOTE_CHECKSUMS_CACHE="$remote_checksums"
    # From here, remote lock is held — ensure cleanup on exit
    trap 'release_remote_lock; release_local_lock' EXIT

    mkdir -p "$LAST_SYNC_DIR"

    local synclist
    synclist=$(load_synclist)
    local all_files
    all_files=$(build_file_union "$synclist")

    if [[ -z "$all_files" ]]; then
        echo "No files to sync."
        release_remote_lock
        trap release_local_lock EXIT
        return 0
    fi

    # Phase 2: Decide actions for every file
    local push_list="" pull_list="" delete_remote_list="" delete_local_list=""
    local base_update_list="" base_remove_list="" conflict_list=""
    local tmpdir
    tmpdir=$(mktemp -d)

    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue
        local local_hash base_hash remote_hash
        local_hash=$(compute_local_checksums "$CLAUDE_DIR" "$filepath" | awk '{print $1}')
        base_hash=$(compute_local_checksums "$LAST_SYNC_DIR" "$filepath" | awk '{print $1}')
        remote_hash=$(get_remote_checksum "$filepath" | awk '{print $1}')

        local action
        action=$(decide_action "$local_hash" "$base_hash" "$remote_hash")

        case "$action" in
            clean) ;;
            push|push-new)
                push_list+="$filepath"$'\n'
                base_update_list+="$filepath"$'\n'
                ;;
            pull|pull-new)
                pull_list+="$filepath"$'\n'
                base_update_list+="$filepath"$'\n'
                ;;
            update-base|create-base)
                base_update_list+="$filepath"$'\n'
                ;;
            delete-remote)
                delete_remote_list+="$filepath"$'\n'
                base_remove_list+="$filepath"$'\n'
                ;;
            delete-local)
                delete_local_list+="$filepath"$'\n'
                base_remove_list+="$filepath"$'\n'
                ;;
            delete-base)
                base_remove_list+="$filepath"$'\n'
                ;;
            conflict)
                conflict_list+="$filepath"$'\n'
                ;;
        esac
    done <<< "$all_files"

    if $DRY_RUN; then
        [[ -n "$push_list" ]] && echo "$push_list" | sed '/^$/d' | sed 's/^/[dry-run] push: /'
        [[ -n "$pull_list" ]] && echo "$pull_list" | sed '/^$/d' | sed 's/^/[dry-run] pull: /'
        [[ -n "$delete_remote_list" ]] && echo "$delete_remote_list" | sed '/^$/d' | sed 's/^/[dry-run] delete remote: /'
        [[ -n "$delete_local_list" ]] && echo "$delete_local_list" | sed '/^$/d' | sed 's/^/[dry-run] delete local: /'
        [[ -n "$conflict_list" ]] && echo "$conflict_list" | sed '/^$/d' | sed 's/^/CONFLICT: /' >&2
        release_remote_lock
        trap release_local_lock EXIT
        rm -rf "$tmpdir"
        [[ -n "$conflict_list" ]] && return 1
        [[ -z "$push_list$pull_list$delete_remote_list$delete_local_list" ]] && echo "Everything in sync."
        return 0
    fi

    # Phase 3: Backup local before any local modifications (pull or delete-local)
    if [[ -n "$pull_list" || -n "$delete_local_list" ]]; then
        create_local_backup
    fi

    # Phase 4: Batch transfers (1 rsync per direction)
    if [[ -n "$push_list" ]]; then
        local push_file="$tmpdir/push_list"
        echo "$push_list" | sed '/^$/d' > "$push_file"
        batch_push "$push_file"
        echo "$push_list" | sed '/^$/d' | sed 's/^/pushed: /'
    fi

    if [[ -n "$pull_list" ]]; then
        local pull_file="$tmpdir/pull_list"
        echo "$pull_list" | sed '/^$/d' > "$pull_file"
        batch_pull "$pull_file"
        echo "$pull_list" | sed '/^$/d' | sed 's/^/pulled: /'
    fi

    # Local deletes (no SSH needed)
    if [[ -n "$delete_local_list" ]]; then
        batch_delete_local "$delete_local_list"
        echo "$delete_local_list" | sed '/^$/d' | sed 's/^/deleted local: /'
    fi

    # Phase 5: Verify + remote deletes + release lock (single SSH call)
    local verify_file="$tmpdir/verify_list"
    echo "$push_list" | sed '/^$/d' > "$verify_file"
    local verify_output
    verify_output=$(remote_finalize "$verify_file" "$delete_remote_list")
    trap release_local_lock EXIT  # remote lock released by remote_finalize

    if [[ -n "$delete_remote_list" ]]; then
        echo "$delete_remote_list" | sed '/^$/d' | sed 's/^/deleted remote: /'
    fi

    # Check verification checksums
    if [[ -n "$push_list" ]]; then
        while IFS= read -r filepath; do
            [[ -z "$filepath" ]] && continue
            local expected_hash actual_hash
            expected_hash=$(md5sum "$CLAUDE_DIR/$filepath" | awk '{print $1}')
            actual_hash=$(echo "$verify_output" | grep -F "$filepath" | awk '{print $1}')
            if [[ "$expected_hash" != "$actual_hash" ]]; then
                echo "error: integrity check failed for $filepath (push)" >&2
            fi
        done <<< "$push_list"
    fi

    # Phase 6: Update base
    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue
        update_base_from_local "$filepath"
    done <<< "$base_update_list"

    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue
        remove_from_base "$filepath"
    done <<< "$base_remove_list"

    rm -rf "$tmpdir"

    # Prune old backups
    prune_old_backups

    # Phase 7: Report conflicts
    if [[ -n "$conflict_list" ]]; then
        echo "$conflict_list" | sed '/^$/d' | sed 's/^/CONFLICT: /' >&2
        notify-send "claude-sync" "Conflicts detected — run /claude-sync:fix" 2>/dev/null || true
        echo "Conflicts detected. Run /claude-sync:fix to resolve." >&2
        return 1
    fi

    if [[ -z "$push_list$pull_list$delete_remote_list$delete_local_list" ]]; then
        echo "Everything in sync."
    fi
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
bats test/test_sync.bats
```

- [ ] **Step 5: Commit**

```bash
git add claude-sync test/test_sync.bats
git commit -m "feat: phase-based sync with batch transfers and local backup"
```

---

### Task 9: Diff command

**Files:**
- Modify: `claude-sync`
- Create: `test/test_diff.bats`

For `diff`, we need to fetch remote file contents. In local-only mode, just read from REMOTE_PATH. In SSH mode, batch-fetch all changed files via a single rsync to a temp dir.

- [ ] **Step 1: Write diff tests**

Create `test/test_diff.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "diff shows unified diff for changed files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "original" > "$LOCAL_DIR/CLAUDE.md"
    echo "modified" > "$REMOTE_DIR/CLAUDE.md"
    echo "original" > "$BASE_DIR/CLAUDE.md"
    run bash ./claude-sync diff
    [ "$status" -eq 0 ]
    [[ "$output" == *"---"* ]]
    [[ "$output" == *"+++"* ]]
    [[ "$output" == *"CLAUDE.md"* ]]
}

@test "diff shows nothing when all clean" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$REMOTE_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"
    run bash ./claude-sync diff
    [ "$status" -eq 0 ]
    [[ "$output" == *"No differences"* ]]
}

@test "diff shows absent files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "only remote" > "$REMOTE_DIR/CLAUDE.md"
    run bash ./claude-sync diff
    [ "$status" -eq 0 ]
    [[ "$output" == *"absent"* ]]
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bats test/test_diff.bats
```

- [ ] **Step 3: Implement cmd_diff**

Add to `claude-sync`:

```bash
# --- Diff command ---

cmd_diff() {
    # Fetch remote checksums (single SSH, no lock needed for read-only)
    fetch_all_remote_checksums

    local synclist
    synclist=$(load_synclist)
    local all_files
    all_files=$(build_file_union "$synclist")

    if [[ -z "$all_files" ]]; then
        echo "No files to compare."
        return 0
    fi

    # Collect files that differ
    local changed_files=""
    declare -A file_actions
    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue
        local local_hash base_hash remote_hash
        local_hash=$(compute_local_checksums "$CLAUDE_DIR" "$filepath" | awk '{print $1}')
        base_hash=$(compute_local_checksums "$LAST_SYNC_DIR" "$filepath" | awk '{print $1}')
        remote_hash=$(get_remote_checksum "$filepath" | awk '{print $1}')
        local action
        action=$(decide_action "$local_hash" "$base_hash" "$remote_hash")
        if [[ "$action" != "clean" ]]; then
            changed_files+="$filepath"$'\n'
            file_actions["$filepath"]="$action"
        fi
    done <<< "$all_files"

    if [[ -z "$changed_files" ]]; then
        echo "No differences found."
        return 0
    fi

    # Batch-fetch remote versions of changed files to a temp dir
    local tmpdir
    tmpdir=$(mktemp -d)
    local fetch_list="$tmpdir/fetch_list"
    echo "$changed_files" | sed '/^$/d' > "$fetch_list"

    if [[ -z "${REMOTE_HOST:-}" ]]; then
        # Local mode: just reference REMOTE_PATH directly
        :
    else
        rsync -a --files-from="$fetch_list" "$REMOTE_HOST:$REMOTE_PATH/" "$tmpdir/remote/" 2>/dev/null || true
    fi

    # Show diffs
    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue
        local action="${file_actions[$filepath]}"
        local local_file="$CLAUDE_DIR/$filepath"
        local remote_file
        if [[ -z "${REMOTE_HOST:-}" ]]; then
            remote_file="$REMOTE_PATH/$filepath"
        else
            remote_file="$tmpdir/remote/$filepath"
        fi

        echo "=== $filepath ($action) ==="
        local local_hash
        local_hash=$(compute_local_checksums "$CLAUDE_DIR" "$filepath" | awk '{print $1}')
        local remote_hash
        remote_hash=$(get_remote_checksum "$filepath" | awk '{print $1}')

        if [[ "$local_hash" == "ABSENT" ]]; then
            echo "(local: absent, remote: exists)"
            cat "$remote_file" 2>/dev/null || true
        elif [[ "$remote_hash" == "ABSENT" ]]; then
            echo "(local: exists, remote: absent)"
            cat "$local_file"
        else
            diff -u --label "local/$filepath" "$local_file" --label "remote/$filepath" "$remote_file" || true
        fi
        echo ""
    done <<< "$changed_files"

    rm -rf "$tmpdir"
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
bats test/test_diff.bats
```

- [ ] **Step 5: Commit**

```bash
git add claude-sync test/test_diff.bats
git commit -m "feat: diff command with batch remote fetch"
```

---

## Chunk 4: Update Command + Skills

### Task 10: Update command

**Files:**
- Modify: `claude-sync`

- [ ] **Step 1: Implement cmd_update**

Add to `claude-sync`:

```bash
# --- Update command ---

cmd_update() {
    : "${REPO_DIR:?REPO_DIR not set in $CONFIG_FILE}"

    if [[ ! -d "$REPO_DIR/.git" ]]; then
        echo "error: $REPO_DIR is not a git repo" >&2
        exit 1
    fi

    echo "Pulling latest from $(git -C "$REPO_DIR" remote get-url origin)..."
    git -C "$REPO_DIR" pull

    # Copy script
    local script_path
    script_path=$(command -v claude-sync || echo "")
    if [[ -n "$script_path" ]]; then
        cp "$REPO_DIR/claude-sync" "$script_path"
        chmod +x "$script_path"
        echo "Updated script: $script_path"
    else
        echo "warning: claude-sync not found in PATH, skipping script copy" >&2
    fi

    # Copy skills
    local skills_dest="$CLAUDE_DIR/skills/claude-sync"
    if [[ -d "$REPO_DIR/skills/claude-sync" ]]; then
        rm -rf "$skills_dest"
        cp -r "$REPO_DIR/skills/claude-sync" "$skills_dest"
        echo "Updated skills: $skills_dest"
    fi

    echo "Update complete (v$(bash "$REPO_DIR/claude-sync" --version | awk '{print $2}'))."
}
```

- [ ] **Step 2: Verify it builds**

```bash
bash ./claude-sync --version
```

- [ ] **Step 3: Commit**

```bash
git add claude-sync
git commit -m "feat: update command for self-update from git repo"
```

---

### Task 11: Skills — init, fix, init-local

**Files:**
- Create: `skills/claude-sync/init.md`
- Create: `skills/claude-sync/fix.md`
- Create: `skills/claude-sync/init-local.md`

- [ ] **Step 1: Create /claude-sync:init skill**

Create `skills/claude-sync/init.md`:

```markdown
---
name: init
description: First-time setup of claude-sync — configure SSH target, test connectivity, run initial sync with interactive conflict resolution, configure SessionStart hook
---

# /claude-sync:init — First-Time Setup

You are setting up claude-sync for the first time on this machine. Follow these steps interactively.

**IMPORTANT — Idempotency:** This skill must be safe to run multiple times. At each step, check if work is already done before acting. Never duplicate hooks, configs, or file entries.

## Step 0: Check if already initialized

Run: `claude-sync status 2>&1`

If it succeeds (exit 0, outputs file status), claude-sync is already configured. Tell the user:

> "claude-sync is already initialized on this machine. Run `claude-sync status` to see current state, or `/claude-sync:fix` to resolve conflicts."

**Stop here** unless the user explicitly wants to re-initialize.

## Step 1: Check prerequisites

Run:
- `which rsync` — must be available
- `which ssh` — must be available
- `which claude-sync` — if not found, ask user where the claude-syncer repo is cloned and suggest adding it to PATH

## Step 2: Check existing config

Check if `~/.config/claude-sync/config` exists. If it does, read it and confirm with the user.

If it doesn't exist:
1. Ask the user for their SSH target (e.g. `user@server.example.com`)
2. Ask for the remote path (suggest `/srv/claude-sync` as default)
3. Ask where the claude-syncer repo is cloned (for self-update)
4. Create the config file:

```bash
mkdir -p ~/.config/claude-sync
cat > ~/.config/claude-sync/config <<EOF
REMOTE_HOST="<user-provided>"
REMOTE_PATH="<user-provided>"
CLAUDE_DIR="$HOME/.claude"
REPO_DIR="<user-provided>"
EOF
```

## Step 3: Test SSH connectivity

Run: `ssh -o ConnectTimeout=5 <REMOTE_HOST> "echo ok"`

If it fails, help the user debug (key not copied, host unreachable, etc.).

## Step 4: Extract local-specific content from CLAUDE.md

Before syncing, check if `~/.claude/CLAUDE.md` contains machine-specific sections (OS, shell, local paths, container runtime, hardware, etc.).

If machine-specific content is found:
1. Show the user which sections look machine-specific
2. Propose moving them to `~/.claude/CLAUDE.local.md` (which is never synced)
3. If user agrees, create `CLAUDE.local.md` with the extracted sections and remove them from `CLAUDE.md`
4. If `CLAUDE.local.md` already exists, propose merging instead of overwriting

If no machine-specific content is found, or if `CLAUDE.local.md` already exists, skip.

**Heuristics for detecting local content:** sections mentioning specific OS names (Ubuntu, Arch, Fedora), kernel versions, `localhost`, IP addresses, hardware models, desktop environments, local file paths outside `~/`.

## Step 5: Run first sync

Run: `claude-sync sync`

- If it succeeds with no conflicts → great, move to step 6
- If it fails with conflicts → for each conflicting file:
  1. Read the local version from `~/.claude/<file>`
  2. Read the remote version via `ssh <HOST> "cat <REMOTE_PATH>/<file>"`
  3. Show the user both versions with a semantic explanation of the differences
  4. Propose a merged version that combines both (e.g. for CLAUDE.md, merge unique sections)
  5. Ask the user to approve the merge
  6. Write the merged version to both local and remote:
     - Write locally to `~/.claude/<file>`
     - Copy to remote: `rsync -a ~/.claude/<file> <HOST>:<REMOTE_PATH>/<file>`
     - Update base: `cp ~/.claude/<file> ~/.config/claude-sync/last-sync/<file>`
  7. After resolving all conflicts, run `claude-sync sync` again to confirm clean state

## Step 6: Install missing plugins

After sync, check if any plugins from `installed_plugins.json` are missing from the local cache:

1. Read `~/.claude/plugins/installed_plugins.json`
2. For each plugin entry, check if its `installPath` exists locally
3. For missing plugins, extract `name@marketplace` and run:
   ```bash
   claude plugin install <name>@<marketplace> --scope user
   ```
4. If `claude` CLI is not available or a plugin fails to install, warn and continue

## Step 7: Configure SessionStart hook

Read `~/.claude/settings.json`.

**Check first:** If a hook with command `claude-sync sync` already exists in `SessionStart`, skip this step entirely. Do NOT add a duplicate.

If not present, add the SessionStart hook:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "command": "claude-sync sync"
      }
    ]
  }
}
```

Be careful to merge with existing hooks — do not overwrite other hooks that may exist. Read the current JSON, add to the array, write back.

## Step 8: Verify

Run `claude-sync status` and show the user the result. Confirm everything is clean.

Print: "claude-sync is configured. Your config will sync automatically at the start of each Claude session. Run `/claude-sync:init-local` to generate machine-specific CLAUDE.local.md."
```

- [ ] **Step 2: Create /claude-sync:fix skill**

Create `skills/claude-sync/fix.md`:

```markdown
---
name: fix
description: Resolve claude-sync conflicts — shows semantic diffs of conflicting files and guides interactive merge resolution
---

# /claude-sync:fix — Conflict Resolution

You are resolving sync conflicts detected by claude-sync. Follow these steps.

## Step 1: Get conflict list

Run: `claude-sync status`

Identify all files marked as `CONFLICT`.

## Step 2: Create backup

```bash
backup_dir=~/.config/claude-sync/backups/$(date -Iseconds)
mkdir -p "$backup_dir"
```

For each conflicting file, back up both versions:
```bash
cp ~/.claude/<file> "$backup_dir/<file>.local"
# For remote:
ssh <REMOTE_HOST> "cat <REMOTE_PATH>/<file>" > "$backup_dir/<file>.remote"
# Base version if it exists:
cp ~/.config/claude-sync/last-sync/<file> "$backup_dir/<file>.base" 2>/dev/null || true
```

## Step 3: For each conflicting file

1. Read all available versions:
   - Local: `~/.claude/<file>`
   - Remote: via SSH `cat` on the remote
   - Base (if exists): `~/.config/claude-sync/last-sync/<file>`

2. Analyze the differences semantically:
   - For `.md` files: identify added/removed/modified sections
   - For `.json` files: compare key-by-key, identify added/changed/removed keys
   - For directories with file conflicts: handle each file independently

3. Propose a merged version:
   - Combine additions from both sides
   - For conflicting modifications to the same section/key: present both versions and ask the user to choose or provide a resolution
   - Explain your reasoning for the proposed merge

4. Ask the user to approve the merge. If they want changes, iterate.

5. Once approved, write the resolved version:
   - Write to local: `~/.claude/<file>`
   - Copy to remote: use rsync or ssh+cat
   - Update base: `cp ~/.claude/<file> ~/.config/claude-sync/last-sync/<file>`

## Step 4: Verify

Run `claude-sync sync` to confirm all conflicts are resolved and everything is clean.

If new conflicts appear (shouldn't happen), repeat from step 1.

Print: "All conflicts resolved. Config is in sync."
```

- [ ] **Step 3: Create /claude-sync:init-local skill**

Create `skills/claude-sync/init-local.md`:

```markdown
---
name: init-local
description: Generate a CLAUDE.local.md file with machine-specific environment details (OS, shell, runtime, etc.) — never synced
---

# /claude-sync:init-local — Generate Machine-Specific Config

Generate `~/.claude/CLAUDE.local.md` by detecting the local environment. This file is never synced by claude-sync.

## Detection

Gather the following information by running commands:

| Info | Command |
|------|---------|
| OS | `lsb_release -d 2>/dev/null \|\| cat /etc/os-release \|\| uname -s` |
| Kernel | `uname -r` |
| Desktop | `echo $XDG_CURRENT_DESKTOP` |
| Display server | `echo $XDG_SESSION_TYPE` |
| Shell | `echo $SHELL` |
| Container runtime | `which docker \|\| which podman \|\| echo "none"` |
| Kubernetes | `which kubectl \|\| which k3s \|\| echo "none"` |
| Package manager | `which apt \|\| which pacman \|\| which dnf` |
| Hostname | `hostname` |

## Generate

Write `~/.claude/CLAUDE.local.md`:

```markdown
# Local Environment

- OS: **<detected>**
- Kernel: **<detected>**
- Desktop: **<detected>** (<display server>)
- Shell: **<detected>**
- Container runtime: **<detected>**
- Kubernetes: **<detected>**
- Package manager: **<detected>**
- Hostname: **<detected>**
```

Show the generated file to the user and ask if they want to add anything machine-specific (e.g. project paths, VPN notes, hardware details).
```

- [ ] **Step 4: Commit**

```bash
git add skills/
git commit -m "feat: skills for init, fix, and init-local"
```

---

### Task 12: Reference files and README

**Files:**
- Create: `synclist.default`
- Create: `README.md`

- [ ] **Step 1: Create synclist.default**

Create `synclist.default`:

```
# Default synclist for claude-sync
# One path per line. Directories end with /
# Override by creating ~/.config/claude-sync/synclist

CLAUDE.md
settings.json
skills/
agents/
plugins/installed_plugins.json
plugins/known_marketplaces.json
```

- [ ] **Step 2: Create README.md**

Create `README.md`:

```markdown
# claude-sync

Sync your Claude Code configuration across machines using rsync over SSH.

## Features

- **Three-way sync** — detects who changed what using a `last-sync` snapshot
- **Never overwrites** — conflicts are detected, not silently resolved
- **Claude-assisted resolution** — `/claude-sync:fix` skill merges conflicts interactively
- **Minimal dependencies** — bash, rsync, ssh

## Quick start

```bash
# Clone
git clone <repo-url> ~/claude-syncer

# Add to PATH
ln -s ~/claude-syncer/claude-sync ~/bin/claude-sync

# Install skills
cp -r ~/claude-syncer/skills/claude-sync ~/.claude/skills/

# Init (run in Claude Code)
# /claude-sync:init
```

## Commands

| Command | Description |
|---------|-------------|
| `claude-sync sync` | Safe bidirectional sync |
| `claude-sync status` | Show per-file sync state |
| `claude-sync diff` | Show diffs between local and remote |
| `claude-sync update` | Self-update from git repo |

Use `--dry-run` / `-n` with `sync` to preview without applying.

## Config

`~/.config/claude-sync/config`:

```bash
REMOTE_HOST="user@your-server.com"
REMOTE_PATH="/srv/claude-sync"
CLAUDE_DIR="$HOME/.claude"
REPO_DIR="$HOME/claude-syncer"
```

## Skills

- `/claude-sync:init` — First-time setup
- `/claude-sync:fix` — Resolve conflicts
- `/claude-sync:init-local` — Generate machine-specific `CLAUDE.local.md`

## How it works

Three-way comparison: for each file, compare LOCAL, BASE (last-sync snapshot), and REMOTE.

- Only local changed → push to remote
- Only remote changed → pull to local
- Both changed differently → CONFLICT (no writes, notification)
- Both changed same way → update base only

No `push` or `pull` commands. No way to accidentally overwrite.
```

- [ ] **Step 3: Commit**

```bash
git add synclist.default README.md
git commit -m "docs: README and default synclist"
```

---

## Chunk 5: Final Integration Tests

### Task 13: End-to-end integration tests

**Files:**
- Create: `test/test_e2e.bats`

Full scenarios exercising the complete workflow.

- [ ] **Step 1: Write e2e tests**

Create `test/test_e2e.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "e2e: first machine bootstrap (empty remote)" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md
skills/" > "$CONFIG_DIR/synclist"
    echo "my config" > "$LOCAL_DIR/CLAUDE.md"
    mkdir -p "$LOCAL_DIR/skills/grimoire"
    echo "spell" > "$LOCAL_DIR/skills/grimoire/SKILL.md"

    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    # Remote should now have everything
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "my config" ]
    [ "$(cat "$REMOTE_DIR/skills/grimoire/SKILL.md")" = "spell" ]
    # Base should be populated
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "my config" ]
}

@test "e2e: second machine joins (has local config, remote exists)" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md
skills/" > "$CONFIG_DIR/synclist"
    # Remote already has config from first machine
    echo "first machine config" > "$REMOTE_DIR/CLAUDE.md"
    mkdir -p "$REMOTE_DIR/skills/grimoire"
    echo "spell" > "$REMOTE_DIR/skills/grimoire/SKILL.md"
    # Local has its own skill but no CLAUDE.md
    mkdir -p "$LOCAL_DIR/skills/necronomicon"
    echo "dark spell" > "$LOCAL_DIR/skills/necronomicon/SKILL.md"

    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    # Local should get remote's CLAUDE.md and grimoire
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "first machine config" ]
    [ "$(cat "$LOCAL_DIR/skills/grimoire/SKILL.md")" = "spell" ]
    # Remote should get local's necronomicon
    [ "$(cat "$REMOTE_DIR/skills/necronomicon/SKILL.md")" = "dark spell" ]
}

@test "e2e: normal workflow — modify, sync, modify other side, sync" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    # Start in sync
    echo "v1" > "$LOCAL_DIR/CLAUDE.md"
    echo "v1" > "$REMOTE_DIR/CLAUDE.md"
    echo "v1" > "$BASE_DIR/CLAUDE.md"

    # Local modifies
    echo "v2 local" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "v2 local" ]

    # Now remote modifies (simulating another machine syncing)
    echo "v3 remote" > "$REMOTE_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "v3 remote" ]
}

@test "e2e: conflict detected and files untouched" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md
skills/" > "$CONFIG_DIR/synclist"
    # In sync for skills, conflict on CLAUDE.md
    echo "base" > "$BASE_DIR/CLAUDE.md"
    echo "local edit" > "$LOCAL_DIR/CLAUDE.md"
    echo "remote edit" > "$REMOTE_DIR/CLAUDE.md"
    mkdir -p "$LOCAL_DIR/skills/new" "$BASE_DIR/skills/new"
    echo "v1" > "$LOCAL_DIR/skills/new/SKILL.md"
    echo "v1" > "$BASE_DIR/skills/new/SKILL.md"
    echo "v2" > "$REMOTE_DIR/skills/new/SKILL.md" 2>/dev/null
    mkdir -p "$REMOTE_DIR/skills/new"
    echo "v2" > "$REMOTE_DIR/skills/new/SKILL.md"

    run bash ./claude-sync sync
    # Should exit non-zero due to conflicts
    [ "$status" -ne 0 ]
    # CLAUDE.md untouched on both sides
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "local edit" ]
    [ "$(cat "$REMOTE_DIR/CLAUDE.md")" = "remote edit" ]
    # But skills/new/SKILL.md should have been pulled (no conflict there, only remote changed)
    [ "$(cat "$LOCAL_DIR/skills/new/SKILL.md")" = "v2" ]
}

@test "e2e: deletion propagates correctly" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "skills/" > "$CONFIG_DIR/synclist"
    # Start with a skill on all three
    mkdir -p "$LOCAL_DIR/skills/old" "$REMOTE_DIR/skills/old" "$BASE_DIR/skills/old"
    echo "content" > "$LOCAL_DIR/skills/old/SKILL.md"
    echo "content" > "$REMOTE_DIR/skills/old/SKILL.md"
    echo "content" > "$BASE_DIR/skills/old/SKILL.md"

    # Delete locally
    rm -rf "$LOCAL_DIR/skills/old"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    # Should be gone from remote and base
    [ ! -f "$REMOTE_DIR/skills/old/SKILL.md" ]
    [ ! -f "$BASE_DIR/skills/old/SKILL.md" ]
}
```

- [ ] **Step 2: Run all tests**

```bash
bats test/
```

Expected: all tests pass.

- [ ] **Step 3: Fix any failures, re-run**

If any test fails, debug and fix. Re-run `bats test/` until all green.

- [ ] **Step 4: Commit**

```bash
git add test/test_e2e.bats
git commit -m "test: end-to-end integration tests for full sync workflow"
```

---

### Task 14: Make script executable and final polish

**Files:**
- Modify: `claude-sync`

- [ ] **Step 1: Make executable**

```bash
chmod +x claude-sync
```

- [ ] **Step 2: Run shellcheck**

```bash
shellcheck claude-sync
```

Fix any warnings.

- [ ] **Step 3: Run full test suite**

```bash
bats test/
```

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: make script executable, shellcheck fixes"
```

- [ ] **Step 5: Run full suite one last time and verify**

```bash
bats test/ && echo "All tests pass"
```
