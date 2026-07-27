# CLAUDE.md — Peezy iOS App
Generated from peezy-conventions-v2.md (audit @ f7e47ad + implementation through Spec 06 Phase C, d2fdf36). Every fact below is code-verified unless explicitly labeled as remote evidence. Read peezy-conventions-v2.md and peezy-v1-architecture.md before spec work.

## What This Is

iOS moving concierge app. Swift/SwiftUI client + Firebase backend (Cloud Functions, Node.js). Users complete an assessment, get personalized tasks generated from the Firestore `taskCatalog`, and work them via the Home card stack and Tasks tab.

## Boundary Constraints (verbatim, all work)

> Don't add features, refactor, or introduce abstractions beyond what the task requires. Don't design for hypothetical future requirements: do the simplest thing that works well. Don't add error handling, fallbacks, or validation for scenarios that cannot happen.

> Before reporting progress, audit each claim against a tool result from this session. Only report work you can point to evidence for; if something is not yet verified, say so explicitly.

> You are operating autonomously. The user is not watching in real time. For reversible actions that follow from the original request, proceed without asking. Before ending your turn: if your last paragraph is a plan, a question, or a promise about undone work, do that work now with tool calls.

## Corrected Facts (supersede all older docs)

1. **Paywall gate is post-assessment, not "after three completed tasks."** The three-task trigger does not exist in code. Hard gate at CompletionFlowView.swift:52-58, dismissible via X (PaywallGateView:31-41). This is the Review #3-approved behavior; changing it is a product decision, not a bug fix.
2. **Four tabs:** Home / Tasks / Chat / Settings. Chat = SupportChatView (live, Firestore-backed support chat). The AI chat was removed; support chat was not.
3. **Catalog v2 is 45 tasks (Spec 06).** actionType: workflow=32, off-app=8, in-app=4, in-app-inventory=1. taskType: survey=32, provide_info=13. 33 rows carry a workflowId (incl. scan_inventory). Spec 06 retired `BUY_PACKING_SUPPLIES`; `PACKING_SESSION_n`, `PACKING_SUPPLIES_KIT`, and `PACKING_READINESS_GATE` are generated per-user and deliberately catalog-external. Flow content lives in the Firestore `flowDefinitions` collection (25 docs) seeded from functions/flowDefinitionsData.json — adding a vertical is a Firestore write.
4. **WorkflowManager.swift does not exist.** TimelineService is deleted. The live task-loading paths are exactly the two below.
5. **Flow rendering is config-driven (Spec 04/05).** FlowEngineView renders flowDefinitions through the untouched component kit; TaskFlowRouter is a thin resolver (capture registry → admin-pushed → in-app map → Swift customs → flowDefinitions lookup → coming-right-up card). The 38 templated screens and the newFlowIds allowlist are deleted. Signed-in clients read definitions directly from Firestore; getWorkflowQualifying remains the one-release fallback.
6. **Movers is the first full SPINE vertical (Spec 05).** BOOK_MOVERS runs inventory capture/reuse → scope → refinement → active in-radius vendor comparison → paywall → booking submission → confirmation. Current/new bedrooms and the storage trio no longer appear in the assessment sequence; the mover refinement view collects those values.
7. **Packing is inventory-driven (Spec 06).** Inventory review creates a reverse-scheduled plan, one due packing session can join the frozen daily dose, incomplete sessions silently reflow, the one-bundle supplies kit uses the concierge callable until a supplier signs, and a stable readiness gate joins after packing on T−1.

## Live Data Paths (the only two)

```
Home:      PeezyHomeViewModel.loadTasks() :295  (one-shot query)
Tasks tab: TasksStore listener → PeezyCardFirestoreMapper.card() :36  (snapshot)
```

Parity rule: these two loaders must stay field-identical except `completedAt` (Mapper-only, deliberate — Home filters completed). No comment marks this coupling in code; any edit touching either loader adds the marker comment or centralizes decoding.

## Key Files (verified)

