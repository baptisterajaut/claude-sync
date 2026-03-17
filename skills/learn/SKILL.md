---
name: learn
description: >
  Review current project's memories and propose promotions to global CLAUDE.md.
  Identifies general patterns worth keeping across all projects.
  TRIGGER when: user wants to consolidate learnings from current project.
allowed-tools: Bash, Read, Edit, Write
---

# /claude-sync:learn — Promote Project Memories

Review the current project's memories and propose promotions to the global `~/.claude/CLAUDE.md`.

## Step 1: Find project memories

Derive the memory path from the current directory:

```bash
project_path=$(pwd | sed 's|/|-|g')
memory_dir="$HOME/.claude/projects/$project_path/memory"
ls "$memory_dir"/*.md 2>/dev/null | grep -v MEMORY.md
```

If the directory doesn't exist or has no memory files, tell the user: "No project memories found for this directory." and stop.

## Step 2: Read memories

Read each memory file found (using the Read tool). Also read `~/.claude/CLAUDE.md` to understand what's already in the global config.

## Step 3: Classify

For each memory, determine:
- **Project-specific** — API quirks, codebase structure, domain knowledge, specific bugs → keep as project memory
- **General pattern** — workflow preferences, coding style, tool usage, feedback that applies everywhere → promote candidate
- **Stale** — outdated, redundant, or already in global CLAUDE.md → removal candidate

## Step 4: Propose

Show the user a summary:
- Memories to promote, with proposed wording for CLAUDE.md
- Memories to keep (explain why they're project-specific)
- Stale memories to remove

## Step 5: Apply

For each promotion the user approves:
1. Edit `~/.claude/CLAUDE.md` to add the content in the appropriate section
2. If the **entire** memory file was promoted, offer to delete it and update the project's MEMORY.md index

Do NOT delete a memory file if only part of it was promoted.
