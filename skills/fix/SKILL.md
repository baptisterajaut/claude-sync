---
name: fix
description: >
  Resolve claude-sync conflicts — shows semantic diffs of conflicting files
  and guides interactive merge resolution.
  TRIGGER when: claude-sync reports conflicts, or user asks to fix sync conflicts.
allowed-tools: Bash, Read, Edit, Write
---

# /claude-sync:fix — Conflict Resolution

You are resolving sync conflicts detected by claude-sync. Follow these steps.

**IMPORTANT — Minimize SSH:** Never run individual `ssh cat` commands per file. Fetch all remote files in ONE rsync call.

## Step 1: Get conflict list

Run `claude-sync status` to see per-file status. Identify which files are `CONFLICT`.

## Step 2: Fetch remote files locally

Fetch all remote files in ONE rsync call so you can read them without further SSH:

Read `~/.config/claude-sync/config` to get `REMOTE_HOST` and `REMOTE_PATH` values, then:

```bash
tmpdir=$(mktemp -d)
rsync -a "<REMOTE_HOST>:<REMOTE_PATH>/" "$tmpdir/"
```

Now all three versions are local:
- **Local:** `~/.claude/<file>`
- **Remote:** `$tmpdir/<file>`
- **Base:** `~/.config/claude-sync/last-sync/<file>` (may not exist for first-sync conflicts)

## Step 3: Create backup

```bash
backup_dir=~/.config/claude-sync/backups/$(date -Iseconds)
mkdir -p "$backup_dir"
```

For each conflicting file:
```bash
cp ~/.claude/<file> "$backup_dir/<file>.local"
cp "$tmpdir/<file>" "$backup_dir/<file>.remote"
cp ~/.config/claude-sync/last-sync/<file> "$backup_dir/<file>.base" 2>/dev/null || true
```

## Step 4: For each conflicting file

1. Read versions locally using the Read tool (already fetched, no SSH, no stdout truncation).

2. Analyze the differences semantically:
   - For `.md` files: identify added/removed/modified sections
   - For `.json` files: compare key-by-key, identify added/changed/removed keys
   - For directories with file conflicts: handle each file independently

3. Propose a merged version:
   - Combine additions from both sides
   - For conflicting modifications to the same section/key: present both versions and ask the user to choose or provide a resolution
   - Explain your reasoning for the proposed merge

4. Ask the user to approve the merge. If they want changes, iterate.

5. Once approved, write the resolved version **locally only**:
   ```bash
   cat > ~/.claude/<file> <<'EOF'
   <merged content>
   EOF
   ```

## Step 5: Push resolved files

After ALL conflicts are resolved locally, run `resolve` which pushes local → remote and updates base for all conflicting files:

```bash
claude-sync resolve
```

Then verify with `claude-sync sync` — should report "Everything in sync."

## Step 6: Cleanup

```bash
rm -rf "$tmpdir"
```

Print: "All conflicts resolved. Config is in sync."
