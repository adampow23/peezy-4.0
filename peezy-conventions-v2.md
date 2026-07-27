# Peezy Conventions v2 — Ground Truth
Supersedes peezy-conventions.md. Source: V1_ARCHITECTURE_MAP.md (audit @ f7e47ad, 2026-07-23) + implementation through Spec 08 Phase D (2026-07-27). Every fact below is code-verified unless explicitly labeled as remote evidence.

## Corrections to prior docs — READ FIRST

These four false premises appeared in peezy-conventions.md, the launch plan, and/or the autopilot skill. Any spec inheriting them is wrong:

1. **Paywall gate is post-assessment, not "after three completed tasks."** The three-task trigger does not exist anywhere in code (exhaustive grep). Current behavior: hard gate at CompletionFlowView.swift:52-58, dismissible via X (PaywallGateView:31-41), so the app is reachable unsubscribed. This is the reviewed-and-approved Review #3 behavior. Changing it is a product decision, not a bug fix.
2. **Four tabs, not three:** Home / Tasks / Chat / Settings. Chat = SupportChatView (live, T06-tested, Firestore-backed support chat). The *AI* chat was removed; support chat was not.
3. **Catalog v2 is 47 tasks (Spec 08).** actionType: workflow=32, off-app=8, in-app=6, in-app-inventory=1. taskType: survey=34, provide_info=13. 35 rows carry a workflowId, including scan_inventory. `MOVE_CHECKIN` and `BOX_RETURN` are the two post-move additions. `BUY_PACKING_SUPPLIES` remains retired; the Spec 06 `PACKING_*` tasks are generated per-user and catalog-external. Flow content lives in 25 Firestore `flowDefinitions` documents.
4. **WorkflowManager.swift does not exist.** TimelineService is dead (zero callers, deleted in cleanup). The live loading paths are exactly two: PeezyHomeViewModel.loadTasks() (Home, one-shot) and TasksStore listener → PeezyCardFirestoreMapper.card() (Tasks tab).

## Live data paths (the only two)

```
Home:      PeezyHomeViewModel.loadTasks() :219 → mapper :257  (one-shot query)
Tasks tab: TasksStore listener :51 → PeezyCardFirestoreMapper.card() :4  (snapshot)
```
Single-decoder rule (LE-025/LE-031 successor): both loaders call
`PeezyCardFirestoreMapper.card()`. Never add or re-inline a second
Firestore→PeezyCard decoder.

## Key files (current, verified)

