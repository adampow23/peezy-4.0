# Spec 06 — Catalog Restructure: Conversations, Nudges, Spawn Engine — Spec

## Purpose
Rebuild the task catalog as the worksheet defines it: rows become conversations that spawn exactly-named tasks with remembered answers, iffy rows become opt-in nudge cards, and every task surface carries its locked content (insider items, call sheets, trip kits, notes, quote tracking).

## Content Source of Truth
`peezy-task-worksheet.xlsx` — every row locked (16 task/conversation tabs + Nudges + Global Mechanics). The catalog JSON in Phase 1 is authored **by Claude.ai from the worksheet**, delivered as a companion file. Claude Code transcribes it into the repo — it does not author, edit, or "improve" content.

## Current State (from peezy-conventions-v2, code-verified @ da1916e)
- Catalog: 56 tasks in `taskCatalog` (seeded by `functions/seedTaskCatalog.js` from `functions/taskCatalogData.json`). actionType: workflow=43, off-app=12, in-app-inventory=1.
- Two live loading paths only: `PeezyHomeViewModel.loadTasks()` (one-shot) and `TasksStore` listener → `PeezyCardFirestoreMapper.card()`. Field-parity rule except `completedAt`.
- Flow engine: `flowDefinitions` in Firestore, served via `getWorkflowQualifying` callable (deployed rules are default-deny; no direct client read). Engine expressiveness capped at observed need: `{value,when,next}` branches, `bodyVariants`, `forEachRow+rowConfigs`, `requiresRow`, `{rowsList}` rowLabels.
- All status writes live in `TaskActionService` (client). Server-created tasks carry status string `"pending"` → decodes `.upcoming`.
- Submissions: `WorkflowService` callable pattern (LE-029), 27 consumers. Zero client-side webhook URLs.
- `userKnowledge/{uid}` client writes THROW under deployed rules — schema greenfield. **Do not route anything through userKnowledge in this spec.**
- Research pipeline (`researchTask`), Move Pass gate, and gift codes shipped in Build 21. This spec is additive to that surface — research flags and pointer fields on catalog rows must survive.

