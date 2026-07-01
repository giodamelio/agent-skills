---
name: research-person
description: Deep-research one person and write a sourced profile to `People/`. Do NOT invoke automatically — only when the user runs it directly, or when another skill (e.g. research-document-people) specifically instructs you to research a person.
---

# Person Research

Produce a sourced intelligence report on a person from as little as a name (better: name + a disambiguating handle — company, website, LinkedIn, or field).

## 0. Disambiguate FIRST — the hard gate (do not skip)

**Nothing else runs until identity is locked.** People names collide even harder than company names — one "David Chen" or "Sarah Miller" maps to dozens of real people, and even distinctive names get confused with a namesake founder, academic, or athlete. This step happens in the **orchestrator (main agent), once, before any researcher is spawned** — the whole fan-out inherits the identity you lock here, so a mistake here poisons every downstream report. The parallel researchers do **not** re-disambiguate.

**Lock identity:**
- The strongest anchors are a **LinkedIn profile URL**, a **personal website**, or a **name + current company/role**. If the user gave one, that is the source of truth. Record the canonical profile URL and the anchoring fact (current employer, field, location).
- If they gave **only a name**, run one search and list the candidate people (current role, employer, location, field, distinguishing detail).
  - If there's an **obvious single match** (the name is distinctive, or context from the user makes it clear), take it and state which one you locked (so the user can correct you).
  - If **two or more are plausible**, **stop and ask the user** with a follow-up question (use `AskUserQuestion`, one option per candidate with role + employer + a distinguishing detail). Do not guess. Never silently merge two same-named people — one wrong job history or photo poisons the whole report.

**Resolve per-site handles (still in the orchestrator).** Same-named people share the trap that a wrong profile silently returns the wrong person. Before fan-out, find and verify the handles you can — LinkedIn `/in/` slug, Crunchbase person profile, X/Twitter handle, GitHub username, personal domain — by confirming each page's role/employer/photo matches the locked identity. A common failure: a generic X/GitHub handle that belongs to someone else with the same name. Pass the verified handles to the researchers; tell them which you couldn't confirm.

**Record** the disambiguation key in the **frontmatter** (`name` + the anchoring `company`/`role`, plus `location` when known) — that's the canonical identity, and refresh runs check against it. Don't add a separate identity line in the body.

## 0.5 Fresh vs. refresh

Before researching, check whether a file for this person already exists in `People/`.

- **No file → fresh run.** Research from scratch; the changelog gets a single initial entry (see §5).
- **File exists → refresh run.** **Read the existing file first.** Use its frontmatter (`name` + anchoring `company`/`role`) as the disambiguation key so you research the *same* person, and note its `researched` date and current facts (role, employer, location, notable work). Do the research as normal, then **compare against the old file**:
  - Surface the changes **in chat** as a short "What changed since `<old date>`" list (e.g. "New role: CTO at Acme", "Left Google", "Published a book"). If nothing material changed, say so.
  - Rewrite the document with the refreshed report + updated frontmatter (`researched` = today).
  - Append a new dated changelog entry summarizing the diff (see §5).
  - Preserve the existing changelog history — never delete past entries.

## 1. What to gather

Core fields (always attempt):
- **Identity** — full name, any professional aliases, current role + employer, location, one-line description
- **Bio / background** — origin, age or generation if public, notable personal background
- **Education** — degrees, institutions, fields, notable advisors/programs, plus professional certifications/licenses
- **Career history** — roles over time (period / title / organization), founding history, board seats, advisory + investing roles
- **Public work** — writing (books, essays, Substack/blog), talks/podcasts, academic publications, patents, notable open-source projects
- **Online presence** — verified social/professional profiles (LinkedIn, X/Twitter, GitHub, personal site, Mastodon, etc.) with follower counts / activity level
- **Recent news** — last ~12 months: job changes, launches, funding they led/raised, press, quotes, controversies
- **Affiliations / network** — companies founded, co-founders, notable connections, boards, memberships

