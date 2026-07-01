---
name: research-company
description: Deep-research a company from minimal input (a name, ideally a name + website) and produce a structured intelligence report — age, founders, funding, key people, products, tech stack, and recent news. Use when the user asks to "research [company]", "look up [company]", "do a company profile / dossier / due diligence on X", or drops a company name + URL expecting a writeup. Pulls from Tracxn, Crunchbase, PitchBook, LinkedIn, SimilarWeb, BuiltWith, G2/Capterra/Product Hunt, TechCrunch/Axios/The Information, SEC EDGAR, Owler, Wellfound, The Org, and Apollo/Clearbit.
disable-model-invocation: true
---

# Company Research

Produce a sourced intelligence report on a company from as little as a name (better: name + website).

## 0. Disambiguate FIRST — the hard gate (do not skip)

**Nothing else runs until identity is locked.** Company names collide constantly — "Fathom" alone matches an AI notetaker, a medical-billing startup, a drug-discovery firm, a web-analytics tool, and a podcast app. This step happens in the **orchestrator (main agent), once, before any researcher is spawned** — the whole fan-out inherits the identity you lock here, so a mistake here poisons every downstream report. The parallel researchers do **not** re-disambiguate.

**Lock identity:**
- If the user gave a **website**, that is the source of truth. Record the canonical domain (follow redirects — `fathom.video` → `fathom.ai`).
- If they gave **only a name**, run one search and list the candidate companies (domain, sector, location, founders).
  - If there's an **obvious single match**, take it and state which one you locked (so the user can correct you).
  - If **two or more are plausible**, **stop and ask the user** with a follow-up question (use `AskUserQuestion`, one option per candidate with domain + sector). Do not guess. Never silently merge two same-named companies — one bad funding figure poisons the whole report.

**Resolve per-site slugs (still in the orchestrator).** Same-named companies share the trap that a wrong slug silently returns the wrong company (Owler's `/company/fathom` → a different Fathom; The Org's `/org/fathom` → a podcast app, while `/org/fathom-video` is correct). Before fan-out, find and verify the canonical slugs you can — Crunchbase org, LinkedIn `/company/`, G2, The Org, Product Hunt — by confirming each page's domain/sector matches the locked identity. Pass the verified slugs to the researchers; tell them which you couldn't confirm.

**Record** the disambiguation key in the **frontmatter** (`website` + `sector`, plus `hq`/`founded` when known) — that's the canonical identity, and refresh runs check against it. Don't add a separate identity line in the body.

## 0.5 Fresh vs. refresh

Before researching, check whether a file for this company already exists in `Data/Companies/`.

- **No file → fresh run.** Research from scratch; the changelog gets a single initial entry (see §5).
- **File exists → refresh run.** **Read the existing file first.** Use its frontmatter (`website` + `sector`) as the disambiguation key so you research the *same* company, and note its `researched` date and current facts (funding, headcount, stage, products, key people). Do the research as normal, then **compare against the old file**:
  - Surface the changes **in chat** as a short "What changed since `<old date>`" list (e.g. "Headcount 120 → 185", "New Series B", "CTO departed"). If nothing material changed, say so.
  - Rewrite the document with the refreshed report + updated frontmatter (`researched` = today).
  - Append a new dated changelog entry summarizing the diff (see §5).
  - Preserve the existing changelog history — never delete past entries.

## 1. What to gather

Core fields (always attempt):
- **Identity** — legal/brand name, canonical domain, HQ, sector, one-line description
- **Age** — founding year + years operating
- **Founders** — names, prior companies, notable background
- **Funding** — total raised, rounds (date / stage / amount / lead), investors, valuation if known, accelerator (YC etc.)
- **Key employees** — C-suite and other notable leaders (CTO, VPs, heads of)
- **Products** — what they sell, key features, target customers, pricing if visible
- **Recent news** — last ~12 months: launches, raises, pivots, layoffs, competitive moves
- **Headcount** — employee count + trend
- **Tech stack** — frameworks, analytics, hosting, CRM (BuiltWith/SimilarWeb/search)
- **Traffic / traction** — monthly visits, growth, revenue estimates
- **Reviews / market position** — G2/Capterra/Product Hunt ratings, competitors
- **Public-company data** — if public or pre-IPO, SEC EDGAR filings

Grab anything else useful: open roles (signals priorities), partnerships, customer logos, controversies.

## 2. Source playbook (shared reference for all researchers)

Three tools, in escalating order: **`WebSearch`** (find URLs + harvest snippets), **`WebFetch`** (load pages that allow it), and the **`camoufox-cli` skill** (anti-detect browser that clears Cloudflare/bot-detection on sites that 403 `WebFetch`). Each source below is tagged with how it behaves through all three (verified June 2026):

