# Chip: Measurement Layer (pre-launch)
Small session. Prereq for every post-launch optimization decision — without it, launch produces no data. Read repo peezy-conventions-v2.md + peezy-execution-protocol.md. Autonomy: PERIPHERY. No new SDK beyond Firebase's own modules (already in the project). Nothing deploys.

## Why
The app currently emits zero analytics and no crash reporting. Ship this before launch so day-one data exists; retrofitting means the first cohort is unmeasurable forever.

## Phase A: Crashlytics
Add FirebaseCrashlytics (SPM module of the existing Firebase package — do NOT touch project.pbxproj; if the module cannot be added without it, STOP and report the exact Xcode steps for Adam). Initialize alongside existing Firebase config. Add a non-fatal log at the three known silent-failure points (any caught-and-swallowed Firestore write): assessment save, identity save, workflow submission — `Crashlytics.crashlytics().record(error:)` in the existing catch blocks, no behavior change.
**Acceptance:** a forced test crash appears in the Crashlytics console (evidence: console screenshot or API read-back); build clean; no behavioral diffs.

## Phase B: Funnel events (Firebase Analytics)
Log exactly these, no more (event-name constants in one file, `AnalyticsEvents.swift`):
1. `explainer_complete`
2. `assessment_start`
3. `assessment_complete` (param: questionCount)
4. `dose_first_complete` (first-ever completed task)
5. `dose_day_complete` (param: dayNumber)
6. `scan_complete` (param: itemCount, cubicFeet)
7. `packing_plan_created`
8. `paywall_view` (param: trigger — "post_assessment" | "book" | "kit" | "concierge")
9. `paywall_convert` (param: trigger, productId)
10. `booking_submit` (param: vertical, isQuoteRequest)
11. `kit_offer_view` / `kit_order` (param: itemTotal)
12. `checkin_complete` (param: flagged bool)

Rules: no PII in any parameter (no names, addresses, emails, phone). Fire at the moment of the state change, in the service layer where possible — not in view bodies (which can re-render). Free tier is unlimited for these; do not add custom user properties beyond `has_subscription`.
**Acceptance:** DebugView (or a logged-event dump) shows each event firing once during a full simulated journey — fresh install → explainer → assessment → scan → dose → paywall → booking → check-in (evidence: event list per step); grep proves no PII parameters.

## Phase C: Doc sync
Conventions gains an "Analytics" section: the event list, the no-PII rule, and the reminder that new surfaces add events at the same service-layer boundary. Update LAUNCH_CHECKLIST (measurement item → done). Update PrivacyInfo.xcprivacy if analytics collection requires a declaration — cross-check with the existing PrivacyInfo launch-checklist item and note whether they can close together.

## Delegation Prompt
```
cd ~/Desktop/Peezy 4.0/. Read peezy-conventions-v2.md, peezy-execution-protocol.md,
then peezy-chip-measurement.md. Execute Phases A→C. PHASE_MANIFEST at start.
Nothing deploys. Do not modify project.pbxproj — if SPM module addition requires
it, STOP and report the Xcode steps. Validator runs the acceptance list.
Investigate and execute.
```
(Codex variant: standard no-hooks block; read CLAUDE.md.)
