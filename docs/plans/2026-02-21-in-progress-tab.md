# In Progress Tab Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a 4th "In Progress" tab to the Task List view (PeezyTimelineView.swift) so that InProgress tasks are separated from Active tasks into their own tab.

**Architecture:** Only one file needs to change: `PeezyTimelineView.swift`. The `TaskTab` enum, filtering logic, tab bar, summary line, and tab empty state all live in this file. No model changes needed — `TaskStatus.inProgress` already exists. `TimelineService` already fetches `InProgress` status from Firestore.

**Tech Stack:** SwiftUI, Swift 5.9+, iOS 17+, `@Observable` (Observation framework)

---

## What We Know (Read Before Implementing)

**File:** `Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift`

**Current `TaskTab` enum (lines 13–17):**
```swift
enum TaskTab: String, CaseIterable {
    case active = "Active"
    case snoozed = "Snoozed"
    case completed = "Completed"
}
```

**Current `activeTasks` filter (lines 62–72):** Includes ALL non-completed, non-skipped, non-snoozed tasks — including `.inProgress` tasks. We need to exclude `.inProgress` here.

**Current `taskSummary` (lines 175–189):** Shows "X active · X snoozed · X done". Needs "X in progress" added.

**Current `tabEmptyState` (lines 292–315):** Has cases for active/snoozed/completed. Needs inProgress case.

**`TaskStatus.inProgress`** = `.inProgress` (raw value "InProgress") — already exists in `PeezyCard.swift` line 8.

**`isInProgress` in `TaskListRow`** (line 362): Already renders the blue `arrow.clockwise.circle.fill` icon and "In Progress · Getting quotes..." subtitle. Row already handles this status correctly.

**DO NOT TOUCH:** `TimelineService.swift`, `PeezyCard.swift`, `PeezyHomeViewModel.swift`, or any `.pbxproj` files.

---

### Task 1: Add `inProgress` case to `TaskTab` enum

**Files:**
- Modify: `Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift:13-17`

**Step 1: Make the change**

Replace the enum (lines 13–17):
```swift
enum TaskTab: String, CaseIterable {
    case active = "Active"
    case inProgress = "In Progress"
    case snoozed = "Snoozed"
    case completed = "Completed"
}
```

**Step 2: Build to verify enum compiles (expect errors — switch statements are now non-exhaustive)**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: Compile errors about non-exhaustive switches on `TaskTab`. That's fine — Task 2+ fixes them.

---

### Task 2: Add `inProgressTasks` computed property and update `activeTasks` filter

**Files:**
- Modify: `Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift` (MARK: - Grouped Tasks section, ~lines 62–90)

**Step 1: Update `activeTasks` to EXCLUDE `.inProgress` tasks**

Current filter at line 63–64:
```swift
allTasks.filter { card in
    card.status != .completed && card.status != .skipped && !isSnoozed(card)
}
```

Replace with (add `&& card.status != .inProgress`):
```swift
allTasks.filter { card in
    card.status != .completed && card.status != .skipped && card.status != .inProgress && !isSnoozed(card)
}
```

**Step 2: Add `inProgressTasks` computed property after `activeTasks`**

Add after the `activeTasks` computed property (after line 72, before `private var snoozedTasks`):
```swift
private var inProgressTasks: [PeezyCard] {
    allTasks.filter { $0.status == .inProgress }
        .sorted { a, b in
            if a.priority.rawValue != b.priority.rawValue {
                return a.priority.rawValue > b.priority.rawValue
            }
            return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
        }
}
```

---

### Task 3: Update `tasksForSelectedTab` and `countForTab`

**Files:**
- Modify: `Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift` (MARK: - Filtered Tasks section, ~lines 94–108)

**Step 1: Update `tasksForSelectedTab` switch**

Current (lines 95–99):
```swift
switch selectedTab {
case .active: return activeTasks
case .snoozed: return snoozedTasks
case .completed: return completedTasks
}
```

Replace with:
```swift
switch selectedTab {
case .active: return activeTasks
case .inProgress: return inProgressTasks
case .snoozed: return snoozedTasks
case .completed: return completedTasks
}
```

**Step 2: Update `countForTab` switch**

Current (lines 103–108):
```swift
switch tab {
case .active: return activeTasks.count
case .snoozed: return snoozedTasks.count
case .completed: return completedTasks.count
}
```

Replace with:
```swift
switch tab {
case .active: return activeTasks.count
case .inProgress: return inProgressTasks.count
case .snoozed: return snoozedTasks.count
case .completed: return completedTasks.count
}
```

---

### Task 4: Update `taskSummary` to include in-progress count

**Files:**
- Modify: `Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift` (lines 175–189)

**Step 1: Replace `taskSummary` computed property**

Current:
```swift
private var taskSummary: String {
    let active = activeTasks.count
    let snoozed = snoozedTasks.count
    let completed = completedTasks.count

    if active == 0 && snoozed == 0 {
        return completed > 0 ? "\(completed) completed" : "No tasks yet"
    }

    var parts: [String] = []
    if active > 0 { parts.append("\(active) active") }
    if snoozed > 0 { parts.append("\(snoozed) snoozed") }
    if completed > 0 { parts.append("\(completed) done") }
    return parts.joined(separator: " · ")
}
```

Replace with:
```swift
private var taskSummary: String {
    let active = activeTasks.count
    let inProgress = inProgressTasks.count
    let snoozed = snoozedTasks.count
    let completed = completedTasks.count

    if active == 0 && inProgress == 0 && snoozed == 0 {
        return completed > 0 ? "\(completed) completed" : "No tasks yet"
    }

    var parts: [String] = []
    if active > 0 { parts.append("\(active) active") }
    if inProgress > 0 { parts.append("\(inProgress) in progress") }
    if snoozed > 0 { parts.append("\(snoozed) snoozed") }
    if completed > 0 { parts.append("\(completed) done") }
    return parts.joined(separator: " · ")
}
```

---

### Task 5: Update `tabEmptyState` to handle the new `.inProgress` case

**Files:**
- Modify: `Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift` (lines 292–315)

**Step 1: Add `.inProgress` case to the `tabEmptyState` switch**

Current switch:
```swift
let (icon, message): (String, String) = {
    switch selectedTab {
    case .active:
        return ("checkmark.seal.fill", "No active tasks — you're all caught up!")
    case .snoozed:
        return ("moon.zzz.fill", "No snoozed tasks")
    case .completed:
        return ("trophy.fill", "No completed tasks yet")
    }
}()
```

Replace with:
```swift
let (icon, message): (String, String) = {
    switch selectedTab {
    case .active:
        return ("checkmark.seal.fill", "No active tasks — you're all caught up!")
    case .inProgress:
        return ("clock.arrow.circlepath", "Nothing in progress yet. Complete a workflow and we'll handle the rest.")
    case .snoozed:
        return ("moon.zzz.fill", "No snoozed tasks")
    case .completed:
        return ("trophy.fill", "No completed tasks yet")
    }
}()
```

---

### Task 6: Build and verify

**Step 1: Run xcodebuild**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

**Step 2: Commit**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && git add "Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift" && git commit -m "feat: add In Progress tab to task list view"
```

---

## Summary of All Changes

| File | Change |
|------|--------|
| `Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift` | Add `.inProgress` to `TaskTab` enum; add `inProgressTasks` computed property; update `activeTasks` to exclude `.inProgress`; update `tasksForSelectedTab` and `countForTab`; update `taskSummary`; update `tabEmptyState` |

**Only 1 file modified.**
