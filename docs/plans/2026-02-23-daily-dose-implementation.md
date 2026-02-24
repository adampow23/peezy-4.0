# Daily Dose Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the endless sequential task queue on the home screen with a "Daily Dose" system that shows users only their tasks for today, computed by evenly distributing all remaining tasks across working days until move day.

**Architecture:** Add `urgencyPercentage` to `PeezyCard`, rework `PeezyHomeViewModel` to compute daily batches using the distribution algorithm and persist completion state via UserDefaults, then update `PeezyHomeView` to show progress info on the welcome card and a celebration card when the day's batch is done.

**Tech Stack:** Swift 5.9, SwiftUI, @Observable (Observation framework), Firebase Firestore, UserDefaults

---

## Before You Start

Read these files (DO NOT rely on memory — re-read them):
- `Peezy 4.0/MainInterface/Models/PeezyCard.swift`
- `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift`
- `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift`
- `Peezy 4.0/Assessment/PeezyTheme/ConfettiView.swift`

Build command for verification (iPhone 17 Pro only — iPhone 16 does NOT exist):
```bash
xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

---

## Task 1: Add `urgencyPercentage` to `PeezyCard`

**Files:**
- Modify: `Peezy 4.0/MainInterface/Models/PeezyCard.swift`

`urgencyPercentage` is written to Firestore by `TaskGenerationService` (field name: `"urgencyPercentage"`, type `Int`) but is not currently on the model. We need it on the card so the ViewModel can sort by it.

**Step 1: Add the stored property**

In `PeezyCard.swift`, after `var lastSnoozedAt: Date?` (line 39), add:

```swift
// Daily Dose — task urgency from catalog (0–99, higher = more urgent)
var urgencyPercentage: Int?
```

**Step 2: Add to initializer**

In the `init(...)` at line 162, add `urgencyPercentage: Int? = nil` as a new parameter (after `taskCategory: String? = nil`). Add `self.urgencyPercentage = urgencyPercentage` to the body.

Full updated signature (parameters only — preserve ALL existing params):
```swift
init(
    id: String = UUID().uuidString,
    type: CardType,
    title: String,
    subtitle: String,
    colorName: String = "white",
    taskId: String? = nil,
    workflowId: String? = nil,
    vendorCategory: String? = nil,
    vendorId: String? = nil,
    priority: Priority = .normal,
    createdAt: Date = Date(),
    status: TaskStatus = .upcoming,
    dueDate: Date? = nil,
    snoozedUntil: Date? = nil,
    lastSnoozedAt: Date? = nil,
    briefingMessage: String? = nil,
    taskCategory: String? = nil,
    urgencyPercentage: Int? = nil
) {
    // ... existing assignments ...
    self.urgencyPercentage = urgencyPercentage
}
```

**Step 3: Build to verify**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` (no errors)

**Step 4: Commit**

```bash
git add "Peezy 4.0/MainInterface/Models/PeezyCard.swift"
git commit -m "feat: add urgencyPercentage field to PeezyCard

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Read `urgencyPercentage` from Firestore in `loadTasks()`

**Files:**
- Modify: `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift`

The Firestore document field is `"urgencyPercentage"` (Int stored as NSNumber). Use `(as? NSNumber)?.intValue` (IMPORTANT: NOT `as? Int` — see CLAUDE.md known bug #8).

**Step 1: Update the Firestore query to include InProgress**

In `loadTasks()`, find the `.whereField("status", in: ...)` call. Change:
```swift
.whereField("status", in: ["Upcoming", "pending", "Snoozed"])
```
to:
```swift
.whereField("status", in: ["Upcoming", "pending", "Snoozed", "InProgress"])
```

**Step 2: Read urgencyPercentage in the document loop**

After the `lastSnoozedAt` parse (around line 151), add:
```swift
let urgencyPercentage = (data["urgencyPercentage"] as? NSNumber)?.intValue
```

**Step 3: Pass urgencyPercentage to the PeezyCard init**

In the `PeezyCard(...)` constructor call (starting at line 159), add:
```swift
urgencyPercentage: urgencyPercentage
```

**Step 4: Separate InProgress tasks from active tasks**

After building `cards`, split them. Replace the existing sort + `self.taskQueue = sorted` block with:

```swift
// Separate InProgress tasks (counted but not queued)
let inProgressCards = cards.filter { $0.status == .inProgress }
let activeCards = cards.filter { $0.status != .inProgress }

