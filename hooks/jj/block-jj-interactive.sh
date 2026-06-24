#!/usr/bin/env bash
# Block interactive jj subcommands (split, commit, squash).
# Called as a PreToolUse hook on Bash — reads the tool JSON from stdin.

set -euo pipefail

CMD=$(jq -r '.tool_input.command // ""')

# Check each subcommand keyword
for subcmd in split commit squash; do
  if echo "$CMD" | grep -qE '(^|[;&|]\s*)jj\s+'"$subcmd"'(\s|$)'; then
    cat <<EOF
{"decision":"block","reason":"Do not use \"jj $subcmd\" directly — it requires an interactive editor. Use \"jj-hunk $subcmd\" instead, which accepts a JSON/YAML hunk spec. Load the /jj-hunk skill for reference."}
EOF
    exit 0
  fi
done
