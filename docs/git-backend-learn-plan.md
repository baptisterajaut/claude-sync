# Git Backend + Learn Skill — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add git transport backend (alternative to rsync) and `/claude-sync:learn` skill for promoting project memories to global CLAUDE.md.

**Architecture:** Two independent features. Git backend: modify `load_config` to handle `BACKEND=git`, add `git_pre_sync`/`git_post_sync`, branch `cmd_sync`/`cmd_resolve` to use them instead of SSH calls. Learn skill: new skill markdown + `learn` command dispatch.

**Tech Stack:** Bash, git, bats-core

**Spec:** `docs/git-backend-learn-spec.md`

---

## Chunk 1: Git Backend

### Task 1: `load_config` git mode + `git_pre_sync` / `git_post_sync`

**Files:**
- Modify: `claude-sync`
- Create: `test/test_git.bats`

- [ ] **Step 1: Write git backend tests**

Create `test/test_git.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
    setup_test_env
    # Set up a local bare repo as "remote" for git tests
    export GIT_BARE="$TEST_DIR/bare.git"
    export GIT_CLONE="$TEST_DIR/repo"
    export GIT_SUBDIR="claude-sync-data"
    git init --bare "$GIT_BARE" >/dev/null 2>&1
    git clone "$GIT_BARE" "$GIT_CLONE" >/dev/null 2>&1
    mkdir -p "$GIT_CLONE/$GIT_SUBDIR"
    # Initial commit so origin/main exists
    touch "$GIT_CLONE/$GIT_SUBDIR/.gitkeep"
    git -C "$GIT_CLONE" add . >/dev/null 2>&1
    git -C "$GIT_CLONE" commit -m "init" >/dev/null 2>&1
    git -C "$GIT_CLONE" push >/dev/null 2>&1

    # Rewrite config for git backend
    cat > "$CONFIG_DIR/config" <<EOF
BACKEND="git"
GIT_REPO="$GIT_CLONE"
GIT_SUBDIR="$GIT_SUBDIR"
CLAUDE_DIR="$LOCAL_DIR"
EOF
}

teardown() { teardown_test_env; }

@test "git: load_config sets REMOTE_PATH from GIT_REPO+GIT_SUBDIR" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    [ "$REMOTE_PATH" = "$GIT_CLONE/$GIT_SUBDIR" ]
    [ "$REMOTE_HOST" = "" ]
    [ "$BACKEND" = "git" ]
}

@test "git: git_pre_sync fetches and checks out subdir" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    # Simulate a remote change: clone again, push a file
    local other="$TEST_DIR/other"
    git clone "$GIT_BARE" "$other" >/dev/null 2>&1
    echo "remote content" > "$other/$GIT_SUBDIR/CLAUDE.md"
    git -C "$other" add . >/dev/null 2>&1
    git -C "$other" commit -m "add file" >/dev/null 2>&1
    git -C "$other" push >/dev/null 2>&1
    # Our clone doesn't have it yet
    [ ! -f "$GIT_CLONE/$GIT_SUBDIR/CLAUDE.md" ]
    # After pre_sync, it should
    git_pre_sync
    [ -f "$GIT_CLONE/$GIT_SUBDIR/CLAUDE.md" ]
    [ "$(cat "$GIT_CLONE/$GIT_SUBDIR/CLAUDE.md")" = "remote content" ]
}

@test "git: git_pre_sync fails on dirty working tree" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "dirty" > "$GIT_CLONE/$GIT_SUBDIR/dirty.txt"
    run git_pre_sync
    [ "$status" -ne 0 ]
    [[ "$output" == *"uncommitted changes"* ]]
}

@test "git: git_post_sync commits and pushes changes" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    echo "new file" > "$GIT_CLONE/$GIT_SUBDIR/test.md"
    git_post_sync
    # Verify it was pushed: clone fresh and check
    local verify="$TEST_DIR/verify"
    git clone "$GIT_BARE" "$verify" >/dev/null 2>&1
    [ "$(cat "$verify/$GIT_SUBDIR/test.md")" = "new file" ]
}

@test "git: git_post_sync does nothing when no changes" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    source ./claude-sync --source-only
    load_config
    local before
    before=$(git -C "$GIT_CLONE" rev-parse HEAD)
    git_post_sync
    local after
    after=$(git -C "$GIT_CLONE" rev-parse HEAD)
    [ "$before" = "$after" ]
}

@test "git: full sync pushes local changes to git repo" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "my config" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    # Verify pushed to bare repo
    local verify="$TEST_DIR/verify"
    git clone "$GIT_BARE" "$verify" >/dev/null 2>&1
    [ "$(cat "$verify/$GIT_SUBDIR/CLAUDE.md")" = "my config" ]
    # Base should be updated
    [ "$(cat "$BASE_DIR/CLAUDE.md")" = "my config" ]
}

@test "git: full sync pulls remote changes" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    # Push a file from another "machine"
    local other="$TEST_DIR/other"
    git clone "$GIT_BARE" "$other" >/dev/null 2>&1
    echo "from other" > "$other/$GIT_SUBDIR/CLAUDE.md"
    git -C "$other" add . >/dev/null 2>&1
    git -C "$other" commit -m "add" >/dev/null 2>&1
    git -C "$other" push >/dev/null 2>&1
    run bash ./claude-sync sync
    [ "$status" -eq 0 ]
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "from other" ]
}

@test "git: sync detects conflict same as rsync mode" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "base" > "$LOCAL_DIR/CLAUDE.md"
    echo "base" > "$BASE_DIR/CLAUDE.md"
    # Push different version from another machine
    echo "base" > "$GIT_CLONE/$GIT_SUBDIR/CLAUDE.md"
    git -C "$GIT_CLONE" add . >/dev/null 2>&1
    git -C "$GIT_CLONE" commit -m "base" >/dev/null 2>&1
    git -C "$GIT_CLONE" push >/dev/null 2>&1
    local other="$TEST_DIR/other"
    git clone "$GIT_BARE" "$other" >/dev/null 2>&1
    echo "remote change" > "$other/$GIT_SUBDIR/CLAUDE.md"
    git -C "$other" add . >/dev/null 2>&1
    git -C "$other" commit -m "change" >/dev/null 2>&1
    git -C "$other" push >/dev/null 2>&1
    # Local also changed
    echo "local change" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync sync
    [ "$status" -ne 0 ]
    [[ "$output" == *"CONFLICT"* ]]
    # Both sides untouched
    [ "$(cat "$LOCAL_DIR/CLAUDE.md")" = "local change" ]
}

@test "git: resolve pushes resolved files" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "base" > "$LOCAL_DIR/CLAUDE.md"
    echo "base" > "$BASE_DIR/CLAUDE.md"
    echo "base" > "$GIT_CLONE/$GIT_SUBDIR/CLAUDE.md"
    git -C "$GIT_CLONE" add . >/dev/null 2>&1
    git -C "$GIT_CLONE" commit -m "base" >/dev/null 2>&1
    git -C "$GIT_CLONE" push >/dev/null 2>&1
    local other="$TEST_DIR/other"
    git clone "$GIT_BARE" "$other" >/dev/null 2>&1
    echo "remote" > "$other/$GIT_SUBDIR/CLAUDE.md"
    git -C "$other" add . >/dev/null 2>&1
    git -C "$other" commit -m "change" >/dev/null 2>&1
    git -C "$other" push >/dev/null 2>&1
    echo "merged" > "$LOCAL_DIR/CLAUDE.md"
    run bash ./claude-sync resolve CLAUDE.md
    [ "$status" -eq 0 ]
    # Verify resolved version in git
    local verify="$TEST_DIR/verify"
    git clone "$GIT_BARE" "$verify" >/dev/null 2>&1
    [ "$(cat "$verify/$GIT_SUBDIR/CLAUDE.md")" = "merged" ]
}

@test "git: status does not fetch (read-only)" {
    export CLAUDE_SYNC_CONFIG_DIR="$CONFIG_DIR"
    echo "CLAUDE.md" > "$CONFIG_DIR/synclist"
    echo "same" > "$LOCAL_DIR/CLAUDE.md"
    echo "same" > "$BASE_DIR/CLAUDE.md"
    echo "same" > "$GIT_CLONE/$GIT_SUBDIR/CLAUDE.md"
    git -C "$GIT_CLONE" add . >/dev/null 2>&1
    git -C "$GIT_CLONE" commit -m "same" >/dev/null 2>&1
    git -C "$GIT_CLONE" push >/dev/null 2>&1
    # Push a change from another machine
    local other="$TEST_DIR/other"
    git clone "$GIT_BARE" "$other" >/dev/null 2>&1
    echo "changed" > "$other/$GIT_SUBDIR/CLAUDE.md"
    git -C "$other" add . >/dev/null 2>&1
    git -C "$other" commit -m "change" >/dev/null 2>&1
    git -C "$other" push >/dev/null 2>&1
    # Status should still show clean (no fetch)
    run bash ./claude-sync status
    [ "$status" -eq 0 ]
    [[ "$output" == *"clean"* ]]
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
bats test/test_git.bats
```

