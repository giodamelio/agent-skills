# Jujutsu (jj) Version Control System

This skill helps you work with Jujutsu, a Git-compatible VCS with mutable commits and automatic rebasing.

**Tested with jj v0.37.0** - Commands may differ in other versions.

## Important: Automated/Agent Environment

When running as an agent:

1. **Always use `-m` flags** to provide messages inline rather than relying on editor prompts:

```bash
# Always use -m to avoid editor prompts
jj desc -m "message"      # NOT: jj desc
jj squash -m "message"    # NOT: jj squash (which opens editor)
```

Editor-based commands will fail in non-interactive environments.

2. **Verify operations with `jj st`** after mutations (`squash`, `abandon`, `rebase`, `restore`) to confirm the operation succeeded.

## Core Concepts

### The Working Copy is a Commit

In jj, your working directory is always a commit (referenced as `@`). Changes are automatically snapshotted when you run any jj command. There is no staging area.

There is no need to run `jj commit`.

### Commits Are Mutable

**CRITICAL**: Unlike git, jj commits can be freely modified. This enables a high-quality commit workflow:

1. Before starting work, run `jj st`. If `@` already has changes, run `jj new` first. If `@` is empty, use it as-is.
2. Describe your intended changes with `jj desc -m"Message"`
3. Make your changes.
4. Do NOT run `jj new` when finished — leave that to the next task's step 1.

You may refine the commit using `jj squash` or `jj absorb` as needed

### Change IDs vs Commit IDs

- **Change ID**: A stable identifier (like `tqpwlqmp`) that persists when a commit is rewritten
- **Commit ID**: A content hash (like `3ccf7581`) that changes when commit content changes

Prefer using Change IDs when referencing commits in commands.

## Essential Workflow

### Starting Work: Describe First, Then Code

**Always create your commit message before writing code:**

```bash
# First, describe what you intend to do
jj desc -m "Add user authentication to login endpoint"

# Then make your changes - they automatically become part of this commit
# ... edit files ...

# Check status
jj st
```

### Creating Atomic Commits

Each commit should represent ONE logical change. Use this format for commit messages:

```
Examples:
- "Add validation to user input forms"
- "Fix null pointer in payment processor"
- "Remove deprecated API endpoints"
- "Update dependencies to latest versions"
```

### Viewing History

```bash
# View recent commits
jj log

# View with patches
jj log -p

# View specific commit
jj show <change-id>

# View diff of working copy
jj diff
```

### Moving Between Commits

```bash
# Create a new empty commit on top of current
jj new

# Create new commit with message
jj new && jj desc -m "Commit message"

# Edit an existing commit (working copy becomes that commit)
jj edit <change-id>

# Edit the previous commit
jj prev -e

# Edit the next commit
jj next -e
```

## Refining Commits

### Squashing Changes

Move changes from current commit into its parent:

```bash
# Squash all changes into parent
jj squash
```

**Note**: `jj squash -i` opens an interactive UI and will hang in agent environments. Avoid it.

### Splitting Commits

