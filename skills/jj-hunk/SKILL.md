---
name: jj-hunk
description: "How to use the jj-hunk CLI for programmatic, non-interactive hunk selection in Jujutsu (jj). Use this skill whenever you need to split, commit, or squash specific hunks or files using jj-hunk, or when constructing a jj-hunk spec. Agents frequently get the spec format wrong — this skill is the authoritative reference for correct spec construction."
allowed-tools: Bash(jj:*), Bash(jj-hunk:*)
---

# jj-hunk: Programmatic Hunk Selection for Jujutsu

`jj-hunk` is a CLI tool that lets you split, commit, and squash specific hunks in Jujutsu without interactive prompts.

**NEVER use `jj split`, `jj commit`, or `jj squash -i`** — these are interactive commands that will hang in agent environments. Always use `jj-hunk` instead.

{{ include "refs" "jj-hunk-spec.md" }}
