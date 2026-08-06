# Task Flow Generation Skill

## What You're Doing
Generating standalone SwiftUI flow files for Peezy task workflows. Each task gets its own file. Each file assembles shared card templates into a linear card sequence.

## Critical Rules
1. **Each flow file is 100% standalone.** No dependency on TaskCardSpec, TaskCardSequence, TaskCardSequenceBuilder, WorkflowManager, WorkflowCardModels, or TaskPreviewData.
2. **Follow the reference files exactly.** Do not invent new components, patterns, or architectures.
3. **One file per task.** Named `{PascalCaseTaskName}Flow.swift`. Example: `ManageGymFlow.swift`
4. **No shared state between flow files.** Each manages its own `@State` for answers and currentIndex.
5. **Copy (question text, options, tips) comes from the task manifest and qualifying data.** Do not invent copy.

## Dependencies (already exist in the project)
- `FlowOption` — simple data struct for tile options
- `TaskFlowHeader` — right-aligned grey header with optional back arrow
- `TaskFlowStack` — card stack depth visual with slide animations
- `TaskFlowTitleCard` — title + body + primary/secondary buttons
- `TaskFlowInfoCard` — title + body + optional caution icon + bold prefix
- `TaskFlowTilesCard` — vertical option list, single or multi select, optional skip button
- `TaskFlowCompactTilesCard` — side-by-side tiles for binary yes/no questions
- `TaskFlowFillBarCard` — percentage fill bar tiles
- `TaskFlowSummaryCard` — completion card with icon, body, subtext
- `PeezyAssessmentButton` — shared button component
- `PeezyTheme` — shared theme (Colors.deepInk, Colors.successGreen, etc.)
- `PeezyHaptics` — haptic feedback
- `InteractiveBackground` — shared background
- `WorkflowService` — Firebase submission service
- `WorkflowAnswers` — answer container for submission

## Three Patterns

### Pattern A: Self-Service (ReturnKeysFlow.swift)
**Used when:** `selfServiceOnly = true` or `actionType = "off-app"` or `taskType = "provide_info"`
**No userId parameter. No Firebase submission.**
```
Card 0: TaskFlowTitleCard — task title + description + "On It" / "Go back"
Card 1: TaskFlowInfoCard — "Good to Know" + tip/insight from catalog
Card 2: TaskFlowSummaryCard — "You're all set!" + closing text + "Done"
```
**Navigation:** Simple advance/goBack, no skip logic, no answers.
**Completion:** Calls `onComplete()` directly — no Firebase.

### Pattern B: Simple Survey (ManageBankFlow.swift)
**Used when:** 1-2 questions, no skip logic needed
**Has userId parameter. Submits to Firebase.**
```
Card 0: TaskFlowTitleCard — task title + intro text + "Continue" / "Go back"
Card 1+: TaskFlowTilesCard — question(s) from qualifying data
Last:  TaskFlowSummaryCard — recap title + closing + "Submit"
```
**Answer handlers:** `selectSingle()` for single-select (auto-advances after 0.3s delay).
**Submission:** Builds `WorkflowAnswers`, calls `WorkflowService().submitAnswers()`.

### Pattern C: Complex Survey (BookMoversFlow.swift)
**Used when:** 3+ questions, skip logic, mixed card types
**Has userId parameter. Submits to Firebase.**
```
Card 0: TaskFlowTitleCard
Card 1-N: Mix of TaskFlowTilesCard, TaskFlowCompactTilesCard, TaskFlowFillBarCard, TaskFlowInfoCard
Last: TaskFlowSummaryCard
```
**Skip logic:** Named card index constants + `shouldSkip()` function + `advance()`/`goBack()` that skip hidden cards.
**Answer handlers:** `selectSingle()`, `toggleMulti()`, `toggleExclusive()` as needed.

## Template API Reference

### TaskFlowTitleCard
```swift
TaskFlowTitleCard(
    taskTitle: String,        // Header text (right-aligned, grey)
    title: String,            // Main title (34pt heavy)
    bodyText: String,         // Subtitle below divider (default: "")
    primaryLabel: String,     // Button text (default: "Continue")
    secondaryLabel: String?,  // Text button below (default: nil)
    onPrimary: () -> Void,
    onSecondary: (() -> Void)?
)
```

### TaskFlowInfoCard
```swift
TaskFlowInfoCard(
    taskTitle: String,
    title: String,            // e.g. "Good to Know" or "Very important to understand"
    bodyText: String,
    primaryLabel: String,     // default: "Continue"
    cautionIcon: String?,     // SF Symbol name, e.g. "exclamationmark.triangle.fill"
    boldPrefix: String?,      // Bold text prepended to bodyText
    showBack: Bool,           // default: false
    onPrimary: () -> Void,
    onBack: (() -> Void)?
)
```

