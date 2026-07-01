---
name: research-document-people
description: Deep-research every person mentioned in a document (a company profile, notes, an article — any file), write a profile for each to `People/`, and rewrite the document so their names become wikilinks to those profiles. User-invoked only.
disable-model-invocation: true
---

# Research the People in a Document

Given a document, deep-research every **person** named in it, write a profile for each to `People/`, and turn their names in the document into Obsidian wikilinks pointing at those profiles. Works on **any file** — a company profile, meeting notes, an article, a roster — not just company notes.

This skill is an **orchestrator**. It finds the people, fans out one subagent per person to research them all in parallel (each following the `research-person` skill), then rewrites the source document to link them. It does **not** research anyone itself.

## Input

A path to the target document (the "source document"). If the user didn't name one, ask which file. Any text file works for extraction; the linking step (§3) assumes an Obsidian/Markdown note, since wikilinks only make sense there.

## 1. Extract the people

Read the source document and list the **individual people** named in it.

- Include real, named individuals — founders, executives, authors, quoted people, attendees, investors, etc.
- **Exclude** companies, products, organizations, and unnamed roles ("the CTO" with no name). Companies are the `research-company` skill's job, not this one.
- For each person, capture the **in-document context** that disambiguates them — role, the company/org they're tied to, location, anything the document states. This is what makes the research land on the *right* same-named person, so pass it through.
- Note the **exact text** each name appears as (e.g. "Jane Q. Doe", "Doe", "Jane") so you can link the right spans in §3.

Present the detected list to the user — name + in-doc context — **before** the heavy research. If the list is long, let them prune it: researching each person fans out several agents, so this is real work. Proceed once confirmed.

## 2. Research each person — one subagent per person, all at once

Research the people **in parallel**: launch **one subagent per confirmed person**, all in a **single message** (multiple Agent calls) so they run concurrently instead of one-after-another. Use a **general-purpose** subagent so it inherits the full toolset — including the `Agent` tool, which it needs to run `research-person`'s own five-agent fan-out (see below).

Give each subagent a prompt that:
- Names the **one** person it owns, plus the disambiguating in-doc context (role, company, location) you gathered.
- Tells it to **run the `research-person` skill** for that person, end to end — disambiguation (§0), fresh-vs-refresh (§0.5), the facet fan-out (§3), and writing `People/<Full Name>.md` in the required format (§4–§5). Inside the subagent, `research-person` spawns its five `researcher-person-*` researchers as **nested** subagents, so every person **and** every facet is researched concurrently.
- Because it runs unattended alongside the others, it must **not** stop to ask the user: if the doc context doesn't settle a same-name collision, it should **skip** the person and report that, rather than guess.
- **Returns**: the exact `People/<Name>.md` filename it wrote, the display-name → canonical-name mapping (so you can alias links in §3), and a skip/failure flag with the reason if it couldn't confirm identity.

> Nested subagents (a subagent spawning its own subagents) require Claude Code v2.1.172+, with a max depth of 5 — this flow only goes two levels deep, so it's well within the limit. On older versions the per-person subagent can't fan out; tell it to gather the five facets **inline** instead — still correct, just less parallel within each person.

Collect all subagent results before moving on:
- Already has a `People/` file → the subagent takes `research-person`'s refresh path and still returns the canonical filename for linking.
- Couldn't confirm a person → no file, no link; carry the reason into the §4 report.

## 3. Link the people in the source document

Once all the subagents have returned, rewrite the **source document** so each researched person's name becomes a wikilink to their new profile.

- Profiles live at `People/<Full Name>.md`; wikilinks resolve by filename across the vault, so **`[[Full Name]]`** links correctly from wherever the source document lives.
- If the name in the document matches the canonical filename, wrap it: `Jane Doe` → `[[Jane Doe]]`.
- If the document's text differs from the canonical name (a short form, initials, "Doe"), use the **alias form** so the visible text is unchanged: `[[Jane Doe|Doe]]`.
- Link each plain-prose mention. **Do not**:
  - re-wrap a name already inside a `[[wikilink]]` or a Markdown link,
  - touch names inside code blocks, inline code, or YAML frontmatter,
  - link anyone you didn't create a confirmed profile for.
- Change **only** the person mentions — leave the rest of the document byte-for-byte intact.

If the source file isn't Markdown (so wikilinks don't apply), still create the `People/` profiles but skip link insertion and say so in the summary.

## 4. Report

Summarize in chat:
- People found, and profiles **created** vs **refreshed**.
- Links added to the source document (count + which names).
- Anyone **skipped** and why (ambiguous, unconfirmed, or already linked).