- [ ] **Step 3: Implement `load_config` git mode**

In `claude-sync`, replace the current `load_config` validation section:

```bash
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "error: not configured (no config at $CONFIG_FILE)" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    : "${CLAUDE_DIR:?CLAUDE_DIR not set in $CONFIG_FILE}"
    CLAUDE_DIR="${CLAUDE_DIR/#\~/$HOME}"

    BACKEND="${BACKEND:-rsync}"
    if [[ "$BACKEND" == "git" ]]; then
        : "${GIT_REPO:?GIT_REPO not set in $CONFIG_FILE}"
        : "${GIT_SUBDIR:?GIT_SUBDIR not set in $CONFIG_FILE}"
        REMOTE_HOST=""
        REMOTE_PATH="$GIT_REPO/$GIT_SUBDIR"
        mkdir -p "$REMOTE_PATH"
    else
        : "${REMOTE_PATH:?REMOTE_PATH not set in $CONFIG_FILE}"
        SSH_PORT="${SSH_PORT:-22}"
        SSH_CMD="ssh -p $SSH_PORT"
        RSYNC_SSH="ssh -p $SSH_PORT"
    fi
}
```

- [ ] **Step 4: Implement `git_pre_sync` and `git_post_sync`**

Add before the `--source-only` guard:

