export const meta = {
  name: 'research-people-in-document',
  description: 'Deep-research every person named in a document — five parallel facet researchers per person — write a sourced People/ profile for each, then wikilink their names in the source document.',
  whenToUse:
    'Invoked by the research-document-people skill AFTER it has read the document, extracted the people, and confirmed the list with the user. Pass the confirmed people (with in-document context and the exact text they appear as) plus the source document path as args. The workflow disambiguates each person, fans out the five researcher-person-* facet researchers per person in parallel, writes each profile, then links the document.',
  phases: [
    { title: 'Identify', detail: 'lock each person’s identity + resolve handles (research-person §0/§0.5); skip on ambiguity' },
    { title: 'Research', detail: 'five researcher-person-* facet agents per person, all in parallel' },
    { title: 'Write', detail: 'synthesize the five findings into People/<name>.md (research-person §4–§5)' },
    { title: 'Link', detail: 'rewrite the source document, turning confirmed names into [[wikilinks]]' },
  ],
}

// ---- args contract (supplied by the research-document-people skill) --------
//   document   : string   — absolute path to the source document
//   today      : string   — YYYY-MM-DD; passed in because Date.now() is unavailable in scripts
//   isMarkdown : boolean   — optional; whether to run the linking phase (defaults from the extension)
//   skillPath  : string   — absolute path to research-person's SKILL.md (single source of truth for
//                           the disambiguation method + Obsidian output format). The invoking skill
//                           always supplies it from the plugin's fixed install path.
//   people     : Array<{
//                   name     : string,    // best full name to research
//                   context  : string,    // in-doc disambiguating context (role, company, location, ...)
//                   mentions : string[],  // exact spans the name appears as in the document
//                }>
//
// Why the workflow fans out the facets ITSELF (instead of an agent running the
// research-person skill): agents spawned by a workflow cannot spawn their own
// subagents, so a per-person agent asked to "fan out five researchers" collapses
// to one agent doing all five inline — shallow. Fanning out here, at the workflow
// layer, is flat (no nesting) and guarantees five dedicated researchers per person.
// Each person's agents share ONLY that person's locked identity — contexts never cross.
// ---------------------------------------------------------------------------

// Normalize args before reading any field. Depending on how the caller passes
// it, `args` can arrive already-parsed OR as a JSON string — reading fields off
// a string silently yields undefined and the workflow bails. Parse defensively.
const A = typeof args === 'string' ? JSON.parse(args) : args
const doc = A && A.document
const today = (A && A.today) || 'today'
const skillPath = (A && A.skillPath) || ''
const people = (A && A.people) || []
const isMarkdown =
  A && typeof A.isMarkdown === 'boolean'
    ? A.isMarkdown
    : typeof doc === 'string' && /\.(md|markdown)$/i.test(doc)

if (!doc) {
  return { error: 'No source document provided. Pass args.document (absolute path).' }
}
if (!people.length) {
  return {
    error:
      'No people provided. The invoking skill must extract the people, confirm them with the user, and pass them as args.people (each with name, context, mentions).',
  }
}

// The five facet researchers — each a dedicated plugin subagent with its own
// tools + output contract. The workflow spawns all five per person in parallel.
const FACETS = [
  { facet: 'bio', agentType: 'obsidian:researcher-person-bio' },
  { facet: 'career', agentType: 'obsidian:researcher-person-career' },
  { facet: 'online', agentType: 'obsidian:researcher-person-online' },
  { facet: 'public-work', agentType: 'obsidian:researcher-person-public-work' },
  { facet: 'news', agentType: 'obsidian:researcher-person-news' },
]

// The invoking skill always passes an absolute skillPath (the plugin installs to
// a fixed location); fall back to that same canonical path if it's ever omitted.
const RP_SKILL = skillPath || '$HOME/.claude/skills/obsidian/skills/research-person/SKILL.md'
const skillPointer = `Read the research-person skill for the full method — it is at: ${RP_SKILL}`

const IDENTITY_SCHEMA = {
  type: 'object',
  properties: {
    locked: { type: 'boolean', description: 'true if exactly one identity was confirmed; false means SKIP this person.' },
    status: { type: 'string', enum: ['fresh', 'refresh', 'skip'] },
    canonicalName: { type: 'string', description: 'Full name to file as People/<name>.md (the filename base). Empty if skipped.' },
    identityBlock: {
      type: 'string',
      description:
        'Compact locked-identity block passed VERBATIM to every facet researcher: name; current company/role; location; sector/field; each verified per-site handle (LinkedIn /in/ slug, personal site, Crunchbase person URL, X/Twitter, GitHub) and which are unconfirmed. Empty if skipped.',
    },
    existingFile: {
      type: 'string',
      description: 'On a refresh, the FULL current contents of People/<name>.md (for diffing + preserving the changelog). Empty otherwise.',
    },
    skipReason: { type: 'string', description: 'If skipped, why (two-plus plausible same-named people, no identifiable match, etc.). Else empty.' },
  },
  required: ['locked', 'status', 'canonicalName', 'identityBlock', 'existingFile', 'skipReason'],
  additionalProperties: false,
}

