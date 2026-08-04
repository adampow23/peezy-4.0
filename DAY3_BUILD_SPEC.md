# Day 3 Build Spec — The Core Feature

Research pipeline, universal task format, AI chat. Inputs: AUDIT_B and AUDIT_C
(evidence + reuse map), PEEZY_LAUNCH_PLAN_AUG2026.md §2.3 and §3 (locked
architecture), Day 2 commits (gate + demolition are DONE — this spec assumes
the post-Day-2 tree).

## Session Protocol (unchanged from Day 2)
One phase per fresh session. Read this spec's phase + cited audit sections +
every named file fully before editing. Build/`node --check` verify per phase.
Commit per phase: `day3: phase N — <name>`. Diff-stat confined to named files.
Copy tone rule and architect ruling apply: describe in-app software behavior
freely; never promise action outside the app. Never hardcode prices or model
strings. Both new callables MUST verify `request.auth` — never accept a UID
from the request body (the peezyRespond hole is why).

## Locked Architecture (do not reinterpret)
- Research is generated per task per user, on demand, cached in Firestore.
- Citation guard is absolute: NO URL reaches a user unless it appeared
  verbatim in a search/fetch result within the same generation session.
- Chat (both surfaces) has NO web access at launch and therefore outputs NO
  URLs, ever — it directs users to "Research this" for sourced links.
- Model strings live in `appConfig/ai` and NOWHERE else. Missing config =
  loud failure, never a silent default.
- Every brief ends with informed-choice content ("what could go wrong") —
  the locked brand DNA.

---

## Phase 1 — appConfig/ai + config reader (functions)
Create `functions/aiConfig.js`:
- `getAIConfig()`: reads Firestore doc `appConfig/ai`, in-memory cache with
  5-minute TTL. Throws `HttpsError('failed-precondition', 'AI config missing —
  seed appConfig/ai')` if the doc or a requested key is absent. No fallback
  model string anywhere in the codebase.
- Expected keys: `researchModel`, `chatModel`, `inventoryModel`,
  `maxSearchesPerBrief` (default seed 5), `briefMaxTokens` (default seed 4096).
Create `functions/seedAppConfig.js` (run-once seeder, same style as existing
seeders) writing: `researchModel: "claude-sonnet-4-6"`, `chatModel:
"claude-sonnet-4-6"`, `inventoryModel: "claude-sonnet-4-6"`,
`maxSearchesPerBrief: 5`, `briefMaxTokens: 4096`.
(Day 4's scanner phase migrates processInventory onto `inventoryModel`; do not
touch processInventory in Day 3.)
VERIFY: `node --check` both files. Adam runs the seeder with the Phase 2 deploy.

## Phase 2 — researchTask (the core function)
READ FIRST: AUDIT_C rows on `resolveProvider` (the web-search loop and
exact-citation gate to lift), on verified context write paths (assessment,
addresses, move date, inventory collections — match those exact names), and
`functions/resolveProvider.js` in full.

New file `functions/researchTask.js`, exported from index.js as callable
`researchTask`, `{ timeoutSeconds: 300, memory: '512MiB' }`.

