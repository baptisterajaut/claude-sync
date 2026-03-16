---
name: init
description: >
  First-time setup of claude-sync — install script, configure SSH target, test connectivity,
  run initial sync with interactive conflict resolution, configure SessionStart hook.
  TRIGGER when: user wants to set up claude-sync on a new machine.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# /claude-sync:init — First-Time Setup

You are setting up claude-sync for the first time on this machine. Follow these steps interactively.

**IMPORTANT — Idempotency:** This skill must be safe to run multiple times. At each step, check if work is already done before acting. Never duplicate hooks, symlinks, configs, or file entries.

## Step 0: Check if already initialized

Run: `claude-sync status 2>&1`

If it succeeds (exit 0, outputs file status), claude-sync is already configured. Tell the user:

> "claude-sync is already initialized on this machine. Run `claude-sync status` to see current state, or `claude-sync fix` to resolve conflicts."

**Stop here** unless the user explicitly wants to re-initialize.

## Step 1: Check prerequisites and PATH

The symlink to `claude-sync` in `~/.local/bin/` is already created by the `claude-sync init` bash command before this skill launches. But `~/.local/bin` may not be in the user's PATH persistently.

Run: `which claude-sync`

If it works, good. If not, `~/.local/bin` isn't in PATH. Fix it:

1. Detect the user's shell: `echo $SHELL`
2. Determine the rc file:
   - `/bin/bash` or `/usr/bin/bash` → `~/.bashrc`
   - `/bin/zsh` or `/usr/bin/zsh` → `~/.zshrc`
   - Other → `~/.profile`
3. Check if the PATH export already exists: `grep -F '.local/bin' <rc-file>`
4. If not present, append:
   ```bash
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> <rc-file>
   ```
5. Tell the user it's been added and will take effect on next shell (current session already has it via `claude-sync init`).

Also check:
- `which rsync` — must be available
- `which ssh` — must be available

If rsync or ssh is missing, tell the user to install them.

## Step 2: Configure SSH target

Check if `~/.config/claude-sync/config` exists. If it does, read it and confirm with the user.

If it doesn't exist:
1. Ask the user for their SSH target (e.g. `user@server.example.com`)
2. Ask for the remote path (suggest `claude-sync-backup` as default — relative to the remote user's home)
3. **Resolve to absolute path**: run `ssh <HOST> "echo \$HOME"` and prepend it to the relative path (e.g. if remote HOME is `/root` and user said `claude-sync-backup`, store `/root/claude-sync-backup`). Always store an absolute path.
4. Create the config:

```bash
mkdir -p ~/.config/claude-sync
cat > ~/.config/claude-sync/config <<'EOF'
REMOTE_HOST="<user-provided>"
REMOTE_PATH="<resolved-absolute-path>"
CLAUDE_DIR="$HOME/.claude"
EOF
```

## Step 3: Test SSH connectivity

Run: `ssh -o ConnectTimeout=5 <REMOTE_HOST> "echo ok"`

If it fails, help the user debug (key not copied, host unreachable, etc.). Do not proceed until SSH works.

## Step 4: Extract local-specific content from CLAUDE.md

Before syncing, check if `~/.claude/CLAUDE.md` contains machine-specific sections (OS, shell, local paths, container runtime, hardware, etc.).

If machine-specific content is found:
1. Show the user which sections look machine-specific
2. Propose moving them to `~/.claude/CLAUDE.local.md` (which is never synced)
3. If user agrees, create `CLAUDE.local.md` with the extracted sections and remove them from `CLAUDE.md`
4. If `CLAUDE.local.md` already exists, propose merging instead of overwriting

If no machine-specific content is found, skip this step.

**Heuristics for detecting local content:** sections mentioning specific OS names (Ubuntu, Arch, Fedora), kernel versions, `localhost`, IP addresses, hardware models, desktop environments, local file paths outside `~/`.

## Step 5: Run first sync

Run: `claude-sync sync`

- If it succeeds with no conflicts → move to step 7
- If it fails with conflicts → for each conflicting file:
  1. Read the local version: `cat ~/.claude/<file>`
  2. Read the remote version: `ssh <REMOTE_HOST> "cat <REMOTE_PATH>/<file>"`
  3. Show the user both versions with a semantic explanation of the differences
  4. Propose a merged version that combines both (e.g. for CLAUDE.md, merge unique sections; for settings.json, merge JSON keys)
  5. Ask the user to approve the merge
  6. Once approved, write the resolved version:
     ```bash
     # Write locally
     cat > ~/.claude/<file> <<'EOF'
     <merged content>
     EOF
     # Copy to remote
     rsync -a ~/.claude/<file> <REMOTE_HOST>:<REMOTE_PATH>/<file>
     # Update base snapshot
     mkdir -p ~/.config/claude-sync/last-sync/$(dirname <file>)
     cp ~/.claude/<file> ~/.config/claude-sync/last-sync/<file>
     ```
  7. After resolving ALL conflicts, run `claude-sync sync` again to confirm clean state

## Step 6: Install missing plugins

After sync, check if `~/.claude/plugins/installed_plugins.json` was synced and contains plugins not present locally:

1. Read `~/.claude/plugins/installed_plugins.json`
2. For each plugin entry, check if its `installPath` directory exists
3. For missing plugins, extract `name@marketplace` from the key and run:
   ```bash
   claude plugin install <name>@<marketplace> --scope user
   ```
4. If a plugin fails to install, warn and continue (don't block the init)

## Step 7: Configure SessionStart hook

Read `~/.claude/settings.json`.

**Check first:** Search for `"claude-sync sync"` in the file. If it already exists anywhere in the hooks, skip this step entirely. Do NOT add a duplicate.

If not present, add a `SessionStart` hook. The exact JSON structure for the hooks entry is:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "claude-sync sync"
          }
        ]
      }
    ]
  }
}
```

**Merge carefully:** Read the full current `settings.json`, add/update only the `hooks` key, preserve all other keys (`enabledPlugins`, `effortLevel`, etc.). If `hooks` already exists with other event types, keep those and add `SessionStart` alongside them. If `SessionStart` already has other hooks, append to the array rather than replacing.

## Step 8: Verify

Run `claude-sync status` and show the user the result. Confirm everything is clean.

Tell the user: "claude-sync is configured. Your config will sync automatically at the start of each Claude session. Run `/claude-sync:init-local` to generate a machine-specific CLAUDE.local.md."
