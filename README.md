# claude-sync

Sync your Claude Code configuration across machines using rsync over SSH or git.

## Features

- **Three-way sync** — detects who changed what using a `last-sync` snapshot
- **Never overwrites** — conflicts are detected, not silently resolved
- **Claude-assisted resolution** — `/claude-sync:fix` skill merges conflicts interactively
- **Plugin sync** — `plugins.list` auto-merges across machines (installs and removals propagated)
- **Two backends** — rsync over SSH or git (works with any forge)
- **Minimal dependencies** — bash + rsync/ssh or git

## Quick start

```bash
git clone git@github.com:baptisterajaut/claude-sync.git
cd claude-sync
./claude-sync init
```

`init` symlinks the script to `~/.local/bin/`, then launches Claude with the init skill to configure your sync backend (rsync or git), run the first sync, and set up the SessionStart hook.

## Commands

| Command | Description |
|---------|-------------|
| `claude-sync sync` | Safe bidirectional sync |
| `claude-sync status` | Show per-file sync state |
| `claude-sync diff` | Show diffs between local and remote |
| `claude-sync resolve [files]` | Accept local version for conflicting files |
| `claude-sync update` | Self-update from git repo |
| `claude-sync init` | First-time setup |
| `claude-sync fix` | Launch Claude to resolve conflicts |
| `claude-sync learn` | Review project memories, promote to global CLAUDE.md |

Use `--dry-run` / `-n` with `sync` to preview without applying.

## Prerequisites

- **bash** (>= 4.0)
- Pick a sync backend:
  - **git mode** — `git` + a private repo (GitHub, GitLab, Gitea, your own dotfiles repo)
  - **rsync mode** — `rsync` + `ssh` + any server with SSH access (a Raspberry Pi, a VPS, a NAS, your prod server if you're feeling adventurous)
- **SSH key-based auth** if using rsync mode — claude-sync runs non-interactively (SessionStart hook), so password prompts will hang:

```bash
ssh-keygen -t ed25519               # if you don't have a key yet
ssh-copy-id user@your-server.com    # copy it to the server
ssh user@your-server.com "echo ok"  # verify it works without password
```

## Config

`~/.config/claude-sync/config` (created by `init`):

### rsync mode (default)
```bash
REMOTE_HOST="user@your-server.com"
REMOTE_PATH="/home/user/claude-sync-backup"  # absolute path, resolved at init
CLAUDE_DIR="$HOME/.claude"
SSH_PORT="22"  # optional, defaults to 22
```

### git mode
```bash
BACKEND="git"
GIT_REPO="/home/user/dotfiles"    # local clone of a private git repo
GIT_SUBDIR="claude-sync"          # subdirectory within the repo
CLAUDE_DIR="$HOME/.claude"
```

Works with any git forge (GitHub, GitLab, Gitea, Forgejo). Must be a private repo.

## What gets synced

`CLAUDE.md`, `settings.json`, `skills/`, `agents/` — via three-way sync (conflict detection).

`plugins.list` — auto-generated from installed plugins, auto-merged (additions and removals propagated, never conflicts).

**Never synced:** `CLAUDE.local.md`, `settings.local.json`, credentials, history, sessions, plugin cache.

## Conflict resolution

```bash
claude-sync sync        # detects conflicts, syncs non-conflicting files
claude-sync fix         # launches Claude to merge conflicts interactively
claude-sync resolve CLAUDE.md settings.json   # pushes resolved files
claude-sync sync        # confirms "Everything in sync."
```

## How it works

Three-way comparison: for each file, compare LOCAL, BASE (last-sync snapshot), and REMOTE.

- Only local changed → push to remote
- Only remote changed → pull to local
- Both changed differently → CONFLICT (no writes, notification)
- Both changed same way → update base only

No `push` or `pull` commands. No way to accidentally overwrite.

## Why not...?

| Project | Approach | Limitation |
|---------|----------|------------|
| [brianlovin/agent-config](https://github.com/brianlovin/agent-config) | Git + symlinks | Manual push/pull, no conflict detection, no plugin sync |
| [miwidot/ccms](https://github.com/miwidot/ccms) | rsync + SSH | Push/pull overwrites destination, no three-way, no plugin sync |
| [claude-code-config-sync](https://www.npmjs.com/package/claude-code-config-sync) | MCP server + git | Heavy (Node.js), git-based, no three-way snapshot, no plugin sync |

claude-sync uses a **three-way snapshot** (`last-sync/`) to detect who changed what — so it never blindly overwrites. Conflicts are resolved interactively through Claude, not silently lost. Plugin lists are auto-merged across machines without conflicts.