| Source | Use for | WebFetch | camoufox-cli | Best path |
|---|---|---|---|---|
| **Company's own site** | Products, pricing, positioning, compliance | ✅ (follow redirects) | — | WebFetch |
| **Tracxn** | Founding, funding, investors, headcount, competitors | ✅ full profile | — | WebFetch |
| **SimilarWeb** | Traffic, geos, rank, revenue/headcount bands | ✅ | — | WebFetch |
| **TechCrunch** | Funding + product news, growth metrics | ✅ articles | — | WebFetch |
| **Product Hunt** | Launches, upvotes, ratings | ✅ | — | WebFetch |
| **G2** | Ratings, review counts, pros/cons | ❌ 403 | ✅ **clean** (exact rating + count) | camoufox |
| **The Org** | Org chart, key people | ⚠️ wrong-company risk | ✅ real chart at the **correct slug** | camoufox + verify slug |
| **Crunchbase** | Investors, rounds, people | ❌ 403 | ⚠️ passes Cloudflare but **$ amounts obfuscated**; investors/rounds/people visible | camoufox for structure, snippets for $ |
| **PitchBook** | Valuation, deal history | ❌ 403 | ⚠️ login-gated shell | search snippets |
| **Capterra** | Ratings, pros/cons | ❌ 403/404 | ⚠️ needs correct URL | snippets / camoufox |
| **LinkedIn** | Founder/exec background, headcount | ⚠️ partial (no titles) | ❌ **authwall** (needs login cookies) | search snippets |
| **Wellfound** | Headcount, jobs, funding | ❌ 403 | ❌ **DataDome CAPTCHA** | search snippets |
| **Owler** | Revenue/competitor estimates | ❌ timeout | ⚠️ JS-gated + **slug returns a namesake** | snippets, verify identity |
| **BuiltWith** | Tech stack | ❌ JS-only, empty | ⚠️ rendered but noisy | search ("<co> tech stack") |
| **Axios** | Deal/news | ⚠️ search 403 | — | `WebSearch allowed_domains:["axios.com"]` → article |
| **The Information** | Deep reporting | ⚠️ paywalled | ❌ hard paywall | headlines via search |
| **SEC EDGAR** | Filings (public only) | ❌ 403 all endpoints | ❌ | manual-check note; skip for private cos |
| **Apollo / Clearbit** | Contact/firmographic | ❌ API-only | ❌ | note as gap |

Rules of thumb:
- **Escalation order per source:** WebFetch → (if 403) camoufox-cli → (if CAPTCHA/authwall/paywall) `WebSearch` snippets. Don't retry a 403 with WebFetch — escalate.
- **camoufox ≠ paywall bypass.** It defeats *bot-detection* (Cloudflare), not *login/Pro* gates. Crunchbase/PitchBook still hide dollar figures logged-out — get those from search snippets.
- **Verify identity on every camoufox load** — check `title`/domain matches before trusting data; a wrong slug looks plausible (Owler/The Org both fail this way).
- **Triangulate ≥2 sources** for funding/headcount; they disagree constantly. Report the range + flag the conflict, never a false single number.
- Cite every non-obvious claim with its source URL.

## 3. Execution — orchestrate parallel researchers

You (the main agent) are the **orchestrator**. You disambiguate, fan out five researcher subagents in parallel, then synthesize their findings into the report. You do **not** gather most data yourself — you delegate it.

1. **Disambiguate + resolve slugs (§0).** Lock identity — asking the user if 2+ candidates are plausible — and verify the canonical per-site slugs. Do not proceed until this is solid.
2. **Check fresh vs. refresh (§0.5).** On a refresh, read the existing file first and pass its known facts to the researchers as a baseline.
3. **Spawn the five researchers in parallel** — one `Agent` call each, in a **single message** so they run concurrently. Pass every researcher the same **locked identity block**: `company_name`, canonical `website`, `sector`, `hq`/`founded` if known, the verified per-site slugs (and which are unconfirmed), and the current date. The agents:
   - `researcher-company-funding` — rounds, investors, valuation, total raised, stage, SEC.
   - `researcher-company-people` — founders, execs, key employees, org, headcount.
   - `researcher-company-product` — products, features, pricing, integrations, reviews, competitors.
   - `researcher-company-traction` — traffic, revenue estimate, tech stack.
   - `researcher-company-news` — last ~12 months of news.
   Each returns a compact, cited findings block (not a full report). Each may use the `camoufox-cli` skill for bot-blocked sites.
4. **Synthesize.** Collect the five blocks, reconcile conflicts across them (esp. headcount/funding — prefer ranges + caveats), and drop anything a researcher flagged as a namesake. If a critical facet came back thin or a researcher failed, do a quick targeted gap-fill yourself or re-spawn that one researcher.
5. **Write the report** (§4–§5): frontmatter + short summary + TOC + sections + changelog. Render locations as wikilinks and create any missing `Locations/` notes (§5). On a refresh, also surface the "what changed" diff in chat.

