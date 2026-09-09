# Ship the Unison LSP as a Claude Code plugin

Claude Code will not read an `.lsp.json` from a project root. This document covers why, and how to package the Unison language server as a plugin in `~/projects/giodamelio/agent-skills` instead.

## Understand why the project-root config failed

Three separate things were tried in `poor-mans-unison-cloud`, and each was blocked for a different reason.

A bare `.lsp.json` at the repo root is never loaded. Every read of that filename in the Claude Code binary joins the path against a *plugin* directory, and each resulting server registers under the key `plugin:${pluginName}:${serverName}`. There is no project-root loader. This is unlike `.mcp.json`, which is a real project-level file — that asymmetry is why the MCP half of the original setup worked and the LSP half silently did nothing.

Declaring a local marketplace in `.claude/settings.json` also failed, but not because of the config shape. Untrusted workspaces have their project-scoped entries dropped before anything loads, gated on `projects[<path>].hasTrustDialogAccepted === true` in `~/.claude.json`. This project has never been trusted, so the marketplace was never registered and the plugin never resolved. The binary carries the error text verbatim:

> Ignoring N entries from …: this workspace has not been trusted. Run Claude Code interactively here once and accept the trust dialog, or set `projects[<path>].hasTrustDialogAccepted: true` in `~/.claude.json`.

For the record, the settings format itself was correct. `extraKnownMarketplaces.<name>.source` is a tagged union whose local variant is `{"source": "directory", "path": ...}` — there is no `"local"` variant — and `enabledPlugins` is a `Record<string, boolean>`, not an array.

The approach below avoids all of this. Anything under `~/.claude/skills/` is auto-scanned for plugin-shaped directories and loaded as `<name>@skills-dir`. That is user scope, so it needs no marketplace registration, no settings entry, and no trust dialog. It is the same mechanism the existing `obsidian` and `jj-hooks` plugins already use.

## Add the plugin source

Create `plugins/unison/.lsp.json` in the `agent-skills` repo:

```json
{
  "unison-lsp": {
    "command": "nc",
    "args": ["127.0.0.1", "5757"],
    "extensionToLanguage": {
      ".u": "unison"
    }
  }
}
```

That is the entire plugin. `mkClaudePlugin` generates the `.claude-plugin/plugin.json` manifest, and its `cp -r ${src}/.` picks up dotfiles, so nothing else needs to be authored.

The `command`/`args`/`extensionToLanguage` shape matches what the official LSP plugins use — compare the `rust-analyzer-lsp` entry in `~/.claude/plugins/marketplaces/claude-plugins-official/.claude-plugin/marketplace.json`.

## Wire it into the flake

Make four edits to `flake.nix`, mirroring how `obsidian` is wired.

Add the plugin derivation after the `obsidian` block, which ends at line 344:

```nix
      # Unison language server, proxied over TCP to a running UCM instance.
      # Ships only .lsp.json — the plugin exists solely to register the LSP
      # server, since Claude Code loads LSP config from plugins, not projects.
      unison = mkClaudePlugin {
        name = "unison";
        description = "Unison language server, proxied to a running UCM instance";
        src = ./plugins/unison;
      };
```

Add it to `allPlugins` on line 346:

```nix
      allPlugins = [jj-hooks jj-split-into-commits obsidian unison];
```

Append `unison` to the `inherit` list on line 348.

Append `packages.unison` to the second `mkSkillsShellHook` list on line 390:

```nix
          + (mkSkillsShellHook
            [packages.jj-hooks packages.jj-split-into-commits packages.obsidian packages.unison]
            [".claude/skills"]);
```

## Activate and verify

Run `nix run .#install` from the `agent-skills` repo, or re-enter its devshell. Either way you should end up with `~/.claude/skills/unison` symlinked into the Nix store.

Start UCM before testing. The LSP server listens on `127.0.0.1:5757`, and `nc` will fail to connect if UCM is not running. Check it with `ss -ltn | grep 5757`.

Restart Claude Code. LSP servers and plugins both resolve at startup, so nothing takes effect mid-session.

Open a `.u` file and request hover information. A working setup returns type information; a broken one returns `No LSP server available for file type: .u`.

## Watch for these

A plugin containing only `.lsp.json`, with no skills or agents, is not exercised by any existing plugin in the `agent-skills` repo. If the skills-dir scan rejects it, that combination is the first thing to suspect.

Hardcoding `nc 127.0.0.1 5757` means the LSP silently dies whenever UCM is not running, with no indication beyond hover returning nothing useful. There is no fallback and no error surfaced at startup.

The original `.lsp.json` was committed to `poor-mans-unison-cloud` in `f996919` and deleted from the working copy during cleanup. Recover it with `jj file show @-.lsp.json` if the copy above is ever in doubt.