```bash
# --- Git backend ---

git_pre_sync() {
    if [[ -n $(git -C "$GIT_REPO" status --porcelain "$GIT_SUBDIR") ]]; then
        echo "error: $GIT_SUBDIR has uncommitted changes in $GIT_REPO" >&2
        return 1
    fi
    git -C "$GIT_REPO" fetch || return 1
    git -C "$GIT_REPO" checkout origin/main -- "$GIT_SUBDIR/" 2>/dev/null || true
}

git_post_sync() {
    [[ -z $(git -C "$GIT_REPO" status --porcelain "$GIT_SUBDIR") ]] && return 0
    git -C "$GIT_REPO" add "$GIT_SUBDIR"
    git -C "$GIT_REPO" commit -m "claude-sync: update" >/dev/null
    local attempts=0
    while ! git -C "$GIT_REPO" push 2>/dev/null; do
        (( attempts++ )) || true
        if (( attempts >= 3 )); then
            echo "error: git push failed after 3 attempts" >&2
            return 1
        fi
        git -C "$GIT_REPO" pull --rebase >/dev/null || return 1
    done
}
```

- [ ] **Step 5: Branch `cmd_sync` for git mode**

In `cmd_sync`, replace the remote_init / remote_finalize blocks:

```bash
# Phase 1
if [[ "$BACKEND" == "git" ]]; then
    git_pre_sync || return 1
    _load_checksums_into REMOTE_CHECKSUMS "$REMOTE_PATH"
else
    acquire_local_lock
    local remote_checksums
    if ! remote_checksums=$(remote_init); then
        echo "error: could not connect to remote (locked or unreachable)" >&2
        return 1
    fi
    _load_remote_checksums_from_output "$remote_checksums"
    trap 'release_remote_lock; release_local_lock' EXIT
fi
```

And at the end (replacing remote_finalize):

```bash
# Phase: finalize
if [[ "$BACKEND" == "git" ]]; then
    git_post_sync
else
    local verify_file="$tmpdir/verify_list"
    # ... existing remote_finalize code ...
fi
```

Also update `cmd_resolve` the same way — skip locks, use `git_pre_sync`/`git_post_sync`.

- [ ] **Step 6: Run tests**

```bash
bats test/test_git.bats
bats test/  # full suite — ensure nothing breaks
```

- [ ] **Step 7: Commit**

```bash
git add claude-sync test/test_git.bats
git commit -m "feat: git transport backend as alternative to rsync"
```

---

### Task 2: Update init skill for git mode

**Files:**
- Modify: `skills/init/SKILL.md`

- [ ] **Step 1: Update the init skill**

Add git mode detection and checks to the skill. In Step 2 (Configure SSH target), replace the single-path flow with:

```markdown
## Step 2: Configure sync target

Ask: "Where should your config be synced? Give me either:
- An SSH target (e.g. `user@myserver.com`) for rsync mode
- A git repo path or URL for git mode (can be a subdirectory of an existing dotfiles repo)"

**Detect mode from answer:**
- Contains `@` without `.git` and no known forge domain → rsync mode
- Contains `.git`, or is a local directory with `.git/` inside, or mentions github/gitlab/gitea/forgejo → git mode

**If rsync mode:** existing flow (SSH port, remote path, resolve to absolute, etc.)

**If git mode:**
1. If it's a URL, ask where to clone it locally (suggest `~/dotfiles` or similar)
2. If it's a local path, verify it's a git repo (`test -d <path>/.git`)
3. Check remote URL: `git -C <path> remote get-url origin`
   - If HTTPS, warn: "HTTPS remotes require a credential helper or token for push. SSH remotes are recommended."
4. Ask: "Is this repo private?" (no automated check)
5. Ask for the subdirectory name within the repo (suggest `claude-sync`)
6. Verify subdirectory exists or create it
7. Test push: `git -C <path> push --dry-run`
8. Create config:

```bash
mkdir -p ~/.config/claude-sync
cat > ~/.config/claude-sync/config <<'EOF'
BACKEND="git"
GIT_REPO="<local-path>"
GIT_SUBDIR="<subdirectory>"
CLAUDE_DIR="$HOME/.claude"
EOF
```
```

