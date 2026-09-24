# My own Coding Agent Skills

Portable skills plus Claude Code plugins, packaged with Nix. Existing Claude and
oh-my-pi installation remains available through `nix run .#install`.

## Codex marketplace

`nix build .#codex-marketplace` generates an `agent-skills` marketplace under
`result/share/codex-marketplace`. It contains skill-only Codex plugins:

| Plugin | Skills |
| --- | --- |
| jj | jujutsu, jj-hunk |
| github-skill-installer | github-skill-installer |
| obsidian-projects | obsidian-projects |
| update-fork | update-fork |
| tuicr | tuicr |
| unison-development | unison-development |
| skill-creator | external skill-creator |
| code-review | external code-review |
| rust-skills | external rust-skills |
| python-expert | external python-expert |
| handoff | external handoff |
| camofox-cli | renamed external camoufox-cli |
| firefox-extension-dev | external firefox-extension-dev |

The existing skill derivations supply all resources and expand shared references.
Claude hooks, bundled-agent plugins, and LSP configuration are excluded. Plugin
versions are `0.1.0+codex.<fingerprint>`, derived from each plugin's skill derivation
paths and the packaging schema version. Changing one skill changes its containing
plugin's version; unchanged derivations retain their versions. No timestamps or
edits to installed manifests are needed.

### Local marketplace paths

Codex CLI resolves the profile symlink when registering a local marketplace, so
the recorded source is a `/nix/store/...` path. The helper accepts a source from
the current or a retained older generation of the dedicated profile. When the
recorded source points to an older generation, it removes and re-adds that
marketplace before refreshing plugins. An unrelated source with the same
marketplace name remains a conflict.

### Setup and updates

Requires Nix with flakes and an installed Codex CLI supporting `plugin marketplace
list --json`, `plugin marketplace add`, and `plugin add`.

```sh
nix run ~/projects/giodamelio/agent-skills#install-codex
```

Run that same command after editing skills. It installs or upgrades one marketplace
package in a dedicated, ordinary Nix profile, registers the current marketplace,
and installs/reinstalls **every** plugin in its catalog, including newly added ones.
Start a **new Codex conversation** afterward to pick up the refreshed skills.

Defaults:

- Checkout: `$HOME/projects/giodamelio/agent-skills`
- Profile: `${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/codex-marketplace`
- Registered source: the Nix store path resolved from `<profile>/share/codex-marketplace`

Override the checkout or profile at runtime:

```sh
nix run .#install-codex -- --source "$PWD" --profile "$HOME/custom profiles/codex-marketplace"
nix run .#install-codex -- --help
```

The checkout is resolved when the helper runs and recorded as an unlocked local
`path:` flake URL, so later upgrades read the current checkout, including new files.
The helper bundles Nushell and uses your installed `nix` and `codex`. Generated
packages remain immutable in the Nix store; installed plugin copies live in
Codex's writable cache outside it.

### Manual profile management

These commands use the default profile location. Set `profile` to your override
if you chose one. Keep exactly one marketplace package in this profile.

```sh
profile="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/codex-marketplace"

# Initial installation (the helper can do this for you).
nix profile add --profile "$profile" \
  ~/projects/giodamelio/agent-skills#codex-marketplace

# Rebuild from the recorded local source.
nix profile upgrade --profile "$profile" --all

# Inspect package and source.
nix profile list --profile "$profile"

# After a manual upgrade, register/refresh Codex without rebuilding.
nix run ~/projects/giodamelio/agent-skills#install-codex -- \
  --profile "$profile" --refresh-only

# Roll back, then restore that generation's Codex plugin installations.
nix profile rollback --profile "$profile"
nix run ~/projects/giodamelio/agent-skills#install-codex -- \
  --profile "$profile" --refresh-only
```

When using a different checkout, also pass `--source` during refresh. Manual local
Git flake references are accepted if Nix records the same unlocked checkout; they
follow Nix's usual tracked-file filtering. The helper's `path:` reference includes
untracked files. Neither interface requires `nix build --profile` or a separate
build before upgrading.

### Troubleshooting

- **Profile conflict:** inspect `nix profile list --profile ... --json`. The helper
  refuses profiles containing unrelated packages, pinned sources, multiple
  packages, or a different checkout. Select the correct source/profile or use a
  fresh dedicated profile.
- **Marketplace conflict:** inspect `codex plugin marketplace list --json`.
  `agent-skills` must refer to the dedicated profile or one of its retained
  generations. The helper refreshes registrations from older generations and
  leaves unrelated registrations alone.
- **No changes in `nix profile history`:** Nix can show this for a package whose
  version did not change even when its store path and contents changed. Compare
  `storePaths` in `nix profile list --json` or inspect the generated skill file.
- **Build failure:** no Codex commands run. Fix the build and rerun the helper.
- **Registration or plugin failure after an upgrade:** the profile stays updated.
  Fix the reported issue and retry with `--refresh-only`. All plugins are retried;
  the helper does not delete caches.
- **Removed catalog entry:** existing Codex installations are not automatically
  uninstalled. Explicitly remove one with `codex plugin remove NAME@agent-skills`.
- **Old skills in an open or resumed conversation:** start a new conversation after
  refresh. Resuming an earlier conversation can retain its old skill metadata.

The packaging follows the [official OpenAI plugin format and marketplace layout](https://developers.openai.com/plugins/build/plugins).

### Build and inspect

```sh
nix build .#codex-marketplace
nix build .#install-codex --no-link
nu --no-config-file scripts/validate-codex-marketplace.nu result/share/codex-marketplace
```

Activation validates the catalog, manifests, skill directories, expanded
references, and absence of symlinks before calling Codex. The standalone validator
prints the catalog's plugin names.
