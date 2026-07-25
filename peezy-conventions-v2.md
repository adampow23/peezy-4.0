# Peezy Conventions v2 — Ground Truth
Supersedes peezy-conventions.md. Source: V1_ARCHITECTURE_MAP.md (audit @ f7e47ad, 2026-07-23) + post-audit cleanup commits (through da1916e). Every fact below is code-verified, not documented-belief.

## Corrections to prior docs — READ FIRST

These four false premises appeared in peezy-conventions.md, the launch plan, and/or the autopilot skill. Any spec inheriting them is wrong:

1. **Paywall gate is post-assessment, not "after three completed tasks."** The three-task trigger does not exist anywhere in code (exhaustive grep). Current behavior: hard gate at CompletionFlowView.swift:52-58, dismissible via X (PaywallGateView:31-41), so the app is reachable unsubscribed. This is the reviewed-and-approved Review #3 behavior. Changing it is a product decision, not a bug fix.
2. **Four tabs, not three:** Home / Tasks / Chat / Settings. Chat = SupportChatView (live, T06-tested, Firestore-backed support chat). The *AI* chat was removed; support chat was not.
3. **Catalog is 56 tasks, not 70.** actionType: workflow=43, off-app=12, in-app-inventory=1. taskType: survey=43, provide_info=13. 44 distinct workflowIds.
4. **WorkflowManager.swift does not exist.** TimelineService is dead (zero callers, deleted in cleanup). The live loading paths are exactly two: PeezyHomeViewModel.loadTasks() (Home, one-shot) and TasksStore listener → PeezyCardFirestoreMapper.card() (Tasks tab).

## Live data paths (the only two)

```
Home:      PeezyHomeViewModel.loadTasks() :295  (one-shot query)
Tasks tab: TasksStore listener → PeezyCardFirestoreMapper.card() :36  (snapshot)
```
Parity rule (LE-025/LE-031, updated): these two loaders must stay field-identical except `completedAt` (Mapper-only, deliberate — Home filters completed). **No comment marks this coupling in code.** Any edit touching either loader adds the marker comment or centralizes decoding.

## Key files (current, verified)

| Area | File | Note |
|---|---|---|
| Entry | MainInterface/Models/PeezyV1App.swift | @main; injects SubscriptionManager.shared (only root env object) |
| Root gate | MainInterface/Views/AppRootView.swift | Builds UserState at :137 (only live construction site) |
| Container | MainInterface/Views/PeezyMainContainer.swift | 4 tabs; still instantiates PeezyStackViewModel at :19/:101/:103 — excise those lines BEFORE deleting that file (Spec 01 run verified deletion-without-excision breaks the build) |
| Home VM | MainInterface/Models/PeezyHomeViewModel.swift | Daily Dose math :182-193; hardcoded newFlowIds :84-113; REWRITE target |
| Router | MainInterface/Models/TaskFlowRouter.swift | Closed 47-case switch; REWRITE target |
| Card model | MainInterface/Models/PeezyCard.swift | 28 fields; id-only Equatable :365-367 (hazard); REWRITE target |
| Identity | MainInterface/Models/UserState.swift | Address parse fixed 8413f2d (city/state only); full rebuild in v1 |
| StoreKit | MainInterface/Models/SubscriptionManager.swift | COMPLIANCE — port verbatim, never touch |
| Paywall | MainInterface/Views/Paywall/PaywallGateView.swift | COMPLIANCE — Review #3 fix lives here |
| Flow kit | Tasks/Task Card Components/ (18 hubs) | All real flow UI; TaskFlowTitleCard has 49 dependents |
| Flow screens | Tasks/Task Cards/ (47 structs) | Templated configs over the kit; superseded by v1 engine |
| Submission | MainInterface/Models/WorkflowService.swift | LE-029 callable pattern; 27 consumers |
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

- Zero client-side webhook URLs. Callable → Firestore audit → server-side webhook + Twilio (LE-029)
- Server-created tasks carry status string "pending" — no TaskStatus case; decodes to .upcoming. Reconcile deliberately in the stage-model work; do not "fix" in passing
- submitWorkflowAnswers response omits submissionId/message/estimatedResponseTime; client defaults mask it
- userKnowledge/{uid}: rules gap patched locally (861f7e2, NOT deployed — reconcile waitlist rule first). Backend contextBuilder.js:40-47 expects {entries:{...}}; client writes flat dict; collection has never had a successful write → schema is greenfield, designed in v1
- Firestore numbers: NSNumber cast pattern everywhere; no unguarded `as? Int`
- Client-owned paths: taskCatalog (r), users/{uid}/tasks, user_assessments, userKnowledge, inventory, inventorySessions, supportChat. Everything else backend-only

## Lessons that map to nothing (do not re-apply)

- 0.3s auto-advance chain — system removed in 089749b; advance is immediate
- cancelWorkflow/onWorkflowDismissed — WorkflowManager gone

## Environment

- Root: ~/Desktop/Peezy 4.0/ (source in nested "Peezy 4.0/"); never run from Documents/ (LE-001)
- `unset CLAUDECODE` if nesting sessions (LE-002); macOS bash is 3.2 (LE-018)
- Xcode 26.6: iOS platform + Metal toolchain must be installed (xcodebuild -downloadPlatform iOS / -downloadComponent MetalToolchain)
- Deployed Firestore rules are NOT readable via firebase-tools 15.6.0; use the Rules REST API with functions/serviceAccountKey.json (read-only). Local firestore.rules is known to drift from deployed — deployed has a live waitlist rule the local file lacks
- Test creds: peezy-test-bot@test.peezyapp.com / PeezyTest2026!
- Accessibility ids: 51 usages in 13 files, mapped to T01-T10 UITests. **All new views require .accessibilityIdentifier() — mandatory convention**

