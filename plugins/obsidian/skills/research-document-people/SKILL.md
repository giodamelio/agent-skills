---
name: research-document-people
description: Deep-research every person mentioned in a document (a company profile, notes, an article — any file), write a profile for each to `People/`, and rewrite the document so their names become wikilinks to those profiles. User-invoked only.
disable-model-invocation: true
---

# Research the People in a Document

Given a document, deep-research every **person** named in it, write a profile for each to `People/`, and turn their names in the document into Obsidian wikilinks pointing at those profiles. Works on **any file** — a company profile, meeting notes, an article, a roster — not just company notes.

This skill is a **thin front-end** over the `research-people-in-document` **workflow** bundled with this plugin (in `workflows/`). It does the two things a background workflow can't: it **finds the people** and **confirms the list with you**. Then it hands the confirmed list to the workflow, which does the heavy research per person **in parallel** and links the document. This skill does **not** research anyone itself.

The workflow deliberately fans out the research **itself** — for each person it locks identity, then spawns the **five `researcher-person-*` facet researchers in parallel** (the same agents `research-person` uses), then synthesizes and writes the profile. It does this at the workflow layer rather than by running the `research-person` skill inside an agent, because **agents spawned by a workflow cannot spawn their own subagents** — an agent told to "fan out five researchers" would collapse to one agent doing all five inline (shallow). Fanning out here keeps every person at full five-facet depth, with each person's agents fully isolated from every other person's.

## Input

A path to the target document (the "source document"). If the user didn't name one, ask which file. Any text file works for extraction; the linking step assumes an Obsidian/Markdown note, since wikilinks only make sense there.

## 1. Extract the people

Read the source document and list the **individual people** named in it.

- Include real, named individuals — founders, executives, authors, quoted people, attendees, investors, etc.
- **Exclude** companies, products, organizations, and unnamed roles ("the CTO" with no name). Companies are the `research-company` skill's job, not this one.
- For each person, capture the **in-document context** that disambiguates them — role, the company/org they're tied to, location, anything the document states. This is what makes the research land on the *right* same-named person, so pass it through.
- Note the **exact text** each name appears as (e.g. "Jane Q. Doe", "Doe", "Jane") so the workflow can link the right spans.

Present the detected list to the user — name + in-doc context — **before** the heavy research. If the list is long, let them prune it: researching each person fans out several agents, so this is real work. Proceed once confirmed.

## 2. Hand off to the workflow

Once the user confirms the list, invoke the **`research-people-in-document` workflow** and pass it the confirmed people plus the source document. The workflow does the heavy lifting: per person it locks identity, fans out the **five `researcher-person-*` facet researchers in parallel**, and writes `People/<Name>.md`; then it rewrites the source document to wikilink the confirmed people and returns a structured report.

The workflow ships **inside this plugin** (it is deliberately *not* a named `.claude/workflows/` command, so it stays out of your slash-command autocomplete). Invoke it by **`scriptPath`**, not by name. The plugin always installs to a fixed location, so both paths you need — the workflow script and `research-person`'s `SKILL.md` (the workflow's agents read the latter for the disambiguation method + Obsidian output format) — are at deterministic paths:

```
scriptPath (workflow) : $HOME/.claude/skills/obsidian/workflows/research-people-in-document.js
skillPath  (args)     : $HOME/.claude/skills/obsidian/skills/research-person/SKILL.md
```

Then call the Workflow tool with the script path as `scriptPath` and `args` as a JSON object. (The harness may deliver `args` to the script JSON-**stringified** even when you pass a real object — that's expected; the workflow parses it defensively. Pass a real object regardless.) The `args` shape:

```
scriptPath: "<resolved workflow-script path>"
args: {
  document:   "<absolute path to the source document>",
  today:      "<YYYY-MM-DD — today's date>",
  isMarkdown: true,
  skillPath:  "<resolved research-person SKILL.md path>",
  people: [
    { name: "Jane Doe",
      context: "co-founder & CEO of Acme, based in San Francisco",
      mentions: ["Jane Q. Doe", "Doe", "Jane"] }
  ]
}
```

- `name` — the best full name to research. `context` — the disambiguating in-doc detail you gathered in §1. `mentions` — every exact span the name appears as, for the linking step.
- Pass `today` explicitly (the workflow can't read the clock). Set `isMarkdown` to `false` for a non-Markdown source so the workflow creates the profiles but skips wikilink insertion.
- The workflow runs unattended, so each person's identity agent is told to **skip** (not ask) when the in-doc context can't settle a same-name collision — it reports the skip instead of guessing.

> The workflow watches live under `/workflows`: an `Identify` group (one agent per person), a `Research` group (five `<facet>:<name>` agents per person, running concurrently), a `Write` group (one per person), then a single `Link` agent. Because the workflow fans the facets out itself, no nested subagent spawning is involved.

## 3. Report

The workflow returns a structured result: `created`, `refreshed`, and `skipped` people, plus a `linking` block (links added, per name). Turn it into a short chat summary for the user:

- People found, and profiles **created** vs **refreshed** (with each refresh's one-line "what changed").
- Links added to the source document (count + which names).
- Anyone **skipped** and why (ambiguous, unconfirmed, or non-Markdown source so no links).