// Sort active tasks: urgencyPercentage DESC, then title ASC for tiebreak
let sorted = activeCards.sorted { a, b in
    let ua = a.urgencyPercentage ?? 0
    let ub = b.urgencyPercentage ?? 0
    if ua != ub { return ua > ub }
    return a.title < b.title
}
```

NOTE: The existing `shouldShow` guard already filters snoozed/completed/skipped cards before they reach this point. The query now returns InProgress too, so we separate them here.

**Step 5: Build to verify**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

**Step 6: Commit**

```bash
git add "Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift"
git commit -m "feat: read urgencyPercentage from Firestore, include InProgress in query, sort by urgency

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Add Daily Dose stored properties and UserDefaults tracking to `PeezyHomeViewModel`

**Files:**
- Modify: `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift`

**Step 1: Add new stored properties**

After `var completedThisSession: Int = 0`, add a new section:

```swift
// MARK: - Daily Dose State

/// All active tasks (not InProgress) sorted by urgency — full list, not sliced
var allActiveTasks: [PeezyCard] = []

/// Count of InProgress tasks for the "all done" screen
var inProgressTaskCount: Int = 0

/// Whether the user has opted to get ahead of schedule
var gettingAhead: Bool = false

/// Which batch offset we're on: 0 = today, 1 = +1 day ahead, etc.
var currentBatchOffset: Int = 0
```

**Step 2: Add UserDefaults keys (private constants)**

After the stored properties block, add:

```swift
// MARK: - UserDefaults Keys (private)

private let kDailyDoseCompletedCount = "dailyDoseCompletedCount"
private let kDailyDoseLastDate = "dailyDoseLastDate"
private let kDailyDoseFirstLaunchDate = "dailyDoseFirstLaunchDate"
```

**Step 3: Add UserDefaults accessors and reset logic**

Add these private helpers anywhere in the class (suggested: above the Helpers section at the bottom):

```swift
// MARK: - Daily Dose UserDefaults

private var dailyDoseCompletedCount: Int {
    get { UserDefaults.standard.integer(forKey: kDailyDoseCompletedCount) }
    set { UserDefaults.standard.set(newValue, forKey: kDailyDoseCompletedCount) }
}

private func todayISOString() -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withFullDate]
    return f.string(from: Date())
}

private func resetDailyCountIfNeeded() {
    let today = todayISOString()
    let lastDate = UserDefaults.standard.string(forKey: kDailyDoseLastDate) ?? ""
    if today != lastDate {
        dailyDoseCompletedCount = 0
        UserDefaults.standard.set(today, forKey: kDailyDoseLastDate)
    }
    // Set first launch date once
    if UserDefaults.standard.string(forKey: kDailyDoseFirstLaunchDate) == nil {
        UserDefaults.standard.set(today, forKey: kDailyDoseFirstLaunchDate)
    }
}
```

**Step 4: Build to verify**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

**Step 5: Commit**

```bash
git add "Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift"
git commit -m "feat: add Daily Dose stored properties and UserDefaults helpers

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Add Daily Dose computed properties to `PeezyHomeViewModel`

**Files:**
- Modify: `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift`

Add these under `// MARK: - Computed Properties`:

