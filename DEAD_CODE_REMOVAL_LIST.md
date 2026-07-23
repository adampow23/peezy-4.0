# Dead Code Removal List

Generated 2026-07-23 at commit `861f7e2` (audit baseline `f7e47ad` + Phase 1/2 cleanup commits).
Final independent confirmation pass for the DELETE candidates named in the pre-rebuild
cleanup spec. Every grep below was run this session across the entire source tree —
production (`Peezy 4.0/`) plus all three test targets (`Peezy 4.0Tests/`, `Peezy 4.0UITests/`, `Tests/`) —
using the pattern:

```
grep -rnE "<symbols>" --include="*.swift" "Peezy 4.0" "Peezy 4.0Tests" "Peezy 4.0UITests" Tests
```

No file was deleted or modified by this pass. Deletion happens through Xcode (removes the
`project.pbxproj` reference together with the file), performed by Adam.

**Summary: 7 SAFE TO DELETE (files) · 1 SAFE TO DELETE (code edit, not a file) · 2 NEEDS REVIEW**

| # | Item | Lines | Verdict |
|---|---|---|---|
| 1 | Inventory/Services/InventoryEstimator.swift | 178 | SAFE TO DELETE |
| 2 | Schema/TaskCatalogSchema.swift | 290 | SAFE TO DELETE |
| 3 | Assessment/AssessmentModels/AnimatedAssessmentProgressBar.swift | 264 | SAFE TO DELETE |
| 4 | Assessment/AssessmentModels/KeyboardObserver.swift | 37 | SAFE TO DELETE |
| 5 | Assessment/PeezyTheme/peezyLayout.swift | 279 | NEEDS REVIEW |
| 6 | MainInterface/Models/PeezyStackViewModel.swift | 559 | NEEDS REVIEW |
| 7 | MainInterface/Views/TaskFlow/WebhookService.swift | 42 | SAFE TO DELETE |
| 8 | Tasks/Task Card Components/TaskFlowTitleCardBleed.swift | 120 | SAFE TO DELETE |
| 9 | `TaskFlowSelect5Card` (type inside TaskFlowTileVariants.swift) | ~95 | SAFE TO DELETE (code edit) |
| 10 | PeezyTimeline/TimelineService.swift | 126 | SAFE TO DELETE |

---

## 1. Inventory/Services/InventoryEstimator.swift — SAFE TO DELETE

Command:
```
grep -rnE "InventoryEstimator|MovingEstimate|FurnitureSummaryItem" --include="*.swift" "Peezy 4.0" "Peezy 4.0Tests" "Peezy 4.0UITests" Tests
```
Output:
```
Peezy 4.0/Inventory/Services/InventoryEstimator.swift:3:struct MovingEstimate {
Peezy 4.0/Inventory/Services/InventoryEstimator.swift:17:    let furnitureItems: [FurnitureSummaryItem]
Peezy 4.0/Inventory/Services/InventoryEstimator.swift:54:struct FurnitureSummaryItem {
Peezy 4.0/Inventory/Services/InventoryEstimator.swift:63:enum InventoryEstimator {
Peezy 4.0/Inventory/Services/InventoryEstimator.swift:90:    static func estimate(from rooms: [ScannedRoom]) -> MovingEstimate {
Peezy 4.0/Inventory/Services/InventoryEstimator.swift:142:        let furnitureSummary: [FurnitureSummaryItem] = furnitureItems.map { item in
Peezy 4.0/Inventory/Services/InventoryEstimator.swift:143:            FurnitureSummaryItem(
Peezy 4.0/Inventory/Services/InventoryEstimator.swift:153:        return MovingEstimate(
```
Analysis: every hit is inside the file itself. All three declared types
(`InventoryEstimator`, `MovingEstimate`, `FurnitureSummaryItem`) have zero external
references anywhere, including tests. Live estimate math lives in
InventoryReviewViewModel (client) and packageInventory.js (server).

## 2. Schema/TaskCatalogSchema.swift — SAFE TO DELETE

Command:
```
grep -rnE "TaskCatalogSchema|AssessmentSource|ConditionFieldInfo" --include="*.swift" "Peezy 4.0" "Peezy 4.0Tests" "Peezy 4.0UITests" Tests
```
Output (in-file hits compressed — 25 hits at TaskCatalogSchema.swift:4–288, all
declarations/self-references; every external hit shown in full):
```
Peezy 4.0/Assessment/AssessmentModels/TaskGenerationService.swift:11:// See TaskCatalogSchema.swift for full documentation.
Peezy 4.0/Assessment/AssessmentModels/TaskConditionerParser.swift:10:// CONDITION FORMAT (from TaskCatalogSchema.swift):
Tests/ConditionParserV2Test.swift:96:// TEST CASES (from real Firestore data via TaskCatalogSchema)
Tests/IntegrationTest.swift:10:// Tests against REAL Firestore task data (from TaskCatalogSchema)
```
Analysis: all four external references are comment lines — no code accesses
`TaskCatalogSchema`, `.conditionFields`, `.assessmentFields`, `AssessmentSource`, or
`ConditionFieldInfo`. Deleting the file leaves four stale doc-comments (harmless;
listed here so they can be cleaned during the rebuild). The architecture map suggests
optionally converting the file's schema documentation to markdown before deleting —
human call, not required for safety.

