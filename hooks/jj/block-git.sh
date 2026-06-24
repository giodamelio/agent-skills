#!/usr/bin/env bash
# Block all git commands with a reminder to use jj instead.
# Called as a PreToolUse hook on Bash — reads the tool JSON from stdin.
#
# Every git command is blocked. Specific command shapes can print a tailored
# message via the overrides below; anything not matched gets DEFAULT_REASON.

set -euo pipefail

CMD=$(jq -r '.tool_input.command // ""')

DEFAULT_REASON="Do not use git directly in this repo — it uses Jujutsu (jj) on top of Git. Use the equivalent jj command instead (e.g. jj status, jj log, jj diff, jj commit). Load the /jujutsu skill for reference."

# emit a block decision with the given reason, then exit
block() {
  jq -n --arg reason "$1" '{decision:"block", reason:$reason}'
  exit 0
}

# Match `git ...` as a command: at start of line, or after a shell
# separator (; & | newline), optionally preceded by `sudo`/env-style words.
if echo "$CMD" | grep -qE '(^|[;&|]|\bsudo\s+|\bcommand\s+)\s*git(\s|$)'; then
  # --- Per-command overrides (checked in order; first match wins) ---

  # git clone -> jj git clone (bots otherwise fall back to web requests)
  if echo "$CMD" | grep -qE '\bgit\s+clone(\s|$)'; then
    block "Use 'jj git clone <url>' instead of 'git clone' when cloning new repos. Do not fall back to web requests."
  fi

  # --- Default: block with the generic reminder ---
  block "$DEFAULT_REASON"
fi
