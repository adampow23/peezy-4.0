# Chip: Post-Test Cleanup (from Adam's first full device test)
Read repo peezy-conventions-v2.md, peezy-execution-protocol.md, peezy-v1-architecture.md. Model: Fable 5 or Sol, xhigh. Autonomy: A CORE (routing + resolver contract), B–F PERIPHERY. Deploys: resolveProvider only (Phase B). All copy marked LOCKED is final — do not paraphrase.

## Phase A: Blockers + routing (CORE)

**A1. Flow exit — LAUNCH BLOCKER.** No task flow has an exit affordance; an accidentally-opened flow can only be escaped by force-quitting. Add a persistent X (top-trailing, standard iOS placement, 44pt target, `flow.exit` identifier) to FlowEngineView AND every custom flow (movers, insurance ×2, cleaners, internet, sell, remove, truck, in-app tasks). Behavior: no answers recorded → dismiss immediately. Answers recorded → confirmation dialog, title "Leave this task?", body (LOCKED): "Your answers are saved. Pick up where you left off anytime." Buttons: "Leave" / "Keep going". Dismissal returns to the originating tab. Per-step persistence already exists (Spec 04) — verify resume lands on the saved step.

**A2. Explainer before signup.** Move ExplainerView ahead of authentication in AppRootView's state machine: unauthenticated + explainer unseen → ExplainerView → auth. Keep the `peezy.explainer.seen` UserDefaults key (device-scoped, pre-auth by design). Card 5 copy changes to point at signup instead of the assessment — replace its body with (LOCKED): "Make an account and we'll build your plan. It takes about a minute — and it's the last time you'll have to think about any of this." Kicker/title unchanged. No auth code changes; routing only. Do NOT touch SIWA/AuthViewModel internals (compliance).

**A3. Dose-complete empty state.** When the frozen dose is complete, the card stack renders NO card — the done-for-today message becomes the empty state itself (existing LOCKED copy: "That's today." / "You're on pace for {moveDate}."), styled per Phase D. Get-ahead affordance is retained but must read as secondary, not as a remaining task.

**A4. Snoozed visibility (no new tab).** In the Tasks tab, add a "Snoozed" section (or filter chip — implementer's call, cite which and why) showing snoozed tasks with their return date. Four tabs stay four tabs.

## Phase B: Resolver intent (CORE, one deploy)

The resolver currently receives a company name only. Pass the TASK'S INTENT alongside it — derived from the task itself and move context, never asked of the user (the assessment already determined it: MANAGE_GYM on a long-distance move = cancel; local = update/transfer). Add `intent` to the resolveProvider payload (enum: cancel | updateAddress | transferLocation | transferRecords | closeAccount — extend as the catalog requires; cite the task→intent mapping table in the report).

Response gains a `requirements` array: notice periods, certified-mail or in-person-only rules, contract-vs-month-to-month distinctions — each requiring a fetched citation, same invariant as URLs (unverifiable → omit the requirement and downgrade to concierge; NEVER state an unverified policy). Client renders requirements as a short list under the action, and when a notice period is present, checks it against the user's move date and surfaces one line (LOCKED pattern): "This one needs {n} days' notice — do it by {date} to be clear before your move." Cache key becomes company + intent.

**Acceptance:** a gym cancellation and a gym address-update on the same company return different paths (evidence); a notice-period requirement renders the date line computed from the identity doc's move date; an uncitable requirement never renders; cache hit on second identical request.

## Phase C: One question per screen (PERIPHERY)

The moving-questions form (scrolling multi-field) becomes one question per screen following the assessment pattern, rendered through the flow engine's existing step model where possible. Same for any other multi-field scrolling form surfaced in a flow — inventory the flows first, list every scrolling form, convert all of them, cite the list.

## Phase D: Visual system (PERIPHERY)

Adopt the explainer's visual language app-wide (it is the reference; read ExplainerView first): type scale, spacing, generous whitespace, card composition.

**D1. Question iconography.** Every assessment question and flow decision step gets ONE large Lucide icon, top-center above the headline. Icon per question defined in a single constants map. No illustrations, no multiple icons per screen.

**D2. Chapter accents.** Assessment chapters — "Your move" / "Your homes" / "Your people" / "Your accounts" (LOCKED names; map existing sections to these, cite the mapping) — each get a subtle accent tint applied ONLY to the question icon and the progress indicator. Screens stay predominantly white.

**D3. Chapter progress.** Replace the flat progress bar with a chaptered tracker: chapter name + position within it. Goal-gradient behavior preserved.

**D4. Option-tile icons** where options are concrete nouns (dwelling type, who's moving, rent/own, etc.). Skip where options are abstract (yes/no, dates).

**Acceptance:** full assessment run screenshotted; every question shows an icon; chapter label and accent change at each boundary; no screen requires scrolling to answer.

## Phase E: ISP screen (PERIPHERY)

NOT a carousel — research is against horizontal swiping for comparison tasks (comparing option B to A requires memory; vertical scrolling is more natural on mobile). Instead: show exactly THREE plan cards, full-width, sized so all three fit without scrolling (or the third clearly peeks). If more providers exist, curate to three by best-fit and add a "See other providers" affordance below. Reuse ComparisonCardView. Same three-card discipline as the mover screen.

## Phase F: Copy voice pass (PERIPHERY, two steps)

**F1.** Dump EVERY user-facing string that is not already LOCKED — subtext, helper text, empty states, button labels, error messages, confirmations — to `COPY_INVENTORY.md` with file, line, current text, and screen context. Do not rewrite anything in this step.
**F2.** STOP and report. Adam's Claude.ai session returns rewritten copy; a follow-up session applies it verbatim.

Reference voice (the explainer): one plain idea per line; sounds spoken, not written; no corporate register; no hollow superlatives; never over-explains.

## Files Summary
Modified: FlowEngineView + all custom flow views (A1), AppRootView + ExplainerView (A2), PeezyHomeView (A3), Tasks tab view (A4), functions/resolveProvider.js + ProviderDirectoryService (B), flow definitions/views (C), assessment views + PeezyTheme constants + progress component (D), SetupInternetFlow/ComparisonCardView (E). Created: icon/chapter constants maps, COPY_INVENTORY.md. Deployed: functions:resolveProvider only.

## Delegation Prompt
```
cd ~/Desktop/Peezy 4.0/. Read peezy-conventions-v2.md, peezy-execution-protocol.md,
peezy-v1-architecture.md, then peezy-chip-post-test-cleanup.md. Execute Phases
A→F in order. A and B are CORE: walked diffs, separate commits, validators against
the acceptance lines. A1 is a launch blocker — verify the exit works from every
flow type. Phase F stops after the inventory dump; do not rewrite copy. Only
sanctioned deploy: functions:resolveProvider. STOP on anything not covered.
Investigate and execute.
```
(Codex variant: standard no-hooks self-enforcement block; read CLAUDE.md.)