Scale to the ask: a quick "look up X" can still run all five (they're cheap and parallel); a deep dossier is the same flow with more gap-fill iteration in step 4.

## 4. Output

Save the finished report as a Markdown file in the Companies directory (the skill's working root, `Data/Companies/`), named with the **pretty company name** only — e.g. `Fathom.md`, `Acme Corp.md`. Use the brand name as the user would write it, not the domain. On a refresh run (§0.5), overwrite the existing file but **carry the prior changelog forward**. Also print the report inline in chat — and on a refresh, lead with the "What changed" summary.

### Frontmatter (machine-readable)

Every saved file MUST begin with a YAML frontmatter block so the directory stays queryable. Schema (the format is still evolving — keep keys stable, add new ones as needed, omit any you can't fill rather than guessing):

```yaml
---
company_name: <pretty company name> # required
website: <canonical url>             # required (follow redirects to the real domain)
linkedin: <company page url>         # if it exists — the /company/ page, not a founder profile
crunchbase: <organization url>       # if it exists
founded: <year>                      # optional
hq: "[[City]]"                       # optional — Obsidian wikilink, quoted (see §5); list for multiple
sector: <one-line category>          # optional
stage: <e.g. Seed, Series A, Public> # optional
total_funding: <e.g. $21.8M>         # optional
researched: <YYYY-MM-DD>             # required (date of this run)
---
```

Rules:
- `company_name`, `website`, and `researched` are mandatory; everything else is best-effort.
- Only include `linkedin`/`crunchbase` when you have a **verified** URL (confirm the company-page slug via search — don't construct it). Omit the key entirely if unverified.
- Use the `/company/<slug>` LinkedIn URL, never a personal founder profile.
- It's fine to add extra keys (e.g. `ticker`, `twitter`, `pitchbook`, `employees`) when the data is solid and useful for later filtering.

## 5. Report format

This file is meant to live in an Obsidian vault. House rules:
- **No top-level H1 title** — the filename is the title. Every section heading is an **H1 (`#`)**, not `##`.
- **Blank line after every heading** before its content.
- The disambiguation key (domain + sector) lives in the **frontmatter**, not the body — no identity line.
- After the summary paragraph, emit the **Table of Contents** block verbatim (it's powered by the Obsidian TOC plugin — reproduce it exactly, including the fenced ` ```table-of-contents ` block, on every report).
- **Location links.** Every city you name as a company location (HQ, offices) is written as an Obsidian wikilink to its bare city name — `[[San Francisco]]`, not `San Francisco, CA` and not `[[San Francisco, CA]]`. Wikilinks resolve by filename across the vault, so the bare `[[City]]` form works from anywhere. This applies in **both places**:
  - **Frontmatter `hq`** — a **quoted** wikilink, e.g. `hq: "[[San Francisco]]"` (the quotes are required, or YAML parses `[[...]]` as a nested list). For multiple locations use a YAML list of quoted links: `hq:\n  - "[[London]]"\n  - "[[Austin]]"`.
  - **Body** — the same `[[City]]` link in Key Stats and/or the summary.
  For each city you link, ensure a note exists at `Data/Locations/<City>.md`; if it doesn't, **create an empty stub** so the link isn't broken (that's the existing convention — the location notes are empty placeholders). Don't link a city that only appears as a namesake/excluded-company detail.

Body starts with a **short** summary paragraph, then the TOC block, then the sections:

````markdown
<Short summary paragraph (2–3 sentences, ~50–70 words): what the company does, who for, and the one most notable thing about it right now. Keep it tight — the detail belongs in the sections below.>

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

# Key Stats

- Founded · Stage · HQ (as a `[[City]]` wikilink) · Headcount · Total raised · Latest round

# Founders & Leadership

- **Name — Role.** Background, prior companies.

# Funding

| Date | Round | Amount | Lead / Notable investors |

Total raised, valuation (if known), accelerator. Note source conflicts.

# Product(s)

Features, target customers, pricing, integrations.

# Traction & Tech

Traffic, revenue est., headcount trend, tech stack, market position vs. competitors.

# Recent News (last ~12 mo)

- **Date — headline.** One line. [source]

# Gaps & Caveats

What couldn't be confirmed; sources that disagreed; disambiguation risk.

# Sources

Markdown links to everything cited.

# Changelog

- **<YYYY-MM-DD>** — <one-line summary of what changed>
  - <optional nested bullets, only a few, only if useful>
````

The **Changelog lives at the very bottom of the file** and grows downward (newest entry last). Keep entries succinct — one sentence max, plus an optional short nested bullet list (a few items at most).

- **Initial (fresh) entry:** just record that the profile was created, e.g. `**2026-06-30** — Initial research.` No detail dump.
- **Refresh entries:** a one-sentence summary of what actually changed since the last run, with optional nested bullets for specifics (e.g. funding, headcount, leadership, product). If nothing material changed, write e.g. `**2026-09-01** — Refresh; no material changes.`
- Never rewrite or delete older entries.

## 6. Quality bar

- Lead with a short (2–3 sentence) summary paragraph, then the Table of Contents block, then a Key Stats bullet list the user can scan in 5 seconds.
- Obsidian formatting: no H1 file title, all section headings are H1, blank line after every heading, and the verbatim `table-of-contents` block right after the summary.
- Distinguish **confirmed** facts from **estimates** (SimilarWeb revenue bands, Owler guesses).
- Always include Gaps & Caveats — an honest "couldn't verify X" beats a confident wrong number.
- If two same-named companies exist, say so explicitly.
- On a refresh, lead the chat reply with what changed since the last run; keep the file's changelog entry to a sentence (+ a few optional nested bullets).