## Corrections from Spec 04 run (2026-07-25)

- **"39 templated flows" is 38.** 47 files − 8 customs − ScanInventory. 38 transcribed (495 strings script-verified byte-for-byte against sources), 38 deleted. Tasks/Task Cards/ now holds exactly 9 structs.
- **Deployed rules are default-deny for new collections** (verified via Rules REST API this session). flowDefinitions therefore has NO client read; it is served through the getWorkflowQualifying callable (Firestore-first lookup — the Q11 adoption, literally). Switch to direct reads only after Adam's reconciled-rules deploy. NOTE: the DEPLOYED ruleset contains the live waitlist rule; the LOCAL firestore.rules still lacks it — the deployed text was captured this session if needed for reconciliation.
- **Spec C.4's `pending_matching` client case was the wrong string.** submitWorkflowAnswers writes `matching_in_progress` to TASK docs (getWorkflowQualifying.js); `pending_matching` only ever lands on workflowSubmissions docs. Client case added for the real string; index.js:225 dropped the phantom from its filter.
- **Full `firebase deploy --only functions` ABORTS**: orphaned cloud function `resetInventory` (us-central1) has no local source (client resets inventory via direct Firestore deletes, InventorySessionManager.swift:428). Use targeted deploys, or Adam runs `firebase functions:delete resetInventory --region us-central1`.
- **Sim + host filesystem:** a synchronous `Data(contentsOf:)` on a host path (~/Desktop) from a sim process blocks first render on TCC — the app shows a white screen with an EMPTY AX tree. Stage files into the app container (`$(simctl get_app_container ...)/tmp`) and read async. Container resets on reinstall — re-stage after every install.
- **Firestore ObjC exceptions are uncatchable in Swift**: `documentWithPath:` with an empty segment SIGABRTs straight through `do/catch`. Guard `!id.isEmpty` before every document() call built from variables (validator-confirmed crash; fixed 45d3197).
- **Type-2 answer keys are a payload contract**: step ids action / handling_update / business_name / current_business / handling_cancel / handling_find must survive any definition edit — submission byte-parity was validated on them.
- **Engine expressiveness is capped at observed need** — {value,when,next} branches, bodyVariants, forEachRow+rowConfigs, requiresRow, {rowsList} rowLabels. Extend only against a new observed need.
- **PBXFileSystemSynchronizedRootGroup handles deletion too** — the 38-file delete built green with zero pbxproj edits.
- **Assessment count UI**: raising a category count is the "+" stepper on a selected tile — re-tapping the tile is a no-op (MultiSelectTile.swift:128-138).
- **Post-submit stage residue**: the engine leaves stage:"capture" on the task doc after submission (old screens wrote no stage). Reconcile when the spine stages become live UI (Spec 05+).
- **Retake leftovers**: assessment retake does not reset the per-uid dose UserDefaults counters and leaves the frozen dailyDose doc — a fresh plan can claim same-day progress (task chip spawned; fix at retakeAssessment).
- **Dead validator agents leave fixture debris** — first Phase A validator died mid-setup (session limit) leaving 3 copied task docs (giveaway: identical rounded .000 createdAt). Audit users/{uid}/tasks after any aborted validator run.
- businessSearch dropdown never renders visually in ANY binary (zero-height ScrollView; rows present in AX) — pre-existing kit bug, both TaskFlowBusinessSearchCard and likely ConfirmAddressCard; task chip spawned.

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
- seedTaskCatalog.js has a stale spot-check constant (CANCEL_YOGA) — one-line fix queued.
- iOS Simulator MCP can hold a stale xcode-select env; AXe fallback works. Fix: restart server or `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

## Corrections from Spec 01 run (2026-07-25)

- `AssessmentDataManager.completeAssessment` does not exist — the method is `saveAssessment()`; `completeAssessment` lives on the Coordinator
- `saveAssessment`'s userKnowledge write THROWS under deployed rules — any code appended after it never runs until rules deploy. Order new writes before it
- peezyLayout.swift's `peezyGlassBackground(cornerRadius:)` (:40) is live via PeezyLiquidGlass.swift:64 — remove that call before deleting the file
- Spec rule: any phase touching a read site must list the read-site files in its manifest
- XcodeBuildMCP may register but not connect; the bundled-AXe fallback works
- Identity doc lives at users/{uid}/identity/identity (doc id "identity")

## Open items (tracked, not forgotten)

- Deploy reconciled firestore.rules (Adam reviews; waitlist rule must be merged in first). After that: optionally add a flowDefinitions read rule and swap FlowDefinitionStore to direct reads (one function)
- Adam: delete or re-source the orphaned cloud fn resetInventory so full functions deploys stop aborting
- markCurrentTaskPeezyHandling + PeezyHomeView's legacy activeTask card path are unreachable post-universal-routing — delete in Spec 05
- seedTaskCatalog.js never writes estPeezy to Firestore though the JSON carries it (pre-existing) — reconcile on next catalog-field change
- Paywall subscribed-pass-through is environment-limited under simctl (StoreKit test config needs an Xcode scheme launch) — verify from Xcode before submission
- Dead-code deletion via Xcode per DEAD_CODE_REMOVAL_LIST.md (7 SAFE + 2 staged removals)
- PrivacyInfo.xcprivacy has no NSPrivacyCollectedDataTypes despite account data + frames→Anthropic; no ToS/Privacy links on auth screens (cheap hardening, next submission)
- backup/friend-changes-2026-04-28 branch: confirm-then-delete
- PeezyClient/PeezyResponse fate tied to v1.1 chat decision; PeezyConfig (:216-219, LIVE via receipt sync) must be extracted first if deleted