| Area | File | Note |
|---|---|---|
| Entry | MainInterface/Models/PeezyV1App.swift | @main; injects SubscriptionManager.shared (only root env object) |
| Root gate | MainInterface/Views/AppRootView.swift | Builds UserState at :137 (only live construction site) |
| Container | MainInterface/Views/PeezyMainContainer.swift | 4 tabs |
| Home VM | MainInterface/Models/PeezyHomeViewModel.swift | Thin VM; DailyDoseEngine owns the daily freeze and routing uses workflowId ?? lowercased taskId |
| Router | MainInterface/Models/TaskFlowRouter.swift | Thin resolver; BOOK_MOVERS routes to the full custom mover spine |
| Flow engine | Tasks/FlowEngine/ | Firestore definitions, component renderer, in-app flows, capture registry, DEBUG harness |
| Card model | MainInterface/Models/PeezyCard.swift | Memberwise Equatable; stage/payload fields; pending and matching_in_progress statuses |
| Vendor data | MainInterface/Models/Vendor.swift + functions/vendorsData.json | Backend-owned vendor/rate-card schema; active filter; strike-array decode with legacy numeric compatibility; three placeholder mover records |
| Vendor accountability | functions/accountabilityLadder.js + functions/submitCheckIn.js + docs/vendor-standards.md | Pure confirmed-strike ladder, transactional review/strike write, active removal reconciliation, and vendor-facing standards |
| Pricing | MainInterface/Models/PricingEngine.swift + PricingConstants.swift + MoveScopeFactory.swift | Pure rate-card math, centralized LOCKED-pending-calibration constants, scope adapter |
| Movers spine | MainInterface/Models/MoversFlowViewModel.swift + Tasks/Task Cards/FindMoversFlow.swift | Capture/reuse through booking confirmation |
| Packing plan | MainInterface/Models/PackingPlanEngine.swift + PackingConstants.swift | Pure locked-order reverse scheduler, completion preservation, overdue reflow, and pace compression flag |
| Packing persistence | MainInterface/Models/TaskActionService.swift | `packingPlan/current`, generated session/kit/gate tasks, `readiness/current`, and completion writes |
| Supplies kit | MainInterface/Models/KitEstimator.swift + Tasks/Task Cards/SuppliesKitView.swift | 12% box headroom, placeholder bundle pricing, one customization sheet, and concierge order |
| Readiness gate | MainInterface/Models/ReadinessGate.swift + Tasks/Task Cards/PackingReadinessView.swift | T−1 evidence checklist with reserve-access prefill and nonblocking consequence copy |
| Post-move check-in | MainInterface/Models/CheckInService.swift + Tasks/Task Cards/MoveCheckInView.swift + functions/submitCheckIn.js | Four factual answers, optional note, durable vendorReviews write, deterministic flags, and best-effort SMS |
| Box return | MainInterface/Models/BoxReturnService.swift + Tasks/Task Cards/BoxReturnView.swift | Durable ordered-kit count → `kitCalibration` round trip; optional existing-concierge pickup |
| User knowledge | MainInterface/Models/UserKnowledgeService.swift + functions/contextBuilder.js | Merge-only `{entries:{key:{value,source,updatedAt}}}` writer and assistant-context flattening |
| Provider resolver | MainInterface/Models/ProviderDirectoryService.swift + functions/resolveProvider.js + providerDirectoryData.json | 46-entry backend-owned directory; exact-citation URL boundary; web-search fallback and resolved cache |
| ISP plans | MainInterface/Models/ISPPlanService.swift + Tasks/Task Cards/SetupInternetFlow.swift + functions/ispPlansData.json | Five curated Firestore cards; pending-affiliate provider fallback; no address-level serviceability claim |
| Identity | MainInterface/Models/UserState.swift | Address parse fixed 8413f2d (city/state only); full rebuild in v1 |
| StoreKit | MainInterface/Models/SubscriptionManager.swift | COMPLIANCE — port verbatim, never touch |
| Paywall | MainInterface/Views/Paywall/PaywallGateView.swift | COMPLIANCE — Review #3 fix lives here |
| Flow kit | Tasks/Task Card Components/ (17 hubs) | Renderer library for the config-driven engine |
| Flow screens | Tasks/Task Cards/ | Remaining custom flows, capture flow, and mover stage views |
| Submission | MainInterface/Models/WorkflowService.swift | LE-029 callable pattern; 11 live construction call sites across 10 Swift files |
| Parser | TaskConditionerParser.swift | AND keys / OR values / strict-cast fail-false :69-74 |
| Generation | TaskGenerationService | NSNumber cast canonical at :73 |
| Inventory | Inventory/ + functions/processInventory.js | Pipeline frozen regions below |

## Frozen regions (never modify)

- CameraPreviewView.swift:12-31 — layerClass AVCaptureVideoPreviewLayer wrapper (LE-005)
- No sharpness filtering, ever (LE-006). Dead remnants: sharpnessScore field, hardcoded 1.0
- SubscriptionManager / PaywallGateView pricing: all price + trial text from live Product objects, never hardcoded (LE-026)
- SIWA first-auth name capture: AuthViewModel.handleAppleSignInCompletion:92-98 (Guideline-4 fix)
- AI disclosure copy + privacy link: InventoryFlowView ~:207-209 (privacy objection fix)
- env-object re-injections at AssessmentFlowView:59 and CompletionFlowView:102 (LE-023 crash fix — fullScreenCover does not inherit)
- ObservableObject stays ObservableObject on: AssessmentCoordinator, AssessmentDataManager, AuthViewModel, SubscriptionManager (LE-007)
- deleteAccount is server-side Admin SDK — no client re-auth, by design
- project.pbxproj, GoogleService-Info.plist, functions/.env — hook-blocked