Grab anything else useful: awards, notable quotes, causes/philanthropy, recurring themes in their public voice.

## 2. Source playbook (shared reference for all researchers)

Three tools, in escalating order: **`WebSearch`** (find URLs + harvest snippets), **`WebFetch`** (load pages that allow it), and the **`camoufox-cli` skill** (anti-detect browser that clears Cloudflare/bot-detection on sites that 403 `WebFetch`). Each source below is tagged with how it behaves through all three (verified June 2026):

| Source | Use for | WebFetch | camoufox-cli | Best path |
|---|---|---|---|---|
| **Personal site / blog** | Bio, current role, contact, voice | ✅ (follow redirects) | — | WebFetch |
| **Company bio / team page** | Title, background blurb, headshot | ✅ | — | WebFetch |
| **Wikipedia** | Notable people: bio, career, dates | ✅ | — | WebFetch |
| **GitHub** | Projects, activity, bio, org membership | ✅ profile + repos | — | WebFetch |
| **Google Scholar** | Publications, citations, co-authors | ⚠️ often 403 | ⚠️ passes but noisy | snippets / camoufox |
| **Google Patents** | Patents + assignees | ✅ | — | WebFetch |
| **Crunchbase (person)** | Roles, board seats, investments | ❌ 403 | ⚠️ passes Cloudflare; roles/history visible | camoufox + snippets |
| **The Org** | Current role, org placement | ⚠️ wrong-person risk | ✅ real chart at the **correct slug** | camoufox + verify slug |
| **Wellfound / AngelList** | Angel investments, roles, startups | ❌ 403 | ❌ DataDome CAPTCHA | search snippets |
| **LinkedIn** | Career history, education, headcount | ⚠️ partial (no titles) / authwall | ❌ **authwall** (needs login cookies) | search snippets |
| **X / Twitter** | Voice, follower count, current activity | ⚠️ login-gated | ⚠️ partial; try nitter mirrors | snippets / search |
| **Podcasts / interviews** | Deep background, career story, quotes | ✅ show-notes pages | — | WebSearch → WebFetch |
| **Conference / talk pages** | Talks, abstracts, video links | ✅ | — | WebFetch |
| **TechCrunch** | Funding + role-change news | ✅ articles | — | WebFetch |
| **Axios** | Deal/news | ⚠️ search 403 | — | `WebSearch allowed_domains:["axios.com"]` → article |
| **The Information** | Deep reporting | ⚠️ paywalled | ❌ hard paywall | headlines via search |

Rules of thumb:
- **Escalation order per source:** WebFetch → (if 403) camoufox-cli → (if CAPTCHA/authwall/paywall) `WebSearch` snippets. Don't retry a 403 with WebFetch — escalate.
- **camoufox ≠ paywall bypass.** It defeats *bot-detection* (Cloudflare), not *login/Pro* gates. LinkedIn/Wellfound stay authwalled; Crunchbase still hides some fields logged-out — get those from search snippets.
- **Verify identity on every source** — check the photo, current employer, and field match the locked person before trusting data; a wrong profile looks plausible. This is the #1 risk in person research. When a fact can't be tied to *this* person, drop it or flag it.
- **Triangulate ≥2 sources** for role history and dates; profiles disagree and go stale. Report the discrepancy, never a false single fact.
- Cite every non-obvious claim with its source URL.

## 3. Execution — orchestrate parallel researchers

You (the main agent) are the **orchestrator**. You disambiguate, fan out five researcher subagents in parallel, then synthesize their findings into the report. You do **not** gather most data yourself — you delegate it.

