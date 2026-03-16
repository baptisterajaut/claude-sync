---
name: init
description: >
  First-time setup of claude-sync — configure SSH target, test connectivity,
  run initial sync with interactive conflict resolution, configure SessionStart hook.
  TRIGGER when: user wants to set up claude-sync on a new machine.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
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
- `which claude-sync` — if not found, ask user where the claude-sync repo is cloned and suggest running `./claude-sync install`

## Step 2: Check existing config

Check if `~/.config/claude-sync/config` exists. If it does, read it and confirm with the user.

If it doesn't exist:
1. Ask the user for their SSH target (e.g. `user@server.example.com`)
2. Ask for the remote path (suggest `~/claude-sync-backup` as default). Note: `~` is expanded using the local `$HOME` — if the remote user has a different home directory, use an absolute path instead.
3. Create the config file:

```bash
mkdir -p ~/.config/claude-sync
cat > ~/.config/claude-sync/config <<EOF
REMOTE_HOST="<user-provided>"
REMOTE_PATH="<user-provided>"
CLAUDE_DIR="$HOME/.claude"
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
  6. Write the merged version to both local and remote
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

If not present, add the SessionStart hook. Be careful to merge with existing hooks — do not overwrite other hooks that may exist. Read the current JSON, add to the array, write back.

## Step 8: Verify

Run `claude-sync status` and show the user the result. Confirm everything is clean.

Print: "claude-sync is configured. Your config will sync automatically at the start of each Claude session. Run `/claude-sync:init-local` to generate machine-specific CLAUDE.local.md."
