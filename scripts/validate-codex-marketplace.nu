#!/usr/bin/env nu

# Validate a generated skill-only marketplace and return its plugin names.
export def main [root: path] {
    let root = ($root | path expand --strict)
    cd $root

    # Packaging dereferences all resources. Reject links before reading manifests.
    for resource in (glob **/*) {
        if ($resource | path type) == symlink {
            error make {msg: $"Copied resource is still a symlink: ($resource)"}
        }
        if ($resource | path type) == file and ($resource | path parse | get extension) == md {
            if (open --raw $resource | str contains '{{ include "refs"') {
                error make {msg: $"Unexpanded shared reference: ($resource)"}
            }
        }
    }

    let catalog = (open .agents/plugins/marketplace.json)
    if $catalog.name? != agent-skills or $catalog.interface?.displayName? != 'Agent Skills' {
        error make {msg: 'Expected the agent-skills marketplace (Agent Skills)'}
    }
    let plugins = $catalog.plugins
    if ($plugins | is-empty) {
        error make {msg: 'Catalog must contain plugins'}
    }
    let names = ($plugins | get name)
    if ($names | uniq | length) != ($names | length) {
        error make {msg: 'Duplicate plugin names in catalog'}
    }
    for entry in $plugins {
        let name = $entry.name
        if $name !~ '^[a-z0-9]+(-[a-z0-9]+)*$' {
            error make {msg: $"Invalid plugin name: ($name)"}
        }
        if $entry.source != {source: local, path: $"./plugins/($name)"} {
            error make {msg: $"($name): expected a relative local plugin source"}
        }
        if $entry.policy != {installation: AVAILABLE, authentication: ON_INSTALL} or $entry.category != Productivity {
            error make {msg: $"($name): invalid policy or category"}
        }
        let plugin = ($root | path join plugins $name)
        let manifest = (open ($plugin | path join .codex-plugin plugin.json))
        if ($manifest | columns | sort) != [description name skills version] or $manifest.name != $name or $manifest.skills != './skills/' {
            error make {msg: $"($name): invalid skill-only manifest"}
        }
        if ($manifest.description | str trim | is-empty) or $manifest.version !~ '^0\.1\.0\+codex\.[a-zA-Z0-9-]+$' {
            error make {msg: $"($name): missing description or fingerprint version"}
        }
        let skills = (ls --all ($plugin | path join skills))
        if ($skills | is-empty) {
            error make {msg: $"($name): plugin must contain skills"}
        }
        for skill in $skills {
            if $skill.type != dir or ($skill.name | path join SKILL.md | path type) != file {
                error make {msg: $"($name): every skill must contain SKILL.md"}
            }
        }
    }
    if ($names | sort) != (ls --all plugins | get name | path basename | sort) {
        error make {msg: 'Plugin directories do not match the catalog'}
    }
    $names
}
