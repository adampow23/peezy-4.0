# Build 24 implementation report

Date: 2026-08-16

## Status

All five requested fixes are implemented. The app builds for a generic iOS Simulator, the Build 24 regression tests pass, `functions/entitlement.js` passes syntax checking, and the supported native Node test set passes 104/104.

The repository-wide test commands are not wholly green for pre-existing reasons documented under **Verification**: one unrelated Swift unit expectation is stale, the raw recursive Node runner discovers Jest files, the nested Jest config points at a nonexistent doubled path, and Xcode's UI-test runner repeatedly failed simulator preflight/launch.

No commit or deployment was performed.

## Preflight and scope

- Read `CLAUDE.md` before inspecting or editing source.
- `BUILD24_AUDIT.md` is not present in the project root, elsewhere in this worktree, or in repository history. The implementation therefore used the supplied Build 24 instructions and the findings from the preceding read-only audit in this task as the source for audit sections 1–3.
- `PHASE_MANIFEST` was the first successfully changed repository file and now lists the complete Build 24 change set (`PHASE_MANIFEST:1-18`).
- Existing unrelated untracked files `entitlement-snapshot-1786850320161.json` and `functions/seedAppReviewGiftCode.js` were preserved unchanged.

## Fix 1 — research exit trap

### Entry points and final dismiss ownership

1. The post-flow fork enters `PostFlowForkView` from `FlowEngineView` (`Peezy 4.0/Tasks/FlowEngine/FlowEngineView.swift:125`). Its research phase embeds `TaskResearchModuleView` (`Peezy 4.0/Tasks/FlowEngine/PostFlowForkView.swift:127`). A persistent top-right close button now sits at the research presentation root, outside the module's `ScrollView`, and calls the idempotent `finish()` path (`PostFlowForkView.swift:113-153`, `PostFlowForkView.swift:211-216`). Its accessibility identifier is exactly `researchCloseButton` (`PostFlowForkView.swift:149`). Because it is a sibling of the complete research card, it remains visible for loading, absent, generating, failed, ready-without-entitlement, and ready states.
2. The task-detail route enters `TaskDetailView` from `TaskFlowRouter` (`Peezy 4.0/MainInterface/Models/TaskFlowRouter.swift:125`) and embeds the same research module inline (`Peezy 4.0/Tasks/Views/TaskDetailView.swift:200-213`). This entry already has the task-detail root close button outside its content `ScrollView` (`TaskDetailView.swift:43-69`), so no close control was added to the reusable `TaskResearchModuleView`.

The new post-flow control deliberately matches the established `FlowExitControl` 44-point, top-right full-screen pattern (`Peezy 4.0/Tasks/FlowEngine/FlowExitControl.swift:254-272`).

## Fix 2 — entitlement denials route to the paywall

### Server error contract

`requireMovePass` now throws:

```text
HttpsError(
  code: "permission-denied",
  message: "Move Pass required",
  details: { reason: "move-pass-required" }
)
```

Evidence: `functions/entitlement.js:39-46`. The message is unchanged, and the only edit in that file is the new details argument. The same helper protects all three callables: `processInventory` (`functions/processInventory.js:632`), `researchTask` (`functions/researchTask.js:774`), and `peezyChat` (`functions/peezyChat.js:378`). On Apple clients, the callable code is `FunctionsErrorCode.permissionDenied` (raw code 7) in `FunctionsErrorDomain`, with the details map under `FunctionsErrorDetailsKey`.

### Shared Swift classification

`FunctionsErrorClassifier` recognizes only this combination:

- `FunctionsErrorDomain`;
- `.permissionDenied`;
- either `details.reason == "move-pass-required"` or the migration fallback message exactly equal to `Move Pass required`.

Other permission denials remain unclassified (`Peezy 4.0/MainInterface/Models/FunctionsErrorClassifier.swift:1-26`). The details extraction supports both Swift dictionaries and `NSDictionary` bridging.

### Scanner

- `InventoryAPIClient` converts the typed callable denial to `InventoryError.movePassRequired`; all other callable mappings remain separate (`Peezy 4.0/Inventory/Services/InventoryAPIClient.swift:29-69`, `InventoryAPIClient.swift:73-89`).
- The complete post-upload callable payload is represented by `InventoryProcessingRequest` (`InventoryAPIClient.swift:4-19`).
- `InventorySessionManager` retains that request on entitlement denial, exposes `movePassRequired`, clears the generic error, and returns to the room list instead of silently losing the work (`Peezy 4.0/Inventory/Models/InventorySessionManager.swift:347-398`). `retryRetainedProcessingRequest()` reuses the same uploaded user/session/room/frame payload without frame extraction or upload (`InventorySessionManager.swift:400-417`). Reset and listener cleanup discard retained state (`InventorySessionManager.swift:500-504`, `InventorySessionManager.swift:671-675`).
- `InventoryFlowView` presents the existing `PaywallGateSheet(surface: .scanner)` from that state. Purchase or gift-code redemption success retries the retained request; dismissal discards it (`Peezy 4.0/Inventory/Views/InventoryFlowView.swift:191-200`, `InventoryFlowView.swift:282-290`). The existing paywall owns the redeem-code option.

