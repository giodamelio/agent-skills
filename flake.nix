{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    anthropic-skills = {
      url = "github:anthropics/skills";
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

    # Generate an smfh manifest for a list of skill derivations
    # skills: list of skill derivations
    # targets: list of relative dir paths (resolved from $HOME)
    mkManifest = pkgs: skills: targets: let
      skillName = skill: builtins.head (builtins.attrNames (builtins.readDir skill));
      mkEntries = skill: let
        name = skillName skill;
      in
        map (target: {
          type = "symlink";
          source = "${skill}/${name}";
          target = "\$HOME/${target}/${name}";
        })
        targets;
    in
      pkgs.writeText "skills-manifest.json" (builtins.toJSON {
        files = builtins.concatMap mkEntries skills;
        clobber_by_default = false;
        version = 3;
      });
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};

      mkLocalSkill = name:
        pkgs.stdenv.mkDerivation {
          inherit name;
          src = ./skills/${name};
          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/${name}
            cp -r $src/* $out/${name}/
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

      # --- Skills ---
      github-skill-installer = mkLocalSkill "github-skill-installer";
      jujutsu = mkLocalSkill "jujutsu";
      obsidian-projects = mkLocalSkill "obsidian-projects";
      update-fork = mkLocalSkill "update-fork";
      skill-creator =
        mkExternalSkill "skill-creator"
        anthropic-skills "skills/skill-creator";

      allSkills = [github-skill-installer jujutsu obsidian-projects update-fork skill-creator];
    in {
      inherit github-skill-installer jujutsu obsidian-projects update-fork skill-creator;

      default = pkgs.symlinkJoin {
        name = "all-skills";
        paths = allSkills;
      };

      # Script to quickly symlink the skills into place
      install = let
        manifest = mkManifest pkgs allSkills [".claude/skills" ".omp/agent/skills"];
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
          mkSkillsShellHook
          [packages.skill-creator]
          [".claude/skills" ".omp/skills"];
      };
    });
  };
}