| Area | File | Note |
|---|---|---|
| Entry | MainInterface/Models/PeezyV1App.swift | @main; injects SubscriptionManager.shared (only root env object) |
| Root gate | MainInterface/Views/AppRootView.swift | Builds UserState at :137 (only live construction site) |
| Container | MainInterface/Views/PeezyMainContainer.swift | 4 tabs |
| Home VM | MainInterface/Models/PeezyHomeViewModel.swift | Thin VM; dose frozen per day via DailyDoseEngine (users/{uid}.dailyDose); universal flowId routing (workflowId ?? lowercased taskId) |
| Router | MainInterface/Models/TaskFlowRouter.swift | Thin resolver (Spec 04); unknown ids → ComingRightUpCard |
| Flow engine | Tasks/FlowEngine/ | FlowDefinition (+row resolution), FlowEngineView (+loader/coming-right-up), InAppTaskFlows, CaptureRegistry, FlowEngineHarness (DEBUG, env-gated) |
| Card model | MainInterface/Models/PeezyCard.swift | Memberwise Equatable; stage/payload fields; TaskStatus incl. pending + matching_in_progress |
| Vendor data | MainInterface/Models/Vendor.swift + functions/vendorsData.json | Backend-owned vendor/rate-card schema; three placeholder movers; active filter gates downstream visibility |
| Pricing | MainInterface/Models/PricingEngine.swift + PricingConstants.swift + MoveScopeFactory.swift | Pure rate-card math, centralized LOCKED-pending-calibration constants, inventory/assessment scope adapter |
| Movers spine | MainInterface/Models/MoversFlowViewModel.swift + Tasks/Task Cards/FindMoversFlow.swift | Capture/reuse → scope → refinement → comparison → paywall → submission → confirmation |
| Packing plan | MainInterface/Models/PackingPlanEngine.swift + PackingConstants.swift | Pure locked-order reverse scheduler, completion preservation, overdue reflow, and >1.5 sessions/day pace flag |
| Packing persistence | MainInterface/Models/TaskActionService.swift | Owns `packingPlan/current`, generated session/kit/gate task docs, `readiness/current`, and atomic completion writes |
| Supplies kit | MainInterface/Models/KitEstimator.swift + Tasks/Task Cards/SuppliesKitView.swift | Pure 12%-headroom estimate, placeholder pricing, customize/dismiss, paywall, and `supplies_kit` concierge submission |
| Readiness gate | MainInterface/Models/ReadinessGate.swift + Tasks/Task Cards/PackingReadinessView.swift | T−1 five-item evidence checklist with reserve-access prefill and nonblocking consequence copy |
| Comparison UI | MainInterface/Views/ComparisonCardView.swift | Vertical-neutral vendor quote card |
| Paywall policy | MainInterface/Models/PaywallPolicy.swift | requiresSubscription(for:) + PaywallGateSheet — the ONE sanctioned second PaywallGateView call site |
| Identity | MainInterface/Models/UserState.swift | Address parse fixed 8413f2d (city/state only); full rebuild in v1 |
| StoreKit | MainInterface/Models/SubscriptionManager.swift | COMPLIANCE — port verbatim, never touch |
| Paywall | MainInterface/Views/Paywall/PaywallGateView.swift | COMPLIANCE — Review #3 fix lives here |
| Flow kit | Tasks/Task Card Components/ (17 hubs) | Renderer library for the engine — PORT VERBATIM (TaskFlowDismissButton deleted Spec 04) |
| Flow screens | Tasks/Task Cards/ | Remaining Swift customs, capture flow, and mover stage views |
| Submission | MainInterface/Models/WorkflowService.swift | Callable pattern (LE-029); 11 live construction call sites across 10 Swift files |
| Parser | TaskConditionerParser.swift | AND keys / OR values / strict-cast fail-false :69-74 |
| Generation | TaskGenerationService | NSNumber cast canonical at :73 |
| Inventory | Inventory/ + functions/processInventory.js | Pipeline frozen regions below |

## Frozen Regions (never modify)

- CameraPreviewView.swift:12-31 — layerClass AVCaptureVideoPreviewLayer wrapper (LE-005)
- No sharpness filtering, ever (LE-006). Dead remnants: sharpnessScore field, hardcoded 1.0
- SubscriptionManager / PaywallGateView pricing: all price + trial text from live Product objects, never hardcoded (LE-026)
- SIWA first-auth name capture: AuthViewModel.handleAppleSignInCompletion:92-98 (Guideline-4 fix)
- AI disclosure copy + privacy link: InventoryFlowView ~:207-209 (privacy objection fix)
- env-object re-injections at AssessmentFlowView:59 and CompletionFlowView:102 (LE-023 — fullScreenCover does not inherit)
- ObservableObject stays ObservableObject on: AssessmentCoordinator, AssessmentDataManager, AuthViewModel, SubscriptionManager (LE-007). New types use @Observable.
- deleteAccount is server-side Admin SDK — no client re-auth, by design
- project.pbxproj, GoogleService-Info.plist, functions/.env — hook-blocked

## Contract Facts a New Client Must Honor

