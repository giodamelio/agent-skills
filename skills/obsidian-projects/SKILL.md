---
description: Manage Obsidian vault project notes and inline TODO items, task lists, and project tasks for the current working directory
---

# Obsidian Projects

Read project notes from an Obsidian vault and manage their inline TODO items. Each project note is a markdown file with YAML frontmatter linking it to a directory on disk.

## Finding the Project Note

Run the helper script to find the project note for a directory:

```bash
${SKILL_DIR}/find-project-note.sh [directory]
```

- If no directory is provided, defaults to the current working directory
- Prints the matching project note path on stdout and exits 0
- Exits 1 with an error message if no matching project note exists

Example:
```bash
${SKILL_DIR}/find-project-note.sh ~/nixos-configs
# Output: /home/user/Documents/life/Projects/NixOS Configs.md
```

## Reading Project Notes

Once you have the file path, read the entire file to understand the project context. The file contains:

1. **YAML frontmatter** with `project_directory` field linking to the project on disk
2. **Body content** with project documentation, notes, and reference material
3. **TODO section** with inline task items

Everything outside the TODO section is read-only reference material.

## Managing TODOs

The TODO section is the **ONLY part of a project file that may be edited**. TODOs appear under a heading with text `TODO` at any level (`# TODO`, `## TODO`, `### TODO`, etc.).

### Format

- `- [ ]` — incomplete task
- `- [x]` — completed task
- Indented items (tab + `- [ ]`) are sub-tasks of the item above
- `~~text~~` (strikethrough) indicates cancelled/abandoned items — leave as historical record

### Operations

**Viewing:** Read the TODO section and present items with their completion status.

**Completing a task:** Change `- [ ]` to `- [x]` when work is done.

**Uncompleting a task:** Change `- [x]` to `- [ ]` if reverting completion.

**Adding tasks:** Append new `- [ ]` items to the end of the TODO section. If no TODO heading exists, create one as `# TODO` at the end of the file.

**Removing tasks:** Only remove items when the user explicitly asks. Prefer marking complete over deleting.

## Creating a New Project Note

**ONLY create a new project note when the user explicitly asks to set up a project.**

To create a new project note:

1. Create a new `.md` file in `~/Documents/life/Projects/` named after the project
2. Include YAML frontmatter with `project_directory` pointing to the project directory on disk
3. Add a `# TODO` section

Example structure:
```markdown
---
project_directory: ~/projects/my-new-project
---

# My New Project

Project description and notes here.

# TODO

- [ ] Initial setup task
```

## Safety Rules

- The TODO section is the **ONLY** part of a project file that may be edited
- Everything else (frontmatter, body text, other headings) is **READ-ONLY**
- **NEVER** modify the YAML frontmatter block
- **NEVER** delete project files
- Only files with `project_directory` frontmatter are valid project notes — do not read or edit other files in the vault
