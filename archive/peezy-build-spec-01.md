# Peezy v1 Build — Spec 01: Harness, Explainer, Identity
Prereqs: peezy-conventions-v2.md and peezy-v1-architecture.md at project root, read in full before any phase. Dead-code deletion (DEAD_CODE_REMOVAL_LIST.md) done by Adam in Xcode. Tree clean.

Model: Fable 5, launched `claude --effort xhigh`. Phases run in order; commit per phase; `git diff` review closes every phase (LE-032).

## Boundary constraints (all phases)

> Don't add features, refactor, or introduce abstractions beyond what the task requires. Don't design for hypothetical future requirements: do the simplest thing that works well. Don't add error handling, fallbacks, or validation for scenarios that cannot happen.

> Before reporting progress, audit each claim against a tool result from this session. Only report work you can point to evidence for; if something is not yet verified, say so explicitly.

> You are operating autonomously. The user is not watching in real time. For reversible actions that follow from the original request, proceed without asking. Before ending your turn: if your last paragraph is a plan, a question, or a promise about undone work, do that work now with tool calls.

Environment repair (missing simulators/platforms/toolchains whose error prescribes its exact fix) — proceed and disclose. Anything touching the repo beyond the phase manifest — STOP and report.

---

## Phase 0: Harness

**0a. Hooks** — create `.claude/hooks/` with a PreToolUse hook enforcing:
- Write/Edit denied on: `project.pbxproj`, `GoogleService-Info.plist`, `functions/.env`, `Configuration.storekit`, everything under `Inventory/Camera/` (LE-005 region), `SubscriptionManager.swift`, `PaywallGateView.swift` (COMPLIANCE — Spec 04 lifts the PaywallGateView block for its one declared edit)
- Write/Edit denied on any file NOT in the current phase's manifest (manifest = a `PHASE_MANIFEST` file the session writes at phase start, listing intended paths; the hook reads it)
- Stop hook: `xcodebuild` must have succeeded in-session before the agent may end its turn on any phase that modified Swift

**0b. CLAUDE.md regeneration** — replace both stale variants with one root CLAUDE.md generated from peezy-conventions-v2.md: corrected facts, key-file table, frozen regions, contract facts, environment notes, and the boundary-constraint block above verbatim. Delete the Documents/ variant's stale key-file claims. Audit CLAUDE.md wording for any instruction telling the model to echo or explain its internal reasoning as response text — rephrase to "report actions and evidence" (Fable 5 refusal-category avoidance).

**0c. Accessibility convention** — add to CLAUDE.md: every new view element that a user can tap, read as a result, or that represents state MUST carry `.accessibilityIdentifier("<area>.<element>")`. Non-negotiable; the stop hook greps new Swift files for at least one identifier per View struct.

Manifest: `.claude/hooks/*`, `CLAUDE.md`, `PHASE_MANIFEST`. Nothing else.

---

## Phase 1: Onboarding explainer (greenfield — complete files below)

Five tap-through cards shown after auth, before assessment question 1, once per user (`UserDefaults` key `peezy.explainer.seen`; also skipped if assessment already complete). Visual language: existing PeezyTheme + InteractiveBackground (both hubs, read-only consumption). Copy is LOCKED — do not rewrite it.

**New file `MainInterface/Views/Onboarding/ExplainerView.swift`:**

```swift
import SwiftUI

/// Five-card tap-through shown once, post-auth, pre-assessment.
/// Copy is locked per peezy-v1-architecture.md §9. Do not edit strings.
struct ExplainerView: View {
    let onFinished: () -> Void
    @State private var index = 0

    private let cards: [ExplainerCard] = [
        .init(
            kicker: "LET'S BE HONEST",
            title: "Moving is a nightmare.",
            body: "You've done it before. The endless list, the calls, the things you find out too late. Nobody enjoys this."
        ),
        .init(
            kicker: "HOW PEEZY WORKS",
            title: "One thing at a time.",
            body: "Peezy tells you exactly what to do and when. No giant checklist staring at you. Open the app, do the thing, done."
        ),
        .init(
            kicker: "ON PURPOSE",
            title: "No feeds. No badges. No fluff.",
            body: "Peezy is plain by design. Every screen exists to get you through this move — not to keep you scrolling."
        ),
        .init(
            kicker: "THE REAL DIFFERENCE",
            title: "We do the parts you hate.",
            body: "Internet setup. Finding movers you can trust. Changing your address everywhere. Peezy handles it — you just approve."
        ),
        .init(
            kicker: "FIRST THINGS FIRST",
            title: "A few questions.",
            body: "They're how Peezy knows what's coming for your move — not someone else's. The more you tell us, the more we can take off your plate."
        )
    ]

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                ExplainerProgressDots(count: cards.count, index: index)
                    .padding(.top, 24)
                    .accessibilityIdentifier("explainer.progress")
                Spacer()
                ExplainerCardView(card: cards[index])
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .accessibilityIdentifier("explainer.card.\(index)")
                Spacer()
                Button(action: advance) {
                    Text(index == cards.count - 1 ? "Let's go" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(PeezyTheme.primaryColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .accessibilityIdentifier("explainer.next")
            }
        }
        .onTapGesture(perform: advance)
        .animation(.easeInOut(duration: 0.25), value: index)
    }

    private func advance() {
        PeezyHaptics.light()
        if index < cards.count - 1 {
            index += 1
        } else {
            UserDefaults.standard.set(true, forKey: "peezy.explainer.seen")
            onFinished()
        }
    }
}

struct ExplainerCard: Identifiable {
    let id = UUID()
    let kicker: String
    let title: String
    let body: String
}

private struct ExplainerCardView: View {
    let card: ExplainerCard
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(card.kicker)
                .font(.caption.weight(.bold))
                .kerning(1.5)
                .foregroundColor(PeezyTheme.secondaryTextColor)
            Text(card.title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(PeezyTheme.primaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
            Text(card.body)
                .font(.body)
                .foregroundColor(PeezyTheme.secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
    }
}

private struct ExplainerProgressDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= index ? PeezyTheme.primaryColor : PeezyTheme.secondaryTextColor.opacity(0.3))
                    .frame(width: i == index ? 24 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: index)
    }
}
```

