---
name: fix
description: >
  Resolve claude-sync conflicts — shows semantic diffs of conflicting files
  and guides interactive merge resolution.
  TRIGGER when: claude-sync reports conflicts, or user asks to fix sync conflicts.
---

# /claude-sync-fix — Conflict Resolution

You are resolving sync conflicts detected by claude-sync. Follow these steps.

## Step 1: Get conflict list

Run: `claude-sync status`

Identify all files marked as `CONFLICT`.

## Step 2: Create backup

```bash
backup_dir=~/.config/claude-sync/backups/$(date -Iseconds)
mkdir -p "$backup_dir"
```

For each conflicting file, back up both versions:
```bash
cp ~/.claude/<file> "$backup_dir/<file>.local"
ssh <REMOTE_HOST> "cat <REMOTE_PATH>/<file>" > "$backup_dir/<file>.remote"
cp ~/.config/claude-sync/last-sync/<file> "$backup_dir/<file>.base" 2>/dev/null || true
```

Read the REMOTE_HOST and REMOTE_PATH from `~/.config/claude-sync/config`.

## Step 3: For each conflicting file

1. Read all available versions:
   - Local: `~/.claude/<file>`
   - Remote: via SSH `cat` on the remote
   - Base (if exists): `~/.config/claude-sync/last-sync/<file>`

2. Analyze the differences semantically:
   - For `.md` files: identify added/removed/modified sections
   - For `.json` files: compare key-by-key, identify added/changed/removed keys
   - For directories with file conflicts: handle each file independently

3. Propose a merged version:
   - Combine additions from both sides
   - For conflicting modifications to the same section/key: present both versions and ask the user to choose or provide a resolution
   - Explain your reasoning for the proposed merge

4. Ask the user to approve the merge. If they want changes, iterate.

5. Once approved, write the resolved version:
   - Write to local: `~/.claude/<file>`
   - Copy to remote: use rsync or ssh+cat
   - Update base: `cp ~/.claude/<file> ~/.config/claude-sync/last-sync/<file>`

## Step 4: Verify

Run `claude-sync sync` to confirm all conflicts are resolved and everything is clean.

Print: "All conflicts resolved. Config is in sync."
