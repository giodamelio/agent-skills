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

    # Generate shell hook ln commands for a list of skills into target dirs
    # skills: list of { drv, name } attrsets
    # targets: list of relative dir paths like ".claude/skills"
    mkSkillsShellHook = skills: targets: let
      mkLinksForSkill = s:
        builtins.concatStringsSep "\n" (map (target: ''
            mkdir -p "${target}"
            ln -sfn "${s.drv}/${s.name}" "${target}/${s.name}"
          '')
          targets);
    in
      builtins.concatStringsSep "\n" (map mkLinksForSkill skills);
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};

      mkLocalSkill = name:
        pkgs.runCommand "skill-${name}" {} ''
          mkdir -p $out/${name}
          cp -r ${./skills/${name}}/* $out/${name}/
        '';

      mkExternalSkill = name: src: subdir:
        pkgs.runCommand "skill-${name}" {} ''
          mkdir -p $out/${name}
          cp -r ${src}/${subdir}/* $out/${name}/
        '';

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
          [
            {
              drv = packages.skill-creator;
              name = "skill-creator";
            }
          ]
          [".claude/skills" ".omp/skills"];
      };
    });
  };
}
