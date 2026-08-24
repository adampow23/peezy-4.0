# Phase B — Resolver intent report

## Locked task → intent mapping

| Caller / flow | Task and move context | Resolver intent |
| --- | --- | --- |
| `financial_accounts` | every provider row | `updateAddress` |
| `memberships` | local move | `transferLocation` |
| `memberships` | long-distance move | `cancel` |
| `manage_vet` | `business_name` address path | `updateAddress` |
| `manage_vet` | `current_business` record path | `transferRecords` |
| `transfer_pharmacy_records` | `business_name` address path | `updateAddress` |
| `transfer_pharmacy_records` | `current_business` record path | `transferRecords` |
| auto/home insurance custom flows | address-update path | `updateAddress` |
| Current catalog | no current caller | `closeAccount` accepted but unused |

Intent is derived from task identity, step identity, and `UserState.isLongDistance`; it is never asked of the user.

## Acceptance evidence

- **B1.1 — PASS.** `ProviderIntent` contains the five locked values. `FlowEngineView` derives it from workflow, step, and `FlowInputs.isLongDistance`; both insurance custom flows pass `updateAddress` directly. `functions/validateResolveProvider.js` proves one in-memory `Example Gym` record returns different exact-cited URLs for `cancel` and `updateAddress`. The deployed live matrix also returned distinct cited paths for Life Time: its cancellation help page for `cancel`, and its account page for `updateAddress`.
- **B1.2 — PASS.** `resolveProvider.js:104–173` validates requirement kind, text, HTTPS citation, exact membership in fetched citations, and notice-day bounds. Any invalid requirement returns concierge with an empty `requirements` array. `ProviderDirectoryService.swift` repeats that boundary before the client can construct a `ProviderResolution`. The deterministic harness covers uncited, invalid-day, and unknown-kind requirements; none survives.
- **B1.3 — PASS.** `ProviderActionCard.swift:56–69` subtracts `noticeDays` from the identity move date and emits the locked sentence. `ProviderActionCard.swift:277–305` obtains that date from `IdentityService.loadOrMigrate`. The DEBUG fixture uses an identity move date of September 30, 2026 and visibly renders: `This one needs 30 days' notice — do it by Aug 31, 2026 to be clear before your move.` Screenshot: `/tmp/peezy-phase-b-provider.png`.
- **B1.4 — PASS.** `resolveProvider.js:314–359` uses `resolved_{normalized company}_{intent}`, reads the directory before search, and stores intent plus intent-specific URL field. The deterministic harness proves different intent document IDs and exactly one search across two identical calls. The deployed live matrix verified the intent-keyed Regions Bank document and an identical second response.
- **B1.5 — PASS.** The mapping table above is implemented at `FlowEngineView.swift:406–432`, `TaskFlowRouter.swift`, and both insurance flows. Resolver intent is not exposed as a question.
- **B1.6 — PASS.** The only deployment command was `firebase deploy --only functions:resolveProvider`. Firebase reported `functions[resolveProvider(us-central1)] Successful update operation`; no rules, seed, or other function deployment ran.

Validation commands and artifacts:

- `node functions/validateResolveProvider.js` — PASS.
- `xcodebuild … build` against an isolated non-Git source copy — `** BUILD SUCCEEDED **`; log at `/tmp/peezy-phase-b-build.log`. The isolated copy avoided the desktop Git scanner blocking on iCloud placeholders. Reported warnings were pre-existing Identity, FrameExtraction, and Crashlytics warnings outside Phase B.
- iPhone 17 Pro / iOS 26.5 DEBUG fixture — PASS; screenshot at `/tmp/peezy-phase-b-provider.png`.
- Independent validator — B1.1–B1.5 PASS and safe to deploy; post-deploy B1.6 confirmed by Firebase output.
- Post-deploy live matrix — authenticated rules boundary, invalid intent rejection, seeded result, unseeded cited result, company+intent cache, same-gym distinct intent paths, and negative concierge fallbacks all PASS.

## Walked diff

- `functions/resolveProvider.js` — request validation, intent-specific lookup/search/cache fields, strict requirement sanitizer, and company+intent cache ID.
- `functions/validateResolveProvider.js` — deterministic server boundary tests, including same-company paths, invalid requirements, legacy company-only cache rejection, cache identity, and second-request hit.
- `functions/liveValidatePhaseB.js` — deployed callable/rules/cache/intent safety matrix.
- `ProviderDirectoryService.swift` — typed intent and requirements, intent-aware direct records and callable payload, and a second exact-citation requirement boundary.
- `FlowEngineView.swift`, `TaskFlowRouter.swift`, `FlowEngineHarness.swift` — task/step/distance intent derivation and move-context plumbing.
- `HandleAutoInsuranceFlow.swift`, `HandleHomeInsuranceFlow.swift` — explicit `updateAddress` intent.
- `ProviderActionCard.swift` — short requirement list and identity-date notice line.
- `PeezyV1App.swift` — DEBUG-only deterministic UI fixture used by the simulator acceptance check.
- `PHASE_MANIFEST`, `PHASE_B_REPORT.md` — locked acceptance and evidence.

## Deploy

Deployed only `functions:resolveProvider` to `peezy-1ecrdl` in `us-central1`. The deployed `resolveProvider.js` SHA-256 was `22ba201b7d9bba674c187501a2986ab44f528739e5a0374a7a80e837607578f0`, byte-identical to the repository source at deploy time.