**Warning**: `jj split` is interactive and will hang in agent environments. **Prefer `jj-hunk`** for non-interactive splitting — see [jj-hunk](#jj-hunk-programmatic-hunk-selection) below. As a fallback (if jj-hunk is not installed), use `jj restore` to move changes out, then create separate commits manually.

### Absorbing Changes

Automatically distribute changes to the commits that last modified those lines:

```bash
# Absorb working copy changes into appropriate ancestor commits
jj absorb
```

### Abandoning Commits

Remove a commit entirely (descendants are rebased to its parent):

```bash
jj abandon <change-id>
```

### Undoing Operations

Reverse the last jj operation:

```bash
jj undo
```

This reverts the repository to its state before the previous command. Useful for recovering from mistakes like accidental `abandon`, `squash`, or `rebase`.

### Restoring Files

Discard changes to specific files or restore files from another revision:

```bash
# Discard all uncommitted changes in working copy (restore from parent)
jj restore

# Discard changes to specific files
jj restore path/to/file.txt

# Restore files from a specific revision
jj restore --from <change-id> path/to/file.txt
```

## jj-hunk: Programmatic Hunk Selection

`jj-hunk` enables non-interactive, programmatic hunk selection for splitting, committing, and squashing in jj. It is designed for AI agents and automation. **Whenever you need to split work into multiple commits, STRONGLY prefer jj-hunk over manual `jj restore` workflows.**

### Availability Check

Before using jj-hunk, verify it is installed:

```bash
jj-hunk --help
```

If the command is not found, fall back to the manual `jj restore` approach described in [Splitting Commits](#splitting-commits).

### Listing Hunks

Inspect what hunks exist in the current changes before deciding how to split:

```bash
# List all hunks in the working copy (JSON output)
jj-hunk list

# List hunks for a specific revision
jj-hunk list --rev @

# List files only (with hunk counts)
jj-hunk list --files

# Output as YAML
jj-hunk list --format yaml

# Generate a spec template with stable hunk IDs (useful as a starting point)
jj-hunk list --spec-template --format yaml

# Filter by path
jj-hunk list --include 'src/**' --exclude '**/*.test.rs'
```

### Splitting Changes into Multiple Commits

Split the working copy (or a revision) into two commits — selected hunks go to the first commit, the rest to the second:

```bash
# Split by file: keep src/foo.rs in first commit, reset everything else
jj-hunk split '{"files": {"src/foo.rs": {"action": "keep"}}, "default": "reset"}' "first commit message"

# Split by specific hunks (0-indexed)
jj-hunk split '{"files": {"src/foo.rs": {"hunks": [0, 1]}}, "default": "reset"}' "first commit message"

# Split a specific revision (not just working copy)
jj-hunk split -r @- '{"files": {"src/foo.rs": {"action": "keep"}}, "default": "reset"}' "first commit message"
```

To iteratively split into many commits, repeat `jj-hunk split` — each call peels off one commit and leaves the rest.

### Committing Selected Hunks

Commit only specific changes from the working copy, leaving the rest uncommitted:

```bash
jj-hunk commit '{"files": {"src/fix.rs": {"action": "keep"}}, "default": "reset"}' "bug fix"
```

### Squashing Selected Hunks

Squash specific changes from a commit into its parent:

```bash
# Squash from working copy into parent
jj-hunk squash '{"files": {"src/cleanup.rs": {"action": "keep"}}, "default": "reset"}'

# Squash a specific revision into its parent
jj-hunk squash -r @- '{"files": {"src/cleanup.rs": {"action": "keep"}}, "default": "reset"}'
```

### Spec Format

The spec is a JSON (or YAML) object that controls which hunks to include.

**CRITICAL: Every spec MUST have a top-level `"files"` key.** File paths go INSIDE `"files"`, never at the top level.

Correct:
```json
{"files": {"path/to/file": {"action": "keep"}}, "default": "reset"}
```

Wrong (missing `"files"` wrapper — will fail):
```json
{"path/to/file": {"action": "keep"}, "default": "reset"}
```

Full example:
```json
{
  "files": {
    "path/to/file": {"action": "keep"},
    "path/to/other": {"action": "reset"},
    "path/to/partial": {"hunks": [0, 2]},
    "path/to/by-id": {"ids": ["hunk-7c3d..."]}
  },
  "default": "reset"
}
```

Per-file actions (nested under `"files"`):
- `{"action": "keep"}` — include all changes in this file
- `{"action": "reset"}` — exclude all changes in this file
- `{"hunks": [0, 1]}` — include only these hunks (0-indexed)
- `{"ids": ["hunk-..."]}` — include hunks by stable ID from `jj-hunk list`

Top-level keys (siblings of `"files"`):
- `"default"` — action for files not listed (`"keep"` or `"reset"`)

Specs can also be read from a file (`--spec-file spec.yaml`) or stdin (`cat spec.json | jj-hunk commit - "msg"`).

### Recommended Workflow: Clean Commit History

When you have a large set of changes that should be multiple commits:

1. **List the hunks** to understand what changed: `jj-hunk list --files`
2. **Group files by logical concern** (e.g. schema, services, tests)
3. **Split iteratively**, peeling off one commit at a time:

```bash
jj-hunk split '{"files": {"src/db/schema.ts": {"action": "keep"}}, "default": "reset"}' "Add database schema"
jj-hunk split '{"files": {"src/api/routes.ts": {"action": "keep"}}, "default": "reset"}' "Add API routes"
jj desc -m "Add UI components"  # remaining changes become the last commit
```

## Working with Bookmarks (Branches)

Bookmarks are jj's equivalent to git branches:

```bash
# Create a bookmark at current commit
jj bookmark create my-feature -r@

# Move bookmark to a different commit
jj bookmark move my-feature --to <change-id>

# List bookmarks
jj bookmark list

# Delete a bookmark
jj bookmark delete my-feature
```

## Git Integration

### Working with Existing Git Repos

```bash
# Clone a git repository
jj git clone <url>

# Initialize jj in an existing git repo
jj git init --colocate
```

### Switching Between jj and git (Colocated Repos)

In a colocated repository (where both `.jj/` and `.git/` exist), you can use both jj and git commands. However, there are important considerations:

**Switching to git mode** (e.g., for merge workflows):
```bash
# First, ensure your jj working copy is clean
jj st

# Then checkout a branch with git
git checkout <branch-name>
```

**Switching back to jj mode**:
```bash
# Use jj edit to resume working with jj
jj edit <change-id>
```

**Important notes:**
- Git may complain about uncommitted changes if jj's working copy differs from the git HEAD
- ALWAYS ensure your work is committed in jj before switching to git
- After git operations, jj will detect and incorporate the changes on next command

### Pushing Changes

When the user asks you to push changes:

```bash
# Push a specific bookmark to the remote
jj git push -b <bookmark-name>

# Example: push the main bookmark
jj git push -b main
```

**Before pushing, ensure:**
1. Your bookmark points to the correct commit (bookmarks don't auto-advance like git branches)
2. The commits are refined and atomic
3. The user has explicitly requested the push

**IMPORTANT**: Unlike git branches, jj bookmarks do not automatically move when you create new commits. You must manually update them before pushing:

```bash
# Move an existing bookmark to the current commit
jj bookmark move my-feature --to @

# Then push it
jj git push -b my-feature
```

If no bookmark exists for your changes, create one first:

```bash
# Create a bookmark at the current commit
jj bookmark create my-feature

# Then push it
jj git push -b my-feature
```

## Handling Conflicts

jj allows committing conflicts — you can resolve them later:

```bash
# View conflicts
jj st
```

**Agent conflict resolution**: Do not use `jj resolve` (interactive). Instead, edit the conflicted files directly to remove conflict markers, then run `jj st` to verify resolution.

## Preserving Commit Quality

**IMPORTANT**: Because commits are mutable, always refine them:

1. **Review your commit**: `jj show @` or `jj diff`
2. **Is it atomic?** One logical change per commit
3. **Is the message clear?** Use imperative verb phrase in sentence case format with no full stop: "Verb object"
4. **Are there unrelated changes?** Use `jj restore` to move changes out, then create separate commits
5. **Should changes be elsewhere?** Use `jj squash` or `jj absorb`

## Quick Reference

| Action | Command |
|--------|---------|
| Describe commit | `jj desc -m "message"` |
| View status | `jj st` |
| View log | `jj log` |
| View diff | `jj diff` |
| New commit | `jj st` then `jj new` only if `@` has changes, then `jj desc -m "message"` |
| Edit commit | `jj edit <id>` |
| Squash to parent | `jj squash` |
| Auto-distribute | `jj absorb` |
| Abandon commit | `jj abandon <id>` |
| Undo last operation | `jj undo` |
| Restore files | `jj restore [paths]` |
| Create bookmark | `jj bookmark create <name>` |
| Push bookmark | `jj git push -b <name>` |
| List hunks | `jj-hunk list` |
| Split by hunk | `jj-hunk split '<spec>' "message"` |
| Commit by hunk | `jj-hunk commit '<spec>' "message"` |
| Squash by hunk | `jj-hunk squash '<spec>'` |

## Best Practices Summary

1. **Describe first**: Set the commit message before coding
2. **One change per commit**: Keep commits atomic and focused
3. **Use change IDs**: They're stable across rewrites
4. **Refine commits**: Leverage mutability for clean history
5. **Embrace the workflow**: No staging area, no stashing - just commits
