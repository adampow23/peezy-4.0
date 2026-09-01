# Daycare Workflow — v3 LOCKED (§A v3.3 amendment applied 2026-08-26)

Supersedes v2. Changes are A12-1a–1e only; domain logic (threshold routing, notice math, escape hatch, GIVE_DAYCARE_NOTICE enrichment, SETUP shortlist, C2 contract) is unchanged.

Status: LOCKED — reference skeleton for the Institution Contact family (vet, pharmacy, medical records, memberships, schools)
Supersedes: DAYCARE_FLOW_SPEC.md (v1)
Change basis: cross-model review round 1 (Reviewer A + Reviewer B), adjudicated. Full accept/reject log in §10.

---

## 1. Structural change from v1: one current-daycare flow, two entry points

v1 gave long-distance movers a thin "letter + a date" notice task while only local movers got the researched closure flow. That failed our own "more complex situation gets more help" principle. Fixed:

**One canonical workflow: `wrap_up_current_daycare`.**
- **Move ≤ 30 mi:** enter at T2 ("staying or leaving?").
- **Move > 30 mi:** generation pre-resolves `leaving = true`; enter at T3. Same research, same call sheet, same closure machinery. Zero added questions for the long-distance parent.
- **SETUP_DAYCARE** stays a separate spawned/generated task.
- **GIVE_DAYCARE_NOTICE** is an idempotent follow-up artifact (see §6), never a parallel thin experience.

Catalog mapping (near-zero schema expansion): TRANSFER_DAYCARE (Local) and the long-distance daycare task both point at this one workflowId; the entry state is resolved at generation time, the same way conditions already gate task creation. The threshold stays tunable; mileage is the v1 heuristic (travel time deferred).

**Threshold escape hatch:** the >30mi task card carries a secondary action — "Actually, we may keep this daycare" — which re-enters at T2. The heuristic routes; it never traps.

---

## 2. Data model: the two dates and the child profile

**Dates — Peezy does NOT know these; default and confirm, don't assume:**
- `last_day_of_current_care` — defaults to move date. Confirmed in one compact card only at the moment a notice deadline is computed ("Last day of care: [move date]? / change").
- `new_care_start_date` — defaults to move date. Confirmed only when availability research runs in SETUP.
- Notice deadline = `last_day_of_current_care − notice_period` (never raw move date).
- **Notice already given and the last-care date moves** → retire the stale deadline reminder **and** create `USER_ACTION_TRACKED` "update your notice with [daycare]" as a full A4 handoff (return: *They accepted the new date / They need it in writing again / They won't change it (→ past-deadline recovery) / Couldn't finish*); the notice already sent remains the daycare's current instruction until they confirm; never a second notice by default (§A A7).
- **Past-deadline recovery:** if the computed deadline is already behind us, never silently create an overdue task. The card becomes an urgent recovery state: "Their notice window has passed — call today and ask for the earliest effective end date." Escalation door prominent.

**Child profile (assessment/profile-level, not asked in-flow):** which children need care, ages/birthdates, current daycare association per child, sibling-placement-together requirement. Generate **one wrap-up task per institution** (two kids at two daycares = two tasks; same daycare = one task covering both). If this data is absent upstream, SETUP asks minimally at the point of need — never re-asked after that.

**Reminder bounds:** every ReminderScheduler instance in this flow caps its options at the nearest of (notice deadline, move date). "One week" is never offered when the deadline is five days out. When the daycare is known, notice-period research may run in the background so "Not sure yet" can show the one decision-relevant fact: "To keep your options open, decide by [date]." (Enhancement — flow works without it.)

---

## 3. Flow logic — `wrap_up_current_daycare`

**T1 — title.** "Sort out daycare for the move." Subline: "Current daycare first — finding a new one is its own step if you need it."

**T2 — keep-or-leave** *(≤30mi entry only)*
"Will [child names] stay at [daycare name if known] after the move?"
- **Staying** → address/contact-update card ("Give the front desk the new address and pickup-route changes — that's it.") → close (C1).
- **Leaving** → T3.
- **Not sure yet** → `DEFERRED` with a date **or event** trigger (the notice-decision date, or the new-care start confirmation), bounded per §2; second cycle changes register and surfaces the support door.

