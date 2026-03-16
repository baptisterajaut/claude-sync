# claude-sync

Bash script + Claude Code plugin to sync `~/.claude/` config across machines via rsync over SSH.

## Architecture

- **`claude-sync`** — single bash script, all logic. Commands: `sync`, `status`, `diff`, `update`, `init`, `fix`, `resolve`
- **`skills/`** — Claude Code plugin skills (`init`, `fix`, `init-local`), invoked as `/claude-sync:init` etc.
- **`.claude-plugin/`** — plugin manifest for namespace support — load with `claude --plugin-dir <repo>`
- **Three-way sync** — `last-sync/` snapshot as base, checksums via md5sum, decisions per-file
- **Batch SSH** — max 3 SSH connections per sync (lock+checksums, rsync transfer, verify+unlock)

## Key design decisions

- **No push/pull** — only `sync` (bidirectional, safe) and `resolve` (explicit conflict resolution)
- **Never overwrites on conflict** — both sides untouched until resolved via Claude
- **`resolve <files...>`** — the only way to force local → remote, must specify files, only works on files actually in conflict
- **`plugins.list`** — auto-generated from `installed_plugins.json`, merged as union (additive), not in the three-way synclist. Conflict only if remote removed a plugin
- **Skills use `claude-sync diff > /tmp` + Edit tool** — no manual rsync/mktemp/ssh in skills
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
| `update` | Git pull + reinstall plugin (follows symlink to find repo) |

## Testing

```bash
bats test/           # run all tests (65)
bats test/test_sync.bats  # sync + resolve tests
```

Tests use temp dirs (`/tmp`) simulating local/remote/base. No SSH needed.

## Config files (not in repo)

- `~/.config/claude-sync/config` — SSH target, remote path (absolute, resolved at init)
- `~/.config/claude-sync/last-sync/` — three-way base snapshot
- `~/.config/claude-sync/backups/` — tar.gz before local modifications (pull/delete only)

## Conflict resolution flow

1. `claude-sync sync` detects conflict → exit 1, lists conflicting files
2. `claude-sync fix` launches Claude with the fix skill
3. Skill runs `claude-sync diff > /tmp/claude-sync-diff.txt`, reads files with Read tool
4. Claude proposes merge, user approves, Claude writes locally with Edit tool
5. `claude-sync resolve <file1> <file2>` pushes resolved files to remote + updates base
6. `claude-sync sync` confirms "Everything in sync."
