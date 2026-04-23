# jj-hunk Spec Format & Command Reference

## The Spec Format

The spec is a JSON object you pass to `jj-hunk` commands to tell them which hunks to include. Getting the spec format right is the single most important thing about using jj-hunk — an invalid spec will either error out or silently do the wrong thing.

### The Golden Rule: Everything Goes Under `"files"`

The spec has exactly two possible top-level keys: `"files"` and `"default"`. File paths are **always nested inside `"files"`** — never at the top level.

**Correct:**
```json
{"files": {"src/main.rs": {"action": "keep"}}, "default": "reset"}
```

**Wrong — will fail:**
```json
{"src/main.rs": {"action": "keep"}, "default": "reset"}
```

This is the most common mistake. The `"files"` wrapper is not optional. Even if you're only selecting one file, it must be inside `"files"`.

### Spec Structure

```json
{
  "files": {
    "path/to/file-a": <file-spec>,
    "path/to/file-b": <file-spec>
  },
  "default": "keep" | "reset"
}
```

Where `<file-spec>` is one of:

| File spec | What it does |
|-----------|-------------|
| `{"action": "keep"}` | Include all hunks in this file |
| `{"action": "reset"}` | Exclude all hunks in this file |
| `{"hunks": [0, 2]}` | Include only these hunks (0-indexed) |
| `{"ids": ["hunk-7c3d..."]}` | Include hunks by their stable ID |

And `"default"` controls what happens to files **not listed** in `"files"`:
- `"reset"` — unlisted files are excluded (this is the safer choice)
- `"keep"` — unlisted files are included

### More Examples

**Keep one file, reset everything else:**
```json
{"files": {"src/db/schema.ts": {"action": "keep"}}, "default": "reset"}
```

**Keep two files:**
```json
{"files": {"src/db/schema.ts": {"action": "keep"}, "src/db/migrations.ts": {"action": "keep"}}, "default": "reset"}
```

**Select specific hunks from a file:**
```json
{"files": {"src/lib/utils.ts": {"hunks": [0, 2]}}, "default": "reset"}
```

**Mix file-level and hunk-level selection:**
```json
{
  "files": {
    "src/db/schema.ts": {"action": "keep"},
    "src/api/routes.ts": {"hunks": [0]}
  },
  "default": "reset"
}
```

### Common Mistakes to Avoid

1. **Missing `"files"` wrapper** — putting file paths at the top level:
   ```json
   ✗  {"src/foo.rs": {"action": "keep"}, "default": "reset"}
   ✓  {"files": {"src/foo.rs": {"action": "keep"}}, "default": "reset"}
   ```

2. **Putting `"default"` inside `"files"`** — it is a sibling, not a child:
   ```json
   ✗  {"files": {"src/foo.rs": {"action": "keep"}, "default": "reset"}}
   ✓  {"files": {"src/foo.rs": {"action": "keep"}}, "default": "reset"}
   ```

3. **Using `"action"` at the top level instead of `"default"`:**
   ```json
   ✗  {"files": {"src/foo.rs": {"action": "keep"}}, "action": "reset"}
   ✓  {"files": {"src/foo.rs": {"action": "keep"}}, "default": "reset"}
   ```

4. **Using a bare string instead of an object for a file spec:**
   ```json
   ✗  {"files": {"src/foo.rs": "keep"}, "default": "reset"}
   ✓  {"files": {"src/foo.rs": {"action": "keep"}}, "default": "reset"}
   ```

5. **Wrapping hunks in an object with `"action"`:**
   ```json
   ✗  {"files": {"src/foo.rs": {"action": "hunks", "hunks": [0]}}, "default": "reset"}
   ✓  {"files": {"src/foo.rs": {"hunks": [0]}}, "default": "reset"}
   ```

## Commands

**NEVER use `jj split`, `jj commit`, or `jj squash -i`** — these are interactive commands that will hang in agent environments. Always use `jj-hunk` instead.

