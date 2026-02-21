# In Progress Task Status Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** When a user completes a workflow survey, write `status: "In Progress"` to Firestore instead of `"Completed"`, and display those tasks with a distinct "In Progress" visual treatment in the timeline.

**Architecture:** `completeWorkflowTask()` in `PeezyHomeViewModel` currently calls `markTaskCompleted()`, which writes `"Completed"`. We'll add a separate `markTaskInProgress()` method that writes `"In Progress"`. The `TaskStatus` enum already has `.inProgress = "InProgress"` — note that `"In Progress"` (with space) is a new raw value we need to add. The timeline's `TaskListRow` already knows how to differentiate snoozed/completed; we'll add an `isInProgress` check with its own icon and styling.

**Tech Stack:** Swift/SwiftUI, Firebase Firestore, iOS 17+, `@Observable`

---

## Key Facts Established by Reading the Code

Before touching anything, these are the confirmed facts:

1. **`TaskStatus` enum** (`PeezyCard.swift:6-12`): Has `.inProgress = "InProgress"`. But the task asks us to write `"In Progress"` (with a space) — this is a **new, different raw value**. We need to add a case `case inProgressWorkflow = "In Progress"` OR reuse `.inProgress` but change its raw value to `"In Progress"`. Since `"InProgress"` is already used in Firestore queries (`whereField("status", in: ["Upcoming", "InProgress", ...])`) for other tasks, we should **keep `.inProgress = "InProgress"` unchanged** and use it — but write it with the existing `"InProgress"` raw value (not `"In Progress"`). The Firestore query already includes `"InProgress"` so it will be fetched automatically.

2. **`completeWorkflowTask()`** (`PeezyHomeViewModel.swift:265-298`): Calls `await markTaskCompleted(task)` at line 286. We need it to call a new `markTaskInProgress(task)` instead.

3. **`markTaskCompleted()`** (`PeezyHomeViewModel.swift:328-345`): Writes `"Completed"` + `completedAt` timestamp. We'll add a parallel `markTaskInProgress()` that writes `"In Progress"` (raw: `"InProgress"`) + `inProgressAt` timestamp.

4. **Home card queue filter** (`PeezyHomeViewModel.swift:124`): Queries `["Upcoming", "InProgress", "pending", "Snoozed"]` — `"InProgress"` is already included, so in-progress tasks will re-appear in the card stack on next load. We need to add a filter to **exclude** `inProgress` tasks from the card queue (they've been submitted, shouldn't show again).

5. **`PeezyCard.shouldShow`** (`PeezyCard.swift:149-159`): Returns false for `completed` and `skipped`. We need to also return false for `inProgress`.

6. **Timeline `activeTasks` filter** (`PeezyTimelineView.swift:63-72`): Excludes `completed` and `skipped` and snoozed. `inProgress` tasks will fall into the active bucket (correct — they ARE active, just awaiting vendor response).

7. **`TaskListRow.statusIcon`** (`PeezyTimelineView.swift:426-439`): Shows checkmark for completed, moon for snoozed, category icon otherwise. We need to add an `inProgress` branch showing a distinct icon.

8. **`TaskListRow` opacity** (`PeezyTimelineView.swift:418`): `.opacity(isCompleted ? 0.5 : (isSnoozed ? 0.7 : 1.0))` — in-progress tasks will show at full opacity (correct).

9. **`borderColor`** (`PeezyTimelineView.swift:477-481`): Yellow border for snoozed, orange for urgent. We can add a cyan/blue border for in-progress.

10. **`TimelineService.fetchUserTasks()`** (`TimelineService.swift:27-29`): Already queries `"InProgress"` — no changes needed here.

11. **`SnoozeManager`**: Does NOT need changes — it only deals with `"Snoozed"` and `"Skipped"` statuses.

---

## Task 1: Add `markTaskInProgress()` to `PeezyHomeViewModel`

**Files:**
- Modify: `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift`

**Step 1: Add `markTaskInProgress()` private method**

After `markTaskCompleted()` (line 345), add:

```swift
private func markTaskInProgress(_ task: PeezyCard) async {
    guard let userId = Auth.auth().currentUser?.uid else { return }

    let db = Firestore.firestore()
    do {
        try await db.collection("users")
            .document(userId)
            .collection("tasks")
            .document(task.id)
            .updateData([
                "status": "InProgress",
                "inProgressAt": FieldValue.serverTimestamp()
            ])
    } catch {
        print("⚠️ Failed to mark task in progress in Firestore: \(error.localizedDescription)")
    }
}
```

**Step 2: Change `completeWorkflowTask()` to call `markTaskInProgress()`**

