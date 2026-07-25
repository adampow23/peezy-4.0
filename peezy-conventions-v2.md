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
| Container | MainInterface/Views/PeezyMainContainer.swift | 4 tabs; PeezyStackViewModel instantiation removed in cleanup |
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

## Open items (tracked, not forgotten)

- Deploy reconciled firestore.rules (Adam reviews; waitlist rule must be merged in first)
- Dead-code deletion via Xcode per DEAD_CODE_REMOVAL_LIST.md (7 SAFE + 2 staged removals)
- PrivacyInfo.xcprivacy has no NSPrivacyCollectedDataTypes despite account data + frames→Anthropic; no ToS/Privacy links on auth screens (cheap hardening, next submission)
- backup/friend-changes-2026-04-28 branch: confirm-then-delete
- PeezyClient/PeezyResponse fate tied to v1.1 chat decision; PeezyConfig (:216-219, LIVE via receipt sync) must be extracted first if deleted
