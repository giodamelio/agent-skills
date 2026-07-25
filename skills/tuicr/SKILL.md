---
name: tuicr
description: Use tuicr's review CLI to read and add comments in TUI review sessions. Discover the right session, poll for the user's comments, and only add agent-authored comments when the workflow calls for it.
---

# tuicr Review Workflow

Interact with tuicr **only through the `tuicr review` CLI** (`list`, `comments`,
`add`). The TUI is where the human reviews code; the CLI is how you discover
sessions, read user comments, and — when appropriate — add agent-authored
comments.

Never launch or drive the TUI yourself. It needs a real controlling terminal and
will fail without one (e.g. in an isolated/sandboxed environment). The human runs
the TUI; you observe and contribute through the CLI. The CLI does not require a
terminal multiplexer, so you can use it regardless of how you are running.

All tuicr state lives under `~/.local/share/tuicr/reviews/`:

- `index.json` — the session index
- `sessions/<id>.json` — per-session data, including `updated_at`
- `active_sessions.json` — liveness records, including each session's
  `last_seen_at`

Read these files directly when the CLI does not surface the field you need
(notably for freshness — see [Attach To A Session](#attach-to-a-session)).

## Core Rule

First decide which workflow the user is asking for:

1. **User-led review of agent-generated changes**
   - The user wants to inspect the patch and write comments in tuicr.
   - Your job is to find the session, then retrieve the user's comments with
     `tuicr review comments` when they say comments are ready. If you are
     explicitly waiting while the user reviews, poll the same command
     periodically and look for new comment IDs.
   - Do not add your own review comments, do not preemptively review your own
     patch, and do not impersonate the user's comments.

2. **Agent review of an AI-generated patch**
   - The user wants you to understand, critique, or summarize a patch.
   - You may inspect the patch and propose findings.
   - If you can confidently identify this workflow and the target session, add
     findings directly with `tuicr review add` and an explicit `--username`
     identifying the agent. Ask first when the workflow or session is ambiguous.

If the user's intent is ambiguous, ask which workflow they want.

## Attach To A Session

1. Determine the repository directory from the user's request, current working
   directory, or recent file operations. Ask if it is ambiguous.

2. List persisted sessions:

   ```bash
   tuicr review list --repo /path/to/repo   # checkout + its repo's PR sessions
   tuicr review list --repo owner/repo      # all sessions for a forge repo
   tuicr review list --all                  # every session across all repos
   ```

   `--repo` is a selector: a checkout path also surfaces PR sessions for that
   checkout's `origin` repo, and a forge coordinate like `owner/repo` matches
   local and PR sessions by owner/repo. Each row carries a `kind` (`local` or
   `pr`) and a usable `slug`. Use `--all` when you don't know the repo.

3. Choose the session **by slug and freshness, not by the `active` flag.**

   > The `active` flag is derived from a liveness check against the TUI's
   > process ID. In an isolated/sandboxed environment that process is not
   > visible, so `active` reads `false` even when a session is live. Do not wait
   > for or rely on `active: true`.

   To select:
   - If the user provided a slug or session JSON path, use it directly.
   - Otherwise pick the session whose `slug` matches the current repo/branch
     (for local sessions) or the target PR (for `pr` sessions).
   - If several match, choose the **freshest**: compare `updated_at` in
     `sessions/<id>.json`, cross-checked against `last_seen_at` in
     `active_sessions.json` under `~/.local/share/tuicr/reviews/`. The most
     recently updated/seen session is the live one.
   - For a PR review, pass the PR slug from the listing (e.g.
     `gh:owner/repo/pr/N`) to `--session`; it is self-contained and needs no
     `--repo`.
   - If no session matches at all, tell the user you are waiting for them to
     start `tuicr` in the repo, then re-run `tuicr review list` after they say
     it is ready.
   - If slug resolution stays ambiguous, ask the user for the slug or repo path
     the session uses.

## Read User Comments

This is the main review loop for user-led review.

There is no push stream from tuicr to the agent. Read comments by running the
CLI on demand. After the user says comments are ready, or after the TUI exits,
run:

```bash
tuicr review comments --repo /path/to/repo --session <slug>
```

The command emits JSON. Each comment includes fields like:

- `id`
- `location`
- `path`
- `start_line`
- `end_line`
- `side`
- `comment_type`
- `lifecycle_state`
- `content`

Treat these comments as the user's review feedback:

- `issue`: blocking problem to fix first
- `suggestion`: consider implementing or explain why not
- `note`: answer or acknowledge
- `praise`: no action required

If you are waiting during an active review, poll this command about every 30
seconds and compare comment IDs with the previous result. Read immediately when
the user says comments are ready. Stop polling once the user says the review is
done or your tooling would block other work.

If the result is empty, ask whether the user saved comments in the intended
session or whether another session should be selected. If the review may have
continued while you were working, rerun `tuicr review comments` before claiming
completion.

## Add Agent Comments

Only add comments when the workflow allows it and, for agent-authored review,
after the user approves writing them into tuicr.

Defaults:

- Prefer line comments when a specific file and line are known.
- Use file comments for file-scoped feedback.
- Use review-level comments only for whole-review summaries.
- Use `--type issue` for problems by default.
- Use `suggestion`, `note`, or `praise` when that better matches the intent.
- Pass `--username` so agent comments are visually distinguishable.

Examples:

```bash
tuicr review add --repo /path/to/repo --session <slug> \
  --target-file src/main.rs \
  --line 42 \
  --side new \
  --type issue \
  --username "Codex" \
  "Handle the empty case here."
```

```bash
tuicr review add --repo /path/to/repo --session <slug> \
  --target-file src/main.rs \
  --type suggestion \
  --username "Codex" \
  "Consider splitting this file-level concern into a helper."
```

Omit `--target-file` for a review-level comment. Add `--end-line` for a range
comment. Use `--side old` for removed lines and `--side new` for added or
unchanged lines in the new file.

For structured input, use `--input` with literal JSON, `@path/to/file.json`, or
`-` for stdin. Supported target types are `review`, `file`, `line`, and
`line_range`.

## Error Handling

| Situation | Action |
|-----------|--------|
| Multiple plausible sessions | Pick the freshest by `updated_at`/`last_seen_at`; ask only if still ambiguous |
| No matching session | Tell the user you are waiting for them to start `tuicr` in the repo |
| `tuicr` not installed | Tell the user to install tuicr |
| Not a repository | Ask for the correct repo directory |
| Comments are empty | Confirm the selected session or ask the user to save/add comments |

## When Not To Use

- The user only wants raw `git diff` output.
- The user explicitly asks for a non-tuicr review workflow.
- The task is remote PR review and no tuicr PR session is involved.
