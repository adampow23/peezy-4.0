# BUILD BRIDGE — Institution Flows Template → Peezy Codebase

Status: PRE-AUDIT BUILD MAP. Per protocol this is not an executable spec — it names what exists, what's new, and the build order, so the code session starts with a scoped audit checklist instead of a blank page. Every "exists" claim below cites PEEZY_STATE or the active seed data; every "needs audit" is flagged for the read-only pass before any spec is written.

---

## 1. What the locked template needs vs. what exists

### 1a. State layer — mostly a mapping, not a rebuild
The disposition model lands almost entirely on the existing persisted vocabulary (H5) — this is the near-zero-schema-expansion win:

| Template disposition | Existing status | Delta |
|---|---|---|
| COMPLETED | Completed | none |
| NOT_APPLICABLE | Dismissed | semantics only (user-confirmed, not hidden) |
| DEFERRED | Snoozed | add trigger (date **or event**), today snooze is time-only — needs audit |
| USER_ACTION_TRACKED | InProgress / UserInProgress | pick one canonical, deprecate the other in new flows |
| WAITING_ON_EXTERNAL | matching_in_progress | rename-in-place candidate: it already means "someone else is working" |
| SUPPORT_ACTIVE | pending | needs audit: current uses of `pending` |

**New metadata, one object:** the disposition contract (`owner, next_action, next_trigger, resume_destination, visible_status_copy`) as a single map field on the task document. One field, not five columns — additive, mapper-safe (H3's shared mapper extends, doesn't fork).
**Genuinely new server logic:** supersession verbs (retire/reopen + Change-plan) and subject-aware canonical keys `(household, subject, institution, TASK_TYPE)`. Builds directly on the spawnTasks token machinery — and **requires the H7 transactional fix first** (the race that allows duplicate spawns becomes user-visible the moment tasks reference each other).

### 1b. Flow engine — 10 step kinds exist; the template needs 4 new, retires 2
Existing (usage across active seed): title(35) info(45) status(37) select(10) decision(15) confirmAddress(5) summary(12) businessSearch(7) confirmDate(2) spawn(3). `skipIfKnown`, `forEachRow`, `rowConfigs`, branches all live.

| Template component | Verdict |
|---|---|
| Roster with per-row cycles | EXISTS structurally (`forEachRow`/`rowGeneration`); per-row *persistence* needs audit — does leaving mid-pass lose row state today? |
| Contextual outcome question | NEW kind `outcome` — a select variant with action-context copy + chips-after-intent + disposition writes. One component, reused by every entry |
| Result card (research-enriched, confidence-tiered) | NEW kind `resultCard` — renders immediately from known data, enriches in place from researchTask output, Verified/Partial/Generic postures, D1 gate lives here |
| ReminderScheduler | NEW shared client component + server scheduled trigger (see 1c) |
| FlowCloseout (stuck door + feedback) | NEW shared component; stuck door rides existing support plumbing (H12), feedback needs one new write path |
| `decision` (help/self, `stage: capture`) | RETIRED for new flows per D1 — audit which Swift routes hardcode it (H6 bespoke shadowing) |
| `summary` as flow-ending call sheet | RETIRED in favor of resultCard; existing content migrates into card tiers |

### 1c. Server — the one genuinely new subsystem is time/event triggers
- **Research**: EXISTS (`researchTask`, gated) — needs output-contract extension for confidence labels + structured facts (policy, deadline, form link) instead of prose-only. Needs audit of current output shape.
- **Scheduled triggers**: NEW. Nothing in the export inventory (H19) is a scheduler; nudge `leadDays` is generation-time, not a clock. Verification checks, deferred reactivation, safe-fallback dates, SLA follow-ups all need one scheduled function scanning `next_trigger` — a single cron-style export, not per-feature timers.
- **Push off state changes**: FCM plumbing EXISTS (H12d) for support; task-state notifications are a new trigger source into the same pipe. **H8 fix is prerequisite** — notifying off swallowed writes ships lies.
- **Idempotent create-or-enrich**: extends spawnTasks; supersession is new but small.
- **Wallet**: NEW collection + storage rules; per-requirement acceptance states are data, not infra. No uploads required in v1 (track-only), which defers the hard privacy surface.
- **Zone/locator automation (school)**: NEW and the least certain — treat as its own later phase; school ships without it using the deep-link posture (NEEDS_CONFIRMATION path) first.

### 1d. Already-flagged debt this build steps on (from PEEZY_STATE §3)
H7 (spawn race) and H8 (detached status writes) graduate from "known gaps" to **Phase 0 blockers** — the entire disposition/notification model assumes acknowledged transactional writes. H27 (catalog companion divergence) must be resolved before the reseed that ships these flows. H21 (rules wildcard) should be narrowed in the same rules pass that adds wallet rules.

---

## 2. Build order (each phase independently shippable)

**Phase 0 — truth in the state layer.** H7 transactional spawn guard; H8 awaited/propagating status writes. No visible features. Everything else stands on this.

**Phase 1 — dispositions + contract field + supersession + subject keys.** Server + mapper + minimal status-copy rendering. Existing flows keep working untouched (mapping is backward-compatible).

**Phase 2 — the four shared components** (`outcome`, `resultCard`, ReminderScheduler, FlowCloseout) + the scheduled-trigger function + task push notifications. This is the big client phase; after it, *any* entry is a data problem.

**Phase 3 — first entry live: Memberships.** Chosen deliberately: no wallet, no calendar automation, no pull path — it exercises exactly the Phase-2 components plus research-fact extension, and its leverage content is the best free demo of the D1 gate. Then **Daycare (amended)** and **Medical records** (adds WAITING verification patterns). Reseed per H27 protocol, human-run.

**Phase 4 — wallet + School.** School ships last and knows it: it consumes everything (wallet, event triggers, conditional modules) and adds locator work. Vet/pharmacy clone in whenever — they're pure data after Phase 2.

**Explicitly deferred:** locator automation beyond deep-link, delegation slot activation, upload storage for wallet, private-school machinery beyond the bounded branch.

---

## 3. Audit checklist for the code session (read-only pass, file:line evidence, before any spec)
1. Per-row state persistence in the flow engine — where does forEachRow progress live, does backgrounding lose it?
2. Snooze implementation — time-only or extensible to event triggers?
3. Current semantics/consumers of `pending` and `matching_in_progress`.
4. researchTask output shape — structured or prose; where confidence labeling attaches.
5. TaskFlowRouter bespoke routes that hardcode `decision`/`summary` (H6/H11 shadowing) — the retire list.
6. Notification tap → deep-link routing: does a push currently resume at a step?
7. spawnTasks token scope — what the H7 fix needs to make keys subject-aware in the same change.
8. Mapper tolerance for the new contract field (H3 path) on old clients.

Deliverable of the code session: Phase 0 spec (small, surgical) + Phase 1 spec, per autopilot protocol. Phases 2–4 spec after Phase 1 verifies.