**T3 — best-route card** *(>30mi entry point; leaving pre-resolved)*. Leads with the researched route: T5→T7 run in the background from the known daycare and the card renders immediately from known data, enriching in place. One-tap **Already handled** → status complete → S1 → C1. Quiet secondary **I'll use my own method** → the same call sheet, deadline, and warnings, tracked as `USER_ACTION_TRACKED` (never an exit) → T8. **Remind me** → `DEFERRED` (date or event, bounded per §2). *(T4 deleted per §A A3 — no help/self screen.)*

**T5 — institution identification (help branch) — conditional:**
- **Daycare known, high confidence** (from profile/T2) → skip straight to T6.
- **Known but ambiguous** → single confirmation card.
- **Unknown** → search ("Search for the daycare — or just type the name you know"), biased to old address. Tapping a result that shows name + address IS the confirmation; no second card unless the match is ambiguous. **Mandatory fallback:** manual entry → T7 tier-3 directly.

**T6 — research.** Two rotating progress lines, 20s timeout, partial render. Targets: website, withdrawal/notice policy, notice period, records-release form, direct phone, final-billing note if visible.

**T7 — result card, tiered, always renders:**
- **Tier 1:** withdrawal process + notice period + form link + phone.
- **Tier 2:** phone number as the largest tappable element + who to ask + script.
- **Tier 3:** generic call sheet + prominent "Get help from a person" door.
- Where notice period was found → compute deadline (per §2, confirming last-care date) → stamp/create GIVE_DAYCARE_NOTICE idempotently.

**T8 — shared close (§A A4 contextual outcome, keyed to the action taken).** Before contact, the time-aware primary is **Remind me** (`DEFERRED`, bounded per §2; reason code captured silently for register-shift logic). After a call — "What happened?":
- **Fully handled** → S1 → C1.
- **They're handling it** → `WAITING_ON_EXTERNAL` (owner = daycare · expectation stated · trigger = their date, else risk-based from the last-care date · fallback = call back / support · resume = this row).
- **I need to do one more thing** → chips: *written notice / final bill or balance / records fee / in-person visit / pick up belongings / other* (other opens a prominent text line) → updates or creates the canonical follow-up task (§6) → S1 → C1.
- **I couldn't finish** → *Try another route / Do this later (`DEFERRED`) / Get help from a person* (→ C2). **S1 is deferred** after C2 — never ask a distressed parent about finding a new daycare in the same breath as their escalation; it runs after human resolution.
Row menu on every row per §A A8 (*Already handled / This doesn't apply / Come back later / Someone else is handling it / I'm handling this outside Peezy / Edit this list*); "This doesn't apply" is one tap → `NOT_APPLICABLE(user_asserted_no_obligation)` unless the roster shows a child still enrolled (then the resolver).

**Snooze cap:** the second reminder cycle changes register and **explicitly surfaces the support door** — "Want help from a person?" — not a third identical ping, and not delegation language.

**S1 — spawn check** (terminal closes of leaving branch, except deferred-stuck):
"Need a daycare near the new place?" — but first checks canonical task state (§6): if SETUP_DAYCARE already exists/active/completed, the question is skipped or acknowledges it ("Your new-daycare search is already on your list").

---

## 4. Flow logic — SETUP_DAYCARE deltas

1. **First select:** "Know which daycare you're looking at?" → *I have one in mind* (search, new-address bias) / *Help me find options* (area mode).
2. **Area mode: 3 initial options, expandable on demand.** Each row: distance from new home, ages served (from child profile), phone. "Show more" pages research — never a fixed exhaustible list.
3. **"None of these fit — keep looking"** is a first-class exit on the shortlist AND a close state: marks the attempted option as tried, preserves notes, returns to shortlist, offers expansion when exhausted. Waitlisted option → scheduled follow-up while the parent continues down the list.
4. **Close states:** Done / They need something from me / Remind me to contact or follow up / **Keep looking** / Booked a tour / I'm stuck. "Booked a tour" → tour-date calendar reminder + one micro-line ("Bring: immunization records. Ask: ratios, openings for [age], deposit terms").
5. Script uses child age from profile; if subsidy/voucher status exists in assessment data, surface a one-line flag on the result card — never invent a question for it.