## Contract facts a new client must honor

- Zero client-side webhook URLs. Mover booking and quote-request payloads first land in the Firestore workflowSubmissions audit, then submitWorkflowAnswers attempts a direct best-effort Twilio SMS. Booking notify = direct Twilio SMS; env vars in functions/.env (Adam-owned). A missing Twilio value logs `SMS notify not configured` without failing the submission
- Server task-doc statuses `pending` and `matching_in_progress` both have TaskStatus cases. `pending_matching` exists only on workflowSubmissions docs
- submitWorkflowAnswers response omits submissionId/message/estimatedResponseTime; client defaults mask it
- Packing plans persist at `users/{uid}/packingPlan/current`. `PACKING_SESSION_n`, `PACKING_SUPPLIES_KIT`, and `PACKING_READINESS_GATE` are engine-generated user task docs, not catalog rows; readiness evidence persists at `users/{uid}/readiness/current`
- Inventory or move-date changes regenerate packing work while preserving completed source groups. Overdue reflow leaves the stable readiness gate at moveDate−1. The frozen daily dose admits at most one packing session and, on T−1, places readiness after packing
- Until a supplier signs, `supplies_kit` uses the existing concierge submission: complete kit + identity payload, `matching_in_progress` task status, and `PEEZY KIT ORDER: ...` SMS or the exact `SMS notify not configured` fallback log
- Catalog rows may carry `surfaceAfterDaysPastMove`; a row with that field cannot join a frozen dose without a move date or before moveDate + n. `MOVE_CHECKIN` uses +1. `BOX_RETURN` uses +7 and generation refresh additionally requires a durable `supplies_kit` workflow response
- `submitCheckIn` writes backend-owned `vendorReviews` as `{vendorId?, userId, answers, flags, submittedAt}`. General reviews use `vendorId:null`. Negative facts produce deterministic flags and exact SMS-family messages `PEEZY FLAG: {vendor} — {flag}.`; notification failure never rolls back the review
- Vendor accountability persists `accountability.strikes` as an array of `{date, source, severity, status, note}`. Legacy numeric strikes decode safely. Confirmed-count ladder: 1 conversation, 2 warning, 3 removal; any confirmed `dayOfPriceChange` removes immediately. Removal means `active:false`, which excludes the vendor from comparison
- `BOX_RETURN` derives delivered from the exact durable `supplies_kit` submitted JSON, stores `kitCalibration:{delivered,returned}` on `users/{uid}`, and reads it back before reporting success. Pickup reuses `requestConcierge` only when toggled with returned > 0; the estimator is intentionally unchanged
- `userKnowledge/{uid}` is client-owned. Assessment, Settings, and in-app task writes merge `{entries:{key:{value,source,updatedAt}}}` through `UserKnowledgeService`; `contextBuilder.js` flattens that same shape. Empty-value calls are not a supported write contract
- `providerDirectory` and `ispPlans` are backend-owned collections: authenticated clients may read them and may not write them. `resolveProvider` is authenticated and is the only runtime writer to resolved directory entries
- No resolver payload may contain `url` unless its exact normalized HTTPS URL appears in the same payload's citations. Only high-confidence cited results are cached as `source: resolved`, `verified: false`; all other resolver outcomes are URL-free concierge
- Firestore numbers: NSNumber cast pattern everywhere; no unguarded `as? Int`
- Client-readable/backend-owned paths include taskCatalog, flowDefinitions, vendors, providerDirectory, and ispPlans. Client-owned paths include users/{uid}/tasks, user_assessments, identity, packingPlan, readiness, workflowResponses, userKnowledge, inventory, inventorySessions, and supportChat. Vendor, definition, provider-directory, and ISP-plan writes remain backend-only

