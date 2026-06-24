# Agent Skills

giodamelio's personal collection of LLM agent skills. Skills are **agent-agnostic** — written in plain language so they work across any AI coding agent (Claude Code, Cursor, Aider, etc.).

## Repository Structure

- `skills/` — portable, **agent-agnostic** skills (one subdirectory each). Installed to both `.claude/skills/` and the oh-my-pi skills dir.
- `plugins/` — **Claude Code plugins** (one subdirectory each), bundling skills/agents/hooks. These are Claude-specific and may use Claude-only features (subagents, hooks). Installed to `.claude/skills/` only, where they auto-load as `<name>@skills-dir`. See [Claude Code Plugin Development](#claude-code-plugin-development).
- `hooks/` — hook scripts (payloads) assembled into plugins by `flake.nix`.
- `references/` — shared files included into skills/plugins at build time (see [Shared References](#shared-references)).

To see what's available, list `skills/` and `plugins/`.

## Managing Skills

- Each skill lives in its own subdirectory under `skills/`
- Skill content MUST be agent-agnostic — no references to agent-specific tools, syntax, or features in the body text
- Agent-specific metadata (e.g. front matter fields) is fine, since other agents will simply ignore it
- The agent-agnostic rule applies to `skills/` only. Content under `plugins/` is a Claude Code artifact and may reference Claude-specific features (e.g. a bundled subagent).

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

The `references/` directory contains canonical source-of-truth files that are included into skills at build time using [gomplate](https://docs.gomplate.ca/) templating. When `nix build` runs, gomplate processes each skill's files, replacing `{{ include "refs" "filename.md" }}` directives with the referenced file's content.

To include a reference file in a skill, use: `{{ include "refs" "filename.md" }}`

Edit the reference file and rebuild — all consuming skills pick up the changes automatically.

Current reference files:
- `references/jj-hunk-spec.md` — jj-hunk spec format and command reference. Included by:
  - `skills/jj-hunk/SKILL.md`
  - `skills/jujutsu/SKILL.md`
  - `plugins/jj-split-into-commits/SKILL.md`

## Claude Code Plugin Development

This repo packages some components as **Claude Code plugins** (hooks, agents) in
addition to portable skills. Plugin packaging is Claude-specific and easy to get
subtly wrong, so **consult the official docs before changing plugin machinery** —
don't rely on memory.

**When to read them:** before adding or modifying hooks, agents, or any plugin
packaging in `flake.nix`; when unsure about plugin directory layout, `hooks.json`
schema, agent frontmatter, skills-directory plugin auto-loading, `${CLAUDE_PLUGIN_ROOT}`,
or marketplace/local-source behavior.

**Where to find them** (index: <https://code.claude.com/docs/llms.txt>):
- [plugins.md](https://code.claude.com/docs/en/plugins.md) — create plugins (skills, agents, hooks, MCP); `--plugin-dir` testing; convert standalone config to a plugin
- [plugins-reference.md](https://code.claude.com/docs/en/plugins-reference.md) — full schema reference: component dirs, **skills-directory plugins** (`<name>@skills-dir`), `${CLAUDE_PLUGIN_ROOT}`, plugin caching/symlink rules
- [plugin-marketplaces.md](https://code.claude.com/docs/en/plugin-marketplaces.md) — marketplaces, local/relative sources, `extraKnownMarketplaces`
- [sub-agents.md](https://code.claude.com/docs/en/sub-agents.md) — agent Markdown file format and frontmatter fields
- [hooks.md](https://code.claude.com/docs/en/hooks.md) — hook events, JSON stdin/stdout, decision format
- [skills.md](https://code.claude.com/docs/en/skills.md) — skill authoring
- [settings.md](https://code.claude.com/docs/en/settings.md) — settings files and hook wiring

**Key facts** (verified against the docs):
- Hooks never auto-load from a directory — they need `settings.json` wiring **or** a plugin. We use a **skills-directory plugin**: a folder under `.claude/skills/` containing `.claude-plugin/plugin.json` auto-loads as `<name>@skills-dir`, in place (no cache copy), bundling its own skills/agents/hooks.
- Plugin agents live in the plugin's `agents/` dir and are namespaced `<plugin>:<agent>`; plugin agents ignore `hooks`/`mcpServers`/`permissionMode` frontmatter.

## Version Control

- Git with [Jujutsu (jj)](https://github.com/martinvonz/jj) also in use
- **You MUST read and follow the `skills/jujutsu/SKILL.md` skill for all version control operations.** Use `jj` commands, not raw `git` commands.