- Zero client-side webhook URLs. Callable → Firestore workflowSubmissions audit → optional server-side webhook + Twilio path (LE-029). Without `NOTIFICATION_WEBHOOK_URL`, the durable submission still lands and the function logs that vendor notification was not sent
- Server task-doc statuses: "pending" (creation) and "matching_in_progress" (post-vendor-submission) — both have TaskStatus cases with waiting treatment (Spec 03/04). "pending_matching" exists ONLY on workflowSubmissions docs, never on task docs
- Merged flows carry per-user rows: catalog rowGeneration → TaskGenerationService stamps flowRows on the task doc → engine expands (forEachRow/requiresRow). 2 bank taps = 2 bank rows inside FINANCIAL_ACCOUNTS
- Packing persistence is `users/{uid}/packingPlan/current`; generated task docs are `PACKING_SESSION_n`, `PACKING_SUPPLIES_KIT`, and the single stable `PACKING_READINESS_GATE`. Checklist evidence is `users/{uid}/readiness/current`; generated tasks do not belong in `taskCatalog`
- Inventory or move-date changes regenerate the plan while preserving completed source groups. Ordinary overdue reflow never changes the readiness due date. The daily dose admits at most one due packing session and places due readiness after it on T−1
- `supplies_kit` remains concierge fulfillment: the callable saves the complete kit/identity envelope, marks `PACKING_SUPPLIES_KIT` `matching_in_progress`, and sends the `PEEZY KIT ORDER: ...` SMS family or logs `SMS notify not configured`
- submitWorkflowAnswers response omits submissionId/message/estimatedResponseTime; client defaults mask it
- userKnowledge/{uid}: rules permit the client-owned document. Backend contextBuilder.js:40-47 expects {entries:{...}}; collection has never had a successful write → schema is greenfield, designed in v1
- Firestore numbers: NSNumber cast pattern everywhere; no unguarded `as? Int`
- Client-owned paths include taskCatalog (r), flowDefinitions (r), vendors (r), users/{uid}/tasks, user_assessments, identity, packingPlan, readiness, workflowResponses, userKnowledge, inventory, inventorySessions, and supportChat. Vendor and definition writes remain backend-only
- Conditions are `[String: [String]]` maps of category values ("Bank Account", not "Chase"); task IDs are UPPER_SNAKE_CASE

## Accessibility Convention (non-negotiable)

Every new view element that a user can tap, read as a result, or that represents state MUST carry `.accessibilityIdentifier("<area>.<element>")`. The Stop hook greps new Swift files for at least one identifier per View struct and blocks the turn otherwise.

## Session Harness (hooks)

- PreToolUse denies Write/Edit on protected files (pbxproj, GoogleService-Info.plist, functions/.env, Configuration.storekit, Inventory/Camera/*, SubscriptionManager.swift, PaywallGateView.swift) and on any repo path not listed in `PHASE_MANIFEST` at repo root. Write PHASE_MANIFEST (intended paths) at phase start.
- Stop hook blocks ending the turn while Swift files are modified without a subsequent successful xcodebuild, or while a new View file lacks accessibility identifiers.

## Environment

- Root: ~/Desktop/Peezy 4.0/ (source in nested "Peezy 4.0/"); never run from Documents/ (LE-001)
- `unset CLAUDECODE` if nesting sessions (LE-002); macOS bash is 3.2 (LE-018)
- Xcode 26.6: iOS platform + Metal toolchain must be installed (xcodebuild -downloadPlatform iOS / -downloadComponent MetalToolchain)
- Build: `xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build` (no iPhone 16 sim exists)
- Seed catalog: `cd functions && node seedTaskCatalog.js`. Spec 06 callable deploy: from repo root, `firebase deploy --only functions:submitWorkflowAnswers --project peezy-1ecrdl`. Do not widen a spec-scoped deploy without explicit authorization
- Deployed Firestore rules are not readable via firebase-tools 15.6.0; use the Rules REST API with functions/serviceAccountKey.json (read-only). Spec 05 Phase 0 reconciled the waitlist rule and added authenticated reads for flowDefinitions and vendors
- Test creds: peezy-test-bot@test.peezyapp.com / PeezyTest2026!
- Code style: Swift 5.9+/iOS 17+, SwiftUI only, async/await, @Observable for new types (exceptions listed in Frozen Regions)

## Workflow

1. Before coding: state what you're changing, which files, and why
2. Read every file you plan to modify BEFORE making changes; if unsure what a file contains, read it first, then report what you found with file:line evidence
3. Build with xcodebuild after every set of changes; fix failures before moving on
4. Report actions and evidence: file paths, line numbers, tool output — not narration
5. `git diff` review before every commit; commit per phase

## Open Items

- kit supplier: replace concierge fulfillment with local supplier handoff when signed.
