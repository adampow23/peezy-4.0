# Peezy v1 Architecture Map
Generated: 2026-07-23 | Commit: f7e47ad ("App Store review #3", 2026-04-29) | Working tree: clean | main == origin/main

Method: read-only audit per `peezy-v1-architecture-audit.md`. Nine parallel read-only exploration passes over all 195 production Swift files (~33,350 lines), `functions/`, project config, and git history. Zero code changes made. Every claim below cites a file path and, where relevant, line numbers verified this session.

**Audit deviation (disclosed):** `lessons-learned.md` and `peezy-conventions.md` do not exist anywhere in the repository or on this machine — they are Claude.ai project files. Lesson content was reconstructed from: the audit spec itself, the `peezy-autopilot` skill, `BUILD1/BUILD2/E2E` spec docs, and both CLAUDE.md variants. No `LE-###` string except LE-001/002/018/019/021/022/032 appears anywhere on disk. Where a lesson's substance could be verified in code, it is; where not, it is marked UNKNOWN.

---

## 1. Executive Summary

The v1.0 client is in better compliance shape and worse documentation shape than its own docs claim. The App Store surface (StoreKit 2, restore, account deletion, privacy declarations, environment-object injection) is verified solid — every price and trial string derives from live `Product` objects, and the triple-rejection fixes are locatable and intact (§4, §9). The capture pipeline's transport layers (record → frame-extract → upload → callable) are already vertical-agnostic; the entire moving vertical is concentrated in one backend file's inline prompt (§6).

**The single biggest architectural risk to the v1 expansion: the app has no workflow spine.** A "workflow" today is a per-flow local `@State currentIndex: Int` inside 47 near-identical hardcoded Swift structs, routed by a closed ~50-case switch (`TaskFlowRouter`) duplicated by a hardcoded allowlist (`PeezyHomeViewModel.newFlowIds`). No stage is persisted anywhere; `TaskStatus` has no ladder resembling Capture→Measure→Scope→Price→Compare→Book→Verify; a task whose id isn't in the allowlist dead-ends on a spinner (§5). The Capture→…→Verify spine is not an extension of this — it is new architecture.

Second risk: the identity layer is broken today. `UserState`'s address fields are never populated (the assessment writes keys `UserState.init` doesn't read), so all seven address-consuming vendor flows and the concierge payload currently receive empty addresses in production (§7).

Third finding: the project's own docs are stale on load-bearing facts — `WorkflowManager.swift` doesn't exist, `TimelineService` is dead, chat is a live fourth tab, the catalog has 56 tasks not 70 (§5, §8, §11).

Classification result: 5 REWRITE, 11 DELETE (~2,090 dead lines), 2 UNKNOWN, 177 PORT.

---

## 2. File Classification Table

Rules applied: non-UI models/services that work → `PORT VERBATIM`; UI reachable in production but lacking accessibility identifiers → `PORT + ANNOTATE`; files whose structure cannot hold the stated v1 requirements → `REWRITE`; dead/orphaned/DEBUG-only → `DELETE`. Risk: `COMPLIANCE` = compliance-critical, `LESSON` = lesson-bearing, `HUB` = 5+ dependents, `LEAF` = ≤2 dependents. "Dependents" = external files referencing the file's primary types (grep-verified).

### 2.1 App entry, root, main container (`MainInterface/`)