## Architecture Decisions (made — do not revisit)
1. **Nudges are task docs.** A catalog row with `tier:"nudge"` generates a normal task doc through the existing TaskGenerationService/conditions path. It *renders* as a nudge card. "No" writes status `"dismissed"` (new status case, terminal). "Yes" calls the spawn callable → real task doc created → nudge doc status `"converted"`. Reuses generation, conditions, both loaders, timeline — zero new trigger logic (Adam's ruling: triggers already exist).
2. **Nudge timing (locked):** nudge doc dueDate = spawn target's dueDate **− 2 days**. Spawned task dueDate = the **original** date rule, exactly what it would've been as a plain task.
3. **Fire broad, card filters (locked):** when a condition can't be fully known from assessment/scan, the nudge fires for the broad category and the card's own wording filters ("Bringing your fridge? If so…"). Never skip on uncertainty.
4. **Conversations are flow definitions.** Each conversation tab becomes a `flowDefinitions` doc run by the existing engine. Engine gains exactly three extensions (observed need, per the expressiveness rule): a `spawnTasks` ending action, `skipIfKnown` on steps (answer memory — never re-ask), and `forEachSelection` spawn (Money Accounts: one task per chosen institution).
5. **One spawn callable.** All task creation outside assessment-time generation goes through a single Cloud Function `spawnTasks` (callable, LE-029 posture): validates against catalog, writes task docs + answer memory server-side, idempotent via client-supplied token. Client never constructs spawned task docs.
6. **Answer memory lives at `users/{uid}/moveAnswers/answers`** (single doc, flat map) — written ONLY by `spawnTasks` (server-side, sidesteps the rules gap). Read path: `getWorkflowQualifying` merges known answers into its response as `knownAnswers`; engine skips `skipIfKnown` steps that resolve. No client write, no rules change required.
7. **Chained spawns** (ISP equipment return; renters end-date after new coverage): catalog rows carry `onCompleteSpawns`. `TaskActionService` completion path: mark complete (client write, unchanged) → if card has spawn ids → call `spawnTasks`.
8. **Sequencing is date math, not a dependency engine.** Auto-insurance-before-registration, utilities-before-school-residency, master-policy-first: expressed as `dateRule` offsets between rows. No blocking graph.
9. **Deletion doctrine (eab4193 lesson):** a deleted row retires its catalog conditions AND any now-orphaned assessment keys in the same commit. Deletions this spec: Employer Records, Hire Packers, Appliance Install, Furniture Assembly (absorbed → Book Movers), Trash & Recycling (absorbed → Utilities). Buy Packing Supplies: parked — row removed, content preserved in JSON under `parked:true` (not seeded).
10. **Quote tracking:** v1 = `quotes:[{company,notes}]` on the task doc, client-owned write. Man-hour normalizer (Book Movers only) = structured quote fields + pure client math. No backend.
11. **Show the date, always:** any scheduled/spawned task renders "Scheduled for {date}" — never bare "scheduled".
12. **Out of scope (flagged, not built):** walk-measurement AR, quote-upload AI analysis, provider email automation, learnings library.

## Lessons Learned (binding on every phase)
LE-005 (camera frozen) · LE-007 (@Observable new classes only) · LE-011 (Cloud Functions plain JS) · LE-018 (bash 3.2) · LE-019 (fresh session per phase) · LE-021 (simplest fix) · LE-022 (write code, never describe) · LE-025/LE-031 (loader field parity + marker comment) · LE-026 (no hardcoded prices — do not touch) · LE-029 (callable pattern) · LE-032 (diff every phase).
Conventions-v2 bindings: NSNumber cast for all Firestore numbers; guard `!id.isEmpty` before every `document()` built from variables; `"pending"` status reconciliation untouched; Type-2 answer keys are a payload contract — existing step ids survive all definition edits; new views take `.accessibilityIdentifier()`.

## Pre-Flight Check
```bash
cd ~/Desktop/"Peezy 4.0" && ls "Peezy 4.0.xcodeproj" || exit 1
ls functions/taskCatalogData.json functions/seedTaskCatalog.js || exit 1
ls PEEZY_SPEC_06_CATALOG_RESTRUCTURE.md peezy-catalog-v2.json || exit 1
xcodebuild -scheme "Peezy 4.0" -destination 'generic/platform=iOS Simulator' build -quiet || exit 1
```

---

## Phase 0: Read-Only Audit (files: 0 modify, 0 create) — GATE
Zero write access. Output: `SPEC06_AUDIT.md` at project root answering, with file:line evidence:

1. `taskCatalogData.json` — current per-row schema: exact field list, one full sample row pasted verbatim. Does `seedTaskCatalog.js` write fields it doesn't know, or a fixed allowlist? (estPeezy is known-dropped — confirm the mechanism.)
2. `PeezyCardFirestoreMapper.card()` + `PeezyHomeViewModel.loadTasks()` — do unknown fields on a task doc pass harmlessly? Paste both decode blocks. Confirm the parity marker comment exists.
3. `TaskStatus` — current cases, exact decode fallback line. Where would `dismissed` / `converted` land today?
4. Flow engine — file path(s), the ending-action handling (what happens at a flow's last step today), and the exact structures for branches/`forEachRow`. Paste the ending handler.
5. `getWorkflowQualifying.js` — response shape verbatim. Where a `knownAnswers` map merges in.
6. `TaskActionService` — the complete() path verbatim. Where a post-complete hook inserts.
7. Card stack rendering — where card variants switch (greeting vs task). Where a nudge variant inserts. Which component names/styles a new card variant should reuse (name them for Phase 3's substitution points).
8. `TaskGenerationService` — where dueDate is computed per row; confirm a per-row `dateRule` offset can slot in.
9. Confirm conventions-v2 facts still hold at HEAD: two loaders only, no TimelineService, 4 tabs, deployed-rules default-deny posture unchanged since da1916e.

**Any answer contradicting this spec's assumptions → STOP. Spec revises before Phase 1 runs.**

---

## Phase 1: Catalog v2 Data + Seeder (files: 2 modify, 1 create)

**READ FIRST:** `functions/taskCatalogData.json`, `functions/seedTaskCatalog.js`, `SPEC06_AUDIT.md` §1.

**Order of operations:** JSON → seed script → Firestore `taskCatalog` → client conditions/generation. Old clients ignore new fields (verified Phase 0 §2) — this phase is deployable before any client change.

**The change:** Replace `taskCatalogData.json` content with `peezy-catalog-v2.json` (companion file, authored from the worksheet — transcribe byte-for-byte). Schema per row:

```json
{
  "id": "auto_insurance",
  "tier": "conversation",            // "task" | "nudge" | "conversation"
  "spawnedOnly": false,               // true = never generated directly; only via spawnTasks
  "parked": false,                    // true = seeder skips
  "title": "Update auto insurance",
  "conditions": ["hasVehicles: true"],
  "dateRule": { "anchor": "moveDate", "offsetDays": -21 },
  "urgency": 60,
  "conversationFlowId": "conv_auto_insurance",   // tier=conversation only
  "nudge": { "cardPrompt": "…? ", "spawnsId": "defrost_freezer_task", "leadDays": 2 },  // tier=nudge only
  "onCompleteSpawns": [ { "id": "return_isp_equipment", "dateRule": { "anchor": "moveDate", "offsetDays": 2 } } ],
  "notesEnabled": true,
  "quoteTracker": "none",             // "none" | "v1" | "manHours"
  "content": {
    "reframe": "…", "directive": "…", "failure": "…",
    "insiderItems": ["…"],
    "callSheet": { "say": ["…"], "ask": ["…"], "get": ["…"] },
    "tripKit": { "docs": ["…"], "bundleWith": ["vehicle_registration"] },
    "walkthrough": ["…"],
    "deepLink": "https://movers.usps.com"
  },
  "research": { /* existing research-scope fields — carried over UNCHANGED per row */ }
}
```
All `content` sub-fields optional per row. Existing fields the current pipeline needs (`actionType`, `taskType`, `workflowId`, pointer/research fields) are preserved on every surviving row exactly as the v2 JSON carries them.

**Seeder:** update `seedTaskCatalog.js` to (a) write the new fields (fix the allowlist per Phase 0 §1 — this also closes the standing estPeezy drop), (b) skip `parked:true` rows, (c) update the stale spot-check constant (queued fix from Spec 02), pointing at `forward_mail`.

**Deletions in the JSON (doctrine #9):** `employer_records`, `hire_packers`, `appliance_install`, `furniture_assembly`, `trash_recycling` rows removed; grep the codebase for each id and retire dead references in this same phase.

**BLAST RADIUS:** TaskGenerationService + conditions parser read `conditions`/`urgency` (unchanged shape). Seeder only. 
**DO NOT CHANGE:** any Swift file, `functions/.env`, firestore.rules, research pipeline functions.
**FALLBACK:** if the seeder allowlist is structural (schema validation), keep validation and extend the schema — do not switch to blind passthrough.
**Verification:** `node -e "JSON.parse(require('fs').readFileSync('functions/taskCatalogData.json'))"` · seed dry-run against emulator or a `--dry` flag printing row count = expected · xcodebuild green (no Swift touched) · diff check.

---

## Phase 2: Spawn Engine — Cloud Function (files: 2 modify, 1 create)

**READ FIRST:** `functions/index.js`, `functions/getWorkflowQualifying.js`, an existing callable for the established callable/auth/idempotency shape, `SPEC06_AUDIT.md` §5.

**Order of operations:** client (conversation ending, nudge Yes, onComplete hook) → `spawnTasks` callable → catalog validate → task docs written under `users/{uid}/tasks` → answer memory merged at `users/{uid}/moveAnswers/answers` → response with created ids.

**Create `functions/spawnTasks.js`** (plain JS, v2 callable):

```js
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

// Request: { token: string, source: {kind:"conversation"|"nudge"|"onComplete", id: string},
//            spawns: [{catalogId, titleParams?:{institution?:string}}],
//            answers?: { [key]: string|number|boolean } }
exports.spawnTasks = onCall(async (req) => {
  const uid = req.auth && req.auth.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const { token, source, spawns, answers } = req.data || {};
  if (!token || typeof token !== "string") throw new HttpsError("invalid-argument", "token required");
  if (!Array.isArray(spawns) || spawns.length === 0) throw new HttpsError("invalid-argument", "spawns required");

  const db = getFirestore();
  const tokenRef = db.doc(`users/${uid}/spawnTokens/${token}`);   // idempotency: critical write pattern
  const existing = await tokenRef.get();
  if (existing.exists) return existing.get("result");

  // Validate every spawn against the catalog before writing anything
  const created = [];
  const batch = db.batch();
  for (const s of spawns) {
    if (!s.catalogId || typeof s.catalogId !== "string" || s.catalogId.length === 0)
      throw new HttpsError("invalid-argument", "catalogId required");
    const cat = await db.doc(`taskCatalog/${s.catalogId}`).get();
    if (!cat.exists) throw new HttpsError("not-found", `Unknown catalog row ${s.catalogId}`);
    const row = cat.data();
    const due = computeDueDate(row.dateRule, await moveDate(db, uid));   // original date rule — nudge lead is NOT applied here
    const title = templateTitle(row.title, s.titleParams);
    const taskRef = db.collection(`users/${uid}/tasks`).doc();
    batch.set(taskRef, {
      catalogId: s.catalogId, title, status: "pending", tier: "task",
      dueDate: due, spawnedFrom: source, createdAt: FieldValue.serverTimestamp(),
      notesEnabled: row.notesEnabled === true, quoteTracker: row.quoteTracker || "none",
    });
    created.push({ id: taskRef.id, catalogId: s.catalogId, title });
  }
  if (answers && typeof answers === "object") {
    batch.set(db.doc(`users/${uid}/moveAnswers/answers`), answers, { merge: true });
  }
  const result = { created };
  batch.set(tokenRef, { result, at: FieldValue.serverTimestamp() });   // token written IN the same batch
  await batch.commit();                                                // critical writes land atomically
  return result;
});
```
Include `computeDueDate` (anchor `moveDate` ± offsetDays; NSNumber-safe reads not applicable server-side, but coerce with `Number()`), `moveDate(db, uid)` reading the identity/assessment doc found in Phase 0, and `templateTitle` (replace `{institution}` when provided; e.g. "Update address with {institution}"). Register in `functions/index.js`. Targeted deploy only (`--only functions:spawnTasks`) — full deploys abort on the orphaned `resetInventory`.

**Modify `getWorkflowQualifying.js`:** add to the response `knownAnswers`: the `users/{uid}/moveAnswers/answers` doc (or `{}`). Nothing else in the response shape changes (Type-2 payload contract).

**BLAST RADIUS:** none client-side until Phases 3–4 call it.
**DO NOT CHANGE:** submitWorkflowAnswers, researchTask, any deployed rule.
**FALLBACK:** if batched token+tasks exceeds batch limits for the largest per-institution spawn (cap: chips are ≤ ~10), split into task batch then token write — token last, after success.
**Verification:** functions emulator test: duplicate token returns identical result with no duplicate docs; unknown catalogId rejects with nothing written; `moveAnswers` merges. Diff check.

---

## Phase 3: Nudge Tier — Client (files: 4–5 modify per audit §2/§3/§7, 1 create)

**READ FIRST:** `PeezyCard.swift`, `PeezyCardFirestoreMapper.swift`, `PeezyHomeViewModel.swift`, `TasksStore`/card stack view from audit §7, `TaskActionService`, `SPEC06_AUDIT.md`.

**Order of operations:** generation writes nudge task doc (tier "nudge", dueDate = target − `leadDays`) → loaders decode `tier` + `nudge` fields → stack renders NudgeCardView → No: `TaskActionService.dismiss()` writes status `"dismissed"` → Yes: `spawnTasks(catalogId: nudge.spawnsId)` then status `"converted"` → spawned task arrives via the existing TasksStore listener at its original date.

**The changes (exact contracts; transcribe against audit-confirmed structures):**
1. `TaskStatus`: add cases `dismissed`, `converted` — both terminal, filtered from Home and stack exactly as `completed` is; Timeline shows neither (dismissed-forever means gone).
2. `PeezyCard`: add `tier: String` (default `"task"`), `nudgePrompt: String?`, `nudgeSpawnsId: String?`. **Both loaders, same fields, marker comment maintained (LE-025/031).** NSNumber-cast any numeric.
3. `TaskGenerationService`: rows with `tier=="nudge"` generate with `dueDate = computed(dateRule of nudge.spawnsId row) - leadDays` (default 2); carry `nudgePrompt = nudge.cardPrompt`, `nudgeSpawnsId`.
4. **Create `NudgeCardView.swift`** (new view: complete code, `#Preview`, `.accessibilityIdentifier("nudgeCard")`, `"nudgeYesButton"`, `"nudgeNoButton"`): card container reuses the exact background/shape modifiers of the standard task card named in audit §7 (named substitution point — Claude Code substitutes the identified modifier chain, changes nothing else). Content: `nudgePrompt` text + two buttons **Yes / No** matching existing button styles named in audit §7.
5. Yes-path: idempotency token = `"\(card.id)-convert"`; on callable success write `converted`; on failure surface the existing error affordance, no status write (task must not silently vanish).

**AIM FOR THIS:** a nudge card visually consistent with the stack, one question, Yes/No; No removes it permanently everywhere; Yes replaces it with the real task dated at the original rule, visible in the list with "Scheduled for {date}".
**AVOID THIS:** a nudge that reappears after No; a Yes that yields no visible task; a nudge appearing in Timeline after dismissal; any third button.
**BLAST RADIUS:** both loaders, status filtering sites (audit lists them), stack switch.
**DO NOT CHANGE:** camera pipeline, SubscriptionManager/Paywall, dose math beyond status filtering, `"pending"` decode.
**FALLBACK:** if adding TaskStatus cases ripples through exhaustive switches beyond the filter sites, keep enum untouched and model dismissal as `completed` + `dismissedAt` timestamp field; filter Timeline on it.
**Verification:** xcodebuild green · UITest: nudge No → relaunch → absent; nudge Yes → task row present with date text · diff.

---

## Phase 4: Conversation Flows — Engine Extensions + Definitions (files: 2–3 modify, definitions are Firestore data)

**READ FIRST:** engine files from audit §4, `getWorkflowQualifying.js`, `WorkflowService.swift`, `SPEC06_AUDIT.md` §4–5.

**Order of operations:** tap conversation row → `getWorkflowQualifying` returns definition + `knownAnswers` → engine walks steps (existing branch structures) → steps with `skipIfKnown` whose key resolves in `knownAnswers` are skipped, their value adopted → ending action `spawnTasks` posts the spawn list + collected answers through one `spawnTasks` call → confirmation state shows each spawned task title + "Scheduled for {date}" from the callable response.

**Engine extensions (exactly three — the expressiveness rule):**
1. Step field `skipIfKnown: "keyName"` — if `knownAnswers[keyName]` exists, adopt and advance.
2. Ending action `{ "action": "spawnTasks", "spawns": [{ "catalogId": "…", "when": {…optional branch guard, existing structure…} }] }` — guards use the existing `{value,when,next}` semantics.
3. `forEachSelection`: on a multi-select chip step marked `spawnPerSelection: true`, the ending expands one spawn per selected chip with `titleParams.institution = chip label` (Money Accounts).

Conversation definitions (12 docs: forward_mail\*, renters, auto, vehicle_reg, drivers_license, money_accounts, utilities, internet, cleaners, daycare_school, truck, movers, homeowners, condo — \*forward_mail is zero-question: definition is a single content screen + spawn ending) ship as JSON in `peezy-catalog-v2.json` under `flowDefinitions`, seeded by the Phase 1 seeder into the `flowDefinitions` collection. Content transcribed from the worksheet — trees, chips, tell-don't-ask lines, honesty forks, exactly as locked.

**BLAST RADIUS:** flow engine only; existing Type-2 flows must run byte-identically (payload contract).
**DO NOT CHANGE:** submitWorkflowAnswers path, existing step ids in any current definition, WorkflowService consumers.
**FALLBACK:** if the ending-action seam resists a second action type, model spawn endings as a final step *kind* rather than an ending action — same three capabilities, different insertion point.
**Verification:** existing flow regression (run one Type-2 flow end-to-end, submission payload byte-compared) · new: auto-insurance conversation spawns `vehicle_registration` dated after it; money accounts with 3 chips spawns 3 titled tasks; re-entering a conversation skips answered steps · xcodebuild green · diff.

---

## Phase 5: Task Surface Content (files: 3–4 modify, 2 create)

**READ FIRST:** the task detail surface (StaticInfoView + the universal anatomy files from Build 21), `PeezyCard.swift`, audit §7 styling names.

**Order of operations:** task doc (`notesEnabled`, `quoteTracker`, catalogId) + catalog content → detail surface renders sections in this order: reframe/directive → insider items → call sheet (if present) → trip kit (if present) → walkthrough behind "Walk me through it" (only when present) → deep link button (familiarity fork: "I've done this" = the link itself; "Walk me through it" = prep screen then same link) → research section (existing, untouched) → notes → quote tracker.

**The changes:**
1. Content decode: catalog `content` object surfaces through the existing catalog-read path (audit confirms where task detail reads catalog rows; content is read from catalog by `catalogId`, NOT copied onto task docs — single source, editable without releases).
2. **Create `TaskContentSections.swift`**: one file, small structs rendering reframe, insiderItems, callSheet (Say/Ask/Get groups), tripKit (docs checklist + Directions button opening Maps with the task's address when present), walkthrough disclosure. Complete code, `#Preview`s, accessibility ids, styling via the named substitution points.
3. **Create `QuoteTrackerView.swift`**: v1 — "+ Add company" → name + notes; rows listed; writes `quotes:[{company,notes}]` to the task doc via `TaskActionService` (client-owned path). Guard `!taskId.isEmpty` before `document()`.
4. Notes: multiline field bound to `notes: String` on the task doc, saved on blur through `TaskActionService`.
5. Scheduling copy: everywhere a snoozed/scheduled/spawned state renders, the string is "Scheduled for {formatted date}" — grep for bare "Scheduled"/"Snoozed" strings and replace with the dated form.

**AIM FOR THIS:** a task opened from the list reads as the worksheet tab does — command-voice content, optional walkthrough, working deep link, notes that persist, quotes that persist.
**AVOID THIS:** content sections rendering as empty headers when a row lacks them; notes lost on navigation; any new Firestore decode without NSNumber-safe casts.
**BLAST RADIUS:** task detail surface; TaskActionService gains two write helpers.
**DO NOT CHANGE:** research render, paywall gating of the detail surface, complete/snooze/chat buttons.
**FALLBACK:** if the detail surface resists insertion (audit shows a closed layout), new sections mount as one `TaskContentContainer` inserted at a single point above research.
**Verification:** xcodebuild · UITest: enter notes → relaunch → present; add quote → present; a content-rich row (Book Movers) shows call sheet, a bare row shows no empty sections · diff.

---

## Phase 6: Man-Hour Normalizer — Book Movers (files: 1 modify, 1 create)

**READ FIRST:** `QuoteTrackerView.swift` (Phase 5), Book Movers catalog row.

**Order of operations:** row has `quoteTracker:"manHours"` → tracker adds structured fields per quote: crew size · quoted hours · per-man rate · travel fee → normalizer computes per quote `totalManHours = crew × hours`, fleet average across quotes, and re-price of each company at the average (`avg × crew × perManRate + travelFee`) → side-by-side display; any quote whose `totalManHours` < average is flagged "Lowball — quoted below the average estimate."

**Create `ManHourNormalizer.swift`:** pure struct, unit-tested math, no Firestore.
```swift
struct MoverQuote: Codable, Equatable { var company: String; var crew: Int; var hours: Double; var perManRate: Double; var travelFee: Double }
struct NormalizedQuote: Equatable { let company: String; let totalManHours: Double; let repricedTotal: Double; let lowball: Bool }
enum ManHourNormalizer {
    static func normalize(_ quotes: [MoverQuote]) -> [NormalizedQuote] {
        guard !quotes.isEmpty else { return [] }
        let manHours = quotes.map { Double($0.crew) * $0.hours }
        let avg = manHours.reduce(0, +) / Double(manHours.count)
        return zip(quotes, manHours).map { q, mh in
            NormalizedQuote(company: q.company,
                            totalManHours: mh,
                            repricedTotal: avg * Double(q.crew) > 0 ? (avg * q.perManRate * Double(q.crew) / Double(q.crew)) + q.travelFee : q.travelFee,
                            lowball: mh < avg && quotes.count > 1)
        }
    }
}
```
Correction to transcribe exactly: `repricedTotal = avg * q.perManRate + q.travelFee` (average man-hours × the company's per-man rate + their travel fee). The expression above must be simplified to that line — it is the spec's single source for the formula.

Tracker UI: `quoteTracker == "manHours"` swaps the v1 notes field for the four structured fields; computed table renders totals + flags; notes field remains beneath. Tests in `/Tests/ManHourNormalizerTests.swift`: empty, single quote (no lowball flag), three-quote known-answer case.

**BLAST RADIUS:** QuoteTrackerView only.
**DO NOT CHANGE:** v1 tracker behavior for `"v1"` rows.
**FALLBACK:** none needed — pure math + one view branch.
**Verification:** unit tests pass · xcodebuild · diff.

---

## Files Summary
**Created:** `functions/spawnTasks.js`, `NudgeCardView.swift`, `TaskContentSections.swift`, `QuoteTrackerView.swift`, `ManHourNormalizer.swift`, `/Tests/ManHourNormalizerTests.swift`, `SPEC06_AUDIT.md` (Phase 0 output), `peezy-catalog-v2.json` (Claude.ai-authored input).
**Modified:** `functions/taskCatalogData.json`, `functions/seedTaskCatalog.js`, `functions/index.js`, `functions/getWorkflowQualifying.js`, `TaskStatus`/`PeezyCard.swift`, `PeezyCardFirestoreMapper.swift`, `PeezyHomeViewModel.swift`, `TaskGenerationService`, `TaskActionService`, flow engine file(s) (audit-named), task detail surface file(s) (audit-named).
**NOT Modified (protected):** camera pipeline, SubscriptionManager, PaywallGateView, researchTask + citation guard, submitWorkflowAnswers, firestore.rules, `functions/.env`, project.pbxproj, GoogleService-Info.plist, SIWA/auth fixes, AI-disclosure copy.

## Build Script
Standard `peezy_build.sh` template: pre-flight, auto-commit per phase, rollback on failure, fresh Claude Code session per phase (LE-019), 25-turn default / 30 for Phases 1 and 4, bash-3.2-safe. Phase order is dependency order — 0 gates everything; 1–2 are backend-deployable alone; 3–6 each leave the build green.

## Open Decisions Deliberately Deferred
- Direct client reads of `flowDefinitions` wait on Adam's reconciled-rules deploy (standing open item) — this spec keeps the callable path.
- `resetInventory` orphan still blocks full function deploys — targeted deploys only until Adam deletes it.
- Nudge cadence ("fed one at a time") ships as dueDate ordering through the existing dose math; a dedicated pacing rule is post-v1 tuning in `appConfig`.