1. **Disambiguate + resolve handles (§0).** Lock identity — asking the user if 2+ candidates are plausible — and verify the canonical per-site handles. Do not proceed until this is solid.
2. **Check fresh vs. refresh (§0.5).** On a refresh, read the existing file first and pass its known facts to the researchers as a baseline.
3. **Spawn the five researchers in parallel** — one `Agent` call each, in a **single message** so they run concurrently. Pass every researcher the same **locked identity block**: `name`, current `company`/`role`, `location` if known, `sector`/field, the verified per-site handles (and which are unconfirmed), and the current date. The agents:
   - `researcher-person-bio` — identity, current role, location, personal background.
   - `researcher-person-career` — employment history, roles, education + certifications, board seats, founding + investing history.
   - `researcher-person-online` — verified social/professional profiles + follower counts / activity.
   - `researcher-person-public-work` — public output: writing, talks, podcasts, publications, patents, OSS.
   - `researcher-person-news` — last ~12 months of news, press, quotes, controversies.
   Each returns a compact, cited findings block (not a full report). Each may use the `camoufox-cli` skill for bot-blocked sites.
4. **Synthesize.** Collect the five blocks, reconcile conflicts across them (esp. role dates and current employer — prefer explicit caveats), and drop anything a researcher flagged as a namesake / wrong-person. If a critical facet came back thin or a researcher failed, do a quick targeted gap-fill yourself or re-spawn that one researcher.
5. **Write the report** (§4–§5): frontmatter + short summary + TOC + sections + changelog. Render locations as wikilinks and create any missing `Data/Locations/` notes; render current employer as a `[[Company]]` wikilink (§5). On a refresh, also surface the "what changed" diff in chat.

