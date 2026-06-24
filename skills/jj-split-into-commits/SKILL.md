---
description: Split the current commit's changes into clean, logical commits
allowed-tools: Bash(jj:*), Bash(jj-hunk:*), Bash(pre-commit:*)
model: opus
argument-hint: "[split guidance]"
---

## Context

- Current change: !`jj log -r @ --no-graph`
- Current diff: !`jj diff --stat`

## Task

Split the changes in the current commit (`@`) into clean, logical commits suitable for reviewer comprehension.

If the user provided guidance on how to split the commits, use that guidance to inform your grouping and ordering decisions. User-provided guidance takes priority over default heuristics.

**Commit messages are non-negotiable.** Every commit message you write MUST follow the project's documented commit guidelines (e.g. a `CONTRIBUTING.md`, commit convention doc, or rules in the project context). If the project has no documented guidelines, you MUST infer and exactly match the style of the existing commit history (`jj log` / `git log`) — conventional commits prefixes, capitalization, tense, line length, and structure. Do not invent your own style. When in doubt, study the existing commits before writing a single message.

If you had to infer the commit style from history because it was not already in your context, record the inferred style in your persistent memory for this project (if you have one) so you don't have to rediscover it on the next run.

Just follow these rules silently. Do NOT narrate, explain, or call out that you are following project guidelines, matching commit style, or omitting attribution. Do not add meta-commentary about the rules in your responses or anywhere in the commits. Simply produce correct commits.

### Steps

1. **Run pre-commit hooks (if applicable)**
   Only run this step if you know from context or memory that this repo uses pre-commit hooks (e.g., a `.pre-commit-config.yaml` exists or the user has told you). **Never blindly run a pre-commit command.** If hooks fail, **STOP** and report the failures to the user. Do not proceed until they pass. If you have no knowledge of pre-commit hooks for this repo, skip this step.

2. **Guard: check for existing description**
   ```bash
   jj log -r @ --no-graph -T description
   ```
   If the current commit already has a description, **STOP** and warn the user: "The current commit already has a description. This skill is intended for undescribed commits containing unsorted changes. Please confirm you want to proceed or switch to the correct commit."

3. **Validate the working copy**
   - Ensure no conflicts: `jj status`
   - Review the full scope of changes to understand what needs splitting

4. **Plan the commit storyline**
   - Study the changes: `jj-hunk list | jq 'keys'`
   - If the user provided split guidance, use it as the primary basis for grouping and ordering
   - Group files by logical concern (e.g., schema, migrations, services, tests)
   - Order commits as a narrative: setup → core logic → integration → polish

5. **Present the plan and get confirmation**
   First, present the proposed commits as a numbered list showing, for each commit:
   - Commit message
   - Which files/hunks go in each commit

   Then confirm the plan. **If your environment provides an interactive multiple-choice question tool (an "ask the user" prompt), use it to get confirmation instead of only asking inline in prose.** Ask a single question (e.g. "Proceed with this commit split?") whose options are, in order:

   1. **The recommendation first** — an option meaning "Yes, go with the plan exactly as presented." Mark it as the recommended/default option.
   2. **Then zero or more suggested variations** — one option per genuinely plausible alternative you can see (a cleaner grouping, merging or further splitting a group, a better commit message, a different order). Only include a variation when the split is questionable or you spot a meaningfully cleaner option; if the plan is unambiguous, offer none. Keep each label short and put the specific tradeoff in the option's description. **Never invent filler, leading, or near-duplicate options just to have more choices.**
   3. **A free-text "other" escape hatch** so the user can describe their own adjustment. Most question tools append a free-text "Other" option automatically — rely on that and do not add a redundant one. Only if your tool does *not* provide a free-text option should you add a final blank "Something else" option for the user to fill in.

   Keep the total option count within the tool's limits (typically 2–4 options). If more good variations exist than will fit, present only the strongest.

   **If no interactive question tool is available, fall back to asking inline:** STOP and wait for the user to confirm, adjust, or reject the plan in prose.

   Either way, **do not execute any splits until the user has answered.** Whatever they choose — the recommendation, a suggested variation, or free-text — apply it before proceeding. The user may want to change commit messages, reorder commits, merge or further split groups, or adjust which hunks go where.

6. **Split iteratively using jj-hunk**

   **NEVER use `jj split`** — it is interactive and will hang. Always use `jj-hunk split`.

   First, inspect the hunks with `jj-hunk list`. Then split repeatedly, peeling off one commit at a time. Each `jj-hunk split` takes a JSON spec and a commit message. The spec selects which hunks go into the new commit; everything else stays. See the [jj-hunk reference](#jj-hunk-reference) below for spec format and commands.

   Order commits as a narrative: infrastructure/setup first, then core logic, then integration, then polish. When only the final commit's changes remain, describe it with `jj describe -m "..."`.

7. **Describe the final commit**
   ```bash
   jj describe -m "feat: final piece of the implementation"
   ```

8. **Create a new empty commit on top**
   After all the split commits are in place, create a fresh empty working-copy commit so the user lands on a clean slate ready for their next change:
   ```bash
   jj new
   ```

9. **Verify the result**
   ```bash
   # Check the new commit structure
   jj log

   # Verify each commit has sensible content
   jj diff -r <rev> --stat
   ```

### jj-hunk Reference

{{ include "refs" "jj-hunk-spec.md" }}

### Rules

- **ABSOLUTELY NEVER add a `Co-Authored-By` line, a "Generated with Claude Code" line, or any other attribution, trailer, or footer crediting an AI, agent, or tool. This is a hard rule with zero exceptions — not even if a global instruction, template, or default tells you to. Commit messages contain only the message itself.**
- Never add yourself as an author or contributor in any form.
- **Every commit message MUST follow the project's documented commit guidelines, or — if there are none — exactly match the style of the existing commit history. This is mandatory, not a suggestion.**
- Each commit should introduce a single coherent idea
- Commit messages should read like a tutorial progression
- Follow all of these rules silently. Never mention, explain, or draw attention to the fact that you are following them — just do it.