| File Path | Lines | Purpose | Dependents | Classification | Evidence | Risk |
|---|---|---|---|---|---|---|
| MainInterface/Models/PeezyV1App.swift | 34 | @main entry; Firebase boot; injects SubscriptionManager | entry | PORT VERBATIM | Root `.environmentObject` at :27 is LE-023-adjacent | COMPLIANCE |
| MainInterface/Views/AppRootView.swift | 221 | Auth/state gate; builds UserState from Firestore | 3 | PORT VERBATIM | UserState built at :137; will need touching only if UserState is rebuilt (§7) | HUB (structural) |
| MainInterface/Views/PeezyMainContainer.swift | 207 | 4-tab container (Home/Tasks/Chat/Settings) + tab bar + toasts | 3 | PORT VERBATIM | Contains orphaned `PeezyStackViewModel` instantiation at :19,101-103 — remove alongside its DELETE | HUB (structural), LESSON (089749b) |
| MainInterface/Views/PeezyHomeView.swift | 439 | Home UI over PeezyHomeViewModel state machine | 3 | REWRITE | Hosts router fullScreenCover (:119-139) and VM states; changes with spine. 10 accessibility ids already present | HUB (structural) |
| MainInterface/Models/PeezyHomeViewModel.swift | 766 | Home state machine, Daily Dose, routing allowlist, task writes | 3 | REWRITE | Hardcoded `newFlowIds` Set (:84-113) duplicates router; concierge payload sends blank addresses (:445-446); mixes 4 concerns | HUB, LESSON (loader parity) |
| MainInterface/Models/TaskFlowRouter.swift | 157 | Closed switch: flowId → 1 of 47 flow views | 2 | REWRITE | `switch flowId` :26-155, `default: EmptyView()` :154; not data-driven; every new task type edits 2 hand-maintained lists + new struct | HUB (fan-out 47) |
| MainInterface/Models/PeezyCard.swift | 388 | Core card model + TaskStatus enum | 20 | REWRITE | Fixed 28-field struct; custom id-only `==` (:365-367) hides status changes from SwiftUI diffing; `taskType` parsed but never consumed; no stage representation; 4 divergent constructors (§5.1) | HUB, LESSON |
| MainInterface/Models/UserState.swift | 306 | Per-user move context struct threaded through app | 21 | REWRITE | `init(from:)` reads `originCity/originState/...` keys (:168-171) that `getAllAssessmentData()` never emits → always nil in production (§7); no phone/email/unit | HUB |
| MainInterface/Models/PeezyClient.swift | 247 | HTTP client for `peezyRespond` + `PeezyConfig` base URLs | 2 | **UNKNOWN** | `PeezyClient` class reachable only via dead PeezyStackViewModel; but `PeezyConfig` (same file, :216-219) is LIVE via SubscriptionAPIClient. Needs human call on v1.1 chat (§11-Q2) | LEAF |
| MainInterface/Models/PeezyResponse.swift | 208 | Codable DTOs for peezyRespond payloads | 2 (both dead/UNKNOWN) | **UNKNOWN** | Only consumers are PeezyClient + PeezyStackViewModel; fate tied to v1.1 chat decision | LEAF |
| MainInterface/Models/PeezyStackViewModel.swift | 559 | Legacy card-stack VM | 1 | DELETE | Instantiated at PeezyMainContainer.swift:19 and loads Firestore data on tab switch, but its `cards` array is never rendered anywhere (grep-verified) — wasted reads. Delete + remove instantiation | LEAF |
| MainInterface/Models/SubscriptionManager.swift | 339 | StoreKit 2 manager (products/purchase/restore/entitlements) | 7 | PORT VERBATIM | All of §4.1; `ObservableObject` deliberately (LE-007) | COMPLIANCE, LESSON, HUB |
| MainInterface/Models/SubscriptionAPIClient.swift | 33 | Fire-and-forget receipt sync to validateSubscription | 1 | PORT VERBATIM | Depends on `PeezyConfig` — relocate that type if PeezyClient.swift is deleted | COMPLIANCE, LEAF |
| MainInterface/Models/SupportChatService.swift | 97 | Firestore support-chat service | 2 | PORT VERBATIM | Live Chat tab (PeezyMainContainer.swift:62) | LEAF |
| MainInterface/Models/SupportMessage.swift | 48 | Support message model | 2 | PORT VERBATIM | — | LEAF |
| MainInterface/Views/SupportChatView.swift | 231 | Chat tab UI (the app's only chat) | 2 | PORT VERBATIM | Has 3 accessibility ids; covered by T06 UI tests | LEAF |
| MainInterface/Models/WorkflowService.swift | 60 | Submits workflow answers via `submitWorkflowAnswers` callable | 27 | PORT VERBATIM | LE-029 pattern; consumed by 27 flows | HUB, LESSON |
| MainInterface/Models/WorkflowCardModels.swift | 70 | `WorkflowAnswers` / `WorkflowSubmissionResponse` | 27 | PORT VERBATIM | Note: server never returns `submissionId/message/estimatedResponseTime` — client defaults fill them (§8) | HUB |
| MainInterface/Models/ToastManager.swift | 105 | Global toast queue singleton | 3 | PORT VERBATIM | From 089749b | LEAF |
| MainInterface/Views/Shared/ToastView.swift | 95 | Toast presentation + overlay | 1 | PORT + ANNOTATE | No accessibility ids | LEAF |
| MainInterface/Models/TimeOfDay.swift | 93 | Time-of-day enum for greetings/theming | 2 | PORT VERBATIM | — | LEAF |
| MainInterface/Views/Shared/HomeBackgroundComponents.swift | 95 | `InteractiveBackground` + loading/empty/error views | ~80 | PORT VERBATIM | Most-referenced type in codebase; stale comments :4-5 reference removed PeezyStackView | HUB (top) |
| MainInterface/Views/Shared/PeezyWordmark.swift | 21 | Brand wordmark | 3 | PORT VERBATIM | — | LEAF |
| MainInterface/Views/Paywall/PaywallGateView.swift | 338 | The only paywall screen | 1 | PORT VERBATIM | §4.1-4.2; 8 accessibility ids; restore button :112-123 | COMPLIANCE, LESSON |
| MainInterface/Views/TaskFlow/WebhookService.swift | 42 | Callable wrapper for submitTaskFlow | 0 | DELETE | `grep -rnw WebhookService` → definition only (independently confirmed by 3 passes); QuoteSelectionFlow calls the callable directly | LEAF (dead) |
| MainInterface/Views/TaskFlow/PreviewData.swift | 90 | #Preview sample data | preview-only | DELETE | Only `UserState.preview` used, only inside a `#Preview`; `previewResearch/previewTransfer` 0 refs. DEBUG-only per spec = DELETE (harmless to keep for previews — human call) | LEAF |

### 2.2 Auth (`Auth/`)

| File Path | Lines | Purpose | Dependents | Classification | Evidence | Risk |
|---|---|---|---|---|---|---|
| Auth/AuthViewModel.swift | 237 | Apple/Google/email auth, sign-out, SIWA name capture | 6 | PORT VERBATIM | SIWA givenName capture (:92-98) is the Guideline-4 rejection fix (089749b) | COMPLIANCE, LESSON, HUB |
| Auth/AuthView.swift | 365 | Sign-in landing | 1 | PORT VERBATIM | 2 ids; re-injects authViewModel into both sheets (:191,195) — LE-023 pattern | COMPLIANCE |
| Auth/LogInView.swift | 210 | Email login sheet | 1 | PORT VERBATIM | 4 ids; T01 tests | LEAF |
| Auth/SignUpView.swift | 197 | Email sign-up sheet | 1 | PORT VERBATIM | 2 ids. Note §4.9: no ToS/Privacy links on auth screens | LEAF |
| Auth/PeezyFormField2.swift | 144 | Styled form field | 2 | PORT VERBATIM | 2 ids | LEAF |
| Auth/TypewriterText.swift | 162 | Animated typewriter text | 1 | PORT + ANNOTATE | — | LEAF |
| Auth/AuthFormButton.swift | 82 | Auth submit button | 2 | PORT + ANNOTATE | — | LEAF |

### 2.3 Assessment engine (`Assessment/AssessmentModels/`)

| File Path | Lines | Purpose | Dependents | Classification | Evidence | Risk |
|---|---|---|---|---|---|---|
| AssessmentCoordinator.swift | 585 | Sequence/branching state machine; completion trigger | 4+ (all questions via env) | PORT VERBATIM | Danger-zone file; 4 dead enum cases (sq-ft steps never sequenced, :34-47 vs buildSequence) | HUB, LESSON |
| AssessmentDataManager.swift | 373 | Answer store; `getAllAssessmentData()` contract; geocoding | ~30 | PORT VERBATIM | Danger zone. ~15 keys always empty (§7); geocode fail-open :236-280; dead `mapServiceToYesNo` :223-226 | HUB, LESSON |
| TaskGenerationService.swift | 190 | Catalog → conditions → user task batch write | 1 | PORT VERBATIM | NSNumber cast fix at :73 | LESSON, LEAF |
| TaskConditionerParser.swift | 206 | Condition evaluation (AND/OR, numeric ops) | 1 | PORT VERBATIM | Strict-cast fail-safe :69-74 (malformed → false); filename typo is historical, keep | LESSON, LEAF |
| AssessmentFlowView.swift | 165 | Hosts flow; owns/injects coordinator+data manager; routes 24 questions | 1 | PORT VERBATIM | Re-injects SubscriptionManager across fullScreenCover :59 (LE-023 fix) | COMPLIANCE, LESSON, HUB (structural) |
| AddressSearchManager.swift | 123 | MKLocalSearchCompleter wrapper | 4 | PORT VERBATIM | Reused by settings + task flow cards | HUB |
| PeezyAssessmentButton.swift | 84 | App-wide primary CTA | 28 | PORT VERBATIM | — | HUB |
| SelectionTile.swift | 137 | Single-select tile | 2 | PORT + ANNOTATE | — | LEAF |
| MultiSelectTile.swift | 154 | Multi-select tile w/ counts | 1 | PORT + ANNOTATE | — | LEAF |
| AnimatedAssessmentProgressBar.swift | 264 | Unused progress bar + header | 0 | DELETE | Live flow renders its own inline bar (AssessmentFlowView:65-103); 0 ext refs | LEAF (dead) |
| KeyboardObserver.swift | 37 | Keyboard height tracker | 0 | DELETE | 0 refs anywhere | LEAF (dead) |

### 2.4 Theme system (`Assessment/PeezyTheme/`)

| File Path | Lines | Purpose | Dependents | Classification | Evidence | Risk |
|---|---|---|---|---|---|---|
| peezyTheme.swift | 206 | Design system (colors/type/layout) | 69 | PORT VERBATIM | Top-3 hub | HUB |
| peezyHaptics.swift | 123 | Haptic helpers | 27 | PORT VERBATIM | — | HUB |
| PeezyCardChrome.swift | 37 | Glass card chrome modifier | 14 | PORT VERBATIM | — | HUB |
| ConfettiView.swift | 209 | Confetti particle system | 5 | PORT VERBATIM | — | HUB |
| PeezyLiquidGlass.swift | 197 | Liquid-glass modifier | 2 | PORT VERBATIM | Used by AppRootView loading view | LEAF |
| peezyLayout.swift | 279 | ~15 layout components | 0 live | DELETE | Sole external ref (`peezyGlassBackground`) is the iOS-16 fallback branch in PeezyLiquidGlass — unreachable on iOS-17+ minimum; every other member self-referenced only | LEAF (dead) |
| peezyButtonStyles.swift | 130 | Button styles | 1 | PORT VERBATIM | Only `.peezyPress` externally used (PeezySettingsView); 4 styles dead inside live file | LEAF |

### 2.5 Assessment UI (`Assessment/AssessmentViews/`)

Templates (`Components/`), all PRODUCTION, each consumed by question views:

| File Path | Lines | Purpose | Dependents | Classification | Evidence | Risk |
|---|---|---|---|---|---|---|
| Components/Singleselecttemplate.swift | 151 | 2-option page template | ~9 | PORT + ANNOTATE | Pure presentation; answers written by question views | HUB |
| Components/Gridselecttemplate.swift | 149 | Grid select template | ~5 | PORT + ANNOTATE | — | HUB |
| Components/Multiselecttemplate.swift | 171 | Multi-select template | 3 | PORT + ANNOTATE | — | LEAF |
| Components/Textentrytemplate.swift | 166 | Text entry template | 1 | PORT + ANNOTATE | — | LEAF |
| Components/Datepickertemplate.swift | 135 | Date picker template | 1 | PORT + ANNOTATE | — | LEAF |
| Components/Explainertemplate.swift | 132 | Explainer/transition template | 2 | PORT + ANNOTATE | — | LEAF |

Onboarding (`Onboarding/`):

| File Path | Lines | Purpose | Dependents | Classification | Evidence | Risk |
|---|---|---|---|---|---|---|
| Onboarding/CompletionFlowView.swift | 145 | Post-assessment stage machine → paywall gate | 1 | PORT VERBATIM | Paywall gating :52-58; re-injects SubscriptionManager :102 (LE-023) | COMPLIANCE, LESSON |
| Onboarding/GeneratingView.swift | 270 | Task-generation progress screen | 1 | PORT + ANNOTATE | Polls Firestore task count | LEAF |
| Onboarding/ReadyView.swift | 133 | "List ready" screen | 1 | PORT + ANNOTATE | — | LEAF |
| Onboarding/SummaryView.swift | 97 | Task-count summary + confetti | 1 | PORT + ANNOTATE | — | LEAF |
| Onboarding/AssessmentIntroView.swift | 93 | Pre-assessment intro | 1 | PORT + ANNOTATE | — | LEAF |

Questions (`Questions/`) — all 24 PRODUCTION, each routed only by AssessmentFlowView, each LEAF, all PORT + ANNOTATE (zero accessibility identifiers in the assessment flow):

| File Path | Lines | Notes |
|---|---|---|
| Questions/AddressAutocompleteView.swift | 254 | Shared by both address questions; inline (no template) |
| Questions/CurrentAddress.swift | 115 | Writes `currentAddress` + unit |
| Questions/NewAddress.swift | 115 | Writes `newAddress` + unit |
| Questions/UserName.swift | 43 | Skipped when SIWA pre-filled (Coordinator :246-248) |
| Questions/MoveDate.swift | 40 | — |
| Questions/CurrentRentOrOwn.swift | 26 | — |
| Questions/CurrentDwellingType.swift | 26 | Branching (adds floor-access) |
| Questions/CurrentFloorAccess.swift | 26 | Conditional |
| Questions/NewRentOrOwn.swift | 26 | — |
| Questions/NewDwellingType.swift | 26 | Branching |
| Questions/NewFloorAccess.swift | 26 | Conditional |
| Questions/AnyKids.swift | 30 | Branching |
| Questions/ChildrenInSchool.swift | 26 | Conditional |
| Questions/ChildrenInDaycare.swift | 26 | Conditional |
| Questions/HasVet.swift | 26 | — |
| Questions/Servicesintro.swift | 32 | Explainer |
| Questions/HireMovers.swift | 62 | Stores canonical "Yes"/"No" (lesson-bearing, §9) |
| Questions/TruckRental.swift | 26 | Conditional on hireMovers=No |
| Questions/HasDeclutter.swift | 26 | — |
| Questions/HireCleaners.swift | 26 | Stores canonical "Yes"/"No" |
| Questions/Addresschangeintro.swift | 32 | Explainer |
| Questions/FinancialInstitutions.swift | 61 | Categories only (not brands) |
| Questions/HealthcareProviders.swift | 61 | Categories only |
| Questions/FitnessWellness.swift | 62 | Categories only |
| Questions/HowHeard.swift | 26 | — |

### 2.6 Menu, Timeline, Schema, Utilities, Preview Content

| File Path | Lines | Purpose | Dependents | Classification | Evidence | Risk |
|---|---|---|---|---|---|---|
| Menu/PeezySettingsView.swift | 1148 | Settings: profile edits, subscription, deletion, sign-out, legal links | 1 | PORT VERBATIM | 14 ids; §4.5-4.6, §4.9. Known defect recorded (not fixed): `user_assessments` edits use `.limit(to:1)` with no orderBy (:743-797) — nondeterministic when retakes create multiple docs | COMPLIANCE |
| PeezyTimeline/TimelineService.swift | 126 | Firestore task fetcher (superseded) | 0 | DELETE | `fetchUserTasks()` has zero call sites; all 5 external "references" are comments (grep-verified this session). Superseded by PeezyCardFirestoreMapper | LEAF (dead), LESSON (its parity role transfers, §9) |
| Schema/TaskCatalogSchema.swift | 290 | Compiled documentation struct | 0 | DELETE | `.conditionFields`/`.assessmentFields` 0 access sites; only mentions are comments. Consider converting content to a markdown doc before deleting | LEAF (dead) |
| Utilities/DateProvider.swift | 62 | Injectable clock w/ DEBUG override | 3 | PORT VERBATIM | Used by PeezyCard, UserState, TaskGenerationService | LEAF |
| Preview Content/PreviewHelpers.swift | 105 | #Preview mock factories | preview-only | DELETE | Entire body inside `#if DEBUG` (:9-105). DEBUG-only per spec = DELETE (harmless to keep — human call) | LEAF |

### 2.7 Inventory capture (`Inventory/`) — production, partially frozen

| File Path | Lines | Purpose | Dependents | Classification | Evidence | Risk |
|---|---|---|---|---|---|---|
| Models/InventoryModels.swift | 143 | InventoryItem/BoundingBox/ScanSession + Firestore codecs | 9 | PORT VERBATIM | Safe double-cast at :90,96 | HUB, LESSON |
| Models/FrameExtractionResult.swift | 8 | ExtractedFrame struct | 6 | PORT VERBATIM | `sharpnessScore` field is a dead remnant of LE-006 removal — do not resurrect | HUB, LESSON |
| Models/InventorySessionManager.swift | 478 | Scan-session orchestrator + listener | 4 | PORT VERBATIM | Reworked in f7e47ad (App Store review #3) | HUB, LESSON, COMPLIANCE |
| ViewModels/RoomCaptureViewModel.swift | 254 | AVCaptureSession owner; record; extract | 1 | PORT VERBATIM | FROZEN (camera code, LE-005 family) | LESSON, LEAF |
| ViewModels/InventoryReviewViewModel.swift | 119 | Room review edit state | 1 | PORT + ANNOTATE | Moving-specific (tiers, box math) | LEAF |
| Views/CameraPreviewView.swift | 31 | UIViewRepresentable AVCaptureVideoPreviewLayer wrapper | 1 | PORT VERBATIM | **FROZEN (LE-005)** — layerClass override pattern :24-30 is the device-bug fix | LESSON, LEAF |
| Views/InventoryCameraView.swift | 505 | Camera viewfinder UI | 2 | PORT VERBATIM | Frozen region adjacent; moving copy only at :144,:370 | LESSON, LEAF |
| Views/InventoryFlowView.swift | 275 | State-driven flow container | 2 | PORT VERBATIM | Carries the Anthropic AI-disclosure copy (~:207-209, commit 05cfff1) — compliance text, do not reword casually | COMPLIANCE, LEAF |
| Views/InventoryProcessingView.swift | 103 | Processing loading screen | 1 | PORT + ANNOTATE | — | LEAF |
| Views/InventoryItemConfirmView.swift | 372 | Low-confidence confirm UI | 1 | PORT + ANNOTATE | Confidence threshold 0.9 lives in SessionManager:51 | LEAF |
| Views/InventoryRoomReviewView.swift | 577 | Room item list editor | 1 | PORT + ANNOTATE | Vertical-specific copy/icons (§6) | LEAF |
| Views/InventoryRoomHubView.swift | 371 | Scanned-rooms hub | 1 | PORT + ANNOTATE | — | LEAF |
| Views/InventoryLockedView.swift | 129 | Post-submission read-only view | 1 | PORT + ANNOTATE | — | LEAF |
| Services/FrameExtractionService.swift | 133 | AVAssetImageGenerator frame pulls | 1 | PORT VERBATIM | **LE-006 embodied**: returns ALL frames, `sharpnessScore: 1.0` hardcoded :74 — sharpness filtering must not return | LESSON, LEAF |
| Services/InventoryAPIClient.swift | 78 | processInventory/packageInventory callables | 1 | PORT VERBATIM | Payload is metadata-only (§6) | LEAF |
| Services/InventoryStorageService.swift | 224 | Frame upload + session doc + listener | 2 | PORT VERBATIM | Storage path constant :67 | LEAF |
| Services/InventoryEstimator.swift | 178 | Box/truck/labor math | 0 | DELETE | `InventoryEstimator`, `MovingEstimate`, `FurnitureSummaryItem` all 0 external refs; live estimates use InventoryReviewViewModel + packageInventory.js instead | LEAF (dead) |

### 2.8 Tasks tab data + UI (`Tasks/Store/`, `Tasks/Views/`) — rebuilt in 089749b, all lesson-bearing

| File Path | Lines | Purpose | Dependents | Classification | Evidence | Risk |
|---|---|---|---|---|---|---|
| Store/TasksStore.swift | 180 | Live snapshot listener on users/{uid}/tasks; action dispatch | 2 | PORT VERBATIM | The LIVE Tasks-tab data path (not TimelineService) | HUB, LESSON |
| Store/PeezyCardFirestoreMapper.swift | 75 | Firestore doc → PeezyCard (the 3rd live constructor) | 1 | PORT VERBATIM | Parity partner of PeezyHomeViewModel.loadTasks (§5.1) | LESSON, LEAF |
| Store/TaskAction.swift | 8 | Row action enum | 5 | PORT VERBATIM | — | HUB |
| Store/TaskGrouping.swift | 75 | Pure partition/sort of tasks | 3 | PORT VERBATIM | — | LEAF |
| Store/ConfettiBus.swift | 20 | Confetti trigger singleton | 2 | PORT VERBATIM | — | LEAF |
| Views/TasksTabView.swift | 130 | Tasks tab root | 1 | PORT + ANNOTATE | — | LEAF |
| Views/TasksList.swift | 101 | Task list scroll | 1 | PORT + ANNOTATE | — | LEAF |
| Views/TaskRow.swift | 101 | Expandable row | 2 | PORT + ANNOTATE | — | LEAF |
| Views/TaskRowButtons.swift | 106 | Status-aware button layouts | 1 | PORT + ANNOTATE | Special-cases scan_inventory :82-98 | LEAF |
| Views/TaskRowHeader.swift | 106 | Row header | 1 | PORT + ANNOTATE | — | LEAF |
| Views/TasksTabBar.swift | 58 | Segmented tab bar | 1 | PORT VERBATIM | Has 1 id | LEAF |
| Views/TaskTab.swift | 7 | Tab enum | 3 | PORT VERBATIM | — | LEAF |
| Views/TasksHeader.swift | 39 | Tab header | 1 | PORT + ANNOTATE | — | LEAF |
| Views/TasksEmptyState.swift | 33 | Empty states | 2 | PORT + ANNOTATE | — | LEAF |
| Views/TasksErrorBanner.swift | 43 | Error + retry banner | 1 | PORT + ANNOTATE | — | LEAF |
| Views/TasksOverlayLayer.swift | 27 | Confetti/reset overlay | 1 | PORT + ANNOTATE | — | LEAF |
| Views/PendingConfirmation.swift | 22 | Reset-confirm model | 1 | PORT VERBATIM | — | LEAF |
| Views/ResetInventoryOverlay.swift | 15 | Reset spinner | 1 | PORT + ANNOTATE | — | LEAF |
| Views/SecondaryActionButton.swift | 21 | Secondary button | 1 | PORT + ANNOTATE | — | LEAF |
| Views/TaskCategoryIcon.swift | 20 | Category → SF Symbol | 1 | PORT VERBATIM | — | LEAF |

### 2.9 Task flow component kit (`Tasks/Task Card Components/`)

| File Path | Lines | Purpose | Dependents | Classification | Evidence | Risk |
|---|---|---|---|---|---|---|
| TaskFlowTitleCard.swift | 135 | Flow cover page | 49 | PORT VERBATIM | Top hub of the flow kit | HUB |
| TaskFlowStack.swift | 68 | Card container/transition | 47 | PORT VERBATIM | — | HUB |
| TaskFlowDismissButton.swift | 33 | Inert shim (`body` = EmptyView) | 48 | PORT VERBATIM | Deliberate no-op kept for API compatibility; removing means editing 48 files for zero behavior change | HUB (inert) |
| TaskFlowInfoCard.swift | 84 | Info/warning card | 42 | PORT VERBATIM | 1 id | HUB |
| TaskFlowStatusCard.swift | 40* | Self-service terminal card (Later/In-progress/Done) | 40 | PORT VERBATIM | *87 lines; 40 dependents | HUB |
| TaskFlowSummaryCard.swift | 112 | Success terminal card | 26 | PORT VERBATIM | 1 id | HUB |
| TaskFlowTilesCard.swift | 145 | Core option-list primitive | 3 | PORT VERBATIM | 1 id | HUB (via variants) |
| TaskFlowTileVariants.swift | 413 | Select2-5/Multi3-6 arity wrappers | 14 max | PORT VERBATIM | `TaskFlowSelect5Card` = dead type (0 refs) — prune when touched | HUB |
| TaskFlowCompactTilesCard.swift | 104 | Binary yes/no tiles | 3 | PORT VERBATIM | — | LEAF |
| TaskFlowFillBarCard.swift | 124 | Fill-bar options | 1 | PORT VERBATIM | — | LEAF |
| TaskFlowDecisionCard.swift | 133 | "Peezy vs myself" card | 18 | PORT VERBATIM | — | HUB |
| TaskFlowHeader.swift | 52 | Shared card header | 11 | PORT VERBATIM | — | HUB |
| TaskFlowBusinessSearchCard.swift | 336 | MapKit business autocomplete | 13 | PORT VERBATIM | — | HUB |
| TaskFlowConfirmAddressCard.swift | 373 | Address confirm/edit | 7 | PORT VERBATIM | Receives the broken empty addresses from TaskFlowRouter (§7) | HUB |
| TaskFlowConfirmDateCard.swift | 229 | Date confirm/edit | 4 | PORT VERBATIM | — | LEAF |
| TaskFlowTitleCardBleed.swift | 120 | Alternate cover page | 0 | DELETE | 0 external refs (own #Preview only) | LEAF (dead) |
| FlowOption.swift | 21 | Tile option model | 24 | PORT VERBATIM | — | HUB |
| AdminMemoFlow.swift | 223 | Admin-pushed memo flow | 1 | PORT VERBATIM | Writes Firestore directly | LEAF |
| QuoteSelectionFlow.swift | 419 | Admin-pushed quote picker | 1 | PORT VERBATIM | Writes task doc + calls submitTaskFlow directly (:356,370) | LEAF |

### 2.10 Task flow screens (`Tasks/Task Cards/`) — 47 files, all PRODUCTION, each referenced only by TaskFlowRouter (LEAF), all PORT VERBATIM

These are heavily templated: all real logic lives in the §2.9 kit; each file is a declarative card-sequence config (local `@State currentIndex` + switch). They carry v1.0 behavior forward as-is; the v1 spine decision (§5.3, §11-Q4) determines whether they are later superseded by a data-driven engine.

Type 1 — self-service (Title→Info→Status), 88 lines each: ReturnKeysFlow, ScheduleTimeOffFlow, UpdateEmployerRecordsFlow, UpdateDriversLicenseFlow, NewDriversLicenseFlow, RegisterVehicleFlow, PhotographRentalFlow, BuyPackingSuppliesFlow, BuyCleaningSuppliesFlow, DefrostFreezerFlow, DiyDeepCleaningFlow, DiyFinalCleaningFlow, ForwardMailFlow, UpdateSchoolFlow, UpdateDaycareFlow, UpdateCreditCardsFlow, UpdateStudentLoansFlow, NotifySchoolFlow, EnrollNewSchoolFlow, FindNewDaycareFlow (20 files).
ScanInventoryFlow (89) — special: delegates to InventoryFlowView; polls `inventory/_metadata` (LESSON).

Type 2 — manage-provider (405-423 lines each): ManageGymFlow (423, reference template), ManageDoctorFlow, ManageDentistFlow, ManageVetFlow, ManageYogaFlow, ManageSpinFlow, ManageMassageFlow, ManageBankFlow, UpdateInvestmentFlow, TransferPharmacyFlow, TransferSpecialistsFlow (11 files).

Type 3 — decision + address (230-246 lines): ArrangeParkingNewFlow, ArrangeParkingOldFlow, ReserveElevatorsNewFlow, ReserveElevatorsOldFlow (246 ea, +date card), SetupUtilitiesFlow, CancelUtilitiesFlow, TransferUtilitiesFlow (230 ea) — all 7 receive empty address strings today (§7).

Type 4 — insurance: HandleAutoInsuranceFlow (419, covers 2 flowIds), HandleHomeInsuranceFlow (418, covers 10 flowIds).

Type 5/6 — survey/vendor: RentTruckFlow (115), FindMoversFlow (330), FindCleanersFlow (251), SetupInternetFlow (197), SellItemsFlow (200), RemoveItemsFlow (243).

---

## 3. Dependency Graph

**Hubs — cannot be touched in isolation (dependent count):**

| Type (file) | Dependents | Blast radius note |
|---|---|---|
| InteractiveBackground (HomeBackgroundComponents.swift) | ~80 | Every screen's background |
| PeezyTheme (peezyTheme.swift) | 69 | All styling |
| TaskFlowTitleCard | 49 | Every flow's cover |
| TaskFlowDismissButton | 48 | Inert — safe but wired everywhere |
| TaskFlowStack | 47 | Every flow's container |
| TaskFlowInfoCard / TaskFlowStatusCard | 42 / 40 | Flow kit |
| PeezyAssessmentButton | 28 | App-wide CTA |
| WorkflowService + WorkflowAnswers | 27 each | All submitting flows |
| PeezyHaptics | 27 | — |
| TaskFlowSummaryCard | 26 | — |
| FlowOption | 24 | Every option list |
| UserState | 21 | REWRITE target — plan migration order |
| PeezyCard + TaskStatus | 20 + 7 | REWRITE target — highest-risk rewrite in the map |
| TaskFlowDecisionCard | 18 | — |
| peezyCardChrome / TaskFlowSelect2Card / TaskFlowBusinessSearchCard / TaskFlowHeader | 14/14/13/11 | — |
| InventoryItem | 9 | — |
| SubscriptionManager | 7 | COMPLIANCE — do not rewrite |
| AuthViewModel / ExtractedFrame / ConfettiView / TaskAction | 6/6/5/5 | — |

**Structural chokepoints (low in-degree, high fan-out):** TaskFlowRouter (fans out to all 47 flows), PeezyMainContainer (owns all 4 tabs + TasksStore lifecycle), AssessmentFlowView (routes all 24 questions, owns both assessment env objects), AssessmentCoordinator/AssessmentDataManager (env-injected into every question), InventoryFlowView (fronts the whole capture subsystem), TasksStore (sole Tasks-tab data source).

**Leaves (safe to change in isolation):** all 47 Task Cards, all 24 assessment questions, all 6 templates, all Inventory views, all Tasks/Views files, onboarding screens, auth sheets.

**Cross-cutting rewrite coupling:** UserState ← AppRootView:137 (construction) and 21 consumers; PeezyCard ← 3 live constructors (PeezyHomeViewModel:295, PeezyCardFirestoreMapper:36, plus static factories) and 20 consumers. Rewriting either without a migration plan breaks the widest surfaces in the app.

---

## 4. Compliance Surface

Everything below is verified at file:line this session. This is the surface that survived three App Store rejections — treat every item as load-bearing.

1. **StoreKit 2** — all in `MainInterface/Models/SubscriptionManager.swift`: `loadProducts()` :130-147 (`Product.products(for:)`); `purchase()` :151-200 (verification handling, `finish()` after state update); `restorePurchases()` :204-220 (`AppStore.sync()`); `updateSubscriptionStatus()` :224-270 (`Transaction.currentEntitlements`, revocation/expiry/trial); transaction listener :290-301 started at app init (PeezyV1App.swift:20).
2. **Prices/trial text** — sourced live, never hardcoded: `PaywallGateView.swift` ctaLabel :172-195 (`intro.period.value`, `displayPrice`), pricing cards :219, :293-304; Settings plan label from `subscriptionPeriod.unit` (PeezySettingsView.swift:421-440). The mandated `grep -rn '\$[0-9]' --include="*.swift"` was run: **every hit is educational moving-cost copy or `$0` closure shorthand, zero subscription prices** — hits: QuoteSelectionFlow.swift:15 (doc comment), HandleHomeInsuranceFlow.swift:303, FindMoversFlow.swift:203,206, ForwardMailFlow.swift:48, ReserveElevatorsNewFlow.swift:164, ReturnKeysFlow.swift:48, SellItemsFlow.swift:87-90 (asset-value picker labels). Literal prices (49.99/6.99, 3-day trial) exist only in `Configuration.storekit` (local StoreKit test config, not shipped UI).
3. **Product IDs** — single definition: `SubscriptionManager.ProductID` :30-33 (`peezy.plus.weekly`, `peezy.plus.annual`); comparisons via `.rawValue` at SubscriptionManager :132,:137,:306 and PeezySettingsView :422. Matches Configuration.storekit :82,:112.
4. **Paywall gating** — hard gate after assessment, subscribers bypass: `CompletionFlowView.swift:52-58`; rendered :98-102; dismissible (X button, PaywallGateView :31-41) so the app is reachable unsubscribed. **The "three completed tasks" trigger named in the audit spec DOES NOT EXIST in code** — exhaustive grep found `PaywallGateView(` instantiated only in CompletionFlowView + previews, and no task-count-based presentation anywhere (see §11-Q6). Restore Purchases: paywall :112-123 AND Settings :374-384.
5. **Account deletion** — client `PeezySettingsView.deleteAccount()` :671-702 → callable `deleteAccount` (`functions/index.js:578-633`): recursive-deletes `users/{uid}`, `userKnowledge/{uid}`, cross-collection refs, Storage files, then `admin.auth().deleteUser`. **No client re-auth needed by design** — server-side Admin SDK deletion is not subject to `requiresRecentLogin` (grep for reauthenticate/requiresRecentLogin: zero hits).
6. **Sign out** — `AuthViewModel.signOut()` :204-208; downstream teardown AppRootView :64-71 (state + userState reset), PeezyMainContainer :92-97 (TasksStore stop).
7. **@EnvironmentObject chain** — declarations: AuthViewModel in 4 views; SubscriptionManager in 4 views; assessment pair in all 25 question views. Injections: root (PeezyV1App:27), AppRootView :35,:45, AuthView :191,:195 (sheets), AssessmentFlowView :55-56 (questions) and :59 (fullScreenCover re-injection), CompletionFlowView :102 (paywall re-injection). **No un-injected reachable path found.** The three fullScreenCover/sheet boundaries that cross env-consuming views are all defensively re-injected — this is the LE-023 crash fix in code. One latent fragility: `PeezyHomeView.swift:22` declares a `subscriptionManager` it never uses; if that view were ever presented in a fresh environment it would crash for an object it doesn't need.
8. **Privacy declarations** — Camera only: `INFOPLIST_KEY_NSCameraUsageDescription` in project.pbxproj :445 (Debug) and :486 (Release); feature reachable (Settings :449-451 → InventoryFlowView :213-215 → camera, plus ScanInventoryFlow). Mic/location/photos: correctly NOT declared and not used (video-only capture input; MKLocalSearchCompleter uses a static region; no photo pickers). `PrivacyInfo.xcprivacy`: declares only UserDefaults CA92.1 — **no `NSPrivacyCollectedDataTypes`/`NSPrivacyTracking` entries despite account data + frames sent to Anthropic; flag for review** (§11-Q8).
9. **Legal URLs** — `https://peezy-1ecrdl.web.app/privacy.html` + `/terms.html` (hosted from `public/` in this repo): paywall links PaywallGateView :137,:140; Settings rows :471-481; plain-text disclosure in InventoryFlowView :207. **Gap: no ToS/Privacy links on Auth/sign-up screens** (grep confirmed zero) — reviewers often expect them at account creation.

---

## 5. Task/Card Layer Assessment

### 5.0 Corrected live-path map (documented beliefs vs. reality)

- LIVE Home: `PeezyHomeViewModel.loadTasks()` (one-shot query).
- LIVE Tasks tab: `TasksStore` snapshot listener → `PeezyCardFirestoreMapper.card()` — **a fourth path absent from all project docs.**
- DEAD: `TimelineService.fetchUserTasks()` — zero callers; all references are comments (verified twice).
- ORPHANED: `PeezyStackViewModel.loadCardsFromFirestore()` — instantiated and loaded by PeezyMainContainer :19,:101-103, cards never rendered.
- `WorkflowManager.swift` (named a key file in CLAUDE.md) **does not exist**.
- There are 4 tabs (Home/Tasks/Chat/Settings), not 3; Chat = live SupportChatView.

### 5.1 PeezyCard construction-site audit (LE-025/LE-031)

Firestore-backed constructors: PeezyHomeViewModel.swift:295, TimelineService.swift:75 (dead), PeezyCardFirestoreMapper.swift:36 (live), PeezyStackViewModel.swift:140 (orphaned). Non-Firestore sites: PeezyCard static factories :271-341, PeezyResponse.swift:95 (backend JSON), previews.

**Parity verdict: the two LIVE paths are in sync on every field except `completedAt`**, which only PeezyCardFirestoreMapper populates (:56) — semi-intentional, since HomeVM filters completed tasks out (:273) and the Tasks tab needs it for the Done section. The orphaned PeezyStackViewModel path omits 10 fields (taskCategory, urgencyPercentage, userInProgressDate/ReturnDate, completedAt, selfServiceOnly, actionType, taskType, tips, whyNeeded) — moot once deleted. **No comment marks the coupling between the two live loaders** — the divergence bug remains one careless edit away (see §9).

### 5.2 Model, parser, routing, Daily Dose — key facts

- **PeezyCard** (MainInterface/Models/PeezyCard.swift): 28 fields (full list §2.1 evidence + agent-verified); `Equatable` is a **custom id-only `==`** (:365-367) — status-only changes are invisible to SwiftUI diffing/`onChange`. `taskType` is parsed by all live loaders and written by TaskGenerationService (:95, default "provide_info") but **never read by any logic** — a dormant routing key. `TaskStatus` has 7 cases; `matchingInProgress` is defined but queries instead filter on a raw `"pending"` string (HomeVM :261) that has no enum case and silently decodes to `.upcoming`.
- **TaskConditionParser** (TaskConditionerParser.swift): AND across keys (:66), OR within value arrays (:116-129), case-insensitive keys and values (:77,:118), malformed value → fail-safe `false` (:69-74), nil/empty conditions → auto-pass (:54), numeric operators >=/<=/>/< (:155-205), Bool/Int/Double coercion (:136). **No key aliasing exists** (no anyPets→hasPets mapping anywhere; the contract keys are produced upstream by AssessmentDataManager).
- **Routing**: closed switch, fully enumerated in §2.9-2.10. flowId resolution: `newFlowId(for:)` checks `card.workflowId` then lowercased `taskId` against the hardcoded `newFlowIds` set (PeezyHomeViewModel :84-122). Router: TaskFlowRouter.swift :26-155. `actionType`'s only consumer is completeTaskFlow :496 (`"off-app"` → complete vs in-progress). **Unroutable task = permanent spinner** (PeezyHomeView :311-321).
- **Daily Dose**: `dailyTarget = max(ceil(activeCount / workingDays), 1)` where workingDays = daysUntilMove − buffer (0/3/7 by proximity) (PeezyHomeViewModel :182-193); sort = urgencyPercentage desc, title asc (:336-341); snooze re-entry = lapsed `snoozedUntil` cards pass `shouldShow` back into the pool without a status write-back (:290, PeezyCard :185-195); snooze writes +2d (later) / +1d (skip) (:562,:592,:641-654).

### 5.3 What must change for ~8 new vendor task types + multi-stage spine + per-task capture (facts, not impressions)

1. **Stage state has no representation.** Stage = in-memory `currentIndex: Int` local to each flow struct; nothing persisted; TaskStatus has no stage cases. A Capture→Measure→Scope→Price→Compare→Book→Verify spine requires a new persisted stage model — this exists nowhere today.
2. **Routing requires 3 hand-edits per new task type** (newFlowIds entry + router case + new flow struct). The dormant `taskType`/`workflowId` fields already flow catalog→Firestore→PeezyCard, so a data-driven router has its inputs available — but no code reads them for routing.
3. **PeezyCard cannot carry stage/capture payloads** — fixed struct, no per-type payload, and its id-only Equatable will suppress UI updates for any new mutable stage field.
4. **Answer capture is per-flow ephemeral local state**, submitted once as opaque `[String:[String]]` (`WorkflowAnswers`) — no intermediate persistence, no resume, no cross-stage handoff.
5. **Per-task capture hook exists exactly once, bespoke**: ScanInventoryFlow delegates to the Inventory subsystem with dedicated lifecycle special-casing in TasksStore (:111-179) and TaskRowButtons (:82-98). No capture protocol/registry to attach an 8th vendor vertical to.
6. **What genuinely carries forward**: the §2.9 component kit (18 hub components hold all real flow UI), TasksStore/TaskGrouping list layer, TaskGenerationService + parser + catalog contract, WorkflowService submission path. The 47 flow structs are declarative configs over the kit — portable as-is, replaceable later.

---

## 6. Capture Pipeline: Generic vs. Vertical-Specific

Pipeline (verified hop-by-hop): RoomCaptureViewModel owns AVCaptureSession (:24,:118-144), records .mp4 to temp (:146-200) → FrameExtractionService pulls frames every 2.5s at ≤1280px via AVAssetImageGenerator (:10-116; count unbounded = floor(duration/2.5)+1) → InventoryStorageService uploads JPEGs (0.7 quality) to Storage `inventory/{userId}/{sessionId}/frame_{i}.jpg` (:58-77) → `processInventory` callable carries **metadata only** (userId/sessionId/roomName/frameCount) → function downloads frames server-side, calls Claude (`claude-sonnet-4-20250514`, max_tokens 4096, images-then-instruction single user message, processInventory.js:147-157) → normalizes/validates items (:183-230) → writes `users/{uid}/inventorySessions/{sessionId}` (:233-237) → client Firestore listener → confirm (<0.9 confidence) or review UI → user save writes durable `users/{uid}/inventory/{roomId}` + `_metadata` (InventorySessionManager :371-414,:455-468). Two distinct Firestore trees: transient `inventorySessions` (per-scan) vs durable `inventory` (user-saved); packageInventory.js reads only the durable tree.

**Separation verdict per stage:**

| Stage | Verdict | Evidence |
|---|---|---|
| Capture UI | Generic mechanics; moving-branded copy only | InventoryCameraView :144,:370 |
| Frame extraction | Fully generic | Pure AVFoundation, parameterized interval/size |
| Upload/invocation | Generic transport; vertical only in string constants | Storage path :67, collection names, callable name |
| Cloud function + vision prompt | **Hardcoded to moving — the entire vertical lives here** | Inline template literal processInventory.js:95-144 (furniture/boxable tiers, 9 cubic-ft reference points) + validation whitelists :183-185; NOT parameterized — client cannot pass prompt/schema |
| Response normalization | Structurally generic; values moving-specific | :183-230 |
| Review UI | Hardcoded furniture/boxable | InventoryReviewViewModel :52-56,:110-118; RoomReviewView icons :509-518 |
| Persistence schema | Moving-shaped fields, hardcoded paths | InventoryItem tier/cubicFeet/isFragile/shouldMove; paths in SessionManager :381-458 |

**Net:** to serve additional verticals, stages A-C need only constant changes; there is currently **no parameterization layer** — a new vertical means editing processInventory.js's inline prompt + whitelists and building a parallel review UI + item schema. The clean seam the new architecture needs is achievable (transport already domain-blind) but does not exist as an abstraction today.

**Frozen regions (recorded, not evaluated):** CameraPreviewView.swift :12-31 (layerClass-override wrapper — LE-005); sharpness filtering verified absent everywhere (LE-006) — remnants are only the dead `sharpnessScore` field (FrameExtractionResult.swift:7) and its hardcoded `1.0` (FrameExtractionService.swift:74); INVENTORY_STAGE2_SPEC.md:17 documents "Do NOT reintroduce sharpness filtering." Dead: InventoryEstimator.swift (§2.7); duplicated live estimate math exists in InventoryReviewViewModel (client) and packageInventory.js (server).

---

## 7. Identity Data: What Exists, What's Missing

**No single identity object exists.** Identity lives in three disconnected representations: (A) `AssessmentDataManager` @Published scalars during assessment; (B) flat dicts at rest in `users/{uid}/user_assessments/{auto-id}` (a NEW doc per completion/retake) + `userKnowledge/{uid}` (merged); (C) `UserState` struct built once at launch (AppRootView:137).

**Verified production bug (recorded, not fixed):** `UserState.init(from:)` reads `originCity/originState/destinationCity/destinationState/originBedrooms` (UserState.swift:168-171 etc.) — keys `getAllAssessmentData()` **never emits** (it emits single-string `currentAddress`/`newAddress`). These fields are always nil outside previews. Consequences: TaskFlowRouter :101-113 builds address strings from nil city/state → all 7 address flows (parking×2, elevators×2, utilities×3) open with empty addresses; `requestConcierge` payload sends blank currentAddress/newAddress (PeezyHomeViewModel :445-446). Whether the backend compensates by reading `userKnowledge` was not verified (§11-Q3).

**Field inventory:** name — assessment `userName`, Firebase Auth displayName (SIWA), UserDefaults cache `peezy.user.firstName`, `UserState.name`. Addresses — full strings exist ONLY at rest (`currentAddress`/`newAddress` + unit numbers, which have zero post-assessment readers). Move date — solid end-to-end (Timestamp → `UserState.moveDate`). Email — Firebase Auth only, never in Firestore/UserState. **Phone — does not exist anywhere in the codebase.** Distance/interstate — CLGeocoder straight-line, 50-mile threshold, administrativeArea comparison; all failure paths default "Long Distance"/"Yes" (over-prepare), 5s timeout race in completeAssessment (AssessmentDataManager :233-281, Coordinator :536-543); ~40 catalog tasks gate on these keys.

**Contract rot:** ~15 of the 44 keys `getAllAssessmentData()` emits are vestigial (always ""/[]/[:]: bedrooms, sq-ft ×4, storage ×3, hasVehiclesDetail, hirePackers, wantToSell, moveConcerns, referral/promo codes, all three `*Details` maps) — so `hasVehicles` is always "No" and `autoRoomList` is always the 5-room default. Multi-select tap counts are collected but dropped at persistence. Editability exists in Settings but targets `user_assessments` with `.limit(to:1)` and no orderBy — nondeterministic with multiple docs — and address edits do not recompute moveDistance.

**What the single identity object needs:** start from `UserState` (already threaded to 21 consumers via @Binding from AppRootView) but (a) carry full address strings + units instead of the never-populated city/state fields, (b) add email + phone, (c) replace the dead key mapping in `init(from:)`, (d) define one authoritative Firestore doc instead of newest-of-N assessment docs.

---

## 8. Backend Contract

Project `peezy-1ecrdl`, region us-central1. 13 deployed functions (exports in functions/index.js); full request/response shapes were captured and verified per function — headline contract:

| Function | Trigger | iOS caller | Purpose |
|---|---|---|---|
| peezyRespond | onRequest | **none live** (only via dead PeezyClient chain) | AI chat + initial_load card generator |
| requestConcierge | onCall | PeezyHomeViewModel:441 | Concierge request → Firestore + webhook + SMS |
| submitTaskFlow | onCall | QuoteSelectionFlow:370 (WebhookService dead) | Task-flow submission |
| submitSupportMessage | onCall | SupportChatService:67 | Support-chat notify + auto-ack |
| deleteAccount | onCall | PeezySettingsView:684 | Full data + Auth deletion |
| getWorkflowQualifying | onCall | **none** — zero Swift refs to "qualif" | Serves qualifying questions (orphaned) |
| submitWorkflowAnswers | onCall | WorkflowService:23 | Persists answers; guidance/mini-assessment/vendor branches |
| validateSubscription | onRequest | SubscriptionAPIClient:15 | Receipt sync |
| processInventory / packageInventory | onCall | InventoryAPIClient:22/:48 | §6 |
| joinWaitlist | onRequest | none (marketing site) | Waitlist |
| healthCheck / notificationHealthCheck | onRequest / onSchedule | none | Probes/alerts |

Key contract facts a rewritten client must honor:
- **LE-029 CONFIRMED**: zero webhook/n8n URLs in Swift (full `http` grep classified — only legal pages, cloudfunctions base, emulator localhost, Apple subscriptions URL). Notifications: callable → Firestore audit doc → `fetch(process.env.NOTIFICATION_WEBHOOK_URL)` (value not in repo) + Twilio SMS via notifyAdmin + hourly health check.
- **Firestore paths the client owns**: `taskCatalog` (read), `users/{uid}/tasks` (TaskGenerationService writes docId=TASK_ID; status updates from 3 UI paths), `user_assessments` + `userKnowledge` (assessment writes), `inventory`/`inventorySessions`/`supportChat`. Backend-only: conciergeRequests, taskFlowSubmissions, workflowSubmissions, adminNotifications, admin/*, subscriptions, waitlistSignups.
- **Server-created tasks use lowercase status `"pending"`** (mini-assessment branch) which the client's TaskStatus enum can't represent (decodes to .upcoming) — a live contract mismatch to preserve or fix deliberately.
- **submitWorkflowAnswers response omits** `submissionId/message/estimatedResponseTime` that the client's `WorkflowSubmissionResponse` models — client defaults mask it.
- **Catalog truth**: 56 tasks (not 70): actionType workflow=43 / off-app=12 / in-app-inventory=1; taskType survey=43 / provide_info=13; 44 distinct workflowIds. Server-side `WORKFLOW_QUALIFYING` (44 keys) + `MINI_ASSESSMENT_WORKFLOWS` (6) are **not consumed by the current client** (questions are hardcoded in Swift flows).
- **Secrets**: none client-side (grep-verified). Functions: ANTHROPIC_API_KEY via env, GMAIL_APP_PASSWORD via Secrets Manager, Twilio via env; serviceAccountKey.json only in standalone node scripts.
- **Possible rules gap**: client writes `userKnowledge/{uid}` (AssessmentDataManager:303) but local firestore.rules has no allow rule for it → §11-Q7.

---

## 9. Lesson-Bearing Code Index

Any file here is high-risk for a clean rewrite. LE labels absent from the repo are reconstructed (see header note); substance verified in code unless marked UNKNOWN.

| Lesson | File : symbol | What breaks if rewritten blind |
|---|---|---|
| LE-005 camera wrapper frozen | CameraPreviewView.swift:12-31, `layerClass` override → AVCaptureVideoPreviewLayer | Replacing the layer-backed pattern with sublayer insertion reintroduces device-only black/frozen preview |
| LE-006 sharpness filter removed | FrameExtractionService.swift:74 (all frames pass, score hardcoded 1.0); dead field FrameExtractionResult.swift:7 | Reintroducing frame filtering starves the vision model on real-device video (documented in INVENTORY_STAGE2_SPEC.md:17) |
| LE-007 keep ObservableObject | AssessmentCoordinator:99, AssessmentDataManager:8, AuthViewModel:16, SubscriptionManager:22 | Converting to @Observable breaks every `.environmentObject`/`@EnvironmentObject` pairing → missing-object crash |
| LE-023 env-object injection crash | AssessmentFlowView.swift:59 and CompletionFlowView.swift:102 re-injections across fullScreenCover; consumer PaywallGateView:16 | Dropping either re-injection crashes the assessment→paywall path (fullScreenCover does not inherit environment objects) |
| LE-025/LE-031 loader field parity | PeezyHomeViewModel.loadTasks :295-318 ↔ PeezyCardFirestoreMapper.card :36-63 (TimelineService is dead — **parity partner has changed**) | A field added to one live loader but not the other appears on Home but vanishes in the Tasks tab. **No comment marks the coupling** — add one, or centralize decoding, in any future edit |
| LE-026 StoreKit-sourced prices | SubscriptionManager :130-137,:305; PaywallGateView :172-193,:219,:293-304 | Hardcoded price/trial strings = rejection risk + wrong regional prices |
| LE-029 callable→webhook pattern | WorkflowService:23, PeezyHomeViewModel:441, SupportChatService:67, QuoteSelectionFlow:370; forwarding index.js:388-556 | Client-side webhook URLs leak endpoints and lose the Firestore audit + SMS fallback + health check |
| Parser strict cast | TaskConditionerParser.swift:69-74 | Reverting to `continue` makes malformed conditions auto-pass → ghost tasks for everyone |
| NSNumber casting | TaskGenerationService:73 (canonical); same pattern in all card loaders, UserState, InventoryStorageService | Plain `as? Int` on Firestore numbers yields nil → unsorted/missing cards. No unguarded `as? Int` remains today |
| Hiring label mapping | HireMovers.swift:21,48-49 / HireCleaners equivalent store canonical "Yes"/"No"; passthrough AssessmentDataManager:213-215; vestigial dead `mapServiceToYesNo` :223-226 | Restoring descriptive option labels without a mapping silently kills all mover/cleaner-conditioned tasks |
| Geocode failure fail-open | AssessmentDataManager:236-280 + fallback :207-208 (defaults "Long Distance"/"Yes"); 5s timeout Coordinator:536-543 | Leaving the keys empty on failure silently drops ~40 distance-gated tasks |
| 0.3s auto-advance chain | **GONE** — no dismissLeft/handleWorkflowContinue/isDemoWorkflow anywhere; current advance is immediate (FindMoversFlow:250-269) | Lesson maps to nothing; the demo-workflow system was removed in 089749b |
| cancelWorkflow/onWorkflowDismissed | **GONE** — WorkflowManager.swift absent | Lesson maps to nothing current |
| SIWA name capture (089749b) | AuthViewModel.handleAppleSignInCompletion :92-98 → UserDefaults + displayName; AssessmentDataManager.init bootstrap; Coordinator skips userName step :246-248 | Losing the first-authorization name capture re-triggers the Guideline-4 rejection (Apple only provides fullName once) |
| Tasks-tab rebuild (089749b) | TasksStore + PeezyCardFirestoreMapper + TaskGrouping + ToastManager + PeezyMainContainer wiring | This replaced the timeline stack — resurrecting TimelineService/PeezyStackViewModel patterns regresses it |
| AI disclosure (05cfff1) | InventoryFlowView.swift ~:207-209 Anthropic/AI disclosure copy + privacy link | Rewording/dropping this text re-opens the App Store privacy objection |
| Review #3 paywall/inventory (f7e47ad) | PaywallGateView (+69 lines), SubscriptionManager (+31), InventorySessionManager (major rework), CompletionFlowView; deleted PaywallValueView.swift | These diffs ARE the third-rejection fix; treat current behavior as reviewed-and-approved |

---

## 10. Accessibility Identifier Coverage

`grep -rn "accessibilityIdentifier" --include="*.swift"` → **51 usages in 13 of ~144 view files** (~9% file coverage). Existing coverage maps exactly to the T01–T10 UITest suite (`Peezy 4.0UITests/`):

| File | Count | Covers |
|---|---|---|
| Menu/PeezySettingsView.swift | 14 | T07 |
| MainInterface/Views/PeezyHomeView.swift | 10 | T02/T03 |
| MainInterface/Views/Paywall/PaywallGateView.swift | 8 | T08 |
| Auth/LogInView.swift / AuthView / SignUpView / PeezyFormField2 | 4/2/2/2 | T01 |
| MainInterface/Views/SupportChatView.swift | 3 | T06 |
| MainInterface/Views/PeezyMainContainer.swift | 2 | T09 |
| Tasks components (InfoCard/TilesCard/SummaryCard/TasksTabBar) | 1 each | T04/T05 |

**Unannotated (0 identifiers):** the entire assessment flow (24 questions + 6 templates + onboarding — the longest user journey), all Inventory views, 43 of 47 task-flow screens, most Tasks-tab views, toast/overlay layers. Automated verification of new work in those areas requires annotation first — hence the `PORT + ANNOTATE` classifications in §2. Test infrastructure that depends on identifiers: 13 UITest files + `E2ETestBase.swift`, plus `Tests/` and `Peezy 4.0Tests/` (19 test files total, outside the 195 production files).

---

## 11. Open Questions for Human Review

1. **Canonical lesson docs are off-repo.** `lessons-learned.md` / `peezy-conventions.md` exist only as Claude.ai project files; `tasks/lessons.md` (referenced by CLAUDE.md) doesn't exist. Options: commit them to the repo (single source of truth) or accept reconstruction risk each audit.
2. **v1.1 chat decision gates 3 files.** `peezyRespond` is deployed but has zero live client callers; `PeezyClient`/`PeezyResponse` are UNKNOWN pending the chat decision; `PeezyConfig` (live, used by receipt sync) must be extracted if they're deleted. Keep the client chain for v1.1, or delete and rebuild later?
3. **The blank-address bug (§7): fix now or fold into the identity rebuild?** Also unverified: whether backend concierge/n8n consumers compensate by reading `userKnowledge` — check n8n/admin side before deciding severity.
4. **Spine strategy: extend or replace the 47 flow structs?** Evidence supports either porting them as-is under a new data-driven router (safe, incremental) or superseding the templated Types 1-3 with a config-driven engine (39 of 47 files are near-identical copies). This is the central v1 build-spec decision; §5.3 lists the constraints.
5. **PeezyCard: extend in place or replace?** 20 dependents; must gain stage + capture payloads and lose the id-only Equatable hazard either way. Migration order matters (three live constructors).
6. **The "three completed tasks" paywall trigger does not exist in code.** Was it a planned-but-dropped feature, or does the audit spec describe an older build? Current gate is post-assessment-only.
7. **Firestore rules: client writes `userKnowledge/{uid}` but local firestore.rules has no allow rule for it.** Either the deployed ruleset differs (verify in console) or the write silently fails in production — both worth confirming.
8. **PrivacyInfo.xcprivacy has no data-collection declarations** despite account data + frames sent to Anthropic, and auth screens carry no ToS/Privacy links. Passed review three times, but both are cheap hardening items for the next submission.
9. **Server-created task status `"pending"`** has no TaskStatus case (decodes to .upcoming) and `matchingInProgress` is defined but never queried — reconcile the status contract before building the stage ladder on top of it.
10. **`backup/friend-changes-2026-04-28` branch** archives 74 modified + 7 untracked files "not intended for merge." Confirm nothing in it is needed before it drifts further.
11. **Orphaned server qualifying-question system** (`getWorkflowQualifying` + 44-key map + 6 mini-assessments): delete, or adopt as the data source for the data-driven flow engine in Q4?
12. **UNKNOWN classifications**: PeezyClient.swift, PeezyResponse.swift (both = Q2). All other files carry a definite classification.
13. **Doc regeneration**: both CLAUDE.md variants are stale on load-bearing facts (WorkflowManager, TimelineService, tab count, catalog size 56≠70, key-file list). Regenerating them from this map would prevent the next agent from acting on dead paths.