### TaskFlowTilesCard
```swift
TaskFlowTilesCard(
    taskTitle: String,
    question: String,
    subtitle: String?,        // default: nil
    options: [FlowOption],
    mode: TileSelectMode,     // .single or .multi
    selectedIds: Set<String>,
    skipLabel: String?,       // default: nil — shows bottom button
    showBack: Bool,           // default: false
    onSelect: (String) -> Void,
    onContinue: (() -> Void)?, // for multi-select Continue / skip button
    onBack: (() -> Void)?
)
```

### TaskFlowCompactTilesCard
```swift
TaskFlowCompactTilesCard(
    taskTitle: String,
    question: String,
    options: [FlowOption],    // Exactly 2 options
    selectedId: String?,
    showBack: Bool,
    onSelect: (String) -> Void,
    onBack: (() -> Void)?
)
```

### TaskFlowFillBarCard
```swift
TaskFlowFillBarCard(
    taskTitle: String,
    question: String,
    options: [FlowOption],    // Must have fillPercent set
    selectedId: String?,
    showBack: Bool,
    onSelect: (String) -> Void,
    onBack: (() -> Void)?
)
```

### TaskFlowSummaryCard
```swift
TaskFlowSummaryCard(
    taskTitle: String,
    title: String,
    bodyText: String,
    primaryLabel: String,     // default: "Submit Request"
    subtext: String?,         // default: nil — subtle grey text
    showBack: Bool,
    onPrimary: () -> Void,
    onBack: (() -> Void)?
)
```

### FlowOption
```swift
FlowOption(
    id: String,
    label: String,
    icon: String,             // SF Symbol name
    subtitle: String?,        // default: nil
    isExclusive: Bool,        // default: false
    fillPercent: Double?       // default: nil — only for FillBarCard
)
```

## Answer Handler Patterns

```swift
// Single-select: set one answer, auto-advance after 0.3s
private func selectSingle(_ key: String, id: String) {
    answers[key] = [id]
    Task {
        try? await Task.sleep(for: .seconds(0.3))
        advance()
    }
}

// Multi-select: toggle option in set
private func toggleMulti(_ key: String, id: String) {
    var current = answers[key] ?? []
    if current.contains(id) {
        current.remove(id)
    } else {
        current.insert(id)
    }
    answers[key] = current
}

// Exclusive multi-select: selecting one replaces others
private func toggleExclusive(_ key: String, id: String) {
    if answers[key]?.contains(id) == true {
        answers[key] = []
    } else {
        answers[key] = [id]
    }
}
```

## Submission Pattern (Pattern B and C only)
```swift
private func submitAndComplete() {
    guard !isSubmitting else { return }
    isSubmitting = true

    var workflowAnswers = WorkflowAnswers(workflowId: workflowId)
    workflowAnswers.answers = answers.mapValues { Array($0) }

    Task {
        do {
            let service = WorkflowService()
            let response = try await service.submitAnswers(
                workflowId: workflowId,
                answers: workflowAnswers,
                userId: userId
            )
            await MainActor.run {
                isSubmitting = false
                if response.success { onComplete() }
            }
        } catch {
            await MainActor.run {
                isSubmitting = false
                onComplete()
            }
        }
    }
}
```

## File Structure
```
TaskFlows/
├── Templates/
│   ├── FlowOption.swift
│   ├── TaskFlowHeader.swift
│   ├── TaskFlowStack.swift
│   ├── TaskFlowTitleCard.swift
│   ├── TaskFlowInfoCard.swift
│   ├── TaskFlowTilesCard.swift
│   ├── TaskFlowCompactTilesCard.swift
│   ├── TaskFlowFillBarCard.swift
│   └── TaskFlowSummaryCard.swift
├── Flows/
│   ├── BookMoversFlow.swift        ← Reference: Pattern C
│   ├── ManageBankFlow.swift        ← Reference: Pattern B
│   ├── ReturnKeysFlow.swift        ← Reference: Pattern A
│   ├── ManageGymFlow.swift         ← Generated
│   ├── ... (53 more)
```

## What NOT To Do
- Do NOT create new shared components or templates
- Do NOT add fields to FlowOption or any template
- Do NOT use any type from the old system (TaskCardSpec, TileOption, WorkflowQuestion, etc.)
- Do NOT add skip logic unless the qualifying data has conditional questions
- Do NOT change the card visual style (fonts, spacing, colors, shadows)
- Do NOT combine multiple tasks into one file