In `completeWorkflowTask()` at line 286, change:
```swift
await markTaskCompleted(task)
```
to:
```swift
await markTaskInProgress(task)
```

**Step 3: Build to verify**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|warning:|BUILD"
```
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add "Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift"
git commit -m "feat: write InProgress status on workflow task completion"
```

---

## Task 2: Exclude `inProgress` tasks from the home card queue

**Files:**
- Modify: `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift`
- Modify: `Peezy 4.0/MainInterface/Models/PeezyCard.swift`

**Problem:** `loadTasks()` queries `"InProgress"` tasks and if `shouldShow` doesn't exclude them, a submitted workflow task will reappear in the home card stack after reloading.

**Step 1: Update `PeezyCard.shouldShow` to exclude `inProgress`**

In `PeezyCard.swift`, in the `shouldShow` computed property (line 149-159), change:
```swift
if status == .completed || status == .skipped {
    return false
}
```
to:
```swift
if status == .completed || status == .skipped || status == .inProgress {
    return false
}
```

**Step 2: Build to verify**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|warning:|BUILD"
```
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add "Peezy 4.0/MainInterface/Models/PeezyCard.swift" "Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift"
git commit -m "feat: exclude inProgress tasks from home card stack"
```

---

## Task 3: Add "In Progress" visual treatment to `TaskListRow`

**Files:**
- Modify: `Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift`

**Step 1: Add `isInProgress` computed property to `TaskListRow`**

In `TaskListRow` (after `isCompleted` at line 358-360), add:
```swift
private var isInProgress: Bool {
    task.status == .inProgress
}
```

**Step 2: Update `statusIcon` to show a progress icon for in-progress tasks**

In `statusIcon` (line 426-439), add a branch before the `else`:
```swift
} else if isInProgress {
    Image(systemName: "arrow.clockwise.circle.fill")
        .font(.system(size: 20))
        .foregroundColor(.cyan)
}
```

So the full `statusIcon` reads:
```swift
@ViewBuilder
private var statusIcon: some View {
    if isCompleted {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 20))
            .foregroundColor(.green)
    } else if isSnoozed {
        Image(systemName: "moon.zzz.fill")
            .font(.system(size: 18))
            .foregroundColor(.yellow)
    } else if isInProgress {
        Image(systemName: "arrow.clockwise.circle.fill")
            .font(.system(size: 20))
            .foregroundColor(.cyan)
    } else {
        Image(systemName: iconForCategory(task.taskCategory))
            .font(.system(size: 18))
            .foregroundColor(.white.opacity(0.5))
    }
}
```

**Step 3: Add subtitle "In Progress · Getting quotes..." below title for in-progress tasks**

In the `VStack` for title/subtitle (line 370-382), after the `if isSnoozed` branch, add:
```swift
if isInProgress {
    Text("In Progress · Getting quotes...")
        .font(.caption)
        .foregroundColor(.cyan.opacity(0.8))
}
```

**Step 4: Update `borderColor` for in-progress tasks**

In `borderColor` (line 477-481), add before the snoozed check:
```swift
if isInProgress { return .cyan.opacity(0.25) }
```

So:
```swift
private var borderColor: Color {
    if isInProgress { return .cyan.opacity(0.25) }
    if isSnoozed { return .yellow.opacity(0.15) }
    if task.priority == .urgent { return .orange.opacity(0.2) }
    return .white.opacity(0.06)
}
```

**Step 5: Build to verify**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|warning:|BUILD"
```
Expected: `BUILD SUCCEEDED`

**Step 6: Commit**

```bash
git add "Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift"
git commit -m "feat: In Progress visual treatment in timeline task list"
```

---

## Files Changed Summary

| File | Change |
|------|--------|
| `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift` | Add `markTaskInProgress()`, call it from `completeWorkflowTask()` instead of `markTaskCompleted()` |
| `Peezy 4.0/MainInterface/Models/PeezyCard.swift` | `shouldShow` excludes `.inProgress` status |
| `Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift` | `TaskListRow` gets `isInProgress` property, cyan icon, "In Progress" caption, cyan border |

## Files NOT Changed

| File | Reason |
|------|--------|
| `SnoozeManager.swift` | Only handles `"Snoozed"` and `"Skipped"` — no changes needed |
| `TimelineService.swift` | Already queries `"InProgress"` in Firestore — no changes needed |
| `PeezyCard.swift:TaskStatus` | `.inProgress = "InProgress"` already exists — no changes needed |
| `PeezyHomeViewModel.swift:loadTasks()` | Already queries `"InProgress"` — `shouldShow` guards the rest |
| `taskCatalogData.json` | Status is runtime data, not catalog data |