---

## 5. Escalation contract (C2) — support, not delegation

**v1 conflated two products. Locked distinction:**
- **v1 ships support-only.** Copy everywhere: **"Want help from a person?"** — a human helps the parent with the next step. No "we'll take this over / contact them for you" language anywhere until the delegation flag flips; users must not be promised fulfillment that doesn't exist yet.
- **SLA is computed, not universal:** during coverage hours → "You'll hear from us within [X] hours"; outside them → "First thing tomorrow — by [time]." A specific kept promise beats a fast broken one.
- **Support has three resolution actions, and every one lands back in the task graph:**
  1. **Resolve & complete** — marks the task done (then runs deferred S1 if pending).
  2. **Create/update follow-up** — writes the canonical follow-up task with what the human learned.
  3. **Return-to-step** — sends the user back to a specific step with a message ("Got their direct line — tap to call the director").
  A support conversation can never end with the task still frozen at "stuck."

---

## 6. Spawn map with idempotency (canonical identities)

Duplicate prevention is a rule, not a hope. Canonical keys:
- `(household, child, institution, GIVE_DAYCARE_NOTICE)` — one wrap-up case per institution is the visible surface, consolidating siblings at 2+ (§A A1-5c) with per-child state; one child's withdrawal never closes another's — T6 discovery and T8 "written notice" both resolve to this ONE task: create if absent, enrich if present (deadline, form link), never duplicate.
- `(household, child, destination, SETUP_DAYCARE)` — S1 checks absent/active/completed before offering.
- `(household, institution, follow-up:{item})` — T8 chip captures update the matching follow-up if one exists.

| Trigger | Effect (idempotent) |
|---|---|
| Leaving branch closes (except deferred-stuck) | S1 → offer/acknowledge SETUP_DAYCARE |
| T6 finds notice period | Create-or-enrich GIVE_DAYCARE_NOTICE with computed deadline (last-care date confirmed) |
| Past-deadline detected | Urgent recovery card, not a backdated task |
| T8 "they need something" | Create-or-update canonical follow-up, due before last-care date |
| SETUP "Booked a tour" | Tour reminder + micro-content |
| SETUP "Keep looking" | Mark tried, return to shortlist, page research on exhaustion |
| C2 stuck | Priority support item; S1 deferred until resolution |
| Ongoing billing/tax relationship survives the move (staying, or a final bill/tax form expected) | Emit `ADDRESS_UPDATE_REFERENCED` (E13); a withdrawn daycare with nothing owed emits nothing |

---

## 7. Shared components (family-wide, build once)

- **ReminderScheduler** — deadline-bounded options, exact-step deep link, silent reason codes, second-cycle register shift → support door.
- **FlowCloseout** — two doors, two urgencies: "Want help from a person?" (priority queue, computed SLA, three resolution actions) / quiet feedback link (thumbs + one line, auto-attached flow ID + branch path + step; never gates the done tap).
- **Research module** — 20s timeout, partial render, tiered degradation, tier 3 always shows the support door.
- **Hidden delegation slot** — remains in the template at the T7/T8 boundary, ships OFF. Flipping it on requires real fulfillment ops (authorization, ownership, status updates, completion evidence) — a launch decision, not a copy change.

---

## 8. Walkthroughs (updated to v2)

**A. Local move, 9pm, switching.** Opens → "Staying or leaving?" → Leaving → Help me → daycare already known from profile → research runs with no name question → "30 days notice, form link, number." Last-care date confirm: "[move date]? ✓" → It's 9pm → "What's next?" → **Remind me to contact** → tomorrow 9am → push deep-links to the result card → calls → "They need something" → *written notice* chip → the existing GIVE_DAYCARE_NOTICE task gains the real deadline (no duplicate) → S1: "Need one near the new place?" → Yes → SETUP card appears. **Test: three questions before the first useful answer — fewer when the daycare is already known. Every hand-off landed.**

**B. 200-mile move.** Enters the SAME closure flow at T3 with leaving pre-resolved — full research, call sheet, notice math, chips. Never sees a keep-or-leave question. Card carries "Actually, we may keep this daycare" if the heuristic guessed wrong. SETUP generated separately against the new city.