## 3. Assessment/AssessmentModels/AnimatedAssessmentProgressBar.swift — SAFE TO DELETE

Command:
```
grep -rnE "AnimatedAssessmentProgressBar|AssessmentProgressHeader" --include="*.swift" "Peezy 4.0" "Peezy 4.0Tests" "Peezy 4.0UITests" Tests
```
Output:
```
Peezy 4.0/Assessment/AssessmentModels/AnimatedAssessmentProgressBar.swift:2://  AnimatedAssessmentProgressBar.swift
Peezy 4.0/Assessment/AssessmentModels/AnimatedAssessmentProgressBar.swift:12:struct AnimatedAssessmentProgressBar: View {
Peezy 4.0/Assessment/AssessmentModels/AnimatedAssessmentProgressBar.swift:206:struct AssessmentProgressHeader: View {
Peezy 4.0/Assessment/AssessmentModels/AnimatedAssessmentProgressBar.swift:236:            AnimatedAssessmentProgressBar(
Peezy 4.0/Assessment/AssessmentModels/AnimatedAssessmentProgressBar.swift:253:            AssessmentProgressHeader(
```
Analysis: all hits in-file (the :236/:253 references are its own previews). The live
assessment flow renders its own inline progress bar (AssessmentFlowView.swift:65-103).

## 4. Assessment/AssessmentModels/KeyboardObserver.swift — SAFE TO DELETE

Command:
```
grep -rnE "KeyboardObserver" --include="*.swift" "Peezy 4.0" "Peezy 4.0Tests" "Peezy 4.0UITests" Tests
```
Output:
```
Peezy 4.0/Assessment/AssessmentModels/KeyboardObserver.swift:2://  KeyboardObserver.swift
Peezy 4.0/Assessment/AssessmentModels/KeyboardObserver.swift:6://  Usage: @StateObject private var keyboard = KeyboardObserver()
Peezy 4.0/Assessment/AssessmentModels/KeyboardObserver.swift:12:final class KeyboardObserver: ObservableObject {
```
Analysis: definition and its own doc-comment only. Zero references anywhere.

## 5. Assessment/PeezyTheme/peezyLayout.swift — NEEDS REVIEW

Command (every public symbol the file declares):
```
grep -rnE "peezyCard|peezyCardSmall|peezyHorizontalPadding|peezyGlassBackground|peezyCardShadow|peezySubtleShadow|peezyButtonShadow|peezyBrandGlow|PeezyPrimaryButton|PeezySecondaryButton|PeezySectionHeader|PeezyIconCircle|PeezyDivider|PeezyLoadingView|PeezyEmptyState" --include="*.swift" "Peezy 4.0" "Peezy 4.0Tests" "Peezy 4.0UITests" Tests
```
Output (in-file hits at peezyLayout.swift:15–257 omitted; all external hits shown):
```
Peezy 4.0/Assessment/PeezyTheme/peezyButtonStyles.swift:26:struct PeezyPrimaryButtonStyle: ButtonStyle {
Peezy 4.0/Assessment/PeezyTheme/peezyButtonStyles.swift:38:struct PeezySecondaryButtonStyle: ButtonStyle {
Peezy 4.0/Assessment/PeezyTheme/peezyButtonStyles.swift:107:extension ButtonStyle where Self == PeezyPrimaryButtonStyle {
Peezy 4.0/Assessment/PeezyTheme/peezyButtonStyles.swift:109:    static var peezyPrimary: PeezyPrimaryButtonStyle { PeezyPrimaryButtonStyle() }
Peezy 4.0/Assessment/PeezyTheme/peezyButtonStyles.swift:112:extension ButtonStyle where Self == PeezySecondaryButtonStyle {
Peezy 4.0/Assessment/PeezyTheme/peezyButtonStyles.swift:114:    static var peezySecondary: PeezySecondaryButtonStyle { PeezySecondaryButtonStyle() }
Peezy 4.0/Assessment/PeezyTheme/peezyButtonStyles.swift:129:    static var peezyCard: PeezyCardButtonStyle { PeezyCardButtonStyle() }
Peezy 4.0/Assessment/PeezyTheme/PeezyLiquidGlass.swift:6://  and a safe fallback to peezyGlassBackground on earlier iOS.
Peezy 4.0/Assessment/PeezyTheme/PeezyLiquidGlass.swift:64:                .peezyGlassBackground(cornerRadius: cornerRadius)
```
Analysis of external hits:
- The seven peezyButtonStyles.swift hits are **name collisions, not references**:
  `PeezyPrimaryButtonStyle`/`PeezySecondaryButtonStyle` are distinct types that merely
  share a prefix with peezyLayout's `PeezyPrimaryButton`/`PeezySecondaryButton`, and
  `peezyCard` at :129 is a `ButtonStyle` static member defined in peezyButtonStyles
  itself, unrelated to peezyLayout's `View.peezyCard()` modifier.
