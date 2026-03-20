---
name: install-skills
description: Install the global agent-agnostic skills from skills/ into Claude Code (~/.claude/skills/) and oh-my-pi (~/.omp/agent/skills/) using GNU stow. Run when setting up this repo for the first time or after adding/removing a skill.
user-invocable: true
---

# Install Skills

Run the install script to symlink the global skills from `skills/` into each agent's skill discovery directory:

```
${CLAUDE_SKILL_DIR}/install.sh
```

This uses GNU stow to create per-skill symlinks. The nix-shell shebang ensures stow is available without requiring a global install.

After running, verify the symlinks were created:
- `ls -la ~/.claude/skills/` — Claude Code global skills
- `ls -la ~/.omp/agent/skills/` — oh-my-pi global skills
