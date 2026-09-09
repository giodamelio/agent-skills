---
name: unison-development
description: Write, test, update, and repair Unison code through the Unison MCP server. Use when working with Unison language files (.u extension), UCM operations, Unison projects, or when `update-definitions` returns `sourceCodeUpdates` for affected definitions that no longer typecheck.
---

# Unison Development

Use the Unison MCP server's tools for every operation. If the server is not connected, stop and say so rather than falling back to ad hoc UCM commands — the command line bypasses the safeguards below.

## Why Unison is different

Unison stores code in the UCM codebase, not in files or Git. Two consequences drive everything else:

- The CLI and `scratch.u` files are not the source of truth, so editing or running code outside the MCP server desyncs your work from the codebase. Drive everything through its tools directly — the one exception is branch creation.
- Git never holds Unison code. A git commit won't capture your changes, so don't reach for version control to record them.

Work in a branch, and use fully qualified names when writing code so references resolve unambiguously.

## Branch first

Before any code change, create a branch with the MCP server's branch tool — working outside a branch mutates shared state. Use a descriptive name like `extract-domain-service` or `fix-login-bug`.

## Workflow

1. **Explore**: `view-definitions`, `search-definitions-by-name`, `list-project-definitions` to understand existing code before writing.
2. **Typecheck**: `typecheck-code` to validate before updating.
3. **Update**: `update-definitions` to apply changes to the codebase.
4. **Test**: `run-tests` to verify.

## When `update-definitions` reports broken dependents

The call returns `sourceCodeUpdates` when affected definitions no longer typecheck:

```
-- The definitions below no longer typecheck with the changes above.
-- Please fix the errors and try `update` again.
```

The server has placed that code in a temporary branch for you to fix. Repair loop:

1. Review **every** affected definition in the `sourceCodeUpdates` response.
2. Fix the type errors, updating signatures where needed, preserving existing behaviour.
3. Include **every** fixed definition in a single `update-definitions` call — any definition left out is removed from the codebase, so completeness here is not optional.
4. Repeat until the update succeeds.

## Modifying abilities

Changing an ability breaks its dependents, so repair them in the same update. View the ability and its `default` handler, use `list-definition-dependents` to find every caller, and include the ability and all dependents in one `update-definitions` call.

## Done when

- Code typechecks via the MCP server.
- Tests pass via `run-tests`.
- Fully qualified names are used throughout.