const WRITE_SCHEMA = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['created', 'refreshed', 'failed'] },
    canonicalName: { type: 'string', description: 'Full name exactly as filed — the People/<name>.md basename. Empty if failed.' },
    filename: { type: 'string', description: 'Exact path written, e.g. "People/Jane Doe.md". Empty if none written.' },
    skipReason: { type: 'string', description: 'If failed, the reason. Else empty.' },
    changedSummary: { type: 'string', description: 'On a refresh, a one-line "what changed since last run". Else empty.' },
  },
  required: ['status', 'canonicalName', 'filename', 'skipReason', 'changedSummary'],
  additionalProperties: false,
}

const LINK_SCHEMA = {
  type: 'object',
  properties: {
    linksAdded: { type: 'number', description: 'Total wikilinks inserted into the source document.' },
    perName: {
      type: 'array',
      items: {
        type: 'object',
        properties: { name: { type: 'string' }, count: { type: 'number' } },
        required: ['name', 'count'],
        additionalProperties: false,
      },
    },
    notes: { type: 'string', description: 'Anything skipped or noteworthy (already-linked names, names not found in prose, etc.).' },
  },
  required: ['linksAdded', 'perName', 'notes'],
  additionalProperties: false,
}

function identifyPrompt(p) {
  const mentions = (p.mentions || []).map((m) => `"${m}"`).join(', ') || '(same as name)'
  return `You lock the identity of ONE person for an Obsidian vault, UNATTENDED. You do NOT write any profile and do NOT research facets — you only confirm WHO this is and prepare the identity for downstream researchers.

Person: "${p.name}"
In-document context (this disambiguates them — use it to lock the RIGHT same-named person, not a namesake): ${p.context || '(none given)'}
Exact spans the name appears as in the document: ${mentions}
Source document: ${doc}
Today's date: ${today}
People/ directory: profiles live at People/<Full Name>.md relative to the vault root; the source document above is inside that vault.

Method — follow the research-person skill's §0 (Disambiguate FIRST) and §0.5 (Fresh vs. refresh). ${skillPointer}. In brief:
- Use WebSearch to find candidates and lock the ONE that matches the in-document context (role / employer / location). Record the anchoring facts.
- Resolve and VERIFY the per-site handles you can (LinkedIn /in/ slug, personal site, Crunchbase person URL, X/Twitter, GitHub) — confirm each page's employer/field matches the locked person. Note which you could NOT confirm. A wrong handle silently poisons a facet researcher, so only pass verified ones.
- You are UNATTENDED: if two or more people plausibly match and the context does not decide, DO NOT guess — return locked=false, status="skip", and the reason.
- Fresh vs. refresh: check whether People/<canonicalName>.md already exists (use Bash/Read). If it does, set status="refresh" and return its FULL current contents in existingFile so the writer can diff and preserve the changelog; otherwise status="fresh".

Return the structured identity. The identityBlock you return is passed VERBATIM to five facet researchers, so make it self-contained: name, current company/role, location, sector/field, and each verified handle (plus which are unconfirmed).`
}

function facetPrompt(facet, id) {
  return `You research the **${facet}** facet of ONE person and return your standard findings block. Do NOT re-disambiguate — but verify every source matches the locked person below (same-named people are the main trap).

Locked identity (use exactly this person):
${id.identityBlock}

Today's date: ${today}
${id.status === 'refresh' ? 'This is a REFRESH of an existing profile — favor what is new/changed, but still return a complete current findings block.' : ''}

Follow your agent instructions for the ${facet} facet and return ONLY your defined findings block.`
}

function writePrompt(id, findings) {
  const blocks = findings
    .map((f) => `### ${f.facet} findings\n${f.text || '(no findings returned — researcher failed or was blocked; note this under Gaps & Caveats)'}`)
    .join('\n\n')
  return `Write the Obsidian profile for ONE person by synthesizing five facet-researcher findings blocks. You are unattended; do not ask anything.

Canonical name: "${id.canonicalName}"
File to write: People/${id.canonicalName}.md (relative to the vault root; the source document ${doc} is inside that vault).
Today's date: ${today}
This is a ${id.status.toUpperCase()} run.

THE OUTPUT FORMAT IS AUTHORITATIVE — read the research-person skill and follow its §4 (Output) and §5 (Report format) EXACTLY: the YAML frontmatter schema, NO H1 file title (every section heading is H1), a blank line after every heading, the verbatim \`table-of-contents\` block right after the summary, [[City]] location wikilinks (and create empty Data/Locations/<City>.md stubs for any that don't exist), [[Company]] wikilinks for the current employer, and the Changelog rules. ${skillPointer}.

Locked identity:
${id.identityBlock}

${id.status === 'refresh' ? `Existing profile — PRESERVE its full changelog history, append one new dated entry summarizing the diff, and set frontmatter \`researched: ${today}\`:\n\n${id.existingFile}\n` : ''}
Findings from the five facet researchers:

${blocks}

