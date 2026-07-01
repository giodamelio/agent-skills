{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    anthropic-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };
    code-review-skill = {
      url = "github:awesome-skills/code-review-skill";
      flake = false;
    };
    rust-skills = {
      url = "github:leonardomso/rust-skills";
      flake = false;
    };
    awesome-llm-apps = {
      url = "github:Shubhamsaboo/awesome-llm-apps";
      flake = false;
    };
    claude-code-toolkit = {
      url = "github:robertguss/claude-code-toolkit";
      flake = false;
    };
    camoufox-cli = {
      url = "github:Bin-Huang/camoufox-cli";
      flake = false;
    };
    smfh = {
      url = "github:feel-co/smfh";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    anthropic-skills,
    code-review-skill,
    rust-skills,
    awesome-llm-apps,
    claude-code-toolkit,
    camoufox-cli,
    smfh,
  }: let
    forAllSystems = nixpkgs.lib.genAttrs [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];

    # Generate shell hook ln commands for a list of skill derivations into target dirs
    # skills: list of skill derivations (each has a single subdir named after the skill)
    # targets: list of relative dir paths like ".claude/skills"
    mkSkillsShellHook = skills: targets: let
      skillName = skill: builtins.head (builtins.attrNames (builtins.readDir skill));
      mkLinksForSkill = skill: let
        name = skillName skill;
      in
        builtins.concatStringsSep "\n" (map (target: ''
            mkdir -p "${target}"
            ln -sfn "${skill}/${name}" "${target}/${name}"
          '')
          targets);
    in
      builtins.concatStringsSep "\n" (map mkLinksForSkill skills);

    # Generate an smfh manifest from a list of install groups.
    # groups: list of { items = [derivations]; targets = [relative dirs from $HOME]; }
    # Each derivation has a single subdir named after it; per-group targets let
    # different kinds of output (skills vs Claude-only hook plugins) go to different dirs.
    mkManifest = pkgs: groups: let
      itemName = item: builtins.head (builtins.attrNames (builtins.readDir item));
      mkEntries = targets: item:
        map (target: {
          type = "symlink";
          source = "${item}/${itemName item}";
          target = "\$HOME/${target}/${itemName item}";
        })
        targets;
      files = builtins.concatMap (g: builtins.concatMap (mkEntries g.targets) g.items) groups;
    in
      pkgs.writeText "skills-manifest.json" (builtins.toJSON {
        inherit files;
        clobber_by_default = true;
        version = 3;
      });
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};

      mkLocalSkill = name:
        pkgs.stdenv.mkDerivation {
          inherit name;
          src = ./skills/${name};
          refs = ./references;
          nativeBuildInputs = with pkgs; [gomplate fd];
          dontUnpack = true;
          installPhase = ''
            mkdir -p "$out/${name}"
            cp -r "$src"/* "$out/${name}/"
            chmod -R u+w "$out/${name}/"
            fd -e md . "$out/${name}" -x gomplate -d "refs=file://$refs/" -f {} -o {}
          '';
        };

      mkExternalSkill = name: src: subdir:
        pkgs.stdenv.mkDerivation {
          inherit name src;
          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/${name}
            cp -r $src/${subdir}/* $out/${name}/
          '';
        };

      # --- Hooks & Claude Code plugins ---
      # Plugin/hook inputs are validated through the module system (lib.evalModules),
      # so typos, bad event names, and wrong-typed scripts fail at eval with a clear
      # message instead of producing a broken plugin.
      lib = pkgs.lib;
      inherit (lib) types mkOption;

      # Generic hook event name -> Claude Code event name. Also the source of truth
      # for the `event` option's allowed values.
      ccEventMap = {
        "pre-tool-use" = "PreToolUse";
        "post-tool-use" = "PostToolUse";
        "session-start" = "SessionStart";
        "user-prompt-submit" = "UserPromptSubmit";
      };

      # Hook script option type. Like the nixpkgs idiom for inline-or-path scripts,
      # this coerces to a single executable file: an inline multiline string is
      # wrapped with writeShellScript, an executable package (writeShellApplication /
      # writeShellScriptBin) is resolved via lib.getExe, and a plain path passes
      # through. (Pass inline text rather than a bare writeShellScript derivation.)
      exeScriptType =
        types.coercedTo
        (types.either types.str types.package)
        (v:
          if builtins.isString v
          then pkgs.writeShellScript "hook" v
          else lib.getExe v)
        types.path;

      # A single hook: one script fired on one event, optionally tool-scoped.
      hookType = types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Hook name; its script installs as hooks/<name>.sh.";
          };
          script = mkOption {
            type = exeScriptType;
            description = "Inline script string, a repo path, or an executable package.";
          };
          event = mkOption {
            type = types.enum (builtins.attrNames ccEventMap);
            description = "Generic event that triggers the hook.";
          };
          tool = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''Optional tool matcher (e.g. "Bash"); omitted means no matcher.'';
          };
        };
      };

      # Options schema for mkClaudePlugin.
      pluginModule = {
        options = {
          name = mkOption {
            type = types.str;
            description = "Plugin name and output subdir; loads as <name>@skills-dir.";
          };
          description = mkOption {
            type = types.str;
            description = "Plugin description, written to plugin.json.";
          };
          version = mkOption {
            type = types.str;
            default = "0.1.0";
            description = "Plugin version, written to plugin.json.";
          };
          src = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Authored plugin content (SKILL.md, agents/, ...), gomplate-processed.";
          };
          hooks = mkOption {
            type = types.listOf hookType;
            default = [];
            description = "Hooks rendered into hooks/hooks.json plus their scripts.";
          };
        };
      };

      # Build a Claude Code hooks.json from validated hooks, grouping by event.
      mkHooksJson = hooks: let
        entries =
          map (h: {
            event = ccEventMap.${h.event};
            inherit (h) tool;
            command = ''bash "''${CLAUDE_PLUGIN_ROOT}/hooks/${h.name}.sh"'';
          })
          hooks;
        events = lib.unique (map (e: e.event) entries);
        entryFor = e:
          {
            hooks = [
              {
                type = "command";
                command = e.command;
              }
            ];
          }
          // (lib.optionalAttrs (e.tool != null) {matcher = e.tool;});
        byEvent = ev: map entryFor (lib.filter (e: e.event == ev) entries);
      in {hooks = lib.genAttrs events byEvent;};

      # Render a Claude Code skills-directory plugin: a single-subdir output
      # ($out/<name>/) with a generated .claude-plugin/plugin.json manifest.
      #   src   — authored plugin content copied in and gomplate-processed.
      #   hooks — validated hook specs rendered to hooks/hooks.json + scripts.
      # `args` is validated against pluginModule. Symlinked into .claude/skills/,
      # the result auto-loads as <name>@skills-dir, bundling its skills/agents/hooks.
      mkClaudePlugin = args: let
        cfg = (lib.evalModules {modules = [pluginModule args];}).config;
        inherit (cfg) name;
      in
        pkgs.runCommand name {nativeBuildInputs = [pkgs.gomplate pkgs.fd];} ''
          mkdir -p "$out/${name}/.claude-plugin"
          cp ${pkgs.writeText "plugin.json" (builtins.toJSON {
            inherit (cfg) name description version;
          })} "$out/${name}/.claude-plugin/plugin.json"
          ${lib.optionalString (cfg.src != null) ''
            cp -r ${cfg.src}/. "$out/${name}/"
            chmod -R u+w "$out/${name}"
            fd -e md . "$out/${name}" -x gomplate -d "refs=file://${./references}/" -f {} -o {}
          ''}
          ${lib.optionalString (cfg.hooks != []) ''
            mkdir -p "$out/${name}/hooks"
            cp ${pkgs.writeText "hooks.json" (builtins.toJSON (mkHooksJson cfg.hooks))} "$out/${name}/hooks/hooks.json"
            ${lib.concatMapStringsSep "\n" (h: ''
                cp ${h.script} "$out/${name}/hooks/${h.name}.sh"
                chmod +x "$out/${name}/hooks/${h.name}.sh"
              '')
              cfg.hooks}
          ''}
        '';

      # --- Skills ---
      github-skill-installer = mkLocalSkill "github-skill-installer";
      jujutsu = mkLocalSkill "jujutsu";
      obsidian-projects = mkLocalSkill "obsidian-projects";
      update-fork = mkLocalSkill "update-fork";
      skill-creator =
        mkExternalSkill "skill-creator"
        anthropic-skills "skills/skill-creator";
      code-review =
        mkExternalSkill "code-review"
        code-review-skill ".";
      rust-skills-pkg =
        mkExternalSkill "rust-skills"
        rust-skills ".";
      python-expert =
        mkExternalSkill "python-expert"
        awesome-llm-apps "awesome_agent_skills/python-expert";
      handoff =
        mkExternalSkill "handoff"
        claude-code-toolkit "skills/handoff";
      # Upstream is "camoufox-cli", but we vendor it under the name "camofox-cli"
      # and rewrite every "camoufox" reference to match (case-preserving).
      camofox-cli-pkg = pkgs.stdenv.mkDerivation {
        name = "camofox-cli";
        src = camoufox-cli;
        nativeBuildInputs = [pkgs.fd];
        dontUnpack = true;
        installPhase = ''
          mkdir -p "$out/camofox-cli"
          cp -r "$src"/skills/camoufox-cli/* "$out/camofox-cli/"
          chmod -R u+w "$out/camofox-cli"
          fd -t f . "$out/camofox-cli" -x sed -i 's/amoufox/amofox/g; s/AMOUFOX/AMOFOX/g' {}
        '';
      };

      allSkills = [github-skill-installer jujutsu obsidian-projects update-fork skill-creator code-review rust-skills-pkg python-expert handoff camofox-cli-pkg];

      # --- Claude Code plugins ---
      # Skills-directory plugins installed into .claude/skills only. Each bundles
      # some mix of skills/agents/hooks via mkClaudePlugin.

      # jj guardrail hooks, bundling two hooks to exercise the multiple-hooks path.
      jj-hooks = mkClaudePlugin {
        name = "jj-hooks";
        description = "Guardrails steering git/interactive-jj usage toward jj-hunk";
        hooks = [
          {
            name = "block-git";
            script = ./hooks/jj/block-git.sh;
            event = "pre-tool-use";
            tool = "Bash";
          }
          {
            name = "block-jj-interactive";
            script = ./hooks/jj/block-jj-interactive.sh;
            event = "pre-tool-use";
            tool = "Bash";
          }
        ];
      };

      # Commit-splitting skill bundled with a change-exploration subagent. The
      # single root SKILL.md is the plugin's default skill, so it stays invocable
      # as /jj-split-into-commits (unchanged), and ships agents/explore-changes.md.
      jj-split-into-commits = mkClaudePlugin {
        name = "jj-split-into-commits";
        description = "Split the current commit's changes into clean, logical commits, with a bundled change-exploration agent";
        src = ./plugins/jj-split-into-commits;
      };

      # Obsidian research tooling. Two deep-research skills (research-company,
      # research-person), each bundled with five parallel researcher subagents
      # (agents/ namespaced obsidian:researcher-company-* / -person-*), plus a
      # research-document-people orchestrator that invokes research-person for
      # every person named in a file and links them. research-company and
      # research-document-people set disable-model-invocation (user-invoked only);
      # research-person stays model-invocable so the orchestrator can call it.
      obsidian = mkClaudePlugin {
        name = "obsidian";
        description = "Obsidian vault research tooling: company, person, and document-people research skills with parallel researcher agents";
        src = ./plugins/obsidian;
      };

      allPlugins = [jj-hooks jj-split-into-commits obsidian];
    in {
      inherit github-skill-installer jujutsu obsidian-projects update-fork skill-creator code-review python-expert handoff jj-hooks jj-split-into-commits obsidian;
      rust-skills = rust-skills-pkg;
      camofox-cli = camofox-cli-pkg;

      default = pkgs.symlinkJoin {
        name = "all-skills";
        paths = allSkills ++ allPlugins;
      };

      # Script to quickly symlink the skills and Claude Code plugins into place
      install = let
        manifest = mkManifest pkgs [
          {
            items = allSkills;
            targets = [".claude/skills" ".omp/agent/skills"];
          }
          {
            items = allPlugins;
            targets = [".claude/skills"];
          }
        ];
      in
        pkgs.writeShellApplication {
          name = "activate-skills";
          runtimeInputs = [smfh.packages.${system}.default];
          text = ''
            smfh -v --impure activate ${manifest}
          '';
        };
    });

    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      packages = self.packages.${system};
    in {
      default = pkgs.mkShell {
        shellHook =
          (mkSkillsShellHook
            [packages.skill-creator]
            [".claude/skills" ".omp/skills"])
          + "\n"
          + (mkSkillsShellHook
            [packages.jj-hooks packages.jj-split-into-commits packages.obsidian]
            [".claude/skills"]);

        packages = [
          smfh.packages.${system}.default
          pkgs.gomplate
        ];
      };
    });
  };
}