**C. Unlisted home daycare.** Search empty → "type the name you know" → tier-3 call sheet → she knows the number → Done. Zero added friction.

**D. Research strikes out AND no answer for two days.** Tier 3 → two reminder cycles → register shift: "Want help from a person?" → computed-SLA promise → human resolves via return-to-step with the director's direct line → parent finishes → deferred S1 runs. **Worst case ends with a human AND an unfrozen task.**

**E. Already done last week.** Three taps: Leaving → I've got it → Already done → S1 still catches the new-daycare need.

**F. Self-reliant caller (new in v2).** I've got it → Doing it now → call sheet → calls → "we need 30 days written notice" → **"What's next?" is right there** → chip → follow-up task created. v1 stranded exactly this person.

---

## 9. Lock conditions — all seven met

1. ✅ Long-distance enters the full closure skeleton, leaving pre-resolved (§1)
2. ✅ Self-service "doing it now" reaches the shared close (§3 T4)
3. ✅ Reminder state valid before contact, after no answer, awaiting reply (§3 T8)
4. ✅ SETUP has "Keep looking" + expandable results (§4)
5. ✅ Last-care date, start date, child ages, multi-child: explicit sources (§2)
6. ✅ Notice/setup creation idempotent with canonical keys (§6)
7. ✅ Escalation: computed SLA, support-vs-delegation locked, three-action return path (§5)
8. ✅ Profile rule: the wrap-up case declares its `REQUIRED_MILESTONE_PROFILE` by entry (staying → address-update milestone only; leaving → notice, records, follow-up, S1); milestones outside the profile are `NOT_REQUIRED(reason, source)`; the case COMPLETES only when every required milestone is complete or not required (§A A2)

---

## 10. Adjudication log (round 1)

**Accepted — Reviewer B (structural):** one canonical flow with two entry points (B-blocker 3; justification: long-distance parents were getting less help for an equally hard closure job — direct violation of our principles; cost is a generation-time entry flag, not schema growth). Self-service routes to shared close (B-1; the strongest single catch of the round). SETUP "Keep looking" loop + 3-expandable shortlist (B-2, merged with Reviewer A's "none of these fit" exit and shortlist-size cut). Support resolution contract with task-graph writeback (B-4). Close prompt → "What's next?" with pre/post-contact-valid states (B-5). Support-vs-delegation copy separation, snooze cap surfaces support not takeover (B-6). Deferred S1 after stuck (B-corr-1). Conditional T5 / tap-as-confirmation (B-corr-2, plus cut of the unconditional confirm card). Deadline-bounded reminders (B-corr-3; background pre-research marked enhancement). Honest test restatement (B-corr-4). Date model with last-care/start-care defaults + past-deadline recovery (B-missing-A; the deadline was genuinely anchored to the wrong event). Child profile + one-task-per-institution (B-missing-B, merged with A-4). Idempotent spawns with canonical keys (B-missing-C; consistent with our existing spawn-race concerns). Threshold escape hatch (B, open-item adjudication).

**Accepted — Reviewer A:** expanded chip set + prominent free text (A-1, merged with A-5 final-bill awareness). Time-aware/computed SLA (A-2, strengthened by B to a specific-time commitment). Child age sourcing (A-4). Records one-liner (immunizations/contacts), subsidy flag only where data exists, tour micro-content, softer search prompt, tier-2 number as largest element, two rotating progress lines (all low-cost enrichments within principle 2).

**Rejected:** A's optional "did they confirm notice received?" step — lives inside the GIVE_DAYCARE_NOTICE task itself, not as an added flow state (cost: one more screen for everyone to catch a case the follow-up task already owns). A's fixed 3–4 shortlist — superseded by 3-expandable, which also satisfies no-dead-ends. Generic pro/con under "Not sure yet" — both reviewers and v1 agree: out. Travel-time-based threshold — deferred; mileage + escape hatch is enough for v1 (B concurs it's not required). Merging T3/T4 — not proposed by either reviewer as an accept; B explicitly argues to keep them separate; agreed, two-way choices beat four-way states.

**Open items carried:** exact copy (peezy-copywriter pass, now unblocked), background notice-period research (enhancement), travel-time threshold (post-launch, feedback-driven).
