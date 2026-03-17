# claude-sync

Bash script + Claude Code plugin to sync `~/.claude/` config across machines via rsync over SSH or git.

## Architecture

- **`claude-sync`** — single bash script, all logic. Commands: `sync`, `status`, `diff`, `update`, `init`, `fix`, `resolve`, `learn`
- **`skills/`** — Claude Code plugin skills (`init`, `fix`, `init-local`, `learn`), invoked as `/claude-sync:init` etc.
- **`.claude-plugin/`** — plugin manifest for namespace support — load with `claude --plugin-dir <repo>`
- **Three-way sync** — `last-sync/` snapshot as base, checksums via md5sum, decisions per-file
- **Two backends** — rsync+SSH (batch SSH, max 3 connections) or git (fetch/checkout/commit/push)

## Key design decisions

- **No push/pull** — only `sync` (bidirectional, safe) and `resolve` (explicit conflict resolution)
- **Never overwrites on conflict** — both sides untouched until resolved via Claude
- **`resolve <files...>`** — the only way to force local → remote, must specify files, only works on files actually in conflict
- **`plugins.list`** — auto-generated from `installed_plugins.json`, auto-merged via three-way (additions + removals propagated, never conflicts). Not in the three-way synclist
- **Skills use `claude-sync diff > /tmp` + Edit tool** — no manual rsync/mktemp/ssh in skills
- **Git backend** — `BACKEND=git` uses a subdirectory of a local git clone as "remote". `git fetch + checkout` to read remote, `git add + commit + push` to write. Git never merges — we do, per-file
- **Local-only test mode** — `REMOTE_HOST=""` makes all operations use local dirs (no SSH), used by all bats tests

## Commands

| Command | Description |
|---------|-------------|
| `sync` | Three-way bidirectional sync, auto-merges plugins.list |
| `status` | Per-file status including plugins.list |
| `diff` | Unified diffs (fetches remote to tmpdir) |
| `resolve [files]` | Push local → remote for conflicting files only |
| `init` | Symlink + launch Claude with `/claude-sync:init` |
| `fix` | Launch Claude with `/claude-sync:fix` |
| `learn` | Launch Claude with `/claude-sync:learn` (promote project memories) |
| `update` | Git pull + reinstall plugin (follows symlink to find repo) |

## Testing

```bash
bats test/           # run all tests (82)
bats test/test_sync.bats  # sync + resolve + plugins tests
bats test/test_git.bats   # git backend tests
```

Tests use temp dirs (`/tmp`) simulating local/remote/base. No SSH needed. Git tests use local bare repos.

## Config files (not in repo)

- `~/.config/claude-sync/config` — SSH target or git repo path, backend selection
- `~/.config/claude-sync/last-sync/` — three-way base snapshot
- `~/.config/claude-sync/backups/` — tar.gz before local modifications (pull/delete only)

## Conflict resolution flow

1. `claude-sync sync` detects conflict → exit 1, lists conflicting files
2. `claude-sync fix` launches Claude with the fix skill
3. Skill runs `claude-sync diff > /tmp/claude-sync-diff.txt`, reads files with Read tool
4. Claude proposes merge, user approves, Claude writes locally with Edit tool
5. `claude-sync resolve <file1> <file2>` pushes resolved files to remote + updates base
6. `claude-sync sync` confirms "Everything in sync."