Scale to the ask: a quick "who is X" can still run all five (they're cheap and parallel); a deep dossier is the same flow with more gap-fill iteration in step 4.

## 4. Output

Save the finished report as a Markdown file in the People directory (the skill's working root, `People/`), named with the **person's full name** as they present it — e.g. `Jane Doe.md`, `Sam Altman.md`. On a refresh run (§0.5), overwrite the existing file but **carry the prior changelog forward**. Also print the report inline in chat — and on a refresh, lead with the "What changed" summary.

### Frontmatter (machine-readable)

Every saved file MUST begin with a YAML frontmatter block so the directory stays queryable. Schema (the format is still evolving — keep keys stable, add new ones as needed, omit any you can't fill rather than guessing):

```yaml
---
name: <full name>                    # required
website: <personal site url>         # if it exists
linkedin: <profile url>              # if verified — the /in/ profile
twitter: <handle or url>             # if verified
github: <profile url>                # if verified
crunchbase: <person profile url>     # if it exists
company: "[[Current Employer]]"      # current org — wikilink, quoted (see §5)
role: <current title>                # optional
location: "[[City]]"                 # optional — Obsidian wikilink, quoted (see §5)
sector: <one-line field/category>    # optional
researched: <YYYY-MM-DD>             # required (date of this run)
---
```

Rules:
- `name` and `researched` are mandatory; everything else is best-effort.
- Only include `linkedin`/`twitter`/`github`/`crunchbase` when you have a **verified** URL that you confirmed belongs to *this* person (matching employer/field/photo) — don't construct or guess it. Omit the key entirely if unverified.
- Use the `/in/<slug>` LinkedIn URL, never a company page.
- It's fine to add extra keys (e.g. `mastodon`, `scholar`, `wikipedia`, `born`) when the data is solid and useful for later filtering.

## 5. Report format

This file is meant to live in an Obsidian vault. House rules:
- **No top-level H1 title** — the filename is the title. Every section heading is an **H1 (`#`)**, not `##`.
- **Blank line after every heading** before its content.
- The disambiguation key (name + anchoring role/employer) lives in the **frontmatter**, not the body — no identity line.
- After the summary paragraph, emit the **Table of Contents** block verbatim (it's powered by the Obsidian TOC plugin — reproduce it exactly, including the fenced ` ```table-of-contents ` block, on every report).
- **Location links.** Every city you name as a person's location (home base, past cities) is written as an Obsidian wikilink to its bare city name — `[[San Francisco]]`, not `San Francisco, CA` and not `[[San Francisco, CA]]`. Wikilinks resolve by filename across the vault, so the bare `[[City]]` form works from anywhere. This applies in **both places**:
  - **Frontmatter `location`** — a **quoted** wikilink, e.g. `location: "[[San Francisco]]"` (the quotes are required, or YAML parses `[[...]]` as a nested list).
  - **Body** — the same `[[City]]` link in Key Facts and/or the summary.
  For each city you link, ensure a note exists at `Data/Locations/<City>.md`; if it doesn't, **create an empty stub** so the link isn't broken (that's the existing convention — the location notes are empty placeholders). Don't link a city that only appears as a namesake/excluded-person detail.
- **Company links.** Render the current employer (and other notable companies they founded or lead) as a `[[Company]]` wikilink so the person cross-links to any company note in the vault. Use the brand name as the company-research skill would file it (e.g. `[[Fathom]]`), not the domain. Don't create company stubs — leave the link unresolved if no company note exists yet.

Body starts with a **short** summary paragraph, then the TOC block, then the sections:

````markdown
<Short summary paragraph (2–3 sentences, ~50–70 words): who this person is, what they're known for, and the one most notable thing about them right now. Keep it tight — the detail belongs in the sections below.>

# Table of Contents
```table-of-contents
title:
style: nestedList # TOC style (nestedList|nestedOrderedList|inlineFirstLevel)
minLevel: 0 # Include headings from the specified level
maxLevel: 0 # Include headings up to the specified level
include: 
exclude: /Table of Contents/
includeLinks: true # Make headings clickable
hideWhenEmpty: false # Hide TOC if no headings are found
debugInConsole: false # Print debug info in Obsidian console
```

# Key Facts

- Current role · Employer (as a `[[Company]]` wikilink) · Based in (as a `[[City]]` wikilink) · Known for · Education (one line)

# Background

Origin and the through-line of who they are. Keep it to what's sourced.

# Career History

| Period | Role | Organization |

Education, certifications/licenses, founding history, board seats, advisory + investing roles. Note source conflicts / gaps.

# Public Work

Writing (books, essays, blog/Substack), talks & podcasts, publications, patents, notable open-source projects. Link the standout items.

# Online Presence

Verified profiles with follower counts / activity level (LinkedIn, X/Twitter, GitHub, personal site, etc.). Note which handles you could not confirm.

# Recent News (last ~12 mo)

- **Date — headline.** One line. [source]

# Gaps & Caveats

What couldn't be confirmed; sources that disagreed; disambiguation / wrong-person risk.

# Sources

Markdown links to everything cited.

# Changelog

- **<YYYY-MM-DD>** — <one-line summary of what changed>
  - <optional nested bullets, only a few, only if useful>
````

The **Changelog lives at the very bottom of the file** and grows downward (newest entry last). Keep entries succinct — one sentence max, plus an optional short nested bullet list (a few items at most).

- **Initial (fresh) entry:** just record that the profile was created, e.g. `**2026-06-30** — Initial research.` No detail dump.
- **Refresh entries:** a one-sentence summary of what actually changed since the last run, with optional nested bullets for specifics (e.g. new role, new publication, relocation). If nothing material changed, write e.g. `**2026-09-01** — Refresh; no material changes.`
- Never rewrite or delete older entries.

## 6. Quality bar

- Lead with a short (2–3 sentence) summary paragraph, then the Table of Contents block, then a Key Facts bullet list the user can scan in 5 seconds.
- Obsidian formatting: no H1 file title, all section headings are H1, blank line after every heading, and the verbatim `table-of-contents` block right after the summary.
- Distinguish **confirmed** facts from **estimates / inferences** (an unverified follower count, an approximate role date).
- Always include Gaps & Caveats — an honest "couldn't verify X" beats a confident wrong fact. Person research is privacy-sensitive: report only what's publicly documented, attribute it, and don't infer private details.
- If two same-named people exist, say so explicitly and state which one this profile is about.
- On a refresh, lead the chat reply with what changed since the last run; keep the file's changelog entry to a sentence (+ a few optional nested bullets).
