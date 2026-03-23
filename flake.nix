{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    anthropic-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    anthropic-skills,
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
      jujutsu = mkLocalSkill "jujutsu";
      obsidian-projects = mkLocalSkill "obsidian-projects";
      update-fork = mkLocalSkill "update-fork";
      skill-creator =
        mkExternalSkill "skill-creator"
        anthropic-skills "skills/skill-creator";

      allSkills = [jujutsu obsidian-projects update-fork skill-creator];
    in {
      inherit jujutsu obsidian-projects update-fork skill-creator;

      default = pkgs.symlinkJoin {
        name = "all-skills";
        paths = allSkills;
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