**Adaptation rule (disclosed):** `PeezyTheme.primaryColor/primaryTextColor/secondaryTextColor` and `PeezyHaptics.light()` are the expected API per the map's hub inventory. READ `PeezyTheme` and `PeezyHaptics` first; if actual member names differ, adapt the references — nothing else. If `InteractiveBackground` takes required parameters, match the call pattern used in `AssessmentFlowView`.

**Integration — one edit in `AppRootView.swift`:** in the state machine (four-state gate at the map's §2.1), insert the explainer between authenticated and assessment states: if authed && !assessmentComplete && !UserDefaults `peezy.explainer.seen` → present `ExplainerView(onFinished:)` that flips local state to route into the assessment. READ AppRootView first; make the minimal insertion consistent with its existing state pattern. DO NOT restructure the state machine.

Verification: build; boot simulator via XcodeBuildMCP; fresh-install launch with test creds; screenshot each of the 5 cards + the transition into assessment question 1; confirm second launch skips the explainer.

Manifest: `ExplainerView.swift` (new), `AppRootView.swift`, `PHASE_MANIFEST`.

---

## Phase 2: Identity object

Architecture doc §4 is the contract. Sub-steps, committed separately:

**2a. Model + doc (greenfield).** New `MainInterface/Models/PeezyIdentity.swift`: the §4 struct, Codable, with `PeezyAddress {street, unit?, city, state, zip, raw}`. Includes `static func parse(addressString:) -> PeezyAddress` — port the 8413f2d parser logic from `UserState.swift` (READ it; it handles both AddressSearchManager formats) and extend it to retain the street component and raw string. New `IdentityService`: load/save `users/{uid}/identity`, plus `migrateIfNeeded()` — if the identity doc is absent but assessment data exists, build it from the newest `user_assessments` doc + Auth email/displayName and write it (one-time, per user, on launch).

**2b. Write path.** `AssessmentDataManager.completeAssessment` additionally writes the identity doc (READ :233-305 first; add alongside, do not restructure the existing persistence — user_assessments keeps writing for backend compatibility this phase). Firestore rules: add owner-only rule for `users/{uid}/identity` in local firestore.rules following the existing per-user pattern. NOT deployed — flag for Adam's reconcile-and-deploy batch.

**2c. Read path.** `UserState` rebuilt to load from the identity doc via `IdentityService` (falling back to migration): full-address fields replace the city/state stopgap; the 21 consumers compile-fix mechanically (most read `.name`/`.moveDate` — unaffected). The seven Type-3 flows and `requestConcierge` payload (PeezyHomeViewModel:445-446) now send full street addresses. DO NOT touch DailyDose math, loaders, or status writes in this pass.

**2d. Settings edits.** PeezySettingsView address/name edits write the identity doc (kills `.limit(to:1)` nondeterminism) and address edits recompute distance via the existing CLGeocoder path (READ AssessmentDataManager:236-280; extract that computation into IdentityService rather than duplicating it — this is the one sanctioned extraction).

**Deferred from §4, deliberately:** contract-rot key purge + catalog condition corrections (needs a catalog edit pass — Spec 02); phone collection (arrives with the first vendor flow — Spec 04); userKnowledge schema adoption (Spec 02, with the flow engine's server work).

Verification: build; fresh-install run — assessment completion produces an identity doc (inspect via Firestore emulator or logged read-back); existing-user run — migration produces it; a Type-3 flow screenshot showing a full street address in TaskFlowConfirmAddressCard; Settings address edit round-trips and updates moveDistance.

Manifest: `PeezyIdentity.swift` (new), `IdentityService.swift` (new), `UserState.swift`, `AssessmentDataManager.swift`, `PeezySettingsView.swift`, `AppRootView.swift`, `firestore.rules`, `PHASE_MANIFEST`.

---

## Files Summary
Created: hooks, PHASE_MANIFEST, ExplainerView.swift, PeezyIdentity.swift, IdentityService.swift. Modified: CLAUDE.md, AppRootView.swift, AssessmentDataManager.swift, UserState.swift, PeezySettingsView.swift, firestore.rules (local only). Deleted: stale Documents/CLAUDE.md variant. Deployed: NOTHING.

## Delegation Prompt
```
cd ~/Desktop/Peezy 4.0/. Read peezy-conventions-v2.md, peezy-v1-architecture.md,
then peezy-build-spec-01.md. Execute Phase 0, then 1, then 2 (2a-2d as separate
commits). Write PHASE_MANIFEST at each phase start. git diff review before every
commit. Verify per spec with XcodeBuildMCP screenshots. STOP on any condition
the spec doesn't cover. Investigate and execute.
```
