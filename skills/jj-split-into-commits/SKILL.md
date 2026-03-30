---
description: Split the current commit's changes into clean, logical commits
allowed-tools: Bash(jj:*), Bash(jj-hunk:*), Bash(pre-commit:*)
model: opus
---

## Context

- Current change: !`jj log -r @ --no-graph`
- Current diff: !`jj diff --stat`

## Task

Split the changes in the current commit (`@`) into clean, logical commits suitable for reviewer comprehension.

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
   - Group files by logical concern (e.g., schema, migrations, services, tests)
   - Order commits as a narrative: setup → core logic → integration → polish

5. **Present the plan and get confirmation**
   Present the proposed commits to the user as a numbered list showing:
   - Commit message
   - Which files/hunks go in each commit

   **STOP** and wait for the user to confirm, adjust, or reject the plan. Do not execute any splits until the user approves. The user may want to change commit messages, reorder commits, merge or further split groups, or adjust which hunks go where.

6. **Split iteratively using jj-hunk**

   First, inspect the hunks to understand what you're working with:

   ```bash
   jj-hunk list
   ```

   Example output:
   ```json
   {
     "src/db/schema.ts": [
       {"index": 0, "type": "insert", "added": "import { pgTable }...\n"},
       {"index": 1, "type": "insert", "added": "export const users = pgTable...\n"},
       {"index": 2, "type": "insert", "added": "export const posts = pgTable...\n"}
     ],
     "src/api/routes.ts": [
       {"index": 0, "type": "replace", "removed": "// TODO\n", "added": "app.get('/users', ...);\n"},
       {"index": 1, "type": "insert", "added": "app.get('/posts', ...);\n"}
     ],
     "src/lib/utils.ts": [
       {"index": 0, "type": "replace", "removed": "function old()...\n", "added": "function new()...\n"},
       {"index": 1, "type": "insert", "added": "export function helper()...\n"},
       {"index": 2, "type": "delete", "removed": "// dead code\n"}
     ]
   }
   ```

   **File-level selection** — when all hunks in a file belong together:

   ```bash
   # Keep entire file, reset everything else
   jj-hunk split '{"files": {"src/db/schema.ts": {"action": "keep"}}, "default": "reset"}' "feat: add database schema"
   ```

   **Hunk-level selection** — when a file has mixed concerns:

   ```bash
   # src/lib/utils.ts has refactoring (hunks 0, 2) and new feature (hunk 1)
   # Extract just the refactoring hunks
   jj-hunk split '{"files": {"src/lib/utils.ts": {"hunks": [0, 2]}}, "default": "reset"}' "refactor: clean up utils"

   # Now hunk 1 remains in working copy for the feature commit
   ```

   **Mixed selection** — combine file-level and hunk-level:

   ```bash
   # Keep all of schema.ts, but only hunk 0 from routes.ts
   jj-hunk split '{"files": {"src/db/schema.ts": {"action": "keep"}, "src/api/routes.ts": {"hunks": [0]}}, "default": "reset"}' "feat: add users endpoint"

   # Next commit: remaining routes.ts hunk 1
   jj-hunk split '{"files": {"src/api/routes.ts": {"hunks": [1]}}, "default": "reset"}' "feat: add posts endpoint"
   ```

   **Typical narrative sequence:**

   ```bash
   # 1. Infrastructure/setup first
   jj-hunk split '{"files": {"src/db/schema.ts": {"action": "keep"}, "drizzle.config.ts": {"action": "keep"}}, "default": "reset"}' "feat: add database schema"

   # 2. Core logic
   jj-hunk split '{"files": {"src/lib/utils.ts": {"hunks": [0, 2]}}, "default": "reset"}' "refactor: prepare utils for new feature"

   # 3. Feature implementation
   jj-hunk split '{"files": {"src/lib/utils.ts": {"action": "keep"}, "src/api/routes.ts": {"hunks": [0]}}, "default": "reset"}' "feat: add user routes"

   # 4. Remaining changes described as final commit
   jj describe -m "feat: add post routes"
   ```

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

### Spec Reference

| Spec | Effect |
|------|--------|
| `{"action": "keep"}` | Include all changes in file |
| `{"action": "reset"}` | Exclude file from this commit |
| `{"hunks": [0, 2]}` | Include only hunks 0 and 2 |
| `"default": "reset"` | Unlisted files excluded (safer) |
| `"default": "keep"` | Unlisted files included |

### Rules

- Never add yourself as an author or contributor
- Never include "Generated with Claude Code" or "Co-Authored-By" lines
- Each commit should introduce a single coherent idea
- Commit messages should read like a tutorial progression
