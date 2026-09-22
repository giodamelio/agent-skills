# Skills are supplied explicitly; no Claude plugin machinery is reused here.
{
  pkgs,
  groups,
}: let
  lib = pkgs.lib;
  schemaVersion = 1;
  names = builtins.attrNames groups;
  manifest = name: {
    inherit name;
    description = "${name} skills from agent-skills";
    skills = "./skills/";
    version =
      "0.1.0+codex."
      + builtins.substring 0 24 (builtins.hashString "sha256" (builtins.toJSON {
        inherit schemaVersion;
        skills = map (skill: toString skill) groups.${name};
      }));
  };
  catalog = {
    name = "agent-skills";
    interface.displayName = "Agent Skills";
    plugins =
      map (name: {
        inherit name;
        source = {
          source = "local";
          path = "./plugins/${name}";
        };
        policy = {
          installation = "AVAILABLE";
          authentication = "ON_INSTALL";
        };
        category = "Productivity";
      })
      names;
  };
in
  pkgs.runCommand "codex-marketplace" {} ''
    root="$out/share/codex-marketplace"
    mkdir -p "$root/.agents/plugins"
    cp ${pkgs.writeText "marketplace.json" (builtins.toJSON catalog)} "$root/.agents/plugins/marketplace.json"
    ${lib.concatMapStringsSep "\n" (name: ''
        mkdir -p "$root/plugins/${name}/.codex-plugin" "$root/plugins/${name}/skills"
        cp ${pkgs.writeText "${name}-plugin.json" (builtins.toJSON (manifest name))} "$root/plugins/${name}/.codex-plugin/plugin.json"
        ${lib.concatMapStringsSep "\n" (skill: ''
            cp -rL ${skill}/. "$root/plugins/${name}/skills/"
          '')
          groups.${name}}
      '')
      names}
  ''