## Lessons that map to nothing (do not re-apply)

- 0.3s auto-advance chain — system removed in 089749b; advance is immediate
- cancelWorkflow/onWorkflowDismissed — WorkflowManager gone

## Environment

- Root: ~/Desktop/Peezy 4.0/ (source in nested "Peezy 4.0/"); never run from Documents/ (LE-001)
- `unset CLAUDECODE` if nesting sessions (LE-002); macOS bash is 3.2 (LE-018)
- Xcode 26.6: iOS platform + Metal toolchain must be installed (xcodebuild -downloadPlatform iOS / -downloadComponent MetalToolchain)
- Deployed Firestore rules are not readable via firebase-tools 15.6.0; use the Rules REST API with functions/serviceAccountKey.json (read-only). **Remote evidence (Spec 07 Phase B acceptance):** the one approved rules deploy retained the reconciled waitlist rule and added authenticated read/no-client-write blocks for providerDirectory and ispPlans
- Test creds: peezy-test-bot@test.peezyapp.com / PeezyTest2026!
- Accessibility ids: 236 usages in 45 Swift files at Spec 08 close. **All new views require .accessibilityIdentifier() — mandatory convention**

## Corrections from Spec 08 run (2026-07-27)

- **Catalog v2 now has 47 rows.** `MOVE_CHECKIN` (+1 day) and `BOX_RETURN` (+7 days, kit-purchase refresh gate) are normal catalog rows; generated `PACKING_*` work remains catalog-external. The sanctioned catalog reseed round-tripped every JSON-declared field and found no ghosts.
- **The verify layer is live.** The check-in callable stores factual reviews before notification, creates pending high strikes only for price-overage/damage flags, and reconciles already-confirmed strikes whenever it touches the vendor. Adam's MVP confirmation path is Firebase Console → `vendors/{vendorId}` → `accountability.strikes`; when confirming a removal state, set sibling `active=false` in the same document.
- **Console-only status edits cannot invoke server code.** The pure transition is unit-tested and `submitCheckIn` reconciles the array transactionally, but there is no sanctioned Firestore trigger. Adam must set `active:false` alongside a console confirmation that reaches removal.
- **Box returns calibrate against the placed order, not a fresh estimate.** Delivered count is read from the durable `supplies_kit` response, returned count round-trips through `users/{uid}.kitCalibration`, and optional pickup reuses the already-deployed concierge callable.
- **The seeder omission was real and is closed.** `seedTaskCatalog.js` now writes `estPeezy` and verifies every JSON-declared field rather than a small projection.
- **The launch audit supersedes scattered open-item lists.** `LAUNCH_CHECKLIST.md` is the canonical owner/status/close-path ledger. It records live state: one unreviewed resolved provider, three active Test Movers, five pending ISP links, and no `ADAM_NOTIFY_NUMBER`.
- **Spec 08 deployment scope stayed bounded.** Remote mutations were exactly `functions:submitCheckIn` plus the task-catalog reseed. Phase B redeployed only that same callable; Phases C/D deployed nothing. The SMS family did not change, so `submitWorkflowAnswers` was not deployed.

## Corrections from Spec 07 run (2026-07-27)

