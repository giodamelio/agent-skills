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

      # --- Hooks ---
      # A hook is a generic, agent-agnostic spec:
      #   { name; script; event; tool ? null; }
      # where `event` is an abstract trigger name and `script` is a path, an inline
      # multiline string, or a derivation. A per-agent renderer turns a group of hooks
      # into that agent's format. Only Claude Code is implemented for now.
      lib = pkgs.lib;

      # Map a generic event name to Claude Code's event vocabulary.
      ccEvent = e:
        {
          "pre-tool-use" = "PreToolUse";
          "post-tool-use" = "PostToolUse";
          "session-start" = "SessionStart";
          "user-prompt-submit" = "UserPromptSubmit";
        }
        .${
          e
        };

      # Resolve a hook's `script` (path | inline string | derivation) to one
      # executable file in the store, reusing lib.getExe for packages.
      hookScriptFile = s:
        if builtins.isString s
        then pkgs.writeShellScript "hook" s
        else if builtins.isPath s
        then s
        else if s ? meta.mainProgram
        then lib.getExe s # writeShellApplication / writeShellScriptBin
        else s; # writeShellScript file

      # Build a Claude Code hooks.json structure from a list of hook specs.
      # Hooks sharing an `event` are grouped into that event's array.
      mkHooksJson = hooks: let
        entries =
          map (h: {
            event = ccEvent h.event;
            matcher = h.tool or null;
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
          // (lib.optionalAttrs (e.matcher != null) {matcher = e.matcher;});
        byEvent = ev: map entryFor (lib.filter (e: e.event == ev) entries);
      in {hooks = lib.genAttrs events byEvent;};

      # Render a group of hooks as a skills-directory plugin: a single-subdir output
      # ($out/<name>/) holding the plugin manifest, the generated hooks.json, and each
      # hook's script. Symlinked into .claude/skills/, it auto-loads as <name>@skills-dir.
      mkClaudeHookPlugin = {
        name,
        description,
        hooks,
      }:
        pkgs.runCommand name {} ''
          mkdir -p "$out/${name}/.claude-plugin" "$out/${name}/hooks"
          cp ${pkgs.writeText "plugin.json" (builtins.toJSON {
            inherit name description;
            version = "0.1.0";
          })} "$out/${name}/.claude-plugin/plugin.json"
          cp ${pkgs.writeText "hooks.json" (builtins.toJSON (mkHooksJson hooks))} "$out/${name}/hooks/hooks.json"
          ${lib.concatMapStringsSep "\n" (h: ''
              cp ${hookScriptFile h.script} "$out/${name}/hooks/${h.name}.sh"
              chmod +x "$out/${name}/hooks/${h.name}.sh"
            '')
            hooks}
        '';

      # --- Skills ---
      github-skill-installer = mkLocalSkill "github-skill-installer";
      jujutsu = mkLocalSkill "jujutsu";
      obsidian-projects = mkLocalSkill "obsidian-projects";
      jj-split-into-commits = mkLocalSkill "jj-split-into-commits";
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

      allSkills = [github-skill-installer jujutsu jj-split-into-commits obsidian-projects update-fork skill-creator code-review rust-skills-pkg python-expert handoff];

      # --- Hook plugins (Claude Code) ---
      # First group: jj-related guardrails, bundling two hooks to exercise the
      # multiple-hooks path. Add more groups the same way, named by functionality.
      jj-hooks = mkClaudeHookPlugin {
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
    in {
      inherit github-skill-installer jujutsu jj-split-into-commits obsidian-projects update-fork skill-creator code-review python-expert handoff jj-hooks;
      rust-skills = rust-skills-pkg;

      default = pkgs.symlinkJoin {
        name = "all-skills";
        paths = allSkills ++ [jj-hooks];
      };

      # Script to quickly symlink the skills (and Claude-only hook plugins) into place
      install = let
        manifest = mkManifest pkgs [
          {
            items = allSkills;
            targets = [".claude/skills" ".omp/agent/skills"];
          }
          {
            items = [jj-hooks];
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
            [packages.jj-hooks]
            [".claude/skills"]);

        packages = [
          smfh.packages.${system}.default
          pkgs.gomplate
        ];
      };
    });
  };
}
