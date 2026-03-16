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
REMOTE_PATH="~/claude-sync-backup"
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