- **userKnowledge now matches the backend contract.** All four client write paths use `UserKnowledgeService` to merge entry envelopes with a source and server timestamp; `contextBuilder` reads the same shape. The old “client writes flat dict / greenfield” note is retired.
- **The provider directory contains 46 seeded providers.** Its current mix is 28 cited links, one cited call, and 17 concierge records. Name/alias matching is category-constrained so an identically named provider in the wrong vertical cannot escape the resolver boundary.
- **Citation safety is enforced in one outbound sanitizer.** `resolveProvider` never returns a URL unless the exact HTTPS URL is present in its cleaned citations. High-confidence cited results write through as unverified `source: resolved` records; medium/low, fake, malformed, timeout, and failure results return URL-free concierge.
- **The resolver's original default model had retired.** **Remote evidence (Spec 07 Phase B acceptance):** the sanctioned function target was corrected to the current pinned `claude-sonnet-4-6`; live unseeded resolution then returned a cited path and cached it successfully. Future callable work must verify configured model availability before deployment.
- **ISP cards are curated candidates, not serviceability results.** Five backend-owned `ispPlans` documents drive `SETUP_INTERNET`. Every current affiliate value is `#AFFILIATE_PENDING`; the client logs this and opens the HTTPS provider URL. Exact-address qualification remains v1.1.
- **Spec 07 deployment scope stayed bounded.** **Remote evidence (Spec 07 Phase B/C acceptance):** mutations were limited to the single approved rules diff, the `resolveProvider` function target, the 46-provider seed, and the five-plan ISP seed. No broad functions deploy, catalog seed, or other rules deploy occurred.
- **Live simulator verification requires installing the newly built app.** **Remote evidence (Spec 07 Phase C acceptance):** the booted simulator initially held an older binary; after installing the current build, the ISP cards, canonical address heading, accessibility tree, Safari handoff, and completion enablement matched the acceptance contract.

## Corrections from Spec 06 run (2026-07-26)

- **Packing work is generated, not catalog-seeded.** Inventory review writes `packingPlan/current` and materializes stable user task documents. The catalog dropped `BUY_PACKING_SUPPLIES`, leaving 45 live rows; reseed verification matched all 45 with no ghosts.
- **The daily-dose rule is one packing session, not one packing-related card.** One due `PACKING_SESSION_n` can join the frozen dose; the single `PACKING_READINESS_GATE` additionally joins after it on T−1 and remains eligible when overdue.
- **Completion preservation is source-key based.** Regeneration after inventory or move-date changes carries completed source groups forward. Ordinary date reflow redistributes incomplete sessions but never moves the readiness gate from moveDate−1.
- **Kit estimates are placeholder supplier data.** Small/medium/large raw box demand receives 12% headroom before rounding; mattress bags and wardrobe/dish accessories remain exact-fit. Customize is the sole line-item escape hatch, while ordering uses the existing hard paywall and concierge submission.
- **Readiness shorthand is concretized as `readiness/current`.** Its five booleans are persisted on every toggle; `completedAt` exists iff all five are true. Existing reserve-access response documents prefill the access checkbox.
- **Spec 06 deployment scope was intentionally narrow.** The only remote mutations were `cd functions && node seedTaskCatalog.js` and, from repo root, `firebase deploy --only functions:submitWorkflowAnswers --project peezy-1ecrdl`. No rules or broad functions deploy occurred.
- **SwiftPM build locking is shared across concurrent Xcode invocations.** A second writer build can wait indefinitely while a validator owns package resolution; serialize final Xcode runs or give them distinct derived/package caches.

## Corrections from Spec 05 run (2026-07-25)

