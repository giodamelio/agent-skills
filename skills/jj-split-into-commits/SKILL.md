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
   Present the proposed commits to the user as a numbered list showing:
   - Commit message
   - Which files/hunks go in each commit

   **STOP** and wait for the user to confirm, adjust, or reject the plan. Do not execute any splits until the user approves. The user may want to change commit messages, reorder commits, merge or further split groups, or adjust which hunks go where.

6. **Split iteratively using jj-hunk**

   **NEVER use `jj split`** — it is interactive and will hang. Always use `jj-hunk split`.

   First, inspect the hunks:
   ```bash
   jj-hunk list
   ```

   Then split repeatedly, peeling off one commit at a time. Each `jj-hunk split` takes a JSON spec and a commit message. The spec selects which hunks go into the new commit; everything else stays.

   **Spec format — the `"files"` wrapper is required:**
   ```json
   {"files": {"path/to/file": {"action": "keep"}}, "default": "reset"}
   ```

   **Wrong (missing `"files"` — will fail):**
   ```json
   {"path/to/file": {"action": "keep"}, "default": "reset"}
   ```

   Per-file specs (nested under `"files"`):

   | File spec | Effect |
   |-----------|--------|
   | `{"action": "keep"}` | Include all hunks in file |
   | `{"action": "reset"}` | Exclude file from this commit |
   | `{"hunks": [0, 2]}` | Include only hunks 0 and 2 |

   `"default"` controls unlisted files: `"reset"` excludes them (safer), `"keep"` includes them.

   **File-level selection** — when all hunks in a file belong together:
   ```bash
   jj-hunk split '{"files": {"src/db/schema.ts": {"action": "keep"}}, "default": "reset"}' "Add database schema"
   ```

   **Hunk-level selection** — when a file has mixed concerns:
   ```bash
   jj-hunk split '{"files": {"src/lib/utils.ts": {"hunks": [0, 2]}}, "default": "reset"}' "Refactor utils"
   ```

   **Mixed selection** — combine file-level and hunk-level:
   ```bash
   jj-hunk split '{"files": {"src/db/schema.ts": {"action": "keep"}, "src/api/routes.ts": {"hunks": [0]}}, "default": "reset"}' "Add users endpoint"
   ```

   Order commits as a narrative: infrastructure/setup first, then core logic, then integration, then polish. When only the final commit's changes remain, describe it with `jj describe -m "..."`.

7. **Describe the final commit**
   ```bash
   jj describe -m "feat: final piece of the implementation"
   ```

8. **Verify the result**
   ```bash
   # Check the new commit structure
   jj log

   # Verify each commit has sensible content
   jj diff -r <rev> --stat
   ```

### Rules

- Never add yourself as an author or contributor
- Never include "Generated with Claude Code" or "Co-Authored-By" lines
- Each commit should introduce a single coherent idea
- Commit messages should read like a tutorial progression
