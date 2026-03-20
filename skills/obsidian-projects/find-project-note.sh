#!/usr/bin/env nix-shell
#!nix-shell -i bash -p coreutils gnugrep findutils

set -euo pipefail

VAULT_DIR="$HOME/Documents/life/Projects"

# Get the directory to search for (default: current directory)
search_dir="${1:-$PWD}"

# Resolve to absolute path
if ! search_dir="$(realpath "$search_dir" 2>/dev/null)"; then
    echo "Error: Directory does not exist: $1" >&2
    exit 1
fi

found=false

# Find markdown files and check each for project_directory
while IFS= read -r -d '' file; do
    # Check if file has project_directory in frontmatter
    if ! grep -q '^project_directory:' "$file" 2>/dev/null; then
        continue
    fi
    
    # Extract project_directory value from YAML frontmatter
    proj_dir=$(sed -n '/^---$/,/^---$/{ /^project_directory:/{s/^project_directory:[[:space:]]*//p; q} }' "$file")
    
    # Skip if no project_directory found
    [[ -z "$proj_dir" ]] && continue
    
    # Expand ~ to $HOME
    proj_dir="${proj_dir/#\~/$HOME}"
    
    # Resolve to absolute path (skip if directory doesn't exist)
    if ! resolved_proj_dir="$(realpath "$proj_dir" 2>/dev/null)"; then
        continue
    fi
    
    # Check if this project matches our search directory
    if [[ "$resolved_proj_dir" == "$search_dir" ]]; then
        echo "$file"
        exit 0
    fi
    
    found=true
done < <(find "$VAULT_DIR" -maxdepth 1 -name '*.md' -print0 2>/dev/null)

if [[ "$found" == false ]]; then
    echo "Error: No project notes found in $VAULT_DIR" >&2
else
    echo "Error: No project note found for directory: $search_dir" >&2
fi
exit 1