- PeezyLiquidGlass.swift:6 is a comment.
- **PeezyLiquidGlass.swift:64 is a live compile-time reference.** It sits in the
  `else` branch of `if #available(iOS 17, *)` (PeezyLiquidGlass.swift:23, branch at
  :61-65, labeled "iOS 16 fallback"). `IPHONEOS_DEPLOYMENT_TARGET = 17.0` in both
  Debug and Release configs (verified in project.pbxproj), so the branch is
  **unreachable at runtime** — confirming the audit — but it still compiles.

Verdict rationale: deleting peezyLayout.swift alone **breaks the build** at
PeezyLiquidGlass.swift:64. Removal order for Adam:
1. In PeezyLiquidGlass.swift, remove the `if #available(iOS 17, *)` check and its
   iOS-16 else-branch (:23, :61-65), keeping the iOS-17 body unconditionally
   (`LiquidRefractionLayer` is already `@available(iOS 17, *)`).
2. Then delete peezyLayout.swift through Xcode.
3. Build.

## 6. MainInterface/Models/PeezyStackViewModel.swift — NEEDS REVIEW

Command:
```
grep -rnE "PeezyStackViewModel" --include="*.swift" "Peezy 4.0" "Peezy 4.0Tests" "Peezy 4.0UITests" Tests
```
Output (in-file hits at PeezyStackViewModel.swift:6–186 omitted; all external hits shown):
```
Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift:18:    // Timeline still uses PeezyStackViewModel for its data loading
Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift:19:    @State private var timelineViewModel = PeezyStackViewModel()
```
The remaining referencer (the spec asked it to be identified): **PeezyMainContainer.swift**,
lines 18 (comment), 19 (instantiation), and its `timelineViewModel` usages:
```
grep -n "timelineViewModel" "Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift"
19:    @State private var timelineViewModel = PeezyStackViewModel()
101:                timelineViewModel.userState = userState
103:                    await timelineViewModel.loadInitialCards()
```
Analysis: the VM is instantiated and loads Firestore data on tab switch, but its
`cards` array is never rendered anywhere (audit-verified; the Tasks tab renders from
`TasksStore`). The load is pure wasted Firestore reads. The comment at :18 is stale —
the Timeline tab no longer exists; Tasks is served by TasksStore.

Verdict rationale: live compile-time referencer → NEEDS REVIEW per the spec's rule.
Removal order for Adam:
1. In PeezyMainContainer.swift remove lines 18-19 and the two `timelineViewModel`
   statements at :101 and :103 (keep the surrounding `userState` handling intact).
2. Then delete PeezyStackViewModel.swift through Xcode.
3. Build.
Note: PeezyMainContainer is a structural hub (owns all 4 tabs) — this is a 4-line
excision, not a refactor.

## 7. MainInterface/Views/TaskFlow/WebhookService.swift — SAFE TO DELETE

Command:
```
grep -rnE "WebhookService" --include="*.swift" "Peezy 4.0" "Peezy 4.0Tests" "Peezy 4.0UITests" Tests
```
Output:
```
Peezy 4.0/MainInterface/Views/TaskFlow/WebhookService.swift:4:enum WebhookService {
```
Analysis: definition only — zero references anywhere, including tests.
QuoteSelectionFlow calls the `submitTaskFlow` callable directly.

## 8. Tasks/Task Card Components/TaskFlowTitleCardBleed.swift — SAFE TO DELETE

