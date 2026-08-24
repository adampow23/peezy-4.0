# Peezy UX Reference Sheet — Best-in-Class Task Guidance
*Built Aug 2026. Match off this. Sources at bottom.*

---

## 1. The Five Reference Apps

### TurboTax — the mini-questionnaire benchmark
World-class at: making a dreaded, complex process feel guided.
**Steal:**
- **Never make the user recall from memory.** Data entered once is never asked again — anywhere. (Their worst pre-redesign sin: asking "are you a farmer?" after occupation was already given.)
- **One question per screen when the question requires thought. Group only trivial questions.**
- Progressive disclosure: show only the current step, nothing ahead.
- Copy = accountant friend, not a form. Speaks to the user's actual motivation, not the process.
**Peezy translation:** Mini-assessments must never re-ask anything from the main assessment. If they said "3-bedroom house" on day one, the movers questionnaire already knows. One violation kills the "Peezy knows me" spell.

### Lemonade (Maya) — the questionnaire *feel* benchmark
World-class at: making form-filling feel like a 90-second conversation.
**Steal:**
- Complex intake rendered as a **playful, linear, one-question-at-a-time chat** — users don't experience it as a form at all.
- Tappable answer chips over typing. Typing is the exception, reserved for names/addresses.
- Momentum: each answer immediately advances. No "Next" buttons, no review screens mid-flow.
**Peezy translation:** The movers mini-assessment is 3–5 taps, zero typing, ends with "Building your cheat sheet…" → brief renders. The questionnaire IS the loading screen for the payoff.

### The Knot — the life-event checklist benchmark (closest category analog)
World-class at: date-anchored task lists for a one-time high-stakes event.
**Steal:**
- **Every task is bucketed by time-to-event** and the list re-prioritizes as the date approaches. The date is the boss — same as Peezy's forced-clock thesis.
- To-Do tab = all tasks in timeline order, grouped by time bucket. Filtered views (budget-only, vendor-only) are separate tabs, never mixed into the main list.
- Tasks are add/delete/customizable — users trust a list they can prune.
- Vendor tasks link directly to the booking action, not to an article about booking.
**Peezy translation:** Group the task list by time buckets ("This week" / "Next 2 weeks" / "Before move day" / "After move"). Keep the 4 sub-tabs as filters, never badges inside rows.

### Things 3 — the list-row visual benchmark
World-class at: scannable, zero-decoration task rows.
**Steal:**
- Row = **title + one small metadata line, nothing else.** Tap row → detail expands. All depth is behind the tap (progressive disclosure).
- Complete = tap the circle on the row itself, with **haptic feedback**. No menu, no detail-view detour.
- Destructive/unusual actions (un-completing) get a confirm. Normal actions never do.
- Project progress shown as a tiny pie — ambient, glanceable, no numbers.
**Peezy translation:** Row anatomy below (§3). Completion haptic is non-negotiable — it's the dopamine hit of the whole app.

### Fabulous — the info-task benchmark
World-class at: making a single simple task feel like a directed ritual, not a chore.
**Steal:**
- **One task surfaced at a time**; today's step only. Momentum without overwhelm — user never feels the weight of the whole list.
- Tasks framed as intentional moments, not checkboxes — presentation does the motivational work, not copy length.
- Missing a day = welcomed back, never shamed.
- Their flaw to avoid: heavy visuals + locked content = feels like it's performing at you. Peezy stays flat and fast.
**Peezy translation:** Info-only tasks (defrost freezer) are ONE screen: severity badge → skip line → directive → nevers. No scroll. Done button. That's the whole task.

---

## 2. Pattern → Task Type Map

| Peezy task type | Pattern | Reference |
|---|---|---|
| Vendor tasks (movers, cleaners, truck) | Chip questionnaire (3–5 taps, 1/screen) → generated cheat sheet | TurboTax + Lemonade |
| Info-only (defrost freezer, photos) | Single directive screen, no scroll | Fabulous |
| Transfer/cancel (utilities, insurance) | Directive + the one decision as an A/B tap → then directive | TurboTax (decide-for-them default) |
| External-action (book truck, call ISP) | State model in §4 | The Knot + Asana |

Universal renderer, four presentations. Content and severity come from catalog fields — presentation is chosen by `taskType`. No per-task custom screens.

---

## 3. Task List Row — Best-in-Class Anatomy

What the top apps show per row, and the Peezy spec:

- **Title:** 2–3 words, ~17pt semibold. The differentiator rule (verb-first when verb differentiates, noun-only inside a family).
- **Severity:** 3–4pt color edge on the row's left, or a small dot before the title. **Not a full-row tint** — a wall of red rows reads as alarm, not information.
- **Due:** relative, right-aligned, secondary color: "This week", "By Aug 20". The Knot proves relative-to-event beats absolute dates.
- **Time cost:** "~10 min" in the metadata line. Research on onboarding checklists: per-step time estimates measurably lower resistance to starting.
- **Complete:** tappable circle on the row (Things pattern) + haptic. Row tap opens detail. Two targets, no ambiguity.
- **No images in rows.** No icons beyond the severity dot. Images belong to the detail screen if anywhere.
- **Grouped by time bucket**, not category. Sub-tabs stay as the only filter mechanism.
- Everything else lives behind the tap.

---

## 4. External-Action State Model ("I booked the truck… now what?")

The gap in most checklist apps: tasks completed *outside* the app. Asana's answer is auto-detecting completion and checking items off silently; ClickUp adds time estimates. Peezy can't auto-detect a U-Haul booking, so the mechanism is a **timed follow-up**:

```
To-Do → [user taps "On it"] → In Progress → follow-up ping → Done
```

1. Task detail shows two primary actions: **Done** (already handled) and **On it** (leaving to do it now).
2. "On it" → task moves to In Progress, Peezy schedules a check-in: *"Did you book the truck?"* — surfaced as a card next open ≥24h later. Two taps: **Booked it** / **Not yet** (→ back to To-Do, top of bucket).
3. Never more than one pending check-in per task. Second "Not yet" → task just sits in To-Do; no nagging loop.
4. Snooze stays what it is: "not now." In Progress means "I'm actively doing this outside the app." Different states, different tabs — already matches the 4 sub-tab structure.

This closes the loop The Knot leaves open (booked vendors get manually checked) without the fake precision of pretending Peezy can see outside itself.

---

## 5. Design Laws (the match-off-this checklist)

1. Ask once, ever. Any question answerable from existing data is never asked.
2. One thought per screen. Trivial questions may share; anything requiring thought stands alone.
3. Chips over keyboards. Typing only for names, addresses, free-text notes.
4. All depth behind the tap. Rows are titles; detail screens are the content.
5. The date is the boss. Buckets, ordering, and urgency all derive from move date.
6. Haptic on complete. Every completion, everywhere.
7. Relative dates only. "This week," never "08/20/2026."
8. Time-cost every task. "~10 min" on the row.
9. One check-in max. Follow up once; never nag.
10. No decoration. No row images, no illustration walls, no celebration screens longer than the haptic.

---

## Sources
- TurboTax UX analyses: uxdesign.cc (Totzeva), producthabits.com, appcues.com, onramp.us
- Lemonade/Maya: uxstudioteam.com, trixlyai.com, Adobe UX blog, jotform.com
- The Knot: help.theknot.com, theknot.com, fueled.com app review
- Things 3: ixd.prattsi.org design critique, thedigitalprojectmanager.com
- Fabulous: Medium (Adedeji case study), thefabulous.co, educationalappstore.com
- Checklist state/estimate research: saasui.design, chameleon.io, appcues.com, smart-interface-design-patterns.com
