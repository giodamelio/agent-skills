# jj-hunk Reference

`jj-hunk` selects parts of a diff without an interactive editor, then lets jj split, commit, or squash that selection.

**NEVER use `jj split`, `jj commit`, or `jj squash -i`** — they open an interactive editor and will hang. Use `jj-hunk` instead.

## Commands

| Command | Result | Revision |
|---------|--------|----------|
| `jj-hunk list [selection]` | Show hunks, or preview what a selection matches | `-r <rev>` (default `@`) |
| `jj-hunk split <selection> "message"` | Selection becomes a new first commit with the message; the rest stays in a second commit | `-r <rev>` (default `@`) |
| `jj-hunk commit <selection> "message"` | Selection is committed with the message; the rest stays in a new working copy | Always `@` (no `-r`) |
| `jj-hunk squash <selection>` | Selection moves from the revision into its parent | `-r <rev>` (default `@`) |

`<selection>` is exactly one of:

- `--query '<hunkset expression>'` — describe the changes to select (see [Select changes with a hunkset query](#select-changes-with-a-hunkset-query))
- `'<json-or-yaml spec>'` — an inline spec as the first positional argument (see [Select hunks with a JSON/YAML spec](#select-hunks-with-a-jsonyaml-spec))
- `--spec-file path.json` or `--spec-file path.yaml` — a spec in a file; omit the positional spec
- `-` — read the spec from stdin

A query and a spec cannot be combined. `split` and `commit` require a message, `squash` takes none.

## Use a hunkset query by default

**Always reach for `--query` first. Write a JSON/YAML spec only when no query can isolate the changes you want.** Don't fall back to a spec just because it feels more familiar.

A query is the better default because:

- It stays valid across rewrites. Spec indices and IDs go stale after every `split`, `commit`, or `squash`, so a spec is only safe right after a fresh `jj-hunk list`.
- A bad query fails loudly before anything changes. Common spec mistakes are accepted, select nothing, and exit 0.
- It is shorter. One `changed(path:glob:"src/db/**")` replaces listing hunks, copying indices, and writing nested JSON.
- It is the only way to select renames, mode changes, binary changes, and empty files.

Fall back to a spec only when one of these is true, and say which:

- The hunks you want share no path or text pattern that separates them from the hunks you don't want, even with `&`, `~`, and `|`.
- Every query you try also catches blocks that belong elsewhere, and you can't tighten it.

When you do use a spec, run `jj-hunk list` immediately before writing it and apply it before any other rewrite.

`-r` must resolve to exactly one revision. Use change IDs, not commit IDs, since commit IDs change on every rewrite.

## Preview every selection before applying it

`list` accepts the same selection as the mutating commands. Run it first and read what it matched:

```bash
jj-hunk list --format text --query 'added(content:"timeout")'
jj-hunk list --format text --spec '{"files": {"src/lib.rs": {"hunks": [0]}}, "default": "reset"}'
jj-hunk list --format text -r <rev> --spec-file spec.yaml
```

An empty preview means the selection matches nothing. A malformed-but-parseable spec (for example one missing the `"files"` wrapper) also previews as empty and exits 0, and applying it is a silent no-op. Previewing is how you catch this.

## Inspect hunks with `jj-hunk list`

```bash
jj-hunk list --files --format text      # files with status and hunk counts
jj-hunk list --format text              # every hunk, compact and readable
jj-hunk list -r <rev> --format text     # hunks of another revision against its parent
jj-hunk list                            # full JSON with ranges and context
jj-hunk list --spec-template --format yaml   # ID-based spec covering every hunk, to edit down
```

Text output:

```
M src/client.rs
  hunk 0 replace hunk-b059bcd9…af36c (before 1+1 after 1+1)
    - let timeout = Duration::from_secs(5);
    + let timeout = Duration::from_secs(30);
  hunk 1 replace hunk-778393b3…f0146 (before 8+1 after 8+1)
    - log::debug!("request");
    + log::info!("request");
A src/new.rs
  hunk 0 insert hunk-5dfe84c1…5817d (before 1+0 after 1+1)
    + pub fn new() {}
```

JSON output is an object with a `files` **array**:

```json
{
  "files": [
    {
      "path": "src/client.rs",
      "status": "modified",
      "hunks": [
        {
          "index": 0,
          "id": "hunk-b059bcd9…",
          "type": "replace",
          "removed": "let timeout = Duration::from_secs(5);\n",
          "added": "let timeout = Duration::from_secs(30);\n",
          "before": {"start": 1, "lines": 1},
          "after": {"start": 1, "lines": 1},
          "context": {"pre": "", "post": "let retries = 3;\n"}
        }
      ]
    }
  ]
}
```

- `index` — 0-based position within the file
- `id` — `hunk-` followed by 64 hex characters; always use the full ID, never an abbreviation
- `type` — `insert`, `delete`, or `replace`
- `status` — `added`, `modified`, `deleted`, and so on; `--files` gives `hunk_count` instead of `hunks`

Other `list` options: `--include <glob>` / `--exclude <glob>` (repeatable; not combinable with `--query`), `--group directory|extension|status`, `--binary skip|mark|include`, `--max-bytes <n>` / `--max-lines <n>` (truncate displayed text only).

### Indices and IDs are single-use

Every `split`, `commit`, or `squash` rewrites the comparison, which renumbers indices and regenerates **all** IDs — including in files you did not touch. Run `jj-hunk list` again before building each new spec. Never reuse an index or ID from an earlier listing.

Queries describe content rather than positions, so the same query stays valid across rewrites. This is the main reason queries are the default.

## Select changes with a hunkset query

A query selects whole edit blocks (hunks) and whole-file operations by what they contain.

```bash
jj-hunk split --query 'added(content:"timeout")' "Increase request timeout"
jj-hunk split --query 'changed(path:glob:"src/db/**")' "Add database schema"
jj-hunk squash -r <rev> --query 'changed(path:glob:"tests/**")'
```

### Predicates

| Function | Selects |
|----------|---------|
| `changed(...)` | Any change; `content:` searches both the removed and added side |
| `added(...)` | Blocks with added text, and whole new files |
| `removed(...)` | Blocks with removed text, and whole deleted files |
| `renamed(...)` | Renames only |
| `mode_changed(...)` | Executable-bit changes only |
| `binary_changed(...)` | Binary-content changes only |
| `all()` / `none()` | Everything / nothing |
| `id("hunk-<64 hex>")` | One exact occurrence from the current listing |

### Fields

| Field | Meaning | Allowed on |
|-------|---------|------------|
| `path:` | The change is in a matching path (old or new) | All predicates |
| `before_path:` / `after_path:` | Match only the old / new path | All predicates |
| `file:` | The whole file was created (`added`) or deleted (`removed`) | `added()`, `removed()` |
| `content:` | Text matches: added side for `added`, removed side for `removed`, either for `changed` | Text predicates |
| `from:` / `to:` | Rename source / destination | `renamed()` |

Multiple fields in one call must all match the same block: `added(path:glob:"src/**", content:"timeout")`.

### Pattern modifiers

- `content:` defaults to case-sensitive substring; path fields default to glob.
- Explicit modifiers: `substring:`, `exact:`, `glob:`, `regex:` — e.g. `content:regex:"timeout|deadline"`, `path:exact:"src/lib.rs"`.
- Globs support `*`, `**`, `?` only. This is not jj's fileset language.
- Regex is Rust `regex` syntax. Use inline flags such as `(?i)` for case-insensitivity. Double backslashes inside the quoted string: `content:regex:"timeout\\s*=\\s*\\d+"`.
- Within one field, combine patterns with `|`, `&`, `~`, and parentheses: `path:glob:"src/**" | glob:"tests/**"`.

### Combine predicates

Top-level operators combine sets of blocks: `|` union, `&` intersection, `~` difference.

```text
changed(path:glob:"src/**") ~ changed(path:glob:"src/generated/**")
removed(content:"fetch_user(") & added(content:"load_user(")
renamed(from:glob:"src/**", to:glob:"archive/**") | changed(after_path:glob:"archive/**")
```

The intersection example selects only blocks that both remove the old call and add the new one.

### Query rules

- Queries select **complete blocks**, never individual lines. If an unrelated edit sits in the same block (no unchanged line between them), it comes along. Preview to check.
- Unchanged context lines are never searched.
- A valid query that matches nothing is a no-op for `split`, `commit`, and `squash`, and exits 0. Check the preview.
- Unknown predicates, unknown fields, or invalid patterns fail before anything is changed.
- `--query` cannot be combined with `--spec`, `--spec-file`, `--include`, `--exclude`, `--files`, or `--spec-template`.
- Renames, mode changes, binary changes, and empty files can only be selected with a query.

### Define aliases

Repeatable global `--alias 'name(params)=expression'` goes **before** the subcommand. Parameters are set expressions referenced as `param()`:

```bash
jj-hunk \
  --alias 'handwritten(sel)=sel() ~ changed(path:glob:"generated/**")' \
  split --query 'handwritten(added(content:"timeout"))' "Increase request timeout"
```

Aliases can also live in jj config under `[hunkset-aliases]`, with each signature quoted: `"handwritten(sel)" = 'sel() ~ changed(path:glob:"generated/**")'`.

## Select hunks with a JSON/YAML spec

A spec is the fallback for when no query can isolate the changes (see [Use a hunkset query by default](#use-a-hunkset-query-by-default)). Build it from a fresh listing.

### The golden rule: file paths go under `"files"`

The spec has exactly two top-level keys, `"files"` and `"default"`. File paths are **always** nested inside `"files"`.

```json
{"files": {"src/main.rs": {"action": "keep"}}, "default": "reset"}
```

### Spec structure

```json
{
  "files": {
    "path/to/file-a": <file-spec>,
    "path/to/file-b": <file-spec>
  },
  "default": "reset"
}
```

| File spec | Selects |
|-----------|---------|
| `{"action": "keep"}` | Every hunk in the file |
| `{"action": "reset"}` | Nothing from the file |
| `{"hunks": [0, 2]}` | Hunks by 0-based index; entries may also be full ID strings |
| `{"ids": ["hunk-<64 hex>"]}` | Hunks by full ID |

`hunks` and `ids` are merged when both are given. `"default"` applies to files not listed: `"reset"` excludes them (the safe choice), `"keep"` includes them.

Paths must match the listing exactly (`"src/lib.rs"`, not `"src/"` or `"./src/lib.rs"`). A path that matches nothing is silently ignored.

The same spec in YAML:

```yaml
files:
  src/db/schema.ts:
    action: keep
  src/api/routes.ts:
    hunks: [0]
default: reset
```

### Examples

```json
{"files": {"src/db/schema.ts": {"action": "keep"}, "src/db/migrations.ts": {"action": "keep"}}, "default": "reset"}
{"files": {"src/lib/utils.ts": {"hunks": [0, 2]}}, "default": "reset"}
{"files": {"src/db/schema.ts": {"action": "keep"}, "src/api/routes.ts": {"hunks": [0]}}, "default": "reset"}
{"files": {"src/wip.rs": {"action": "reset"}}, "default": "keep"}
```

The last example selects everything except `src/wip.rs`.

### Avoid these spec mistakes

Each wrong form below either fails to parse or is accepted and silently selects the wrong thing (marked "silent").

```
✗  {"src/foo.rs": {"action": "keep"}, "default": "reset"}                 missing "files" wrapper (silent: selects nothing)
✗  {"files": {"src/foo.rs": {"action": "keep"}, "default": "reset"}}      "default" inside "files"
✗  {"files": {"src/foo.rs": {"action": "keep"}}, "action": "reset"}       "action" instead of "default" (silent: ignored)
✗  {"files": {"src/foo.rs": "keep"}, "default": "reset"}                  bare string file spec
✗  {"files": {"src/foo.rs": {"action": "hunks", "hunks": [0]}}, ...}      "action" with "hunks"
✗  {"files": {"src/foo.rs": {"ids": ["hunk-4c1b"]}}, ...}                 abbreviated ID
✗  {"files": {"./src/foo.rs": {"action": "keep"}}, ...}                   path not as listed (silent: selects nothing)
✓  {"files": {"src/foo.rs": {"action": "keep"}}, "default": "reset"}
```

Spec limits: a hunk or ID selection on a renamed file is rejected, and renames, mode changes, binary changes, and empty files cannot be selected by spec. Use a query for those.

## Know where changes and change IDs end up

After `jj-hunk split -r X <selection> "msg"`:

- The **selected** changes stay in change `X`, which now has the new message `"msg"`.
- The **remaining** changes move to a new child commit with a new change ID, carrying `X`'s original description.
- Output lines `Selected changes :` and `Remaining changes:` print both change IDs.

When `X` is `@`, the working copy follows the remaining changes, so repeated `jj-hunk split` on `@` keeps peeling commits off the bottom. When `X` is not `@`, use the `Remaining changes:` change ID as the `-r` for the next split.

After `jj-hunk commit <selection> "msg"`, the selected changes become `@-` with the message, and `@` is a new commit holding the rest.

After `jj-hunk squash -r X <selection>`, the selection moves into `X-` and both keep their change IDs. If that empties `X`, jj abandons it.

## Avoid the description editor when emptying a commit

`jj-hunk squash` hangs on a description editor when **both** of these are true:

- The selection is everything in the source revision, so the source becomes empty.
- The source and its parent both have non-empty descriptions.

jj then wants you to merge the two descriptions. Clear the source description first, and the parent keeps its own message:

```bash
jj describe -r X -m ""
jj-hunk squash -r X --query 'all()'
```

A partial squash never prompts — the source keeps its own description.

## Move changes between existing commits

`jj-hunk squash -r` moves a selection from any revision into its parent in one step. No temporary split, rebase, or extra squash is needed.

```bash
# Move test changes from X into X's parent
jj-hunk list --format text -r X --query 'changed(path:glob:"tests/**")'
jj-hunk squash -r X --query 'changed(path:glob:"tests/**")'
```

To move a selection further back, repeat `squash -r` one parent at a time, previewing each hop. Use a query here, because it stays valid after each rewrite and a spec would need a new listing at every hop:

```bash
jj-hunk squash -r C --query 'added(content:"retry_limit")'   # C -> B
jj-hunk squash -r B --query 'added(content:"retry_limit")'   # B -> A
```

At each hop the query also matches any of the parent's own blocks that fit it. Preview first and tighten the query (add `path:` or a more specific `content:`) if it does.

## Split a commit into many commits

1. **Inspect** the changes:
   ```bash
   jj-hunk list --files --format text
   jj-hunk list --format text
   ```

2. **Plan** the commits by logical concern, ordered as a narrative (setup, core logic, integration, polish).

3. **Peel off one commit at a time** with a query, previewing each selection first:
   ```bash
   jj-hunk list --format text --query 'changed(path:glob:"src/db/**")'
   jj-hunk split --query 'changed(path:glob:"src/db/**")' "Add database schema"

   jj-hunk list --format text --query 'changed(path:glob:"src/api/**") ~ changed(content:"debug!")'
   jj-hunk split --query 'changed(path:glob:"src/api/**") ~ changed(content:"debug!")' "Add API routes"
   ```
   Fall back to a spec only for a commit no query can isolate, and run `jj-hunk list` right before writing it, because indices and IDs change after every split.

4. **Describe the remainder** as the last commit:
   ```bash
   jj describe -m "Add UI components"
   ```

5. **Verify** each commit:
   ```bash
   jj log
   jj diff -r <change-id> --stat
   ```

If a split goes wrong, `jj undo` reverts the last operation.

## Quick reference

```
jj-hunk list --format text [-r REV] [--query Q | --spec S | --spec-file F]
jj-hunk split  [-r REV] (--query Q | 'SPEC' | --spec-file F | -) "message"
jj-hunk commit          (--query Q | 'SPEC' | --spec-file F | -) "message"
jj-hunk squash [-r REV] (--query Q | 'SPEC' | --spec-file F | -)

Query (default):
        changed|added|removed(path:, before_path:, after_path:, file:, content:)
        renamed(from:, to:)  mode_changed(path:)  binary_changed(path:)
        all()  none()  id("hunk-<64 hex>")
        modifiers: substring: exact: glob: regex:     operators: | & ~ ( )

Spec (fallback; list first):
        {"files": {"path": {"action": "keep"|"reset"}
                 | {"hunks": [0, 2]}
                 | {"ids": ["hunk-<64 hex>"]}},
         "default": "reset"|"keep"}
```
