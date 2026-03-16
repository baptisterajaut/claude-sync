# claude-sync — Design Spec

Sync tool for Claude Code configurations across multiple machines, using rsync over SSH with three-way conflict detection.

## Goals

- Sync Claude Code config (skills, agents, settings, plugins manifest) across machines
- Never lose local config — no blind overwrites
- Detect conflicts and surface them clearly (desktop notification + Claude skill for resolution)
- Zero heavy dependencies: bash + rsync + ssh
- Shareable: config file makes the script work with any SSH target

## Non-goals

- Real-time sync (not Syncthing)
- Version history (not git-based)
- Secret management (credentials are never synced)

## Architecture

### Files synced

Relative to `~/.claude/`:

| Path | Type | Notes |
|------|------|-------|
| `CLAUDE.md` | file | Global instructions |
| `settings.json` | file | Plugins, hooks, effort level |
| `skills/` | directory | Custom skills (recursive, excludes `skills/claude-sync/` — those come from the repo) |
| `agents/` | directory | Custom agents (recursive) |
| `plugins/installed_plugins.json` | file | Plugin list (used by init to reinstall — not auto-loaded by Claude Code) |
| `plugins/known_marketplaces.json` | file | Marketplace registry (needed for plugin install) |

### Files never synced

| Path | Reason |
|------|--------|
| `CLAUDE.local.md` | Machine-specific env (new convention) |
| `settings.local.json` | Machine-specific permissions |
| `skills/claude-sync/` | Managed by repo install/update, not sync |
| `.credentials.json` | Secret |
| `history.jsonl` | Session state |
| `sessions/`, `projects/`, `tasks/` | Session state |
| `plugins/cache/` | Re-downloadable |
| Everything else in `~/.claude/` | Not config |

### Directory layout

```
~/.config/claude-sync/
├── config                   # SSH target + paths (machine-specific, not synced)
├── synclist                 # Override for files to sync (optional)
├── last-sync/               # Snapshot of last successful sync (three-way base)
│   ├── CLAUDE.md
│   ├── settings.json
│   ├── skills/
│   ├── agents/
│   └── plugins/
│       └── installed_plugins.json
└── backups/                 # Timestamped backups before conflict resolution
    └── 2026-03-16T10:30:00/
```

### Config file

`~/.config/claude-sync/config` — plain key=value, sourceable by bash:

```bash
REMOTE_HOST="user@rajaut.fr"
REMOTE_PATH="/srv/claude-sync"
CLAUDE_DIR="$HOME/.claude"
REPO_DIR="$HOME/claude-syncer"       # where the claude-syncer repo is cloned
```

### Synclist

Default hardcoded in the script. Overridable by `~/.config/claude-sync/synclist` (one path per line, `#` comments):

```
CLAUDE.md
settings.json
skills/
agents/
plugins/installed_plugins.json
plugins/known_marketplaces.json
```

## Script: `claude-sync`

### Commands

| Command | Description |
|---------|-------------|
| `sync` | Bidirectional safe sync with conflict detection |
| `diff` | Show `diff -u` between local and remote for each changed file (recurses into directories) |
| `status` | Per-file summary: `clean` / `local→` / `←remote` / `CONFLICT` / `new-local` / `new-remote` |
| `update` | Self-update: pull latest claude-sync from its git repo, update script + skills (no `--dry-run` — use `git -C $REPO_DIR fetch && git -C $REPO_DIR log HEAD..origin/main` to preview) |

No `push` or `pull` commands. No unilateral overwrites.

`sync` supports `--dry-run` (`-n`) to preview actions without applying them. `update` does not support `--dry-run` (use `git -C $REPO_DIR fetch && git -C $REPO_DIR log HEAD..origin/main` to preview). Read-only commands (`diff`, `status`) are unaffected by `--dry-run`.

### Concurrency protection

**Local lock**: `~/.config/claude-sync/.lock` prevents concurrent runs on the same machine. Created at start, removed via `trap` on exit. Contains `PID TIMESTAMP`. Stale detection: if PID is not running, lock is reclaimed. PID reuse is a theoretical risk but acceptable for a personal tool (syncs are short-lived).

**Remote lock**: `$REMOTE_PATH/.claude-sync.lock` prevents concurrent syncs from different machines. Acquired/released as part of the batched SSH calls (see SSH minimization below).

### Sync algorithm (three-way)

For each entry in the synclist, compare checksums of three versions:

