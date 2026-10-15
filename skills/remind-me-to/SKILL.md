---
name: remind-me-to
description: Write REMIND-ME-TO comments that the remind-me-to CLI checks for you, so a TODO resurfaces once its blocking condition is met. Use whenever you are about to leave a TODO, FIXME, HACK, or workaround comment that waits on something external (a PR merging, an issue closing, a release or tag, a nixpkgs version, or a date), and whenever the user says "remind me to ...", "add a reminder", or invokes /remind-me-to.
---

# Remind Me To

`remind-me-to` scans source files for `REMIND-ME-TO:` comments and reports the ones whose conditions are met. A plain `TODO` is forgotten; a `REMIND-ME-TO` fails a check once it is actionable.

## Decide when to use it

Write a `REMIND-ME-TO` comment instead of a plain `TODO` when the follow-up is blocked on a condition the tool can check:

- An upstream PR merging, closing, or shipping in a release
- An issue closing
- A tag or version existing upstream
- A commit appearing in a release
- A branch being deleted
- A nixpkgs package reaching a version
- A calendar date passing

Also write one whenever the user asks you to be reminded about something, even without the word TODO.

Keep a plain `TODO` when nothing external gates the work, such as "refactor this when you have time". If the user asked for a reminder but gave no condition, ask for one. If there is no natural trigger, suggest `date_passed` with a date they choose.

## Write the comment

Syntax, in the file's own comment style (`//`, `#`, `--`, `/* */`, and so on):

```
REMIND-ME-TO: <description> <operation>=<argument> [<operation>=<argument> ...]
```

- The description is an imperative action: "remove the retry workaround", not "retry workaround".
- Put the comment directly above the code it concerns.
- Multiple conditions are OR'd: the reminder triggers when any one is met.

### Operations

| Operation | Argument | Triggers when |
|---|---|---|
| `pr_merged` | `github:owner/repo#123` | The PR is merged |
| `pr_closed` | `github:owner/repo#123` | The PR is closed |
| `pr_released` | `github:owner/repo#123` | The PR's merge is in a release |
| `issue_closed` | `github:owner/repo#99` | The issue is closed |
| `tag_exists` | `github:owner/repo@>=2.0.0` | A tag matching the version requirement exists |
| `commit_released` | `github:owner/repo@abc1234` | The commit is in a release |
| `branch_deleted` | `github:owner/repo@branch-name` | The branch no longer exists |
| `nixpkg_version` | `package@>=3.0` | The nixpkgs package reaches the version |
| `date_passed` | `2026-06-01` | The date has passed |

Use only `github:` as the forge prefix. It is the only forge the tool documents. For a project hosted elsewhere, fall back to `date_passed`.

### Examples

```rust
// REMIND-ME-TO: remove the manual header parsing pr_merged=github:owner/repo#123
```

```nix
# REMIND-ME-TO: switch to the nixpkgs package nixpkg_version=some-tool@>=3.0
```

```python
# REMIND-ME-TO: drop the compat shim pr_released=github:owner/repo#200 date_passed=2026-12-31
```

## Use real references only

Every PR number, issue number, repo, tag, and commit must be one you have verified exists. A wrong reference either never triggers or triggers immediately, and both defeat the reminder.

- Look the reference up (the forge's CLI, its web UI, or the dependency's changelog) before writing it.
- If you cannot find it, ask the user for it. Do not guess a number.
- For `tag_exists` and `nixpkg_version`, check the current version first, so the requirement is one that is not yet satisfied.

## Validate the comment

After adding or editing a reminder, parse the file without hitting the network:

```sh
remind-me-to check --dry-run <file>
```

Your reminder must appear in the "Found N reminder(s)" list. A `WARN ... reminder has no operations` line means the condition is malformed. Fix the comment and rerun.

To confirm the condition is not already met, run the real check on that file:

```sh
remind-me-to check --format llm <file>
```

Exit code 0 means no reminders need attention. Exit code 2 means at least one condition is met, and the output lists each one. If your new reminder is listed, its condition is already satisfied: do the work now instead of leaving a reminder.

## Act on triggered reminders

When you run `remind-me-to check --format llm` and it exits 2, each listed reminder is due. Do the action in its description, then delete the comment. Do not delete a triggered reminder without doing the work or confirming with the user.
