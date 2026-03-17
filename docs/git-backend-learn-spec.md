# Git Backend + Learn Skill — Design Spec

Two additions to claude-sync: a git transport backend (alternative to rsync) and a `/claude-sync:learn` skill.

## Feature 1: Git Backend

### Config

```bash
BACKEND="git"                          # "rsync" (default) or "git"
GIT_REPO="/home/user/dotfiles"        # local clone path
GIT_SUBDIR="claude-sync"              # subdirectory within the repo
```

### How it works

Git is **only a transport** — our three-way logic is unchanged. The subdir in the git repo plays the role of "remote".

**Flow for `cmd_sync`:**

1. `git fetch` (get latest, no working tree changes)
2. `git checkout origin/main -- "$GIT_SUBDIR/"` (materialize remote state into subdir)
3. Checksums: local from `~/.claude/`, base from `last-sync/`, remote from subdir (all local, fast)
4. `decide_action` per file — same three-way logic
5. **pull** files: subdir → `~/.claude/` + update base
6. **push** files: `~/.claude/` → subdir
7. **conflict** files: touch nothing
8. Plugins.list: same auto-merge
9. If subdir changed: `git add + commit + push`
10. If push fails: re-fetch, re-checkout, re-sync (max 3 retries)
11. Update base

**Key insight:** `git checkout origin/main -- subdir/` = "read remote". `git add + commit + push` = "write to remote". Git never merges — we do, per-file.

### `cmd_resolve` in git mode

1. `git fetch + checkout subdir/`
2. Three-way: non-conflicting files sync normally
3. Resolved files: `~/.claude/` → subdir (local wins)
4. `git add + commit + push` (normal commit, no force push)
5. Update base

### `cmd_status` / `cmd_diff`

Read-only. No fetch. Read current subdir state. User runs `sync` first for fresh data.

### No remote lock

Git push is atomic. Retry loop handles diverged remote. No `.claude-sync.lock`.

### `load_config`

```bash
BACKEND="${BACKEND:-rsync}"
if [[ "$BACKEND" == "git" ]]; then
    : "${GIT_REPO:?GIT_REPO not set}"
    : "${GIT_SUBDIR:?GIT_SUBDIR not set}"
    REMOTE_HOST=""
    REMOTE_PATH="$GIT_REPO/$GIT_SUBDIR"
    mkdir -p "$REMOTE_PATH"
else
    : "${REMOTE_PATH:?REMOTE_PATH not set}"
    CLAUDE_DIR="${CLAUDE_DIR/#\~/$HOME}"
fi
```

### New functions

```bash
git_pre_sync() {
    if [[ -n $(git -C "$GIT_REPO" status --porcelain "$GIT_SUBDIR") ]]; then
        echo "error: $GIT_SUBDIR has uncommitted changes" >&2
        return 1
    fi
    git -C "$GIT_REPO" fetch || return 1
    git -C "$GIT_REPO" checkout origin/main -- "$GIT_SUBDIR/" 2>/dev/null || true
}

git_post_sync() {
    [[ -z $(git -C "$GIT_REPO" status --porcelain "$GIT_SUBDIR") ]] && return 0
    git -C "$GIT_REPO" add "$GIT_SUBDIR"
    git -C "$GIT_REPO" commit -m "claude-sync: update"
    local attempts=0
    while ! git -C "$GIT_REPO" push 2>/dev/null; do
        (( attempts++ )) || true
        if (( attempts >= 3 )); then
            echo "error: git push failed after 3 attempts" >&2
            return 1
        fi
        git -C "$GIT_REPO" pull --rebase || return 1
    done
}
```

### Init (git mode)

Skill detects: `user@host` → rsync. Path/URL with `.git` or known forge → git.

Checks: clone exists? SSH or HTTPS? repo private? (ask user). subdir exists? push works?

### Duplicate files

Base (`last-sync/`) + subdir both local. Small overhead (text files). Price for per-file conflict independence from git.

### Testing

Local bare repo, no network:
```bash
git init --bare /tmp/test-remote.git && git clone /tmp/test-remote.git /tmp/test-repo
```

---

## Feature 2: `/claude-sync:learn`

```bash
claude-sync learn    # launches Claude with /claude-sync:learn
```

### Skill steps

1. Derive memory path: `pwd | sed 's|/|-|g'` → `~/.claude/projects/<encoded>/memory/`
2. Check exists, bail if empty
3. Read each `*.md` (not MEMORY.md)
4. Classify: project-specific (keep) / general (promote) / stale (remove)
5. Propose promotions with wording for `~/.claude/CLAUDE.md`
6. Apply via Edit tool with user approval
7. Cleanup fully-promoted files only

### Script

```bash
learn) cmd_launch_skill "learn" ;;
```

No load_config needed.