Command:
```
grep -rnE "TaskFlowTitleCardBleed" --include="*.swift" "Peezy 4.0" "Peezy 4.0Tests" "Peezy 4.0UITests" Tests
```
Output:
```
Peezy 4.0/Tasks/Task Card Components/TaskFlowTitleCardBleed.swift:2://  TaskFlowTitleCardBleed.swift
Peezy 4.0/Tasks/Task Card Components/TaskFlowTitleCardBleed.swift:18:struct TaskFlowTitleCardBleed: View {
Peezy 4.0/Tasks/Task Card Components/TaskFlowTitleCardBleed.swift:77:TaskFlowTitleCardBleed(
Peezy 4.0/Tasks/Task Card Components/TaskFlowTitleCardBleed.swift:86:TaskFlowTitleCardBleed(
Peezy 4.0/Tasks/Task Card Components/TaskFlowTitleCardBleed.swift:95:TaskFlowTitleCardBleed(
Peezy 4.0/Tasks/Task Card Components/TaskFlowTitleCardBleed.swift:104:TaskFlowTitleCardBleed(
Peezy 4.0/Tasks/Task Card Components/TaskFlowTitleCardBleed.swift:113:TaskFlowTitleCardBleed(
```
Analysis: all hits in-file (:77–113 are its own `#Preview` blocks). The live cover
page for all 47 flows is TaskFlowTitleCard.

## 9. `TaskFlowSelect5Card` — SAFE TO DELETE (code edit, not a file deletion)

Command:
```
grep -rnE "TaskFlowSelect5Card" --include="*.swift" "Peezy 4.0" "Peezy 4.0Tests" "Peezy 4.0UITests" Tests
```
Output:
```
Peezy 4.0/Tasks/Task Card Components/TaskFlowTileVariants.swift:108:struct TaskFlowSelect5Card: View {
Peezy 4.0/Tasks/Task Card Components/TaskFlowTileVariants.swift:325:TaskFlowSelect5Card(
```
Analysis: declared at TaskFlowTileVariants.swift:108; the only other reference (:325)
is inside the file's own `#Preview("SS-5 · Insurance Provider")` block (verified this
session at :323-330). Zero production references.

This item is a type inside a **live** file (the other tile variants are used by up to
14 flows), so removal is an edit to TaskFlowTileVariants.swift — delete the
`TaskFlowSelect5Card` struct and its preview block — not an Xcode file deletion. Left
untouched by this phase per the report-only boundary.

## 10. PeezyTimeline/TimelineService.swift — SAFE TO DELETE

Commands:
```
grep -rnE "TimelineService" --include="*.swift" "Peezy 4.0" "Peezy 4.0Tests" "Peezy 4.0UITests" Tests
grep -rn "fetchUserTasks" --include="*.swift" "Peezy 4.0" "Peezy 4.0Tests" "Peezy 4.0UITests" Tests
```
Output (first command; in-file hits at TimelineService.swift:1–114 omitted; all
external hits shown):
```
Peezy 4.0/Tasks/Store/PeezyCardFirestoreMapper.swift:6:    /// Ported from TimelineService.fetchUserTasks().
Peezy 4.0/MainInterface/Models/PeezyStackViewModel.swift:71:    // MARK: - Direct Firestore Loading (matches TimelineService)
Peezy 4.0/MainInterface/Models/PeezyStackViewModel.swift:88:            // Query active tasks - same filter as TimelineService
Peezy 4.0/MainInterface/Models/PeezyStackViewModel.swift:112:                // Parse priority (same logic as TimelineService)
Peezy 4.0/MainInterface/Models/PeezyStackViewModel.swift:198:    /// Color name for priority (matches TimelineService)
```
Output (second command):
```
Peezy 4.0/Tasks/Store/PeezyCardFirestoreMapper.swift:6:    /// Ported from TimelineService.fetchUserTasks().
Peezy 4.0/PeezyTimeline/TimelineService.swift:14:    func fetchUserTasks() async throws -> [PeezyCard] {
```
Analysis: all five external references are comment lines; `fetchUserTasks()` has zero
call sites. Four of the five stale comments live in PeezyStackViewModel.swift (item 6,
itself being deleted); the last (PeezyCardFirestoreMapper.swift:6) is a doc-comment
that can stay or be reworded during the rebuild. Superseded by TasksStore +
PeezyCardFirestoreMapper.

---

## Deliberately excluded

- **TaskFlowDismissButton** — inert (body = EmptyView) but referenced by 48 files;
  kept as an API-compatibility shim until the rebuild reworks those files (per spec).
- **PreviewData.swift / PreviewHelpers.swift** — classified DELETE in the
  architecture map (DEBUG/preview-only) but not part of this removal list; the map
  marks them "harmless to keep for previews — human call."

## Removal procedure reminder

All file deletions go through Xcode (File → Delete → Move to Trash) so
`project.pbxproj` is updated in the same step. Recommended order: items 1–4, 7, 8, 10
(no dependencies), then item 6 (edit PeezyMainContainer first), then item 5 (edit
PeezyLiquidGlass first), then item 9 (pure code edit). Build after each deletion.