- **Flow definitions now load directly.** Signed-in clients read `flowDefinitions` from Firestore first; the getWorkflowQualifying callable is retained as a one-release fallback.
- **Vendors are backend-owned rate-card documents.** VendorStore queries `vertical == "movers"` and `active == true`, then defensively filters active records. The seed has Test Mover A/B/C and marks all three as placeholder data.
- **Pricing is a pure domain module.** PricingEngine evaluates 2/3/4-person crews, minimum hours, access/packing/specialty labor plus vendor flat fees, drive time, date surcharges, and confidence ranges. The smallest crew whose physical load/unload estimate is at most six hours is selected; drive time is excluded from that ceiling. PricingConstants is the single LOCKED-pending-calibration source.
- **BOOK_MOVERS is the first full spine.** The custom flow captures or reuses inventory, shows scope, gathers mover refinements, and gates moves over 100 miles (or missing mileage) to the concierge quote card. Local moves load active in-radius vendors, sort distinct estimates by low price, gate booking on subscription, submit the booking envelope, and show confirmation.
- **The mover envelope has seven top-level sections.** `identity`, `scope`, `estimate`, `chosen_vendor`, `requested_window`, `notes`, and `quoteRequest` are serialized into WorkflowService's `[String: [String]]` answer contract. Concierge requests keep the same shape with empty estimate/vendor objects and `quoteRequest: true`.
- **Tier-3 assessment migration is sequence-only.** currentBedrooms, newBedrooms, hasStorage, storageSize, and storageFullness remain modeled/persisted and render in the mover flow, but no longer appear in AssessmentCoordinator's sequence. No task-catalog condition references those five keys; the control-profile task set is unchanged with them removed.
- **Mover notification is direct Twilio.** submitWorkflowAnswers no longer consults NOTIFICATION_WEBHOOK_URL for mover submissions. It sends only first name, origin/destination cities, move date, and the approved booking or quote summary; full identity and scope stay in Firestore.
- **Phase E remote inventory check was unavailable.** `firebase functions:list --project peezy-1ecrdl` failed because the local Firebase CLI credentials require reauthentication; the Phase 0 resetInventory deletion was not independently rechecked during closeout.

## Corrections from Spec 04 run (2026-07-25)

- **"39 templated flows" is 38.** 47 files − 8 customs − ScanInventory. 38 transcribed (495 strings script-verified byte-for-byte against sources), 38 deleted. Tasks/Task Cards/ now holds exactly 9 structs.
- **At the Spec 04 close, deployed rules were default-deny for new collections.** flowDefinitions therefore used the getWorkflowQualifying callable. Spec 05 Phase 0 subsequently reconciled the waitlist rule, added the authenticated read, and moved the client to direct reads with a callable fallback.
- **Spec C.4's `pending_matching` client case was the wrong string.** submitWorkflowAnswers writes `matching_in_progress` to TASK docs (getWorkflowQualifying.js); `pending_matching` only ever lands on workflowSubmissions docs. Client case added for the real string; index.js:225 dropped the phantom from its filter.
- **At the Spec 04 close, full `firebase deploy --only functions` aborted** because orphaned cloud function `resetInventory` (us-central1) had no local source. Spec 05 Phase 0 deleted it; the Spec 08 read-only `firebase functions:list` succeeded and verified it absent.
- **Sim + host filesystem:** a synchronous `Data(contentsOf:)` on a host path (~/Desktop) from a sim process blocks first render on TCC — the app shows a white screen with an EMPTY AX tree. Stage files into the app container (`$(simctl get_app_container ...)/tmp`) and read async. Container resets on reinstall — re-stage after every install.
- **Firestore ObjC exceptions are uncatchable in Swift**: `documentWithPath:` with an empty segment SIGABRTs straight through `do/catch`. Guard `!id.isEmpty` before every document() call built from variables (validator-confirmed crash; fixed 45d3197).
- **Type-2 answer keys are a payload contract**: step ids action / handling_update / business_name / current_business / handling_cancel / handling_find must survive any definition edit — submission byte-parity was validated on them.
- **Engine expressiveness is capped at observed need** — {value,when,next} branches, bodyVariants, forEachRow+rowConfigs, requiresRow, {rowsList} rowLabels. Extend only against a new observed need.
- **PBXFileSystemSynchronizedRootGroup handles deletion too** — the 38-file delete built green with zero pbxproj edits.
- **Assessment count UI**: raising a category count is the "+" stepper on a selected tile — re-tapping the tile is a no-op (MultiSelectTile.swift:128-138).
- **Post-submit stage residue**: the engine leaves stage:"capture" on the task doc after submission (old screens wrote no stage). Reconcile when the spine stages become live UI (Spec 05+).
- **Retake leftovers were fixed in `5b06b5a`.** `DailyDoseEngine.resetForRetake` deletes the frozen Firestore dose and all three per-uid UserDefaults counters before task regeneration.
- **Dead validator agents leave fixture debris** — first Phase A validator died mid-setup (session limit) leaving 3 copied task docs (giveaway: identical rounded .000 createdAt). Audit users/{uid}/tasks after any aborted validator run.
- **The businessSearch dropdown chip was fixed in `5b06b5a`.** Results now claim flexible height with layout priority, keyboard padding preserves that space, and the results container has a stable accessibility identifier.

