# claude-sync

Bash script + Claude Code plugin to sync `~/.claude/` config across machines via rsync over SSH.

## Architecture

- **`claude-sync`** — single bash script, all logic. Commands: `sync`, `status`, `diff`, `update`, `init`, `fix`, `resolve`
- **`skills/`** — Claude Code plugin skills (`init`, `fix`, `init-local`), invoked as `/claude-sync:init` etc.
- **`.claude-plugin/`** — plugin manifest for namespace support
- **Three-way sync** — `last-sync/` snapshot as base, checksums via md5sum, decisions per-file
- **Batch SSH** — max 3 SSH connections per sync (lock+checksums, rsync transfer, verify+unlock)

## Key design decisions

- **No push/pull** — only `sync` (bidirectional, safe) and `resolve` (explicit conflict resolution)
- **Never overwrites on conflict** — both sides untouched until resolved via Claude
- **`plugins.list`** instead of `installed_plugins.json` — machine-independent plugin names, auto-generated
- **Local-only test mode** — `REMOTE_HOST=""` makes all operations use local dirs (no SSH), used by all bats tests

## Testing

```bash
bats test/           # run all tests
bats test/test_sync.bats  # run specific test file
```

Tests use temp dirs (`/tmp`) simulating local/remote/base. No SSH needed.

## Config files (not in repo)

- `~/.config/claude-sync/config` — SSH target, remote path (machine-specific)
- `~/.config/claude-sync/last-sync/` — three-way base snapshot
- `~/.config/claude-sync/backups/` — tar.gz before local modifications

## Sync flow

1. `remote_init` — single SSH: lock + mkdir + checksums
2. `decide_action` per file — 15 cases (normal/deletion/new file)
3. Backup local if pulling
4. `batch_push`/`batch_pull` via rsync `--files-from`
5. `remote_finalize` — single SSH: verify checksums + delete + unlock
6. Update `last-sync/` base
