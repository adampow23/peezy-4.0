# Peezy Copy Rewrite — apply verbatim
Source: copy inventory triage (750 entries). Verdict summary: most of the catalog, flow-definition, and packing/mover strings are already in voice — LEAVE UNTOUCHED. This file contains only changes. Where a string exists in BOTH AssessmentCoordinator.swift and a question-view file, both locations are listed and BOTH must change (verify which renders; change both regardless).

## Global rules (apply everywhere they match)

**G1 — One narrator: "we", never "I".** Peezy speaks as we. Every first-person-singular string changes (specific rewrites below cover the known instances; grep `I'll ` and `I'm ` in user-facing strings to catch strays — EXCLUDE peezyBrain.js, which is an orphaned chat persona, and the ProviderActionCard call scripts, where "I" is the USER speaking on a phone call: correct as-is).

**G2 — The multi-select helper (3 instances + 3 view duplicates).** AssessmentCoordinator 599, 605, 611 + FinancialInstitutions.swift:6, HealthcareProviders.swift:6, FitnessWellness.swift:6:
OLD: "Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you."
NEW: "Tap everything you have. More than one of something? Tap it once per account — we track each one separately."

**G3 — The response-time line (~15 instances across flowDefinitionsData.json and Swift flows).**
OLD: "Response times are typically 24–48 hours."
NEW: "Expect word back within 24–48 hours."

**G4 — Swipe → tap (5 instructions in miniAssessmentWorkflows.js: lines 27, 114, 205, 274, 364, 450).** Replace "Swipe right if you have this[…], left if you don't." pattern with: "Tap yes for everything you have — no if you don't." Line 27's variant becomes: "Tap yes for each account you have — we'll grab names after." ⚑ FLAG: these referenced swipe gestures, which were removed from the product months ago. Verify what the mini-assessment UI actually renders; if it truly swipes, that's a design bug to report, not a copy fix.

## Targeted rewrites

| Location | Current | New |
|---|---|---|
| Coordinator:401 | When are we moving? If it's not 100% official yet, just drop your best guess below! | When are we moving? Not official yet? Your best guess works. |
| Coordinator:417 | This helps me figure out things like lease breaks, security deposits, or listing prep. | This tells us whether we're dealing with lease stuff, deposits, or listing prep. |
| Coordinator:429 + CurrentAddress:10 | I'll use this for mail forwarding, utilities, change of address—all the stuff you'd normally have to chase down yourself. | This powers your mail forwarding, utilities, address changes — all the stuff you'd normally chase down yourself. |
| Coordinator:434 and :478 | What's access like? | What's the access like? |
| Coordinator:473 + NewAddress:10 | Same deal—I'll use it to get utilities, internet, and everything else set up before you even walk in the door. | Same deal — this is how utilities, internet, and everything else get set up before you walk in. |
| Coordinator:490 | Are there any items in storage that will be making the move as well? | Anything in a storage unit making the move too? |
| Coordinator:522 | Will any children be making the move with you? | Any kids making the move with you? |
| Coordinator:546 | Will any vehicles be moving with you? | Any vehicles coming along? |
| Coordinator:555 + ServicesIntro:11 | We'll ask about services you're planning to hire or even just interested in receiving quotes from — movers, packers, cleaners, and more. | Movers, packers, cleaners — tell us who you're hiring, or just curious about, and we'll line up the quotes. |
| Coordinator:579 | We can assist with that process as well as plan b if they don't sell. | We'll help you sell — with a plan B ready for anything that doesn't. |
| Coordinator:584 | And for the final deep clean of your current home, would you like to get some quotes for professional cleaners? | Want quotes for the final deep clean of your current place? |
| Coordinator:593 + AddressChangeIntro:11 | You'll need to update your address with certain companies. We can help with that — and if you need to cancel something or find a new provider, we've got you covered. | Banks, doctors, memberships — they all need your new address. We'll handle the updates, the cancellations, and finding new ones near you. |
| Coordinator:598 + FinancialInstitutions:5 | Let's start with finance related accounts you might have. | First up: the money accounts. |
| Coordinator:610 + FitnessWellness:5 | And lastly, do you have any wellness-related memberships? | Last one: any gyms, studios, or wellness memberships? |
| AssessmentIntroView:55 | Just a quick 90 second setup | A few minutes of questions — then we take it from here. |
| GeneratingView:34 | Checking logistics requirements... | Mapping your deadlines... |
| GeneratingView:35 | Evaluating your household needs... | Factoring in your household... |
| GeneratingView:37 | Matching vendor categories... | Lining up the right help... |
| ReadyView:60 | We've organized everything you need for a smooth move. | Every task you need, none you don't — ordered by deadline. |
| SignUpView:46 | Sign up to get started with Peezy | Make your account — your plan is next. |
| QuoteSelectionFlow:142 | Tap an option to select it. You can always change your mind. | Tap one. You can change your mind anytime. |
| InAppTaskFlows:205 | Is this the real date? | Is this date locked in now? |
| TaskActionService:658 | A final readiness record protects the estimate and explains avoidable overages. | This record is what keeps your estimate honest if move day runs long. |
| MoversCaptureCard:30 | A room-by-room scan gives every company the same scope. If video isn't an option, home details still produce a wider estimate range. | A quick scan gives every company the exact same job to price. No video? Home details work too — the range is just wider. |
| miniAssessment:204 | Insurance companies need your new address - rates can change by location! | Insurers need the new address — rates change by ZIP. |
| miniAssessment:449 | Let's make sure nothing gets delivered to your old address! | Let's make sure nothing keeps landing at the old address. |

## Flagged for Adam (not rewritten — decisions needed)

1. **Coordinator:618 — the referral question: DELETE (Adam-approved).** Remove the question view, its coordinator step, and its dict key in the same commit (per the eab4193 lesson: views, keys, and any conditions retire together — grep the catalog to confirm nothing references it). Assessment shortens by one screen.
2. **PaywallGateView:52–129 — untouched.** Launch monetization is the shipped Peezy+ subscription (Adam-confirmed); this copy is current and compliance-frozen.
3. **InventoryFlowView:228 — untouched.** AI-disclosure/privacy block from an App Store fix. Frozen.
4. **peezyBrain.js strings — untouched.** Orphaned function; gets a pass if/when card chat ships in v1.1.
5. **G4's swipe references** — copy fixed either way; the session MUST verify what the mini-assessment UI actually renders and report a design bug if it truly swipes.

## Everything else: KEEP AS-IS
Explicitly reviewed and left alone for being already in voice: the entire taskCatalogData.json desc/tips/whyNeeded set, the flowDefinitions bodies (except G3 instances), all packing-plan and readiness strings, mover comparison/confirmation copy, TasksList empty states, dose greetings, provider call scripts, support auto-acknowledgment, all short factual errors, and every LOCKED line.

## Application instructions (for the agent session)
Apply G1–G4 and the table verbatim — zero paraphrasing, zero additional "improvements" to neighboring strings. For coordinator+view duplicate pairs, change both. After application: build, run the full assessment + one manage-provider flow + the mover flow in the simulator, screenshot each changed screen, and grep-verify no instance of the OLD strings remains (excluding flagged items). Deploy functions ONLY if miniAssessmentWorkflows.js or flowDefinitionsData.json changed (reseed/redeploy per their existing patterns).
