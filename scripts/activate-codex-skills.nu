#!/usr/bin/env nu
use validate-codex-marketplace.nu

# Run external commands with stage-specific errors; keep build progress visible.
def run-command [stage: string, command: string, args: list<string>, --json] {
    if $json {
        let result = (^$command ...$args | complete)
        if ($result.stderr | is-not-empty) {
            print --stderr --no-newline $result.stderr
        }
        if $result.exit_code != 0 {
            error make {msg: $"($stage) failed \(exit ($result.exit_code)\)"}
        }
        $result.stdout | from json
    } else {
        try {
            do --capture-errors { ^$command ...$args }
        } catch {
            error make {msg: $"($stage) failed. If the profile was updated, retry with --refresh-only."}
        }
    }
}

# Accept Nix's unlocked local path and Git flake references, never pinned URLs.
def source-path [reference: string] {
    let path = if ($reference | str starts-with 'path:/') {
        $reference | str replace 'path:' ''
    } else if ($reference | str starts-with 'git+file:///') {
        $reference | str replace 'git+file://' ''
    } else if ($reference | str starts-with '/') {
        $reference
    } else {
        return null
    }
    if $path =~ '[?#]' { return null }
    $path | url decode | path expand
}

def inspect-profile [profile: path, source: path] {
    let data = (run-command 'Profile inspection' nix [profile list --profile $profile --json] --json)
    let entries = ($data.elements | values)
    if ($entries | is-empty) { return false }
    if ($entries | length) != 1 {
        error make {msg: 'Profile conflict: expected exactly one codex-marketplace package'}
    }
    let entry = ($entries | first)
    if ($entry.attrPath? | default '') !~ '^packages\.[^.]+\.codex-marketplace$' or $entry.active? != true or (source-path ($entry.originalUrl? | default '')) != $source {
        error make {msg: 'Profile conflict: expected an active codex-marketplace package from the selected unlocked local source'}
    }
    true
}

def marketplace-matches [] {
    let data = (run-command 'Marketplace inspection' codex [plugin marketplace list --json] --json)
    $data.marketplaces | where name == agent-skills
}

def profile-roots [profile: path] {
    # Nix keeps numbered profile generations alongside the current symlink.
    # Codex resolves local marketplace sources to one of these store paths.
    glob $"($profile)-*-link"
        | each { |generation| $generation | path join share codex-marketplace | path expand }
        | append ($profile | path join share codex-marketplace | path expand)
        | uniq
}

def check-registration [matches: list, root: path, profile: path, --newly-added] {
    if ($matches | length) != 1 {
        error make {msg: 'Marketplace registration: expected exactly one agent-skills marketplace'}
    }
    let entry = ($matches | first)
    let source = $entry.marketplaceSource?
    let recorded = $source.source?
    let current = ($root | path expand)
    if $source.sourceType? != local or $recorded not-in (profile-roots $profile | append $root) {
        if $newly_added {
            error make {msg: $"Marketplace registration recorded an unexpected source: ($recorded); expected a generation of ($profile)"}
        }
        error make {msg: $"Marketplace conflict: agent-skills is registered at ($recorded); expected a generation of ($profile)"}
    }
    if ($entry.root | path expand) != ($recorded | path expand) {
        error make {msg: 'Marketplace conflict: registered root does not match its source'}
    }
    if $newly_added and $recorded != $root and $recorded != $current {
        error make {msg: $"Marketplace registration did not use the current profile generation: ($recorded)"}
    }
    $recorded == $root or $recorded == $current
}

# Install or upgrade the dedicated Nix profile, then refresh every Codex plugin.
def main [
    --source: path # Local checkout; defaults to ~/projects/giodamelio/agent-skills
    --profile: path # Defaults to $XDG_STATE_HOME/nix/profiles/codex-marketplace
    --refresh-only # Refresh Codex without adding or upgrading the Nix profile
] {
    try {
        activate $source $profile $refresh_only
    } catch {|err|
        print --stderr $"activate-codex-skills: ($err.msg)"
        exit 1
    }
}

def activate [source: any, profile: any, refresh_only: bool] {
    for executable in [nix codex] {
        if (which $executable | is-empty) {
            error make {msg: $"Required executable not found: ($executable)"}
        }
    }
    let source = ($source | default ($env.HOME | path join projects giodamelio agent-skills) | path expand)
    let state = ($env.XDG_STATE_HOME? | default --empty ($env.HOME | path join .local state))
    # Preserve the profile symlink so Codex can follow future generations.
    let profile = ($profile | default ($state | path join nix profiles codex-marketplace) | path expand --no-symlink)
    if not $refresh_only and ($source | path join flake.nix | path type) != file {
        error make {msg: $"Source is not a local flake checkout: ($source)"}
    }
    let present = (inspect-profile $profile $source)
    if $refresh_only {
        if not $present {
            error make {msg: 'Refresh-only requires an installed marketplace profile'}
        }
    } else if $present {
        run-command 'Profile upgrade' nix [profile upgrade --profile $profile --all]
    } else {
        mkdir ($profile | path dirname)
        # Encode individual path components, including spaces and URL delimiters.
        let encoded = ($source | split row / | each { url encode --all } | str join /)
        let reference = $"path:($encoded)#codex-marketplace"
        run-command 'Profile installation' nix [profile add --profile $profile $reference]
    }
    let root = ($profile | path join share codex-marketplace)
    let names = (try {
        validate-codex-marketplace $root
    } catch {|err|
        error make {msg: $"Marketplace validation failed: ($err.msg)"}
    })
    let matches = (marketplace-matches)
    if ($matches | is-empty) {
        run-command 'Marketplace registration' codex [plugin marketplace add $root]
        # Exit status alone does not prove that Codex recorded this generation.
        let _ = (check-registration (marketplace-matches) $root $profile --newly-added)
    } else {
        if not (check-registration $matches $root $profile) {
            run-command 'Marketplace removal' codex [plugin marketplace remove agent-skills]
            run-command 'Marketplace registration' codex [plugin marketplace add $root]
            let _ = (check-registration (marketplace-matches) $root $profile --newly-added)
        }
    }
    mut failures = []
    for name in $names {
        let succeeded = (try {
            run-command $"Plugin installation: ($name)" codex [plugin add $"($name)@agent-skills"]
            true
        } catch {|err|
            print --stderr $err.msg
            false
        })
        if not $succeeded { $failures = ($failures | append $name) }
    }
    print $"Profile: ($profile)\nMarketplace: ($root)\nRefreshed (($names | length) - ($failures | length))/($names | length) plugins."
    if ($failures | is-not-empty) {
        error make {msg: $"Failed plugins: ($failures | str join ', '). Retry with --refresh-only."}
    }
    print 'Start a new Codex conversation to use the refreshed skills.'
}