Reconcile conflicts across the blocks (especially current employer and role dates — prefer explicit caveats over a false single fact), drop anything a researcher flagged as a namesake / wrong-person, and record thin or blocked facets under Gaps & Caveats. Write the file with Write. Then return the structured result (status, canonicalName, filename, skipReason if failed, and on a refresh a one-line changedSummary).`
}

function linkPrompt(linkable) {
  const list = linkable
    .map((r) => {
      const mentions = (r.input.mentions || []).map((m) => `"${m}"`).join(', ') || `"${r.canonicalName}"`
      return `- canonicalName: "${r.canonicalName}"  |  mentions in the document: ${mentions}`
    })
    .join('\n')
  return `Rewrite the source document so each researched person's name becomes an Obsidian wikilink to their profile in People/.

Source document: ${doc}

Confirmed people (each has a profile at People/<canonicalName>.md):
${list}

Rules — follow EXACTLY:
- Profiles resolve by filename across the vault, so link as [[<canonicalName>]].
- If the visible mention text equals the canonicalName, wrap it in place: Jane Doe -> [[Jane Doe]].
- If the mention differs from the canonicalName (a short form, initials, or surname), use the alias form so the visible text is UNCHANGED: Doe -> [[Jane Doe|Doe]], Jane -> [[Jane Doe|Jane]].
- Link each plain-prose mention. DO NOT:
  - re-wrap a name already inside a [[wikilink]] or a Markdown [link](...),
  - touch names inside fenced code blocks, inline code, or YAML frontmatter,
  - link anyone not in the list above.
- Change ONLY these person mentions — leave the rest of the document byte-for-byte intact.

Read the document, then use Edit to make the changes. Return how many links you added in total and per name, plus any notes on what you skipped.`
}

// --- Phases 1-3: identify -> fan out 5 facets -> write, pipelined per person -
// pipeline (not parallel) so each person flows Identify -> Research -> Write
// independently with no barrier: person B can be mid-facet while person A writes.
// Each stage runs in a fresh isolated agent that sees only this person's data.
const results = (
  await pipeline(
    people,
    // Stage 1 — Identify: lock identity + fresh/refresh (skip on ambiguity).
    (p) => agent(identifyPrompt(p), { label: `identify:${p.name}`, phase: 'Identify', agentType: 'general-purpose', schema: IDENTITY_SCHEMA }),
    // Stage 2 — Research: five facet researchers in parallel for THIS person.
    async (id, p) => {
      if (!id || !id.locked || id.status === 'skip') {
        return { skip: true, id, input: p }
      }
      const findings = await parallel(
        FACETS.map((fc) => () =>
          agent(facetPrompt(fc.facet, id), { label: `${fc.facet}:${p.name}`, phase: 'Research', agentType: fc.agentType }),
        ),
      )
      return { skip: false, id, input: p, findings: FACETS.map((fc, i) => ({ facet: fc.facet, text: findings[i] })) }
    },
    // Stage 3 — Write: synthesize the five findings into People/<name>.md.
    async (bundle, p) => {
      if (bundle.skip) {
        return {
          status: 'skipped',
          input: p,
          canonicalName: bundle.id ? bundle.id.canonicalName : '',
          filename: '',
          skipReason: (bundle.id && bundle.id.skipReason) || 'identity could not be locked',
          changedSummary: '',
        }
      }
      const w = await agent(writePrompt(bundle.id, bundle.findings), {
        label: `write:${p.name}`,
        phase: 'Write',
        agentType: 'general-purpose',
        schema: WRITE_SCHEMA,
      })
      return w ? { ...w, input: p } : { status: 'failed', input: p, canonicalName: bundle.id.canonicalName, filename: '', skipReason: 'write agent failed', changedSummary: '' }
    },
  )
).filter(Boolean)

const linkable = results.filter((r) => r.status !== 'skipped' && r.status !== 'failed' && r.canonicalName)
log(
  `Researched ${results.length}/${people.length} people (5 facet researchers each) — ${linkable.length} profiles written, ${
    results.length - linkable.length
  } skipped/failed.`,
)

// --- Phase 4: link the confirmed people in the source document --------------
// Barrier: one agent edits the single source document, only after every profile
// exists so the wikilinks resolve. It receives only names — no research context.
phase('Link')
let linking = null
if (!isMarkdown) {
  log('Source is not Markdown — profiles created, but skipping wikilink insertion.')
} else if (!linkable.length) {
  log('No confirmed profiles to link — skipping the link phase.')
} else {
  linking = await agent(linkPrompt(linkable), { label: 'link-document', phase: 'Link', agentType: 'general-purpose', schema: LINK_SCHEMA })
}

// --- Report data (the invoking skill renders the §3 summary for the user) ---
return {
  document: doc,
  isMarkdown,
  created: results.filter((r) => r.status === 'created').map((r) => ({ name: r.canonicalName, filename: r.filename })),
  refreshed: results.filter((r) => r.status === 'refreshed').map((r) => ({ name: r.canonicalName, filename: r.filename, changed: r.changedSummary })),
  skipped: results
    .filter((r) => r.status === 'skipped' || r.status === 'failed')
    .map((r) => ({ name: r.input.name, status: r.status, reason: r.skipReason })),
  linking,
}