- [ ] **Step 2: Commit**

```bash
git add skills/init/SKILL.md
git commit -m "feat: init skill supports git backend configuration"
```

---

### Task 3: Update README and CLAUDE.md

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update README**

Add git backend to Config section:

```markdown
## Config

### rsync mode (default)
`~/.config/claude-sync/config`:
```bash
REMOTE_HOST="user@your-server.com"
REMOTE_PATH="/home/user/claude-sync-backup"
CLAUDE_DIR="$HOME/.claude"
SSH_PORT="22"
```

### git mode
```bash
BACKEND="git"
GIT_REPO="/home/user/dotfiles"
GIT_SUBDIR="claude-sync"
CLAUDE_DIR="$HOME/.claude"
```
Works with any git forge (GitHub, GitLab, Gitea, Forgejo). Use a private repo.
```

Update prerequisites to mention git as optional.

Add `learn` to commands table:

```markdown
| `claude-sync learn` | Review project memories, promote to global CLAUDE.md |
```

- [ ] **Step 2: Update CLAUDE.md**

Add git backend to architecture and key design decisions.

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: document git backend and learn command"
```

---

## Chunk 2: Learn Skill

### Task 4: Learn skill and command dispatch

**Files:**
- Create: `skills/learn/SKILL.md`
- Modify: `claude-sync`

- [ ] **Step 1: Create the learn skill**

Create `skills/learn/SKILL.md`:

```markdown
---
name: learn
description: >
  Review current project's memories and propose promotions to global CLAUDE.md.
  Identifies general patterns worth keeping across all projects.
  TRIGGER when: user wants to consolidate learnings from current project.
allowed-tools: Bash, Read, Edit, Write
---

# /claude-sync:learn — Promote Project Memories

Review the current project's memories and propose promotions to the global `~/.claude/CLAUDE.md`.

## Step 1: Find project memories

Derive the memory path from the current directory:

```bash
project_path=$(pwd | sed 's|/|-|g')
memory_dir="$HOME/.claude/projects/$project_path/memory"
ls "$memory_dir"/*.md 2>/dev/null | grep -v MEMORY.md
```

If the directory doesn't exist or has no memory files, tell the user: "No project memories found for this directory." and stop.

## Step 2: Read memories

Read each memory file found (using the Read tool, not cat). Also read `~/.claude/CLAUDE.md` to understand what's already in the global config.

## Step 3: Classify

For each memory, determine:
- **Project-specific** — API quirks, codebase structure, domain knowledge, specific bugs → keep as project memory
- **General pattern** — workflow preferences, coding style, tool usage, feedback that applies everywhere → promote candidate
- **Stale** — outdated, redundant, or already in global CLAUDE.md → removal candidate

## Step 4: Propose

Show the user a summary:
- Memories to promote, with proposed wording for CLAUDE.md
- Memories to keep (explain why they're project-specific)
- Stale memories to remove

## Step 5: Apply

For each promotion the user approves:
1. Edit `~/.claude/CLAUDE.md` to add the content in the appropriate section
2. If the **entire** memory file was promoted, offer to delete it and update the project's MEMORY.md index

Do NOT delete a memory file if only part of it was promoted.
```

- [ ] **Step 2: Add `learn` command to script**

In the usage text, add:
```
    learn     Review project memories and promote to global CLAUDE.md
```

In the command dispatch:
```bash
    learn)   cmd_launch_skill "learn" ;;
```

- [ ] **Step 3: Run full test suite**

```bash
bats test/
```

All existing tests should pass (learn is just a command dispatch, no logic changes).

- [ ] **Step 4: Commit**

```bash
git add skills/learn/SKILL.md claude-sync
git commit -m "feat: learn skill for promoting project memories to global CLAUDE.md"
```

---

### Task 5: Final verification

- [ ] **Step 1: Run full test suite**

```bash
bats test/
```

All tests pass (72 existing + new git tests).

- [ ] **Step 2: Test git backend manually (if a git repo is available)**

```bash
# Create a test repo
mkdir /tmp/test-dotfiles && cd /tmp/test-dotfiles && git init
git commit --allow-empty -m "init"
# ... set up a bare remote or use a real one
```

- [ ] **Step 3: Push**

```bash
git push
```
