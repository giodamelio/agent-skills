---
name: github-skill-installer
description: Fetch Claude skills from GitHub repositories and package them as installable .skill files. Use this skill whenever the user wants to install a skill from GitHub, pull a skill from a repo, update a skill they previously installed from GitHub, grab a skill from a URL, or says things like "install the X skill from GitHub", "fetch my skills from my repo", "update my custom skills", or "get the skill at github.com/user/repo". Also trigger when the user shares a GitHub link to a directory containing a SKILL.md file or a repo known to contain skills.
---

# GitHub Skill Installer

Fetch skills from GitHub repos, validate them, package them as `.skill` files, and present them to the user with the one-click "Copy to your skills" install button.

## How it works

Run the bundled `scripts/fetch_and_package.py` script. It handles cloning, discovery, validation, and packaging in one shot.

## Quick reference

```bash
# Install a specific skill from a repo
python /path/to/this/skill/scripts/fetch_and_package.py https://github.com/user/repo --skill-path path/to/skill-dir

# Auto-discover all skills in a repo
python /path/to/this/skill/scripts/fetch_and_package.py https://github.com/user/repo

# Install from a specific branch or tag
python /path/to/this/skill/scripts/fetch_and_package.py https://github.com/user/repo --ref v1.2.0

# Install from a subdirectory (monorepo)
python /path/to/this/skill/scripts/fetch_and_package.py https://github.com/user/repo --skill-path skills/my-cool-skill
```

## Workflow

### 1. Parse the user's request

The user might provide:
- A full GitHub URL (`https://github.com/user/repo`)
- A GitHub URL pointing to a specific directory (`https://github.com/user/repo/tree/main/skills/foo`)
- A shorthand (`user/repo`)
- A repo URL plus a skill name or path ("the `bar` skill from github.com/user/repo")
- Just a vague reference ("update my skills from my repo") — check conversation context or memory for the repo

Extract:
- **repo_url**: The GitHub clone URL. Accept `user/repo` shorthand and expand to `https://github.com/user/repo`.
- **ref** (optional): Branch, tag, or commit. Default: the repo's default branch.
- **skill_path** (optional): Path within the repo to a specific skill directory. If the URL points to a `/tree/branch/path`, extract the ref and path from it.

If the URL points to a specific directory (contains `/tree/`), parse it:
- `https://github.com/user/repo/tree/main/skills/foo` → repo=`https://github.com/user/repo`, ref=`main`, skill_path=`skills/foo`

### 2. Run the script

```bash
python <skill-dir>/scripts/fetch_and_package.py <repo_url> \
  [--ref <branch-or-tag>] \
  [--skill-path <path/to/skill>] \
  [--output-dir /mnt/user-data/outputs]
```

The script will:
1. Clone the repo (shallow, depth=1) to a temp directory
2. If `--skill-path` is given, look for `SKILL.md` at that path
3. If no `--skill-path`, auto-discover all directories containing a `SKILL.md` file
4. Validate each skill's frontmatter (name, description, no angle brackets, kebab-case, length limits)
5. Package each valid skill as a `.skill` zip file in the output directory
6. Print a JSON summary of what was packaged

### 3. Present results

After the script completes, call `present_files` on each `.skill` file it produced. This gives the user the "Copy to your skills" button for one-click installation.

If the script found multiple skills, present them all. Briefly list what was found — skill name and description for each — so the user knows what they're installing.

If validation failed for any skill, report which ones failed and why. The user may want to fix them or skip them.

### 4. Handle updates

When the user says "update my skills" or "pull the latest version":

1. **Check the installed skill's `source` frontmatter first.** Every skill packaged by this installer has a `source` field in its SKILL.md frontmatter that records the GitHub URL it was installed from. Read the installed skill's SKILL.md at `/mnt/skills/user/<skill-name>/SKILL.md`, parse the frontmatter, and extract the `source` value.

   The `source` field is a standard GitHub tree URL:
   ```
   source: https://github.com/user/repo/tree/main/path/to/skill
   ```
   This URL can be passed directly to the script as the repo argument — `parse_github_tree_url()` will decompose it into repo, ref, and skill-path automatically.

2. **If no `source` field exists**, ask the user for the GitHub URL. Don't guess or try to infer it from conversation history — just ask.

3. Re-run the script with the recovered or provided URL — it always pulls fresh from the repo.

4. The new `.skill` file will overwrite when installed, updating the skill.

Remind the user that installing the new `.skill` file will replace the old version.

## Edge cases

- **Private repos**: `git clone` over HTTPS won't work for private repos without auth. If the clone fails with an auth error, let the user know and suggest they either make the repo public or download the skill folder manually and upload it as a zip.
- **No skills found**: If auto-discovery finds no `SKILL.md` files, tell the user. Suggest they check the repo structure or point to a specific subdirectory.
- **Large repos**: The `--depth 1` shallow clone keeps things fast, but very large repos may still take a moment. That's fine.
- **Non-GitHub repos**: The script works with any git-hostable URL. GitLab, Codeberg, etc. all work if the domain is accessible from the network.

## Examples

**Example 1: Install a specific skill**
User: "Install the sourdough-scaler skill from github.com/giodamelio/claude-skills"
→ Run: `python .../fetch_and_package.py https://github.com/giodamelio/claude-skills --skill-path sourdough-scaler`
→ Present: `sourdough-scaler.skill`

**Example 2: Install all skills from a repo**
User: "Grab all the skills from https://github.com/someuser/my-skills"
→ Run: `python .../fetch_and_package.py https://github.com/someuser/my-skills`
→ Present: all discovered `.skill` files

**Example 3: URL pointing to a subdirectory**
User: "Install this: https://github.com/user/repo/tree/main/skills/research-helper"
→ Parse: repo=`https://github.com/user/repo`, ref=`main`, skill_path=`skills/research-helper`
→ Run: `python .../fetch_and_package.py https://github.com/user/repo --ref main --skill-path skills/research-helper`
→ Present: `research-helper.skill`

**Example 4: Update using source frontmatter**
User: "Update my homelab planner skill"
→ Read `/mnt/skills/user/nixos-homelab-planner/SKILL.md`, parse frontmatter `source` field
→ `source: https://github.com/giodamelio/agent-skills/tree/main/skills/nixos-homelab-planner`
→ Run: `python .../fetch_and_package.py https://github.com/giodamelio/agent-skills/tree/main/skills/nixos-homelab-planner`
→ Present the fresh `.skill` file

**Example 5: Update with no source field (legacy skill)**
User: "Update my homelab planner skill"
→ Read `/mnt/skills/user/nixos-homelab-planner/SKILL.md` — no `source` field found
→ Ask the user: "I don't have a source URL stored for that skill. What's the GitHub URL?"
→ User provides URL → re-run the script
→ Present the fresh `.skill` file (which now includes the `source` field for next time)