## Corrections from Spec 03 run (2026-07-25)

- TaskStatus: `pending` case added (server lowercase); `matchingInProgress` deleted (never written, never queried). Server ALSO writes `pending_matching` and queries `matching_in_progress` (snake case) — no client case, falls back to .upcoming; reconcile in Spec 04.
- PeezyCard Equatable is now synthesized memberwise; the TasksList `.id(rowIdentity)` fossil workaround remains (harmless) — removable in Spec 04.
- Single decode path: PeezyCardFirestoreMapper is the only Firestore→PeezyCard constructor; marker comment in place.
- DailyDoseEngine holds the dose math verbatim; TaskActionService holds all status writes + setStage. `skipCurrentTask` (+1d snooze) has zero UI callers — delete in Spec 04.
- Dose target currently recomputes live (day can close early) — freeze-at-first-computation lands in Spec 04.
- Simulator: `simctl defaults` writes never reach the app container; use the lldb `frame variable` recipe for in-process decode checks.

## Corrections from Spec 02 run (2026-07-25)

- **The dead-key origin story:** commit eab4193 ("Cleanup complete", April 10) deleted the question VIEWS for hasVehicles, wantToSell, storage trio, bedrooms, moveDateType, MoveConcerns, and the entire interstitial system — but left the dict keys and catalog conditions alive. That's what created the four production-dead tasks. Lesson: deleting a question requires retiring its keys AND its catalog conditions in the same commit, or the catalog silently rots.
- Spec-author rule: before writing any assessment phase, check question-view existence against the Coordinator's step enum — the data manager keeps keys alive after views die.
- The interstitial/inputContext system does not exist (deleted in eab4193); inputContext(for:) is dead code with zero consumers. Reflect-back beats need a mechanism decision (Spec 04).
- Restored views (Spec 02 Phase A/B): HasVehicles, WantToSell, HasStorage/StorageSize/StorageFullness, CurrentBedrooms, NewBedrooms, MoveDateType — from git history, current template API, accessibility ids.
- The stale `CANCEL_YOGA` catalog spot-check was replaced during Spec 04; Spec 08 additionally added exact declared-field round-trip verification.
- iOS Simulator MCP can hold a stale xcode-select env; AXe fallback works. Fix: restart server or `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

## Corrections from Spec 01 run (2026-07-25)

- `AssessmentDataManager.completeAssessment` does not exist — the method is `saveAssessment()`; `completeAssessment` lives on the Coordinator
- `saveAssessment`'s userKnowledge write THROWS under deployed rules — any code appended after it never runs until rules deploy. Order new writes before it
- At the Spec 01 audit, peezyLayout.swift's `peezyGlassBackground(cornerRadius:)` was live via PeezyLiquidGlass.swift:64; the dependency and file were removed in later cleanup
- Spec rule: any phase touching a read site must list the read-site files in its manifest
- XcodeBuildMCP may register but not connect; the bundled-AXe fallback works
- Identity doc lives at users/{uid}/identity/identity (doc id "identity")

## Open items

`LAUNCH_CHECKLIST.md` is the single source of truth. It carries every launch
gate, owner, current evidence, and exact close path, plus deferred cleanup and
the historical chips already verified closed. Do not add a second open-item
list here.