All `jj-hunk` commands require a spec argument. Running any command without a spec will block waiting on stdin and hang.

### `jj-hunk list` — Inspect Hunks Before Acting

Always list hunks first to understand what you're working with. The output tells you what files changed, how many hunks each has, and the content of each hunk.

```bash
# List all hunks in working copy (JSON output)
jj-hunk list

# List hunks for a specific revision
jj-hunk list --rev @-

# List files only, with hunk counts
jj-hunk list --files

# Generate a spec template you can edit
jj-hunk list --spec-template --format yaml

# Filter by path
jj-hunk list --include 'src/**' --exclude '**/*.test.rs'
```

The output looks like this:
```json
{
  "src/db/schema.ts": [
    {"id": "hunk-4c1b...", "index": 0, "type": "insert", "added": "import { pgTable }...\n"},
    {"id": "hunk-9a2b...", "index": 1, "type": "replace", "removed": "old line\n", "added": "new line\n"}
  ],
  "src/api/routes.ts": [
    {"id": "hunk-7c3d...", "index": 0, "type": "delete", "removed": "dead code\n"}
  ]
}
```

Each hunk has:
- `index` — 0-based position (use in `"hunks"` spec)
- `id` — stable SHA256-based ID like `"hunk-4c1b..."` (use in `"ids"` spec)
- `type` — `"insert"`, `"replace"`, or `"delete"`
- `added` / `removed` — the actual content changed

### `jj-hunk split` — Split a Commit in Two

Selected hunks go to a new first commit with the given message. Everything else stays in the original commit.

```bash
jj-hunk split '<spec>' "commit message for first half"

# Split a specific revision (not just working copy)
jj-hunk split -r @- '<spec>' "commit message"
```

To split into many commits, call `split` repeatedly — each call peels off one commit.

### `jj-hunk commit` — Commit Selected Hunks

Like `split`, but operates on the working copy. Selected hunks are committed; the rest remain uncommitted.

```bash
jj-hunk commit '<spec>' "commit message"
```

### `jj-hunk squash` — Squash Selected Hunks into Parent

Moves selected hunks from a commit into its parent commit.

```bash
# Squash from working copy into parent
jj-hunk squash '<spec>'

# Squash a specific revision into its parent
jj-hunk squash -r @- '<spec>'
```

## Recommended Workflow

1. **List hunks** to see what changed:
   ```bash
   jj-hunk list --files
   jj-hunk list
   ```

2. **Plan your commits** — group changes by logical concern.

3. **Split iteratively**, peeling off one commit at a time:
   ```bash
   # First commit: database schema
   jj-hunk split '{"files": {"src/db/schema.ts": {"action": "keep"}}, "default": "reset"}' "Add database schema"

   # Second commit: API routes
   jj-hunk split '{"files": {"src/api/routes.ts": {"action": "keep"}}, "default": "reset"}' "Add API routes"

   # Remaining changes become the last commit — just describe it
   jj describe -m "Add UI components"
   ```

4. **Verify** the result:
   ```bash
   jj log
   jj diff -r <change-id> --stat
   ```

## Spec Input Methods

The spec can be provided in several ways:

- **Inline JSON** (most common): `jj-hunk split '{"files": ...}' "msg"`
- **Stdin**: `cat spec.json | jj-hunk commit - "msg"`
- **File**: `jj-hunk split --spec-file spec.yaml "msg"`
- **YAML** also works in place of JSON for any of these methods

## Quick Spec Reference

```
{
  "files": {                              ← REQUIRED wrapper
    "path/file": {"action": "keep"},      ← include all hunks
    "path/file": {"action": "reset"},     ← exclude all hunks
    "path/file": {"hunks": [0, 2]},       ← include specific hunks (0-indexed)
    "path/file": {"ids": ["hunk-..."]}    ← include by stable ID
  },
  "default": "reset"                      ← what to do with unlisted files
}
```
