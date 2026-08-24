# Day 1 Audits — Read-Only. Zero Write Access to Source.

## Ground Rules (apply to every audit)
- **You may not modify, create, or delete any source file.** Your ONLY writable location is `audit_reports/`. Any change outside that directory is a failed audit and will be reverted.
- **Evidence, not memory.** Every claim cites `file:line` and, where freshness matters, the last-touch commit (`git log -1 --format='%h %ad' -- <file>`).
- **Read before concluding.** Never report a component's status from its name, a comment, or an old doc. Open it.
- **Distinguish three states precisely:** WORKING (code path complete and plausible end-to-end), BROKEN (exists but a defect prevents function — name the defect), MISSING (does not exist). "Exists but I didn't trace it" is not a state — trace it.
- **No fixes. No refactors. No opinions in the evidence tables.** Recommendations go only in the designated section of each report.
- Cross-reference git log on anything surprising. A stale report burned us before (Codex incident); the reflex is verify-first.

## Report Format (identical for all four)
Write `audit_reports/AUDIT_<X>_REPORT.md`:

```
# Audit <X>: <Name>
## Verdict (3 sentences max)
## Evidence Table
| Claim | Status | Evidence (file:line) | Last touched |
## Working
## Broken (with the specific defect, each)
## Missing
## Implications for Day <N> build
## Open Questions for Adam (only questions code cannot answer)
```

---

## Audit A — Scanner Pipeline, End to End
**Feeds: Day 4 build. The four outputs are launch-gating; this audit determines the gap.**

Trace the complete path and report the state of every link:

1. **Capture:** the room scan entry point in the client. Which view initiates it, what does it capture (photos / RoomPlan / video), where does it upload (Storage path)?
2. **Processing:** the Cloud Function that consumes the upload. Name it, read it fully. Where does the model string come from — hardcoded, env, or Firestore config? (History: a retired model string silently broke this in production. Report the exact current string and its source.)
3. **Inventory:** the Firestore write. Collection, document shape, fields. Has it ever populated for a real user? (`userKnowledge` historically never populated — check whether that defect pattern applies here.)
4. **Output 1 — Move cost estimate:** where computed, what inputs (does it consume the pricing engine — 6-hour ceiling, specialty-item fees, 100-mile gate?), where displayed.
5. **Output 2 — Truck size estimate:** same trace.
6. **Output 3 — Packing plan:** does generation consume inventory data, the move date (reverse scheduling), or both? Where does it live client vs server?
7. **Output 4 — Supplies estimate:** same trace. Is it derived from the inventory scan as designed?
8. **Gating:** which of these surfaces currently check subscription state, and how?

Also flag: any mock data in production files, any stubbed output, any TODO/FIXME in the pipeline, any debug logging left in production code.

---

## Audit B — Task Catalog + n8n Touchpoints
**Feeds: Day 2 removal + Day 3 universal-format build.**

1. **n8n inventory (for removal):** every webhook call site — client and functions. For each: file:line, which task types trigger it, the env var / URL it hits, and what the user sees after it fires. This list must be exhaustive; Day 2 deletes from it.
2. **Concierge references:** every code path or task definition that promises or implies human handling ("we'll take it from here", support-team handoff states, notification-pending states).
3. **Catalog structure:** where task definitions live (Firestore collection + any client-side seeds). Document the current per-task schema: every field, with an example task. Count total tasks. Report which fields exist for: pointers/guidance content, condition arrays, task type/format discriminators, research or chat flags.
4. **Rendering formats:** how many distinct task presentation formats exist in the client today (guidance card, deep-link, multi-step workflow, mini-assessment, anything else)? File:line for each renderer.
5. **Gap analysis:** current schema and renderers vs. the universal anatomy in PEEZY_LAUNCH_PLAN_AUG2026.md §2.3 — what's reusable, what's net-new, field by field.
6. **Trigger logic:** where the current paywall trigger (3-completed-tasks) lives, everywhere it's referenced. Day 2 replaces it with first-gated-tap; this is the demolition map.

---

## Audit C — Research Remnants
**Feeds: Day 3 — the core feature. Resurrect-vs-rebuild swings the schedule.**

For each component: verdict RESURRECT (works or near-works, wire it up), REBUILD (exists but wrong shape for the §3 architecture), or DEAD (ignore).

1. **peezyBrain.js** (or successor): read it fully. What does it actually do today, what model string, what context does it assemble, is it deployed (check functions deploy config), is anything calling it?
2. **Chat client surfaces:** what survives of the contextual chat UI after the April strip — views, view models, typewriter rendering, mic input, thumbs up/down QC. Present but unreachable? Deleted? Reachable?
3. **Provider directory / LLM resolver:** the component that carried the never-return-an-uncited-URL rule. Does the citation-guard logic exist anywhere in code today? File:line.
4. **Claude API call sites in functions/:** every one. Which are live, which are dead code.
5. **Web search capability:** does any existing function use web search / external fetch? If yes, how are results and URLs handled?
6. **Context assembly:** what per-user context is already gatherable server-side (assessment answers, addresses, move date, inventory) — collections and field names, verified against actual Firestore-write code, not docs.
7. **Reuse estimate:** for the §3.1 pipeline (context assembly → search-enabled generation → citation guard → cache → client render), state per stage what exists and what's net-new.

---

## Audit D — Copy Inventory
**Feeds: Day 2 in-app sweep + Friday listing/screenshot work.**

1. **Grep the iOS codebase** (case-insensitive) for every user-visible string matching: `pinky`, `promise`, `money back`, `money-back`, `guarantee`, `concierge`, `we'll handle`, `we handle`, `handled for you`, `trial`, `3 days`, `free for`, `weekly`, `annual`, `yearly`, `subscription`, `cancel anytime`, `$` (any literal dollar amount in a string). For each hit: file:line, the full string, and a keep/kill/rewrite recommendation (kill = contradicts a locked decision; rewrite = needs new-model wording; keep = accurate under the new model).
2. **functions/ sweep:** same terms in any string that reaches users (notifications, generated content templates).
3. **Task catalog content:** flag any task pointer/description text in Firestore seed files or catalog docs that references concierge handling or promises Peezy executes on the user's behalf.
4. **App Store listing:** if listing text exists in the repo (fastlane metadata or docs), audit it against the same terms. If not in repo, state so — it becomes a manual Friday item.
5. **peezy-site repo:** if present locally (check sibling directories), run the same term sweep on user-facing pages. If not present, state so — manual item.
6. **Output a single consolidated removal table** ordered by file, ready to drive Day 2 string changes without re-searching.

---

## Completion
Each audit ends by confirming: `git status --porcelain` shows ONLY new files under `audit_reports/`. If anything else changed, say so explicitly at the top of your report — do not attempt to fix or revert it yourself.
