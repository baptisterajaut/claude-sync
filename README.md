# claude-sync

Sync your Claude Code configuration across machines using rsync over SSH.

## Features

- **Three-way sync** — detects who changed what using a `last-sync` snapshot
- **Never overwrites** — conflicts are detected, not silently resolved
- **Claude-assisted resolution** — `/claude-sync:fix` skill merges conflicts interactively
- **Plugin sync** — `plugins.list` auto-merges across machines (union of all plugins)
- **Minimal dependencies** — bash, rsync, ssh

## Quick start

```bash
git clone git@github.com:baptisterajaut/claude-sync.git
cd claude-sync
./claude-sync init
```

`init` symlinks the script to `~/.local/bin/`, then launches Claude with the init skill to configure SSH, run the first sync, and set up the SessionStart hook.

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

Use `--dry-run` / `-n` with `sync` to preview without applying.

## Config

`~/.config/claude-sync/config` (created by `init`):

```bash
REMOTE_HOST="user@your-server.com"
REMOTE_PATH="/home/user/claude-sync-backup"  # absolute path, resolved at init
CLAUDE_DIR="$HOME/.claude"
```

## What gets synced

| Path | Method |
|------|--------|
| `CLAUDE.md` | Three-way sync |
| `settings.json` | Three-way sync |
| `skills/` | Three-way sync (excludes `skills/claude-sync/`) |
| `agents/` | Three-way sync |
| `plugins.list` | Additive merge (union of all machines' plugins) |

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
