# Agent Skills

giodamelio's personal collection of LLM agent skills. Skills are **agent-agnostic** — written in plain language so they work across any AI coding agent (Claude Code, Cursor, Aider, etc.).

## Repository Structure

Each skill is a subdirectory under `skills/`. To see all available skills, list that directory.

## Managing Skills

- Each skill lives in its own subdirectory under `skills/`
- Skill content MUST be agent-agnostic — no references to agent-specific tools, syntax, or features in the body text
- Agent-specific metadata (e.g. front matter fields) is fine, since other agents will simply ignore it

## Skills

To see all available skills, list the `skills/` directory. Each subdirectory contains a `SKILL.md` with instructions. Skills may also include other files in their directory that are required to use them.

**DO NOT add a list of specific skills to this file.** This file must never be updated when skills are added, removed, or changed. The `skills/` directory is the single source of truth — list it dynamically instead.

## Nix Flake

Skills are packaged as Nix derivations in `flake.nix`:

- `nix build` — builds all skills (local + external) combined into a single output
- `nix build .#<skill-name>` — builds an individual skill (e.g. `nix build .#jujutsu`)
- `nix develop` — enters a devshell that symlinks external skills (skill-creator) into `.claude/skills/` and `.omp/skills/` for agent discovery
- The default package is intended for home-manager consumption to install all skills globally

## Shared References

The `references/` directory contains canonical source-of-truth files that are **manually inlined** into multiple skills. This is necessary because skills are packaged independently and cannot reference external files at runtime.

**CRITICAL: Updates flow both ways.** If you update a reference file, you MUST update every skill that inlines its content. If you update the inlined content in any skill, you MUST also update the reference file AND all other skills that inline it. The reference file's header comment lists all consuming skills. Failing to sync means skills will diverge and agents will get inconsistent instructions.

Current reference files:
- `references/jj-hunk-spec.md` — jj-hunk spec format and command reference. Inlined into:
  - `skills/jj-hunk/SKILL.md` (full version)
  - `skills/jujutsu/SKILL.md` (condensed version in the jj-hunk section)
  - `skills/jj-split-into-commits/SKILL.md` (condensed version in step 6)

## Version Control

- Git with [Jujutsu (jj)](https://github.com/martinvonz/jj) also in use
- **You MUST read and follow the `skills/jujutsu/SKILL.md` skill for all version control operations.** Use `jj` commands, not raw `git` commands.
