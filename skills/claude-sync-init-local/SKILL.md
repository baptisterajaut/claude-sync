---
name: claude-sync-init-local
description: >
  Generate a CLAUDE.local.md file with machine-specific environment details
  (OS, shell, runtime, etc.) — never synced by claude-sync.
  TRIGGER when: user wants to create or update their local environment config.
user-invocable: true
---

# /claude-sync-init-local — Generate Machine-Specific Config

Generate `~/.claude/CLAUDE.local.md` by detecting the local environment. This file is never synced by claude-sync.

## Detection

Gather the following information by running commands:

| Info | Command |
|------|---------|
| OS | `lsb_release -d 2>/dev/null \|\| cat /etc/os-release \|\| uname -s` |
| Kernel | `uname -r` |
| Desktop | `echo $XDG_CURRENT_DESKTOP` |
| Display server | `echo $XDG_SESSION_TYPE` |
| Shell | `echo $SHELL` |
| Container runtime | `which docker \|\| which podman \|\| echo "none"` |
| Kubernetes | `which kubectl \|\| which k3s \|\| echo "none"` |
| Package manager | `which apt \|\| which pacman \|\| which dnf` |
| Hostname | `hostname` |

## Generate

If `~/.claude/CLAUDE.local.md` already exists, show the current content and ask if the user wants to regenerate or update it.

Write `~/.claude/CLAUDE.local.md`:

```markdown
# Local Environment

- OS: **<detected>**
- Kernel: **<detected>**
- Desktop: **<detected>** (<display server>)
- Shell: **<detected>**
- Container runtime: **<detected>**
- Kubernetes: **<detected>**
- Package manager: **<detected>**
- Hostname: **<detected>**
```

Show the generated file to the user and ask if they want to add anything machine-specific (e.g. project paths, VPN notes, hardware details).