```swift
// MARK: - Daily Dose Computed Properties

private var daysUntilMoveValue: Int {
    userState?.daysUntilMove ?? 30
}

private var bufferDays: Int {
    if daysUntilMoveValue <= 10 { return 0 }
    if daysUntilMoveValue <= 14 { return 3 }
    return 7
}

private var workingDays: Int {
    max(daysUntilMoveValue - bufferDays, 1)
}

var dailyTarget: Int {
    guard !allActiveTasks.isEmpty else { return 0 }
    return max(Int(ceil(Double(allActiveTasks.count) / Double(workingDays))), 1)
}

var isTodayComplete: Bool {
    dailyDoseCompletedCount >= dailyTarget && dailyTarget > 0
}

/// Calendar day number we're on in the plan (1-indexed)
var dayNumber: Int {
    let firstLaunchStr = UserDefaults.standard.string(forKey: kDailyDoseFirstLaunchDate) ?? todayISOString()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let firstDate = formatter.date(from: firstLaunchStr) else { return 1 }
    let cal = Calendar.current
    let days = cal.dateComponents([.day], from: firstDate, to: Date()).day ?? 0
    return days + 1
}

/// Approximate total plan days (elapsed + remaining)
var totalPlanDays: Int {
    dayNumber + daysUntilMoveValue
}

/// "Today: X of Y done" — shown on welcome card
var progressText: String {
    let done = min(dailyDoseCompletedCount, dailyTarget)
    return "Today: \(done) of \(dailyTarget) done"
}

/// "Day X of Y · Z tasks remaining" — shown on welcome card
var dayProgressText: String {
    "\(allActiveTasks.count) tasks remaining · \(daysUntilMoveValue) days until move"
}

/// Subtext for the daily celebration card
var celebrationSubtext: String {
    // How many days of tasks we've done beyond today
    let aheadDays = currentBatchOffset
    if aheadDays > 0 {
        return "You're \(aheadDays) \(aheadDays == 1 ? "day" : "days") ahead — nice work."
    }
    if daysUntilMoveValue <= bufferDays + 2 {
        return "You're in great shape for move day."
    }
    return "Right on schedule. Enjoy the rest of your day."
}

/// Enum to drive which done-card variant is shown
enum DailyDoseViewState {
    case batchComplete(aheadDays: Int)  // STATE 2/3
    case allTasksDone                   // STATE 4
    case normalDone                     // existing "start next task" card
}

var dailyDoseViewState: DailyDoseViewState {
    if allActiveTasks.isEmpty {
        return .allTasksDone
    }
    if isTodayComplete && !gettingAhead {
        return .batchComplete(aheadDays: currentBatchOffset)
    }
    if gettingAhead && taskQueue.isEmpty {
        // Just finished a get-ahead batch
        return .batchComplete(aheadDays: currentBatchOffset)
    }
    return .normalDone
}
```

**Step 1: Build to verify**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

**Step 2: Commit**

```bash
git add "Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift"
git commit -m "feat: add Daily Dose computed properties and DailyDoseViewState

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Wire `loadTasks()` to populate `allActiveTasks` and slice `taskQueue`

**Files:**
- Modify: `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift`

**Step 1: Call `resetDailyCountIfNeeded()` at the start of `loadTasks()`**

At the top of `loadTasks()`, immediately after `await MainActor.run { self.state = .loading }`, add:

```swift
resetDailyCountIfNeeded()
```

**Step 2: Set `allActiveTasks` and `inProgressTaskCount` in the MainActor block**

Find the `await MainActor.run { self.taskQueue = sorted; self.state = .welcome }` block. Replace it with:

```swift
await MainActor.run {
    self.allActiveTasks = sorted
    self.inProgressTaskCount = inProgressCards.count
    // Slice to today's batch only
    let batch = Array(sorted.prefix(self.dailyTarget))
    self.taskQueue = batch
    // If today's batch was already completed (app re-opened same day), go straight to done
    if self.isTodayComplete {
        self.state = .done
    } else {
        self.state = .welcome
    }
}
```

NOTE: `dailyTarget` is a computed property that reads `allActiveTasks` — set `allActiveTasks` first, then slice.

**Step 3: Update `hasMoreTasks` and `totalTaskCount`**

The existing `hasMoreTasks` and `totalTaskCount` computed properties read `taskQueue`. After this change, `taskQueue` is only today's slice. Update these to reflect the OVERALL task count:

Replace:
```swift
var hasMoreTasks: Bool { !taskQueue.isEmpty }
var totalTaskCount: Int { taskQueue.count }
```
with:
```swift
var hasMoreTasks: Bool { !taskQueue.isEmpty }
var totalTaskCount: Int { taskQueue.count }
var hasMoreTasksOverall: Bool { !allActiveTasks.isEmpty }
var totalActiveTaskCount: Int { allActiveTasks.count }
```

(Keep the originals for existing callers that reference `taskQueue` state, add new ones for daily dose UI.)

**Step 4: Build to verify**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

**Step 5: Commit**

```bash
git add "Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift"
git commit -m "feat: slice taskQueue to today's batch on load, populate allActiveTasks

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Increment `dailyDoseCompletedCount` on task completion

