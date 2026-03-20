# Agent Skills

giodamelio's personal collection of LLM agent skills. Skills are **agent-agnostic** — written in plain language so they work across any AI coding agent (Claude Code, Cursor, Aider, etc.).

## Repository Structure

Each skill is a subdirectory under `skills/`. To see all available skills, list that directory.

## Managing Skills

- Each skill lives in its own subdirectory under `skills/`
- Skill content MUST be agent-agnostic — no references to agent-specific tools, syntax, or features in the body text
- Agent-specific metadata (e.g. front matter fields) is fine, since other agents will simply ignore it

## Version Control

- Git with [Jujutsu (jj)](https://github.com/martinvonz/jj) also in use
