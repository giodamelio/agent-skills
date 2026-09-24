{pkgs}: let
  # Latest anthropics/skills main commit on 2026-09-24. Fetch only this file.
  quickValidateSource = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/anthropics/skills/33375500bcea98d610eb30ce10ac4e59b89c390d/skills/skill-creator/scripts/quick_validate.py";
    hash = "sha256-Z89XA0AgE5Nsj7da1qGv7NiEHUXMXmBrY06wWCX942U=";
  };

  # Plugin skills also use these Claude Code frontmatter keys. Extend only the
  # allowlist; retain upstream's checks for required fields and valid values.
  quickValidate = pkgs.runCommand "quick-validate-skill.py" {} ''
    cp ${quickValidateSource} "$out"
    substituteInPlace "$out" --replace-fail \
      "'metadata', 'compatibility'}" \
      "'metadata', 'compatibility', 'argument-hint', 'disable-model-invocation', 'model'}"
  '';

  python = pkgs.python3.withPackages (ps: [ps.pyyaml]);
in
  pkgs.writeShellApplication {
    name = "validate-skills";
    runtimeInputs = [python pkgs.findutils];
    text = ''
      count=0
      failures=0
      while IFS= read -r -d $'\0' skill; do
        count=$((count + 1))
        printf '%s: ' "$skill"
        python ${quickValidate} "$(dirname "$skill")" || failures=$((failures + 1))
      done < <(find . \( -name .git -o -name .jj \) -prune -o -type f -name SKILL.md -print0)
      printf 'Validated %s skills; %s failed\n' "$count" "$failures"
      test "$count" -gt 0 && test "$failures" -eq 0
    '';
  }
