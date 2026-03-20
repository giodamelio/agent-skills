#!/usr/bin/env nix-shell
#!nix-shell -i bash -p stow

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Install global skills into Claude Code
mkdir -p "$HOME/.claude/skills"
stow -d "$REPO_ROOT" -t "$HOME/.claude/skills" skills

# Install global skills into oh-my-pi
mkdir -p "$HOME/.omp/agent/skills"
stow -d "$REPO_ROOT" -t "$HOME/.omp/agent/skills" skills

echo "Skills installed successfully."
