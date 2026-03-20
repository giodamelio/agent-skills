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

## Project-Local Skills

This repo also has a `.skills/` directory containing skills that are only relevant when working on this repo itself (not shared globally). These are symlinked into `.claude/skills/` and `.omp/skills/` so each agent discovers them natively.

- `.skills/` — project-local, agent-agnostic skills for this repo
- `.claude/skills/` and `.omp/skills/` — generated symlinks, gitignored

## Version Control

- Git with [Jujutsu (jj)](https://github.com/martinvonz/jj) also in use
- **You MUST read and follow the `skills/jujutsu/SKILL.md` skill for all version control operations.** Use `jj` commands, not raw `git` commands.