**Auth + input:** require `request.auth`; input `{ taskId: string, force?:
bool, prefs?: object }` (`prefs` = the vendor mini-assessment answers from
Phase 4's client, optional).

**Cache-first:** research docs live at `users/{uid}/research/{taskId}`. If the
doc exists with `status == "ready"` and `force != true`, return it unchanged.

**Generation sequence:**
1. Write/merge the doc with `{ status: "generating", startedAt }` (client
   listens on this doc for progress UX).
2. Assemble context from the verified collections: assessment answers, both
   addresses, move date, days-until-move (computed), inventory summary if a
   completed scan exists (room count, item count, heavy/fragile flags, total
   cube), the task's catalog definition (title, desc, whyNeeded, tips), and
   `prefs` if provided.
3. Read the task's `researchScope` from the catalog: `"web"` → include the
   web-search tool (Anthropic web search, lifted from resolveProvider's loop)
   capped at `maxSearchesPerBrief`; `"reasoning"` → no tools; `"none"` →
   return `HttpsError('failed-precondition', 'task not research-enabled')`.
4. Call the model (`researchModel`, `briefMaxTokens`) with the system prompt
   in Appendix A and a user message containing the context blocks. Demand
   ONLY the JSON schema in Appendix B.
5. Parse (strip fences defensively). **Citation guard:** collect every URL
   the search/fetch tool results actually returned this session; walk the
   parsed brief recursively; any URL not in that set is stripped and the
   containing source entry removed. If a `sources`-backed section lost ALL its
   sources, regenerate ONCE (same context, appended instruction: "Previous
   attempt cited URLs not present in search results. Only cite URLs exactly
   as returned by search."). Second failure → persist the brief with the
   affected section's `items` intact but `sources: []` and top-level
   `degraded: true` — never ship a fabricated link, never ship a hole.
6. Persist: `{ status: "ready", generatedAt, modelUsed, degraded,
   regenerationCount, brief: <Appendix B object>, prefsUsed: prefs ?? null }`.
   Return the doc. On any thrown error: persist `{ status: "failed",
   error: <message> }` so the client never spins forever.

VERIFY: `node --check`; unit-style dry run via `firebase functions:shell` if
available, else defer live test to Phase 4's simulator pass. Adam deploys
(`firebase deploy --only functions`) and runs `node seedAppConfig.js` after
this phase commits.

## Phase 3 — Catalog research fields + reseed
READ FIRST: AUDIT_B catalog schema rows; `functions/taskCatalogData.json`.
For every task, add `researchScope`: `"web"` for tasks whose value depends on
current/local facts (utilities, internet, movers, truck rental, storage,
cleaners, junk removal, insurance, USPS/DMV/registration, schools, vet/
pharmacy/records transfers); `"reasoning"` for situational-guidance tasks
(packing, decluttering, notification checklists, PTO, kids/pets day-of plans);
`"none"` only for pure-mechanical rows with nothing to research.
For vendor-type tasks (movers, cleaners, truck, storage, junk, internet), add
`researchPrefs`: an array of 2-4 `{ id, question, options: [string] }` asking
what matters most (price vs. speed vs. care, timing constraints, special
items) — plain-spoken wording, options mutually exclusive, no free text.
Reuse existing `tips` as the pointer spine — do not delete or rewrite them in
this phase.
VERIFY: JSON parses; Adam reseeds (`node seedTaskCatalog.js`) and spot-checks
one `researchScope` and one `researchPrefs` in the console.

## Phase 4 — Universal task detail (client)
READ FIRST: AUDIT_B renderer map (TaskFlowRouter, FlowEngineView, the two
loader paths, PeezyCardFirestoreMapper); Phase 6 (Day 2) router gate code.

New `Peezy 4.0/Tasks/Views/TaskDetailView.swift` — the universal anatomy from
the launch plan §2.3, presented by TaskFlowRouter for every gated task tap
(subscription check already lives in the router; do not re-gate):
1. Header: task title + `whyNeeded` (rendered at last — Audit B found it
   never displayed).
2. Pointers: the catalog `tips`, styled as the expert spine.
3. Research module:
   - No research doc → "Research this for me" button. For tasks with
     `researchPrefs`, present the 2-4 questions inline first (simple option
     rows), then call `researchTask` with `prefs`.
   - `status == "generating"` → progress state ("Peezy is researching your
     situation…") via Firestore listener on `users/{uid}/research/{taskId}`.
   - `status == "ready"` → render the brief: sections with the existing
     typewriter treatment on first reveal (resurrect per AUDIT_C), sources as
     tappable links WITH publisher names, `questionsToAsk` and `redFlags` as
     distinct styled lists for vendor tasks, `whatCouldGoWrong` always last.
     A quiet "Refresh research" action calls with `force: true`.
   - `status == "failed"` → plain retry state.
4. Primary CTA: if the task routes to a bespoke flow, "Start" launches it
   unchanged; otherwise the detail view carries the Complete action itself.
5. Footer bar: Complete / Snooze / Chat (Chat wires in Phase 6; stub the
   button visibly disabled this phase if needed).
Keep bespoke flow internals untouched. Match PeezyTheme.
VERIFY: build; simulator (Move Pass account): open a `reasoning` task →
generate → brief renders; open a `web` task (utilities or internet) →
generate → sources render and every link opens; open a `researchPrefs` task →
questions precede generation. Confirm cache: reopen → instant, no second call.

## Phase 5 — peezyChat (functions) + new identity
READ FIRST: AUDIT_C chat rows; `functions/systemPrompt.js`,
`functions/knowledgeBase.js`, `functions/peezyBrain.js` (being replaced);
`functions/index.js` support-message handling.

1. New `functions/peezyChat.js`, callable, auth required, `{ timeoutSeconds:
   120 }`. Input `{ surface: "task" | "support", taskId?: string, message:
   string }`.
   - History: read the last 20 messages from `users/{uid}/chats/{surface ==
     "task" ? taskId : "support"}/messages`; append the user message (persist
     it first).
   - Context: for task surface — the task's catalog def + the user's research
     doc if ready + the same user context blocks as researchTask. For support
     — user context + app-facts block (Appendix C includes the product facts:
     Move Pass terms, what's free vs. gated, how to restore purchases).
   - Model: `chatModel`. System prompt: Appendix C. No tools. Post-process:
     strip any URL the model emits (rule: chat outputs no URLs; it suggests
     "Research this" for sourced links).
   - Persist the assistant message; return it.
2. Replace `systemPrompt.js` content with Appendix C (export
   `buildChatSystemPrompt(context)`); delete `peezyBrain.js` and
   `knowledgeBase.js` (their concierge content is dead; anything factual worth
   keeping is already superseded by catalog tips + research).
VERIFY: `node --check`; Adam deploys after Phase 6 commits (single deploy for
both chat phases).

## Phase 6 — Chat surfaces (client)
READ FIRST: SupportChatView (live per conventions-v2), AUDIT_C typewriter/
input component rows, TaskDetailView from Phase 4.
1. SupportChatView: rewire sends to `peezyChat(surface: "support")`; render
   from the chat messages collection; keep the existing submitSupportMessage
   write as the transcript record only if it doesn't double-write — otherwise
   the chats collection is the single record. Add the disclaimer line under
   the composer: "Peezy can make mistakes. Double-check anything important."
2. Task chat: the Phase 4 footer Chat button presents the same chat UI with
   `surface: "task"`, taskId, pre-scoped to that task. Same disclaimer.
3. Thumbs up/down per assistant message IF the April components resurrect in
   under ~30 lines (write `{ rating }` onto the message doc); otherwise skip
   — logged, not built. Do not build new QC infrastructure this week.
VERIFY: build; simulator: support chat answers a product question with no
URL; task chat on a researched task references the brief's content; both show
the disclaimer.

## Phase 7 — Verification sweep
- Greps recorded in SESSION_NOTES: no model string literals outside
  seedAppConfig (`grep -rn "claude-" functions/*.js "Peezy 4.0" | grep -v seedAppConfig`
  → only comments/none); no URL construction in chat path; researchTask and
  peezyChat both check `request.auth` (grep the guard).
- Build + clean-install simulator pass: assessment → gate → purchase →
  3 research generations (one web, one reasoning, one prefs) → both chat
  surfaces → Box Return with prerequisite data (carried from Day 2).
- Cost sanity: note token usage from one web brief's function logs.

## Appendix A — researchTask system prompt (verbatim)
You are Peezy's research engine. You produce a decision-ready brief for ONE
moving task for ONE specific person, using their real situation. You are built
from professional moving expertise: practical, specific, plain-spoken.

Rules:
1. Use their context (dates, addresses, household, inventory) in every
   section. Generic advice is failure — if a sentence could appear in anyone's
   brief, sharpen it or cut it.
2. You may only cite URLs that appear in your search results, character for
   character. Never construct, complete, or recall a URL. If search did not
   return a source for a claim, state the claim without a link or omit it.
3. Never promise that Peezy or any person will contact, book, arrange, or
   handle anything. You equip; the user acts. Describe what Peezy's app
   features do (research, scan, plan) freely.
4. No fixed prices as facts unless a cited source states them; ranges labeled
   as typical are allowed when attributed to the search results.
5. Write like a sharp friend who did this professionally for a decade: short
   sentences, no corporate tone, no hedging filler.
6. Vendor tasks MUST include questionsToAsk (the questions that expose a bad
   operator) and redFlags (the tells, each with why it matters in one clause).
7. Every brief ends with whatCouldGoWrong: the honest tradeoffs of each
   realistic choice, so the user decides with eyes open.
8. Output ONLY the JSON object in the required schema. No markdown fences, no
   preamble.

## Appendix B — brief JSON schema (verbatim, all fields required unless noted)
{
  "headline": "one sentence: the single most useful thing for THIS user",
  "sections": [
    { "heading": "string", "items": [ "string (1-3 sentences each)" ] }
  ],
  "questionsToAsk": [ "string" ],        // vendor tasks; else []
  "redFlags": [ "string" ],              // vendor tasks; else []
  "whatCouldGoWrong": [ "string" ],      // always ≥ 2 entries
  "sources": [
    { "title": "string", "publisher": "string", "url": "exact URL from search" }
  ]                                       // [] for reasoning-scope tasks
}

## Appendix C — chat system prompt (verbatim core; function injects context)
You are Peezy — a knowledgeable, warm moving expert inside the Peezy app.
You help {name} with their move using their real situation: {context blocks}.

Rules:
1. Never output a URL of any kind. When a sourced answer would help, say:
   "Tap Research on that task and Peezy will pull the current details with
   sources."
2. Never promise that Peezy or any person will contact, book, arrange, or
   handle anything outside the app. Peezy's app features (research, scanner,
   packing plan) can be described and recommended freely.
3. Answer from the provided context and general moving expertise. If you
   don't know something specific to their providers or region, say so and
   point to Research.
4. Product facts you may state: the Move Pass is a one-time payment for six
   months of access, nothing renews; the free tier shows the task list;
   Restore Purchases lives in Settings; account/billing help:
   support@peezymove.com.
5. Short, direct, human. One question at a time. Never end with filler.

## Explicitly Deferred
Scanner pipeline changes, cube sheet integration, truck size, processInventory
model migration, redeemGiftCode + mint script (Day 4). Listing, screenshots,
IAP (Friday). Thumbs QC beyond the cheap resurrect. Chat web access
(post-launch).