- **LOCAL** — `~/.claude/<path>`
- **BASE** — `~/.config/claude-sync/last-sync/<path>`
- **REMOTE** — `$REMOTE_HOST:$REMOTE_PATH/<path>`

For directories, comparison is file-by-file (a conflict on one file doesn't block others).

A file's checksum is its `md5sum` output. An absent file has a special checksum `ABSENT`.

| LOCAL vs BASE | REMOTE vs BASE | Action |
|---------------|----------------|--------|
| same | same | Nothing (clean) |
| changed | same | Propagate local → remote, update base |
| same | changed | Propagate remote → local, update base |
| changed | changed, LOCAL=REMOTE | Update base only (same change both sides) |
| changed | changed, LOCAL≠REMOTE | **CONFLICT** — notify, touch nothing |

**Deletion cases** (BASE exists but one side is now ABSENT):

| LOCAL | REMOTE | Action |
|-------|--------|--------|
| ABSENT | same as BASE | Propagate deletion to remote, remove from base |
| same as BASE | ABSENT | Propagate deletion to local, remove from base |
| ABSENT | ABSENT | Remove from base |
| ABSENT | changed (≠BASE) | **CONFLICT** — one side deleted, other modified |
| changed (≠BASE) | ABSENT | **CONFLICT** — one side modified, other deleted |

**New file cases** (no BASE entry):

| LOCAL | REMOTE | Action |
|-------|--------|--------|
| exists | ABSENT | Propagate local → remote, create base |
| ABSENT | exists | Propagate remote → local, create base |
| exists, LOCAL=REMOTE | exists | Create base only (same file both sides) |
| exists, LOCAL≠REMOTE | exists | **CONFLICT** — both sides created different versions |

Local and base checksums are computed the same way. The union of all three file lists determines the full set of files to compare (handles new/deleted files on any side).

### SSH minimization

Design principle: **minimize SSH connections** to reduce server log noise and latency. A full `sync` uses at most **3 remote connections**:

**SSH call 1 — lock + bootstrap + checksums (read-only):**

```bash
ssh "$REMOTE_HOST" '
  # Lock (atomic via noclobber)
  set -C
  echo "'"$HOSTNAME"'" > "'"$REMOTE_PATH"'/.claude-sync.lock" 2>/dev/null || {
    # Check stale (>5min)
    age=$(( $(date +%s) - $(stat -c %Y "'"$REMOTE_PATH"'/.claude-sync.lock" 2>/dev/null || echo 0) ))
    if [ "$age" -gt 300 ]; then
      rm -f "'"$REMOTE_PATH"'/.claude-sync.lock"
      echo "'"$HOSTNAME"'" > "'"$REMOTE_PATH"'/.claude-sync.lock"
    else
      echo "LOCKED_BY $(cat "'"$REMOTE_PATH"'/.claude-sync.lock")" >&2
      exit 1
    fi
  }
  set +C
  # Bootstrap
  mkdir -p "'"$REMOTE_PATH"'"
  # Checksums
  cd "'"$REMOTE_PATH"'" && find . -type f -not -name ".claude-sync.lock" -exec md5sum {} +
'
```

One connection, three jobs. Output is the checksum list; exit code signals lock failure.

**rsync call 2 — batch transfer (one per direction, or skip if nothing to transfer):**

Push (local→remote): `rsync -a --files-from=<push-list> "$CLAUDE_DIR/" "$REMOTE_HOST:$REMOTE_PATH/"`
Pull (remote→local): `rsync -a --files-from=<pull-list> "$REMOTE_HOST:$REMOTE_PATH/" "$CLAUDE_DIR/"`
Deletions (remote): `rsync -a --files-from=<delete-list> --delete --existing "$REMOTE_HOST:$REMOTE_PATH/"`

`--files-from` takes a file with one path per line. Built from the decision phase. If both push and pull are needed, that's 2 rsync calls.

For remote deletions, use a single SSH within the verify call (see below) instead of rsync --delete.

**SSH call 3 — verify checksums + delete remote files + release lock:**

```bash
ssh "$REMOTE_HOST" '
  cd "'"$REMOTE_PATH"'"
  # Verify pushed files
  md5sum <list of pushed files>
  # Delete remote files
  rm -f <list of files to delete>
  # Release lock
  rm -f .claude-sync.lock
'
```

Output is the verification checksums. Compared locally against expected values.

**Total: 2-3 SSH/rsync connections for a full sync.** If everything is clean (no changes), only SSH call 1 runs + lock release (piggybacked or separate tiny call).

For `status` and `diff` (read-only): only SSH call 1 is needed (checksums), no lock needed.

### Sync execution phases

The sync command works in phases, not file-by-file:

1. **Lock** — acquire local lock, then remote lock (SSH call 1)
2. **Checksum** — compute local + base checksums locally, remote checksums from SSH call 1 output
3. **Decide** — run three-way comparison for every file, build action lists:
   - `push_list` — files to rsync local→remote
   - `pull_list` — files to rsync remote→local
   - `delete_remote_list` — files to delete on remote
   - `delete_local_list` — files to delete locally
   - `base_update_list` — files whose base needs updating
   - `conflict_list` — files with conflicts
4. **Backup** — if `pull_list` or `delete_local_list` is non-empty, create a tar backup of the synced local files before modifying them
5. **Transfer** — execute rsync push + rsync pull + local deletes (batch)
6. **Verify + remote delete + unlock** — SSH call 3: verify pushed file checksums, delete remote files, release lock
7. **Update base** — copy final state to `last-sync/` for all modified files
8. **Notify** — if conflicts, `notify-send` + stderr

### Conflict handling

On conflict:
1. Exit code non-zero
2. Print conflicting file list to stderr
3. Desktop notification via `notify-send` (silent failure if unavailable: `notify-send ... 2>/dev/null || true`)
4. Resolution via `/claude-sync:fix` skill (interactive merge through Claude)

Non-conflicting files are still synced — a conflict on `CLAUDE.md` does not block `skills/` from syncing.

### Integrity verification

After rsync push, SSH call 3 returns checksums of pushed files on the remote. Compared locally against expected values. If mismatch:

- **Push mismatch**: error out, base not updated for that file. Next sync will retry.
- **Pull mismatch**: restore local file from backup tar. Base not updated. Next sync will retry.

### Write ordering

`last-sync/` is updated **only after** confirmed successful transfer + integrity verification. On partial failure, `last-sync/` is left unchanged — the next sync will re-detect the same changes and retry.

### Backups

Before any pull or local deletion, a backup tar is created:

```bash
~/.config/claude-sync/backups/YYYY-MM-DDTHH:MM:SS.tar.gz
```

Contains the current local state of all synced files. Lightweight (text files only, typically <100KB). Created on every sync that modifies local files (not just conflict resolution).

Backups older than 30 days are pruned during `sync` runs.

### Remote bootstrap

Handled by SSH call 1: `mkdir -p "$REMOTE_PATH"` runs before checksums. If the directory didn't exist, the checksum output is empty, which means all local files are "new-local" → push everything.

### First sync (no base exists)

When `last-sync/` is empty (new machine or first run), there is no BASE. The algorithm uses the "New file cases" table above (no BASE entry). For directories (`skills/`, `agents/`), comparison is **file-by-file inside the directory**:

- Files that exist only on one side → propagate to the other (no conflict)
- Files that exist on both sides and are identical → write base
- Files that exist on both sides and differ → **CONFLICT** on that specific file

This means non-overlapping files merge cleanly (e.g. machine A has `skills/foo/` and machine B has `skills/bar/` → both get both). Only files present on both sides with different content require interactive resolution via `/claude-sync:init`.

**Edge case — very first machine ever (no base, remote empty):** all local files propagate to remote, base is created from local. No conflicts possible.

## Skills

### `/claude-sync:init`

First-time setup, run interactively through Claude. **Idempotent** — safe to run multiple times (checks if already initialized, never duplicates hooks).

1. Check if already initialized (if so, exit early with status message)
2. Ask for SSH target (or check if `~/.config/claude-sync/config` exists)
3. Test SSH connectivity
4. **Extract local-specific content from `CLAUDE.md`** — detect machine-specific sections (OS, env, local paths) and propose moving them to `CLAUDE.local.md` before syncing
5. Create `~/.config/claude-sync/` structure
6. Run first sync — for each conflict:
   - Read both versions (local + remote)
   - Show semantic diff to user
   - Propose merge, ask for validation
   - Apply chosen resolution
7. **Install missing plugins** — read `installed_plugins.json`, extract plugin names, run `claude plugin install <name>@<marketplace>` for each plugin not already present in the local cache. Requires `known_marketplaces.json` to be synced first.
8. Configure `SessionStart` hook in `~/.claude/settings.json` (check for duplicates first)
9. Verify `claude-sync` is in PATH

### `/claude-sync:fix`

Conflict resolution through Claude:

1. Run `claude-sync status` to list conflicts
2. For each conflicting file:
   - Read all 3 versions (local, remote, base)
   - Show semantic diff (Claude understands the content, not just text diff)
   - Propose a merge
   - Ask user to validate
3. Write resolved version to local + remote
4. Update base
5. Re-run `claude-sync sync` to confirm clean state

### `/claude-sync:init-local`

Generate `~/.claude/CLAUDE.local.md` by detecting the local environment. This file is never synced.

1. Detect: OS, kernel, desktop environment, display server, shell, container runtime, Kubernetes, package manager, hostname
2. Generate `CLAUDE.local.md` with the detected values
3. If file already exists, show diff and ask before overwriting
4. Show result to user, ask if they want to add anything (project paths, VPN notes, hardware, etc.)

## Plugin sync

Claude Code does **not** auto-install plugins from `installed_plugins.json`. The file contains absolute paths to the plugin cache which are machine-specific. Syncing it provides the **list of plugins to install**, not working plugins.

On a new machine, `/claude-sync:init` reads the synced `installed_plugins.json` + `known_marketplaces.json` and runs `claude plugin install` for each missing plugin. This is the only reliable way to replicate the plugin setup.

## Hook integration

`SessionStart` hook in `~/.claude/settings.json` (configured by `/claude-sync:init`):

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

On conflict, Claude sees the non-zero exit code and stderr output, informing the user at session start.

## Self-update

`claude-sync update` pulls the latest version of the repo and reinstalls:

1. `git -C "$REPO_DIR" pull`
2. Copy `claude-sync` script to PATH location
3. Copy `skills/claude-sync/` to `~/.claude/skills/claude-sync/` (overwrite — these are repo-managed, not user-edited)

The `REPO_DIR` config value points to the local clone of the claude-syncer repo.

## Convention: `CLAUDE.local.md`

New convention for machine-specific global instructions. Lives at `~/.claude/CLAUDE.local.md`, never synced. Contains environment details (OS, shell, container runtime, local paths, etc.).

A companion skill `/claude-sync:init-local` could auto-generate this file by detecting the local environment.

## Dependencies

- **bash** (>= 4.0)
- **rsync**
- **ssh** (with key-based auth to target)
- **md5sum** (coreutils)
- **notify-send** (optional, for desktop notifications)

## Repo structure

```
claude-syncer/
├── claude-sync              # The script
├── skills/
│   └── claude-sync/
│       ├── init.md          # /claude-sync:init skill
│       ├── fix.md           # /claude-sync:fix skill
│       └── init-local.md    # /claude-sync:init-local skill
├── synclist.default         # Default synclist (reference)
└── README.md
```

## Prior art

Reviewed before finalizing this design:

| Project | Mechanism | What we learned |
|---------|-----------|-----------------|
| [miwidot/ccms](https://github.com/miwidot/ccms) | rsync + SSH | Lock file + trap pattern, checksum verification post-sync, dry-run + confirmation. No three-way — push/pull overwrites the destination. |
| [brianlovin/agent-config](https://github.com/brianlovin/agent-config) | git + symlinks | Backup manifests with JSON metadata, interactive conflict resolution menu. Symlink approach is clever but fragile with rsync. |
| [claude-code-config-sync](https://www.npmjs.com/package/claude-code-config-sync) | MCP server + git | File-level conflict detection before push, staging directory for safe merge analysis. Heavy (TypeScript/Node.js MCP server). |

None implement three-way sync with a last-sync snapshot. All use push/pull which risks overwrites.

## Known limitations

- **TOCTOU window**: checksum fetch and rsync are not atomic. A file changing on the remote between the two could cause a silent overwrite. Mitigated by the remote lock (held for the entire sync duration) and post-sync integrity verification.
- **`settings.json` is JSON but treated as opaque blob**: conflict resolution via `/claude-sync:fix` should be JSON-aware (merge keys, not pick-one-version). The skill handles this since Claude understands JSON structure.

## Resolved questions

- **Plugin auto-install**: Claude Code does NOT auto-install from `installed_plugins.json`. The file contains absolute paths and is a state record, not a declarative manifest. `/claude-sync:init` handles plugin installation by reading the synced file and running `claude plugin install` for each missing plugin.
