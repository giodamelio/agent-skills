# Update Fork

Rebase a fork's local changes onto updated upstream. This skill covers the complete workflow: assessing the situation, creating safety backups, executing the rebase, resolving conflicts with a local-changes-first policy, and cleaning up after user confirmation.

## When to Use This Skill

- User asks to rebase upstream changes onto their fork
- User asks to sync/update their fork with upstream
- User asks to incorporate upstream updates while preserving local modifications

## Workflow Overview

The rebase workflow has six phases:

1. **Assess** - Detect VCS, identify upstream, understand local changes
2. **Prepare** - Create backup ref, fetch upstream
3. **Execute** - Run the rebase
4. **Resolve** - Handle conflicts preserving local intent; abort if irreconcilable
5. **Verify and Confirm** - Present results, get user approval
6. **Cleanup** - Remove backup refs (only after user confirms or after rollback)

Rollback is available at any point until Phase 6 completes.

## Phase 1: Assess

### Detect VCS

Check which version control system is in use:

- `.jj/` directory present → Jujutsu (jj)
- `.git/` directory present → Git

**If using jj**: Follow the `jujutsu` skill for command syntax and agent-environment caveats (e.g., always use `-m` flags, avoid interactive commands).

### Identify Upstream

Auto-detect the upstream remote and branch:

**jj:**
```bash
# List all bookmarks including tracked remotes
jj bookmark list --all

# Look for tracked upstream bookmarks like upstream/main or origin/main
```

**git:**
```bash
# List remotes
git remote -v

# Check tracking branches
git branch -vv
```

**Convention fallback** (if not auto-detectable):
- Remote: prefer `upstream`, fall back to `origin`
- Branch: prefer `main`, fall back to `master`

### Understand Local Changes

**CRITICAL PRECONDITION**: Before rebasing, read and understand every local commit ahead of upstream.

For each local commit:
1. Read the diff: `jj diff -r <change>` or `git show <commit>`
2. Understand its purpose — what behavior does it add or modify?
3. Note which files it touches
4. Record a mental summary of intent — this drives conflict resolution later

Do NOT proceed to Phase 2 until you understand what each local change does and why it exists.

## Phase 2: Prepare

### Create Backup

Always create a backup before rebasing. Always clean it up later.

**jj:**
```bash
# Record the current operation ID
jj op log --limit 1
# Note the operation ID (e.g., "abc123def") — this is the rollback point
```

**git:**
```bash
# Create a backup branch with timestamp
git branch backup-pre-rebase-$(date +%Y%m%d-%H%M%S)
```

### Fetch Upstream

**jj:**
```bash
jj git fetch --remote upstream
# Or if using origin:
jj git fetch --remote origin
```

**git:**
```bash
git fetch upstream
# Or if using origin:
git fetch origin
```

## Phase 3: Execute

### jj

```bash
# Rebase local changes onto upstream tip
jj rebase -d upstream/main
# Or: jj rebase -d origin/main
```

jj never blocks on conflicts — they are recorded in the commits. The rebase always "succeeds" even with conflicts.

### git

```bash
# Stash uncommitted changes first
git stash

# Rebase onto upstream
git rebase upstream/main
# Or: git rebase origin/main
```

Conflicts halt the rebase; resolve per-commit (see Phase 4), then `git rebase --continue`.

## Phase 4: Resolve Conflicts

### Conflict Policy

1. **Always preserve local change intent** — local modifications exist deliberately
2. Incorporate upstream changes that don't contradict local modifications
3. When upstream refactored code we also modified: adapt local modifications to the new upstream structure
4. Do NOT silently drop local changes
5. Do NOT blindly accept upstream over local

### When to Abort

Abort the rebase and report to the user when:

- Upstream fundamentally restructured the area our local changes modify
- Resolving would require **rewriting** (not just adapting) the local changes
- The conflict is not a merge conflict but a **design conflict** — the approaches are incompatible
- You cannot confidently preserve the intent of local changes

**Abort procedure:**

1. Roll back to backup (see Rollback section)
2. Report to the user:
   - What upstream changed
   - What local changes conflict
   - Why automatic resolution is not feasible
   - Let the human decide how to proceed

### Resolution Mechanics

**jj:**
```bash
# Find conflicted changes
jj log  # Conflicted changes are marked

# Edit the conflicted change
jj edit <change-id>

# Edit files to remove conflict markers, preserving local intent
# jj auto-snapshots the resolution

# Verify resolution
jj st

# Move to next conflicted change or return to working copy
jj edit @
```

**git:**
```bash
# Git halts at each conflict during rebase
# Edit conflicted files to remove markers, preserving local intent

# Stage resolved files
git add <resolved-files>

# Continue to next commit
git rebase --continue

# Repeat until rebase completes
```

## Phase 5: Verify and Confirm

After resolving all conflicts:

1. **Review each rebased commit** — confirm local change intent is preserved
   - `jj log -p` or `git log -p` to review
2. **Run tests/checks** if the user requests
3. **Present a summary to the user:**
   - How many commits were rebased
   - Which commits had conflicts and how they were resolved
   - Any behavior changes to flag

**Ask the user to confirm the result is acceptable.**

Do NOT proceed to Phase 6 until the user confirms.

## Phase 6: Cleanup Backup

Runs ONLY after user confirmation (or after rollback completes).

**git:**
```bash
# Delete the backup branch
git branch -D backup-pre-rebase-<timestamp>
```

**jj:**
```bash
# The backup operation ID is no longer needed
# jj op log retains full history regardless; no explicit cleanup required
# But note that the operation ID recorded in Phase 2 is now stale
```

If the user was NOT satisfied: rollback first (see below), then cleanup completes as part of rollback.

## Rollback

Available from Phase 3 through Phase 5 (before cleanup).

**jj:**
```bash
# Restore to the backup operation ID from Phase 2
jj op restore <backup-operation-id>
```

**git (rebase in progress):**
```bash
# Abort the in-progress rebase
git rebase --abort

# Pop stashed changes if any
git stash pop
```

**git (rebase completed but user rejected result):**
```bash
# Reset to backup branch
git reset --hard backup-pre-rebase-<timestamp>

# Pop stashed changes if any
git stash pop

# Delete backup branch (cleanup)
git branch -D backup-pre-rebase-<timestamp>
```

After rollback completes, the repository is restored to pre-rebase state and backup refs are cleaned up.
