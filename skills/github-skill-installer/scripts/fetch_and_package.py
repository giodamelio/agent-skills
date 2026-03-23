#!/usr/bin/env python3
"""
Fetch skills from a GitHub repository, validate, and package as .skill files.

Usage:
    python fetch_and_package.py <repo_url> [options]

Options:
    --skill-path PATH    Path within repo to a specific skill directory
    --ref REF            Branch, tag, or commit to checkout (default: repo default)
    --output-dir DIR     Where to write .skill files (default: /mnt/user-data/outputs)
    --keep-clone         Don't delete the cloned repo after packaging (for debugging)

Examples:
    python fetch_and_package.py https://github.com/user/repo
    python fetch_and_package.py https://github.com/user/repo --skill-path skills/my-skill
    python fetch_and_package.py user/repo --ref v2.0 --output-dir ./out
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

import yaml


# ---------------------------------------------------------------------------
# Validation (mirrors skill-creator's quick_validate logic)
# ---------------------------------------------------------------------------

ALLOWED_FRONTMATTER_KEYS = {
    "name", "description", "license", "allowed-tools", "metadata", "compatibility",
    "source",
}


def validate_skill(skill_path: Path, fix: bool = True, source: str | None = None) -> tuple[bool, str]:
    """
    Validate a skill directory. Returns (is_valid, name_or_error).

    If fix=True (default), missing frontmatter fields are derived from the
    directory name and first heading, and the SKILL.md is rewritten with valid
    frontmatter before packaging. This lets us package Claude Code-style skills
    (which often lack strict frontmatter) for Claude.ai.

    If source is provided, it is written into the frontmatter as the 'source'
    field so that future updates can locate the original repo.
    """
    skill_md = skill_path / "SKILL.md"
    if not skill_md.exists():
        return False, f"SKILL.md not found in {skill_path}"

    content = skill_md.read_text(encoding="utf-8")

    # Try to parse existing frontmatter
    frontmatter = {}
    body = content
    if content.startswith("---"):
        match = re.match(r"^---\n(.*?)\n---\n?(.*)", content, re.DOTALL)
        if match:
            try:
                parsed = yaml.safe_load(match.group(1))
                if isinstance(parsed, dict):
                    frontmatter = parsed
                    body = match.group(2)
            except yaml.YAMLError:
                pass  # Treat as no frontmatter

    # Derive name from frontmatter or directory name
    name = frontmatter.get("name", "")
    if not name or not isinstance(name, str):
        name = skill_path.name  # directory name as fallback
    name = name.strip().lower()
    # Enforce kebab-case: replace underscores/spaces with hyphens, strip non-allowed chars
    name = re.sub(r"[_ ]+", "-", name)
    name = re.sub(r"[^a-z0-9-]", "", name)
    name = re.sub(r"-{2,}", "-", name).strip("-")
    if not name:
        return False, "Cannot derive a valid name from directory or frontmatter"
    if len(name) > 64:
        name = name[:64].rstrip("-")

    # Derive description from frontmatter, first paragraph, or first heading
    desc = frontmatter.get("description", "")
    if not desc or not isinstance(desc, str):
        # Try first heading + next paragraph
        heading_match = re.search(r"^#\s+(.+)$", body, re.MULTILINE)
        para_match = re.search(r"^(?!#)(\S.{10,}?)$", body, re.MULTILINE)
        if heading_match and para_match:
            desc = f"{heading_match.group(1).strip()}. {para_match.group(1).strip()}"
        elif heading_match:
            desc = heading_match.group(1).strip()
        elif para_match:
            desc = para_match.group(1).strip()
        else:
            desc = f"Skill: {name}"
    desc = desc.strip()
    # Sanitize
    desc = desc.replace("<", "").replace(">", "")
    if len(desc) > 1024:
        desc = desc[:1021] + "..."

    if fix:
        # Rewrite SKILL.md with valid frontmatter
        frontmatter["name"] = name
        frontmatter["description"] = desc
        # Inject source URL for future updates
        if source:
            frontmatter["source"] = source
        # Remove any unexpected keys
        for key in list(frontmatter.keys()):
            if key not in ALLOWED_FRONTMATTER_KEYS:
                del frontmatter[key]

        new_content = "---\n" + yaml.dump(frontmatter, default_flow_style=False, allow_unicode=True).strip() + "\n---\n\n" + body.lstrip("\n")
        skill_md.write_text(new_content, encoding="utf-8")
        print(f"  FIXED frontmatter for '{name}'")

    return True, name


# ---------------------------------------------------------------------------
# Repo cloning
# ---------------------------------------------------------------------------


def normalize_repo_url(raw: str) -> str:
    """Accept shorthand 'user/repo' or full URL; return a clone-able HTTPS URL."""
    raw = raw.strip().rstrip("/")
    # Already a full URL
    if raw.startswith("http://") or raw.startswith("https://"):
        # Strip /tree/branch/... if present (handled separately)
        base = re.sub(r"/tree/.*$", "", raw)
        if not base.endswith(".git"):
            base += ".git"
        return base
    # Shorthand: user/repo
    if re.match(r"^[\w.-]+/[\w.-]+$", raw):
        return f"https://github.com/{raw}.git"
    raise ValueError(f"Cannot parse repo URL: {raw}")


def parse_github_tree_url(raw: str) -> tuple[str, str | None, str | None]:
    """
    Parse a GitHub URL that may point to a subdirectory.
    Returns (repo_url, ref_or_none, path_or_none).
    """
    m = re.match(
        r"https?://github\.com/([\w.-]+/[\w.-]+)/tree/([^/]+)(?:/(.+))?", raw.strip()
    )
    if m:
        repo = f"https://github.com/{m.group(1)}.git"
        ref = m.group(2)
        path = m.group(3)  # may be None
        return repo, ref, path
    return normalize_repo_url(raw), None, None


def clone_repo(repo_url: str, dest: Path, ref: str | None = None) -> None:
    """Shallow-clone a repo. Optionally checkout a specific ref."""
    cmd = ["git", "clone", "--depth", "1"]
    if ref:
        cmd += ["--branch", ref]
    cmd += [repo_url, str(dest)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"git clone failed (exit {result.returncode}):\n{result.stderr.strip()}"
        )


# ---------------------------------------------------------------------------
# Skill discovery
# ---------------------------------------------------------------------------

# Directories to skip when searching for skills
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", "evals"}


def discover_skills(root: Path) -> list[Path]:
    """Find all directories under *root* that contain a SKILL.md file."""
    skills: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        # Prune directories we don't want to descend into
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        if "SKILL.md" in filenames:
            skills.append(Path(dirpath))
    return skills


# ---------------------------------------------------------------------------
# Packaging
# ---------------------------------------------------------------------------

EXCLUDE_DIRS = {"__pycache__", "node_modules", ".git"}
EXCLUDE_GLOBS = {"*.pyc"}
EXCLUDE_FILES = {".DS_Store"}
ROOT_EXCLUDE_DIRS = {"evals"}


def should_exclude(rel_path: Path) -> bool:
    parts = rel_path.parts
    if any(p in EXCLUDE_DIRS for p in parts):
        return True
    if len(parts) > 1 and parts[1] in ROOT_EXCLUDE_DIRS:
        return True
    name = rel_path.name
    if name in EXCLUDE_FILES:
        return True
    return any(__import__("fnmatch").fnmatch(name, pat) for pat in EXCLUDE_GLOBS)


def package_skill(skill_path: Path, output_dir: Path, source: str | None = None) -> Path | None:
    """
    Zip a skill directory into a .skill file.
    Returns the output path, or None on failure.
    """
    valid, name_or_error = validate_skill(skill_path, source=source)
    if not valid:
        print(f"  SKIP  {skill_path.name}: {name_or_error}")
        return None

    skill_name = name_or_error  # validate_skill returns the name on success
    output_dir.mkdir(parents=True, exist_ok=True)
    out_file = output_dir / f"{skill_name}.skill"

    with zipfile.ZipFile(out_file, "w", zipfile.ZIP_DEFLATED) as zf:
        for fp in skill_path.rglob("*"):
            if not fp.is_file():
                continue
            arcname = fp.relative_to(skill_path.parent)
            if should_exclude(arcname):
                continue
            zf.write(fp, arcname)

    print(f"  OK    {skill_name} -> {out_file}")
    return out_file


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch and package skills from GitHub")
    parser.add_argument("repo", help="GitHub repo URL or user/repo shorthand")
    parser.add_argument("--skill-path", help="Path within repo to a specific skill dir")
    parser.add_argument("--ref", help="Branch, tag, or commit to checkout")
    parser.add_argument(
        "--output-dir",
        default="/mnt/user-data/outputs",
        help="Where to write .skill files",
    )
    parser.add_argument(
        "--keep-clone", action="store_true", help="Keep cloned repo for debugging"
    )
    args = parser.parse_args()

    # Parse URL (may contain /tree/branch/path)
    repo_url, parsed_ref, parsed_path = parse_github_tree_url(args.repo)
    ref = args.ref or parsed_ref
    skill_path_override = args.skill_path or parsed_path

    # Clone
    tmp_dir = Path(tempfile.mkdtemp(prefix="skill-fetch-"))
    clone_dest = tmp_dir / "repo"
    print(f"Cloning {repo_url}" + (f" (ref: {ref})" if ref else "") + " ...")
    try:
        clone_repo(repo_url, clone_dest, ref)
    except RuntimeError as exc:
        print(f"\nERROR: {exc}")
        # Check for common auth error
        if "Authentication" in str(exc) or "could not read" in str(exc):
            print(
                "\nThis looks like a private repo. git clone over HTTPS can't access "
                "private repos without credentials. Either make the repo public or "
                "download the skill folder manually and upload it as a zip."
            )
        shutil.rmtree(tmp_dir, ignore_errors=True)
        sys.exit(1)

    # Discover skills
    if skill_path_override:
        target = clone_dest / skill_path_override
        if not target.exists():
            print(f"\nERROR: Path '{skill_path_override}' not found in the repo.")
            print("Available top-level directories:")
            for p in sorted(clone_dest.iterdir()):
                if p.is_dir() and p.name != ".git":
                    print(f"  {p.name}/")
            shutil.rmtree(tmp_dir, ignore_errors=True)
            sys.exit(1)
        skills = [target] if (target / "SKILL.md").exists() else discover_skills(target)
    else:
        skills = discover_skills(clone_dest)

    if not skills:
        print("\nNo skills found (no directories with SKILL.md).")
        print("Searched in:", clone_dest if not skill_path_override else target)
        shutil.rmtree(tmp_dir, ignore_errors=True)
        sys.exit(1)

    print(f"\nFound {len(skills)} skill(s). Packaging...\n")

    # Build a canonical source URL for each skill as a GitHub tree URL.
    # Format: https://github.com/user/repo/tree/REF/path/to/skill
    # This is a clickable link and encodes repo, ref, and skill-path.
    def _build_source(skill_dir: Path) -> str:
        base = repo_url.removesuffix(".git")
        # Determine the ref to embed; fall back to "main" if none was specified
        source_ref = ref or "main"
        rel = skill_dir.relative_to(clone_dest)
        if str(rel) != ".":
            return f"{base}/tree/{source_ref}/{rel}"
        else:
            return f"{base}/tree/{source_ref}"

    output_dir = Path(args.output_dir)
    results = []
    for sp in sorted(skills):
        source = _build_source(sp)
        out = package_skill(sp, output_dir, source=source)
        if out:
            # Read the name and description for the summary
            content = (sp / "SKILL.md").read_text(encoding="utf-8")
            fm_match = re.match(r"^---\n(.*?)\n---", content, re.DOTALL)
            fm = yaml.safe_load(fm_match.group(1)) if fm_match else {}
            results.append(
                {
                    "name": fm.get("name", sp.name),
                    "description": fm.get("description", ""),
                    "source": fm.get("source", source),
                    "file": str(out),
                }
            )

    # Cleanup
    if not args.keep_clone:
        shutil.rmtree(tmp_dir, ignore_errors=True)

    # Summary
    print(f"\n{'='*60}")
    print(f"Packaged {len(results)} skill(s):")
    for r in results:
        print(f"  - {r['name']}: {r['file']}")
    print(f"{'='*60}")

    # Machine-readable output
    print("\n__JSON_SUMMARY__")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
