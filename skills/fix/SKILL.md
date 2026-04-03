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

## Step 1: See conflicts and diffs

```bash
claude-sync status
claude-sync diff > /tmp/claude-sync-diff.txt
```

Read `/tmp/claude-sync-diff.txt` to understand all differences. Identify files marked `CONFLICT` in the status output.

## Step 2: For each conflicting file

1. Read the local version: `~/.claude/<file>`
2. Read the base version (if exists): `~/.config/claude-sync/last-sync/<file>`
3. The remote version is visible in `/tmp/claude-sync-diff.txt`

4. Analyze the differences semantically:
   - For `.md` files: identify added/removed/modified sections
   - For `.json` files: compare key-by-key, identify added/changed/removed keys
   - For directories with file conflicts: handle each file independently

5. Propose a merged version:
   - Combine additions from both sides
   - For conflicting modifications to the same section/key: present both versions and ask the user to choose
   - Explain your reasoning

6. Ask the user to approve the merge. If they want changes, iterate.

7. Once approved, apply the merge to the local file using the Edit or Write tool.

## Step 3: Finalize

After editing a conflicting file locally, the conflict may already be resolved (e.g. the local version now matches the remote). In that case, `resolve` will report "not in conflict" — this is expected. Run `sync` directly instead:

```bash
claude-sync sync
```

If the file still differs from remote after your edit, push the resolved version explicitly:

```bash
claude-sync resolve <file1> <file2> ...
```

Then verify:

```bash
claude-sync sync
```

Should report "Everything in sync."