### Research

- `TaskResearchModel.generateResearch` returns a typed outcome. A Move Pass denial restores the module to `.absent` and returns `.movePassRequired`; unrelated failures still become `.failed` (`Peezy 4.0/Tasks/Views/TaskResearchModule.swift:177-184`, `TaskResearchModule.swift:249-282`).
- `TaskDetailView` stores the denied request in `pendingResearchRequest`, which drives its existing research paywall binding and retries the same request on success (`Peezy 4.0/Tasks/Views/TaskDetailView.swift:99-106`, `TaskDetailView.swift:216-243`).
- `PostFlowForkView` stores the denied request and changes to `.paywall`; its existing completion path returns to research and retries that request (`Peezy 4.0/Tasks/FlowEngine/PostFlowForkView.swift:165-177`, `PostFlowForkView.swift:196-205`). Automatic post-flow generation now uses the same typed request path (`PostFlowForkView.swift:180-185`).

### Purchase race

The direct StoreKit purchase path now waits for the first of server sync or a five-second timeout before returning `.success` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:177-191`, `SubscriptionManager.swift:435-455`). The race uses independent tasks rather than a structured group that could wait indefinitely for a cancellation-insensitive Firebase call. A failure or timeout does not create a new purchase failure state; local StoreKit success remains authoritative and a slow sync remains best effort.

### Explicit non-scope

No AI-chat gating was added. `SupportChatView` and the `peezyChat` client call site were not changed, and human support behavior remains untouched.

## Fix 3 — scanner dismiss ownership

`InventoryFlowHostingMode` makes ownership explicit (`Peezy 4.0/Inventory/Views/InventoryFlowView.swift:12-20`). The task route passes `.task` (`Peezy 4.0/Tasks/Task Cards/ScanInventoryFlow.swift:31-35`); Settings passes `.settings` (`Peezy 4.0/Menu/PeezySettingsView.swift:217-227`).

| Surface/state | Task-hosted behavior | Settings-hosted behavior | Actual action |
|---|---|---|---|
| Intro/info and first-scan coaching | The outer top-right `FlowExitControl` is the single visible whole-task X. Coaching has no internal X (`InventoryScanCoachingView.swift:10-75`). | The settings host overlay supplies the top-right whole-flow X. | Calls `InventoryFlowView.closeFlow()` for Settings; task exit goes through `FlowExitControl` and its exit coordinator. |
| Room hub / room-name entry / estimate | The room-hub X is suppressed by `showsDismissControl: false`. | The room hub keeps its own top-right X; the settings overlay is suppressed here to avoid duplication. | Whole-flow dismissal (`InventoryRoomHubView.swift:46-72`; `InventoryFlowView.swift:79-84`, `293-303`). |
| Camera | The outer task X remains top-right. The camera's existing top-left X remains. | The settings whole-flow X is top-right. The camera's existing top-left X remains. | Top-right exits the host flow. Top-left first cleans capture and then returns only to the room hub (`InventoryCameraView.swift:269-285`; `InventoryFlowView.swift:88-96`). The two controls now have distinct corners and distinct scopes. |
| Camera permission/error fallbacks | Host whole-flow X remains available. | Settings whole-flow X remains available. | Existing `Go back` and error `Dismiss` controls call the same camera `onCancel`, returning to rooms (`InventoryCameraView.swift:188-205`, `InventoryCameraView.swift:473-496`). |
| Processing | Host whole-flow X remains available. | Settings whole-flow X remains available. | Whole-flow exit; `InventoryProcessingView` still has no child dismiss of its own. |
| Item confirmation | Host whole-flow X remains available. | Settings whole-flow X remains available. | Whole-flow exit. The card's internal “Cancel” only leaves its correction-edit mode; it is not a scanner dismiss. |
| Room review | Host whole-flow X remains available. | Settings whole-flow X remains available. | Whole-flow exit. Delete-alert Cancel only cancels deletion; Rescan returns to camera (`InventoryRoomReviewView.swift:65-86`; `InventoryFlowView.swift:117-129`). |
| Submitted/locked inventory | The outer task X remains the host owner. | `InventoryLockedView` keeps its existing X and the settings overlay is suppressed. | Whole-flow dismissal (`InventoryLockedView.swift:52-68`; `InventoryFlowView.swift:53-61`, `293-297`). |

The settings overlay uses the same 44-point visual geometry as the task flow control and has accessibility identifier `inventory.settings.close` (`InventoryFlowView.swift:305-324`). The retained room-hub control now has identifier `inventory.roomHub.close` (`InventoryRoomHubView.swift:49-69`). No capture/review view was duplicated.

## Fix 4 — quote entry labels

The Compare Quotes add/edit form now gives every requested field both a persistent visible caption and a matching placeholder/accessibility label:

- Company name
- Crew size
- Hours they quoted
- Hourly rate ($)
- Travel fee ($)
- Notes

Evidence: `Peezy 4.0/Tasks/Task Cards/MoversQuotesView.swift:118-200`. Existing field accessibility identifiers were retained.

## Fix 5 — off-app header mismatch

### Cause

Catalog presentation data is stored under the catalog document's nested `content` map (`functions/seedTaskCatalog.js:164-165`; examples at `functions/taskCatalogData.json:1043-1051` and `1185-1199`). `TaskDetailView` passes the complete catalog document to `TaskContent` (`Peezy 4.0/Tasks/Views/TaskDetailView.swift:431-460`), but the old decoder read `tripKit` and `walkthrough` only from the top level. Header text was then separately hard-coded in each view. That split allowed the displayed section identity and the catalog content shape to drift.

### Fix

- `TaskContent` now reads presentation fields from nested `content`, with top-level fallback for existing direct callers/previews, while `notesEnabled` and `quoteTracker` remain top-level. NSNumber-safe boolean decoding is retained (`Peezy 4.0/Tasks/Views/TaskContentSections.swift:7-34`).
- Semantic headers are centralized: trip-kit/document content is `What to bring`; walkthrough steps are `Guided next steps` (`TaskContentSections.swift:54-57`).
- `TripKitSection`, `WalkthroughDisclosure`, and the deep-link walkthrough fork use the appropriate semantic header (`TaskContentSections.swift:238-247`, `308-337`, `346-380`).

No catalog seed, workflow definition, or flow-definition file was changed.

## Regression coverage

`Peezy 4.0Tests/Build24RegressionTests.swift:1-101` covers:

- stable details-based denial classification;
- exact legacy-message fallback;
- rejection of unrelated permission denials;
- nested catalog-content decoding and exact semantic headers;
- scanner retry reusing the identical retained uploaded-session request.

`functions/tests/entitlement.test.js:1-15` locks the server error's code, unchanged message, and stable reason.

## Verification

| Check | Result |
|---|---|
| `xcodebuild ... -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO -quiet` | **PASS**. Final build completed with exit 0. Existing Swift 6 migration and Crashlytics script warnings remain outside this change set. |
| Build 24 Swift regression suite | **PASS**, 5/5. The final serial unit-target run also records all five as passed. |
| Swift unit-test target, serial | **101 passed, 2 skipped, 1 failed**. The sole failure is existing `AssessmentTier3MigrationTests.swift:30`: expected `steps.count == 26`, actual 25. That test and assessment code were not changed. |
| Full Xcode test plan | **Not green / harness degraded**. Before the run was stopped after repeated no-progress retries, it reproduced the same unrelated unit failure, reported an existing `EstimateIntegrityPhaseBUITests.testCoverageStripAndActions` failure, and repeatedly failed parallel UI-runner launches with simulator `Busy` preflight errors. A focused Settings scanner UI test was retried serially on both the original and a separate clean simulator; the runner still failed/hung during launch diagnostics, so no assertion result was available. |
| `node --check entitlement.js` in `functions` | **PASS**. |
| `node --test *.test.js tests/*.test.js` in `functions` | **PASS**, 104/104. |
| Literal recursive `node --test` in `functions` | **Not green due to repository test-runner mixing**: the same 104 native tests pass, while 8 files under `functions/peezy-brain-ralph/tests` fail because Node's runner discovers Jest globals (`expect`, `describe`, `beforeAll`). |
| Nested `peezy-brain-ralph` intended `npm test -- --runInBand` | **Configuration failure before tests**: Jest resolves `<rootDir>` to `.../tests` but requests `<rootDir>/tests/helpers/matchers.js`, which does not exist. No nested test source/config was changed. |
| `git diff --check` | **PASS**. |

## Constraint confirmation

- No Firestore/security rules changed.
- The `entitlement.js` edit is limited to the HttpsError details field.
- No human-support-chat, AI-chat routing, dose math, catalog data, or flow definitions changed.
- No commit, deployment, seed, or destructive repository operation was performed.