**Files:**
- Modify: `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift`

**Step 1: Update `completeCurrentTask()`**

Find `completeCurrentTask()`. After `completedThisSession += 1`, add:

```swift
dailyDoseCompletedCount += 1
```

**Step 2: Update `completeWorkflowTask()`**

Find the `await MainActor.run { self.completedThisSession += 1; ... }` block inside `completeWorkflowTask()`. Add `self.dailyDoseCompletedCount += 1` inside the same MainActor block, right after `self.completedThisSession += 1`.

**Step 3: Build to verify**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add "Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift"
git commit -m "feat: increment dailyDoseCompletedCount on task completion

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 7: Add `getAhead()` method to `PeezyHomeViewModel`

**Files:**
- Modify: `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift`

Add this method in a new `// MARK: - Get Ahead` section (suggested: after `completeWorkflowTask()`):

```swift
// MARK: - Get Ahead

/// Called when user taps "Want to get ahead?" or "Keep going?"
/// Loads the next day's batch of tasks into taskQueue.
func getAhead() {
    currentBatchOffset += 1
    gettingAhead = true

    let startIndex = dailyTarget * currentBatchOffset
    let nextBatch = Array(allActiveTasks.dropFirst(startIndex).prefix(dailyTarget))

    if nextBatch.isEmpty {
        // No more tasks — show all-done state
        state = .done
    } else {
        taskQueue = nextBatch
        state = .welcome
    }
}
```

**Step 1: Build to verify**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

**Step 2: Commit**

```bash
git add "Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift"
git commit -m "feat: add getAhead() to load next day's task batch

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 8: Update welcome card in `PeezyHomeView` to show daily progress

**Files:**
- Modify: `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift`

The welcome card (`welcomeCard` computed property) currently shows:
1. Greeting text
2. Thin divider
3. Welcome subtitle
4. Task count (via `taskReadyText`)
5. "Get started" button (if `hasMoreTasks`)

**Step 1: Replace the task count row with daily progress**

Find the `HStack` that shows `viewModel.taskReadyText` (around line 234). Replace that entire `HStack` with:

```swift
// Daily progress
VStack(alignment: .leading, spacing: 6) {
    Text(viewModel.progressText)
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.8))

    Text(viewModel.dayProgressText)
        .font(.system(size: 14, weight: .regular))
        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.45))
}
.padding(.top, 8)
```

**Step 2: Update the welcome subtitle**

The existing `welcomeSubtitle` computed property on the ViewModel says "Here's what's on your plate today." when no move date — this is fine and can stay.

When getting ahead, update the subtitle to be more appropriate. Add this to `PeezyHomeViewModel`:

```swift
var welcomeSubtitleForDailyDose: String {
    if gettingAhead {
        return "Here's your next batch."
    }
    return welcomeSubtitle  // existing logic
}
```

In `PeezyHomeView.welcomeCard`, change `viewModel.welcomeSubtitle` to `viewModel.welcomeSubtitleForDailyDose`.

**Step 3: Build to verify**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add "Peezy 4.0/MainInterface/Views/PeezyHomeView.swift" \
        "Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift"
git commit -m "feat: show daily progress on welcome card

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 9: Replace `doneCard` with Daily Dose aware card variants in `PeezyHomeView`

**Files:**
- Modify: `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift`

This is the biggest UI change. We replace the single `doneCard` with a switch on `viewModel.dailyDoseViewState`.

**Step 1: Add `@State private var confettiActive = false` to `PeezyHomeView`**

Near the top of `PeezyHomeView`, after the existing `@State` properties, add:

```swift
@State private var confettiActive = false
```

**Step 2: Replace `doneCard` with a dispatching computed property**

Replace the entire `private var doneCard: some View { ... }` with:

```swift
// MARK: - Done Card (dispatches to appropriate variant)

@ViewBuilder
private var doneCard: some View {
    switch viewModel.dailyDoseViewState {
    case .batchComplete(let aheadDays):
        dailyCelebrationCard(aheadDays: aheadDays)
    case .allTasksDone:
        allTasksDoneCard
    case .normalDone:
        normalDoneCard
    }
}
```

**Step 3: Add `dailyCelebrationCard`**

Add after the `doneCard` property:

```swift
// MARK: - Daily Celebration Card (STATE 2 / 3)

private func dailyCelebrationCard(aheadDays: Int) -> some View {
    ZStack {
        glassCard {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 15) {
                    Text("You're all done for today!")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundColor(PeezyTheme.Colors.deepInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    Rectangle()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 50, height: 2)

                    Text(viewModel.celebrationSubtext)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // "Get ahead" button — only if there are more tasks
                if viewModel.hasMoreTasksOverall &&
                   viewModel.allActiveTasks.count > viewModel.dailyTarget * (viewModel.currentBatchOffset + 1) {
                    Button(action: {
                        confettiActive = false
                        viewModel.getAhead()
                    }) {
                        Text(aheadDays > 0 ? "Keep going?" : "Want to get ahead?")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
            }
        }

        // Confetti overlay — fills the card area, pointer events pass through
        ConfettiView(isActive: $confettiActive, intensity: .high) {
            // onSettling: particles have finished — leave confettiActive true
            // so it doesn't restart; particles are already gone
        }
        .frame(width: 340, height: 500)
        .allowsHitTesting(false)
    }
    .onAppear {
        confettiActive = true
    }
    .onDisappear {
        confettiActive = false
    }
}
```

**Step 4: Add `allTasksDoneCard`**

```swift
// MARK: - All Tasks Done Card (STATE 4)

private var allTasksDoneCard: some View {
    glassCard {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                Text("You're all set!")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundColor(PeezyTheme.Colors.deepInk)

                Rectangle()
                    .fill(Color.black.opacity(0.15))
                    .frame(width: 50, height: 2)

                if let days = viewModel.userState?.daysUntilMove {
                    Text("Your move is in \(days) \(days == 1 ? "day" : "days") and Peezy is handling the rest.")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Peezy is handling the rest.")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                }

                if viewModel.inProgressTaskCount > 0 {
                    Text("We're working on \(viewModel.inProgressTaskCount) \(viewModel.inProgressTaskCount == 1 ? "thing" : "things") for you.")
                        .font(.subheadline)
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
    }
}
```

**Step 5: Rename existing `doneCard` body to `normalDoneCard`**

The previous `doneCard` logic (showing "Nice work" / "On a roll" + "Start next task") becomes `normalDoneCard`. Since we replaced `doneCard` in Step 2, add the old content under a new name:

```swift
// MARK: - Normal Done Card (mid-batch, task completed)

private var normalDoneCard: some View {
    glassCard {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                Text(doneHeadline)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)

                Rectangle()
                    .fill(Color.black.opacity(0.15))
                    .frame(width: 50, height: 2)

                Text(doneSubtitle)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            if viewModel.hasMoreTasks {
                Button(action: { viewModel.startNextTask() }) {
                    Text("Start next task")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
    }
}
```

DELETE the old `doneCard`, `doneHeadline`, and `doneSubtitle` implementations — they've been replaced above.

Actually, keep `doneHeadline` and `doneSubtitle` since `normalDoneCard` uses them. Only delete the old `doneCard` var that's now replaced by the `@ViewBuilder` dispatcher above.

**Step 6: Build to verify**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

**Step 7: Commit**

```bash
git add "Peezy 4.0/MainInterface/Views/PeezyHomeView.swift"
git commit -m "feat: add daily celebration, all-done, and normal done card variants

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 10: Final verification and summary commit

**Step 1: Full build**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

**Step 2: Verify the before/after summary**

**BEFORE:** `taskQueue` = ALL active tasks from Firestore (Upcoming + Snoozed + pending), sorted by `dueDate ASC` then `priority DESC`. The home screen shows tasks one at a time until all are exhausted, then shows a generic "done" card.

**AFTER:** `taskQueue` = `allActiveTasks.prefix(dailyTarget)` — only today's batch by urgency. After completing `dailyTarget` tasks, the `.done` state shows a celebration card with confetti. User can tap "Want to get ahead?" to load the next batch. When ALL tasks across ALL batches are done, shows the "all set" card.

**Step 3: Report all changed files to user**

```
Peezy 4.0/MainInterface/Models/PeezyCard.swift
  - Added: urgencyPercentage: Int? field + initializer param

Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift
  - Added: allActiveTasks, inProgressTaskCount, gettingAhead, currentBatchOffset
  - Added: UserDefaults keys + accessors (dailyDoseCompletedCount, dailyDoseLastDate, dailyDoseFirstLaunchDate)
  - Added: resetDailyCountIfNeeded()
  - Added: Daily Dose computed properties (dailyTarget, isTodayComplete, dayNumber, progressText, etc.)
  - Added: DailyDoseViewState enum
  - Added: getAhead() method
  - Changed: Firestore query now includes "InProgress"
  - Changed: Read urgencyPercentage from Firestore
  - Changed: Sort order: urgencyPercentage DESC, title ASC (was dueDate ASC, priority DESC)
  - Changed: taskQueue initialized to todaysBatch only (was all active tasks)
  - Changed: completeCurrentTask() and completeWorkflowTask() now increment dailyDoseCompletedCount

Peezy 4.0/MainInterface/Views/PeezyHomeView.swift
  - Added: @State confettiActive: Bool
  - Changed: welcomeCard shows progressText + dayProgressText instead of taskReadyText
  - Changed: doneCard dispatches to dailyCelebrationCard / allTasksDoneCard / normalDoneCard
  - Added: dailyCelebrationCard (with ConfettiView)
  - Added: allTasksDoneCard
  - Added: normalDoneCard (replaces old doneCard body)
```

---

## Edge Cases to Watch

1. **`dailyTarget == 0`** when `allActiveTasks.isEmpty` — `isTodayComplete` returns false (guarded by `dailyTarget > 0`), correctly showing `allTasksDone` state via `allActiveTasks.isEmpty` check.

2. **User re-opens app same day** — `resetDailyCountIfNeeded()` sees today == lastDate, preserves count. `isTodayComplete` may already be true → `state = .done` directly after load.

3. **`urgencyPercentage` is nil** (tasks created before this field existed) — sort treats nil as 0 (lowest urgency), placed at end of batch. Acceptable degradation.

4. **`shouldShow` guard** — `PeezyCard.shouldShow` filters snoozed/completed/skipped before `cards` array is built, so InProgress cards reach the `inProgressCards` split correctly (they pass `shouldShow` since it only blocks completed/skipped/snoozed).

5. **Demo workflow** — `startDemoWorkflow()` bypasses `loadTasks()` entirely and sets `currentTask` directly, so daily dose logic is not involved. Correct — demo mode is unaffected.
