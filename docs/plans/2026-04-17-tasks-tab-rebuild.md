# Tasks Tab — Greenfield Rebuild Architecture

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan in sequenced batches. This is an **architecture plan**, not a task-by-task TDD recipe — each "Section" defines a design decision, and Section 7 (Migration) lists the execution order.

**Goal:** Replace `PeezyTimelineView.swift` with a greenfield Tasks tab whose architecture makes the reset-inventory stale-read bug structurally impossible, keeps Home and Tasks in sync without manual refresh, and reduces the current ~800-line view to a set of small, single-responsibility components.

**Architecture (3 sentences):** A single `@Observable TasksStore` owns the authoritative task state, sourced from a Firestore **snapshot listener** (not one-shot reads) tied to the authenticated user's lifecycle. All user intents flow through one typed `TaskAction` dispatcher on the store — the store performs the write, and the listener's next snapshot propagates the new state into every consumer (Home card stack AND Tasks tab) automatically. The view layer is a dumb tree of small structs that render from store state and emit actions; no view writes to Firestore directly, no view holds its own copy of tasks.

**Tech Stack:** SwiftUI (iOS 17), `@Observable` (Observation framework), Firebase Firestore (snapshot listeners + offline persistence), Firebase Functions (existing `resetInventory`), Firebase Auth.

---

## Principles

Five rules the rebuild is organized around. Every decision below traces back to one of these:

1. **Listener-first, never polling.** Tasks come from a `snapshotListener`, not `getDocuments()`. The server pushes truth; we never "ask again later."
2. **One source of truth.** `TasksStore.tasks` is the only `[PeezyCard]` array in the app. Home tab and Tasks tab both read from it.
3. **One action path.** All mutations go through `TasksStore.dispatch(_:)`. No view calls `Firestore.firestore()` directly.
4. **Optimistic + reconciled, never optimistic + refetched.** Writes update local state immediately; the listener's next snapshot reconciles. We never manually refetch to "confirm" a write.
5. **Dumb views, typed intents.** Rows emit `TaskAction` cases. Only the store interprets them.

---

# Section 1 — Data Layer

## 1.1 Source of truth

**One `@Observable` class, `TasksStore`, owns an array of `[PeezyCard]` populated by a Firestore snapshot listener.**

```swift
@Observable
final class TasksStore {
    static let shared = TasksStore()       // app-wide singleton, injected via .environment
    private(set) var tasks: [PeezyCard] = []
    private(set) var loadState: LoadState = .idle
    private(set) var pendingResetTaskIds: Set<String> = []   // tasks with in-flight CF calls

    private var listener: ListenerRegistration?
    private var authHandle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()

    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    func start() { ... }   // attach auth listener; auth listener attaches snapshot listener
    func stop()  { ... }   // detach everything (sign-out, app termination)
    func dispatch(_ action: TaskAction) async { ... }   // see Section 2
}
```

## 1.2 Listener lifecycle

The snapshot listener is **keyed by `Auth.currentUser.uid`** and re-attaches automatically on auth change. This is the single place auth state touches task data.

```swift
func start() {
    authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
        guard let self else { return }
        self.detachListener()
        guard let uid = user?.uid else {
            self.tasks = []
            self.loadState = .idle
            return
        }
        self.attachListener(uid: uid)
    }
}

private func attachListener(uid: String) {
    loadState = .loading
    listener = db.collection("users").document(uid).collection("tasks")
        .whereField("status", in: ["Upcoming", "InProgress", "UserInProgress",
                                   "matching_in_progress", "pending", "Snoozed", "Completed"])
        .addSnapshotListener(includeMetadataChanges: false) { [weak self] snap, err in
            guard let self else { return }
            if let err {
                self.loadState = .failed(err.localizedDescription)
                return
            }
            guard let snap else { return }
            self.tasks = snap.documents.compactMap { PeezyCard.fromFirestore($0) }
                                       .sorted(by: PeezyCard.defaultSort)
            self.loadState = .loaded
        }
}
```

**Error handling:**
- Listener errors → set `loadState = .failed(msg)`, keep last-good `tasks`. View shows a banner with a retry tap.
- Retry: `detachListener(); attachListener(uid:)`.
- App background/foreground: leave listener attached. Firestore SDK handles socket reconnection internally. Detach only on sign-out, `deinit`, or explicit `stop()`.

## 1.3 Write path

**All writes go through `dispatch(_:)`.** Each write:
1. Performs an optimistic local mutation on `tasks` (synchronous, immediate UI update).
2. Issues the Firestore (or Cloud Function) write.
3. On failure, reverts the optimistic mutation.
4. On success, does nothing — the listener will emit the authoritative snapshot within ~100-300ms and either confirm our optimistic change or correct it.

```swift
func dispatch(_ action: TaskAction) async {
    switch action {
    case .markComplete(let card):
        await performWrite(
            taskId: card.id,
            optimistic: { $0.status = .completed; $0.completedAt = Date() },
            revert: { $0.status = card.status; $0.completedAt = nil },
            firestoreUpdate: [
                "status": "Completed",
                "completedAt": FieldValue.serverTimestamp()
            ],
            onSuccess: { ToastManager.shared.show("Nice work", style: .success) },
            onFailure: { ToastManager.shared.show("Couldn't mark complete", style: .error) },
            haptic: .success,
            celebrate: true
        )

    case .undo(let card):
        await performWrite(
            taskId: card.id,
            optimistic: { $0.status = .upcoming; $0.completedAt = nil },
            revert: { $0.status = .completed },
            firestoreUpdate: [
                "status": "Upcoming",
                "completedAt": FieldValue.delete()
            ],
            onSuccess: { ToastManager.shared.show("\(card.title) moved back to active") },
            onFailure: { ToastManager.shared.show("Couldn't undo", style: .error) }
        )

    case .resetInventory(let card):
        await performInventoryReset(card)    // see Section 5

    case .open(let card):
        NavigationBus.shared.request(.openTask(card))    // see Section 2.4
    }
}
```

## 1.4 Why this eliminates the stale-read bug

The current bug sequence:
```
reset → optimistic update → getDocuments(source: .server) → stale snapshot → overwrite
```
With a listener:
```
reset → optimistic update → Firestore commit → listener fires with authoritative snapshot
```
**We never call `getDocuments` after a write.** There is no "refetch" — only the listener's continuous truth. Stale reads are structurally impossible because we don't perform reads ourselves.

## 1.5 Home tab consumption

`PeezyHomeViewModel` currently loads its own tasks. After migration it reads from `TasksStore.shared.tasks` (or gets injected). When a Tasks-tab action mutates store state, the listener propagates, and Home's derived card stack recomputes automatically — **no cross-tab refresh code needed.**

*Scope note (Section 9): Home tab rewiring is out of scope for this plan. But the store is designed so a single-line change — `self.cards = TasksStore.shared.tasks.filter { $0.shouldShow }` — will later unify the two.*

## 1.6 Offline behavior

Firebase Firestore's offline persistence is enabled by default in this app. That gives us for free:
- Writes queue locally and replay on reconnect.
- The listener emits cached documents immediately, so the tab never shows an empty flash.
- `includeMetadataChanges: false` keeps us from handling "has pending writes" churn.

We don't need any offline-specific branching in the store.

---

# Section 2 — Action Layer

## 2.1 The typed action model

```swift
enum TaskAction {
    case open(PeezyCard)            // navigate to Home + open the flow
    case markComplete(PeezyCard)    // status → Completed, show confetti
    case undo(PeezyCard)            // status → Upcoming
    case resetInventory(PeezyCard)  // destructive, confirmed, CF-backed
}
```

## 2.2 Who dispatches

**Only `TaskRowButtons`** (the small button view inside a row) emits actions. Rows themselves are dumb. The dispatcher is injected once at the tab root:

```swift
struct TasksTabView: View {
    @State private var store = TasksStore.shared
    @State private var pendingConfirm: PendingConfirmation?

    var onAction: (TaskAction) -> Void {
        { action in
            switch action {
            case .resetInventory(let card):
                pendingConfirm = .resetInventory(card)    // show dialog first
            default:
                Task { await store.dispatch(action) }
            }
        }
    }
}
```

## 2.3 Who handles

**`TasksStore.dispatch(_:)`** is the sole handler. Exactly one function for every action, and each action gets the same four concerns handled uniformly inside `performWrite(...)`:
1. Optimistic mutation
2. Firestore/CF call
3. Revert-on-failure
4. Side effects (toast, haptic, confetti)

## 2.4 Navigation — the `.open` case

Navigation must cross tabs (Tasks → Home). We keep the existing `onNavigateToTask: (PeezyCard) -> Void` callback contract as the integration point. Inside the new tab view:

```swift
struct TasksTabView: View {
    var onNavigateToTask: (PeezyCard) -> Void   // injected by PeezyMainContainer
    ...
    // in the onAction closure:
    case .open(let card):
        onNavigateToTask(card)
}
```

(We do **not** invent a new `NavigationBus` — the callback contract already works; `TasksStore` just forwards `.open` through the injected closure. See the revised `dispatch` pseudo-code in 1.3.)

## 2.5 Feedback surfacing

All feedback is uniform:

| Action | Haptic | Toast | Confetti |
|---|---|---|---|
| `open` | `.light` | — | — |
| `markComplete` | `.success` | — (confetti is the feedback) | ✓ |
| `undo` | `.light` | "{Title} moved back to active" | — |
| `resetInventory` | `.medium` | "Inventory reset — ready to scan again" (success) / "Couldn't reset" (error) | — |

Failures always toast with `.error` style. Never silent failures.

## 2.6 Error handling inside `performWrite`

```swift
private func performWrite(
    taskId: String,
    optimistic: (inout PeezyCard) -> Void,
    revert: (inout PeezyCard) -> Void,
    firestoreUpdate: [String: Any],
    onSuccess: () -> Void,
    onFailure: () -> Void,
    haptic: PeezyHaptics.Style = .light,
    celebrate: Bool = false
) async {
    guard let uid = Auth.auth().currentUser?.uid,
          let idx = tasks.firstIndex(where: { $0.id == taskId })
    else { onFailure(); return }

    let snapshot = tasks[idx]
    optimistic(&tasks[idx])                  // immediate UI update
    PeezyHaptics.fire(haptic)
    if celebrate { ConfettiBus.shared.fire() }

    do {
        try await db.collection("users").document(uid)
                    .collection("tasks").document(taskId)
                    .updateData(firestoreUpdate)
        onSuccess()
    } catch {
        if let i = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[i] = snapshot    // restore exactly
        }
        onFailure()
    }
}
```

`ConfettiBus` is a trivial `@Observable` singleton with `var isFiring: Bool` and `fire()` that auto-resets after 3s — it decouples "any action wants to celebrate" from a view-owned `@State` flag.

---

# Section 3 — View Architecture

## 3.1 Component hierarchy

```
TasksTabView                 ← tab root; owns store reference + confirm dialog state
├── TasksHeader              ← title + home button
├── TasksLoadingOrEmpty      ← spinner / empty-state / error banner
└── TasksContent             ← only shown when loaded && non-empty
    ├── TasksTabBar          ← To-Do / In Progress / Done segmented control
    ├── ScrollView + refreshable
    │   └── TasksList(selectedTab:)
    │       ├── (todo)        → TaskSection(rows: todo)
    │       ├── (inProgress)  → TaskSection(title: "You're on it", rows: uip)
    │       │                   TaskSection(title: "Peezy is on it", rows: inp)
    │       └── (done)        → TaskSection(rows: done)
    └── ConfettiOverlay       ← observes ConfettiBus
        ResetInventoryOverlay ← observes TasksStore.pendingResetTaskIds

TaskSection
└── ForEach(rows) { TaskRow(card:) }

TaskRow                      ← single row, expand/collapse, emits onAction
├── TaskRowHeader            ← icon + title + subtitle + badges + chevron
└── TaskRowButtons(context:) ← declarative button stack (Section 4)
```

## 3.2 Responsibilities

| Component | Owns | Knows About |
|---|---|---|
| `TasksTabView` | selected tab, expanded row id, pending confirmation | `TasksStore`, `onNavigateToTask` callback |
| `TasksHeader` | — | user name string, home callback |
| `TasksLoadingOrEmpty` | — | `loadState`, `tasks.isEmpty`, retry callback |
| `TasksTabBar` | — | `selectedTab` binding, counts |
| `TasksList` | — | `selectedTab`, derived row arrays |
| `TaskSection` | — | optional title string, `[PeezyCard]` |
| `TaskRow` | expand state binding (via id) | single `PeezyCard`, `isExpanded: Bool`, `onAction` closure |
| `TaskRowHeader` | — | card display fields |
| `TaskRowButtons` | — | `TaskRowContext`, `onAction` closure |
| `ConfettiOverlay` | — | `ConfettiBus.shared.isFiring` |

## 3.3 State location

Single principle: **state is held at the lowest component that needs to share it.**

| State | Lives in |
|---|---|
| `tasks` array | `TasksStore` (singleton) |
| `loadState` | `TasksStore` |
| `pendingResetTaskIds` | `TasksStore` |
| `selectedTab: TaskTab` | `TasksTabView` (`@State`) — doesn't persist across tab switches |
| `expandedTaskId: String?` | `TasksTabView` (`@State`) — centralized |
| `pendingConfirm: PendingConfirmation?` | `TasksTabView` (`@State`) |
| `ConfettiBus.isFiring` | `ConfettiBus` singleton |

**Expand is centralized** (not per-row) so that tapping one row automatically collapses any other. Each `TaskRow` receives `isExpanded: Bool` and an `onTapChevron: () -> Void` closure; the tab view toggles the one string.

## 3.4 Derived row arrays (static functions)

Move the current inline `todoTasks / userInProgressTasks / inProgressTasks / completedTasks` logic into a **pure functional partitioner** living outside the view:

```swift
enum TaskGrouping {
    struct Groups {
        var todo: [PeezyCard]
        var userInProgress: [PeezyCard]
        var peezyInProgress: [PeezyCard]
        var completed: [PeezyCard]
    }
    static func partition(_ tasks: [PeezyCard], now: Date = Date()) -> Groups { ... }
}
```

This is testable in isolation (pure function, no SwiftUI, no Firestore) — it's the highest-ROI unit test in the whole rebuild. See Section 8.

---

# Section 4 — Row Button Matrix

## 4.1 The mapping

`TaskRowButtons` takes a single input — `TaskRowContext` — and returns a declarative list of buttons. No nested `if` chains in the view.

```swift
struct TaskRowContext {
    let card: PeezyCard
    let tab: TaskTab
}

enum TaskRowButton: Identifiable {
    case primary(title: String, action: TaskAction)      // filled pill
    case secondary(title: String, action: TaskAction)    // outlined pill
    case destructiveLink(title: String, action: TaskAction)  // red underline link

    var id: String {
        switch self {
        case .primary(let t, _), .secondary(let t, _), .destructiveLink(let t, _):
            return t
        }
    }
}

enum TaskRowButtonLayout {
    case none
    case single(TaskRowButton)
    case pair(TaskRowButton, TaskRowButton)                       // side-by-side, equal width
    case pairWithLink(TaskRowButton, TaskRowButton, TaskRowButton) // pair + link below
}

extension TaskRowButtons {
    static func layout(for ctx: TaskRowContext) -> TaskRowButtonLayout {
        let c = ctx.card
        switch (ctx.tab, c.status, c.isScanInventory) {

        // — TO-DO TAB —
        case (.todo, _, _) where !c.isSnoozedEffective:
            return .single(.primary(title: "Open Task", action: .open(c)))
        case (.todo, _, _) /* snoozed */ :
            return .single(.primary(title: "Open Task", action: .open(c)))

        // — IN PROGRESS : YOU'RE ON IT —
        case (.inProgress, .userInProgress, true /*scan_inventory*/):
            return .pairWithLink(
                .secondary(title: "Open Task", action: .open(c)),
                .primary(title: "Mark as complete", action: .markComplete(c)),
                .destructiveLink(title: "Reset inventory", action: .resetInventory(c))
            )
        case (.inProgress, .userInProgress, false):
            return .pair(
                .secondary(title: "Open Task", action: .open(c)),
                .primary(title: "Mark as complete", action: .markComplete(c))
            )

        // — IN PROGRESS : PEEZY IS ON IT —
        case (.inProgress, .inProgress, _), (.inProgress, .matchingInProgress, _):
            return .single(.primary(title: "Open Task", action: .open(c)))

        // — DONE TAB —
        case (.done, .completed, true /*scan_inventory*/):
            return .single(.primary(title: "Reset inventory", action: .resetInventory(c)))
        case (.done, .completed, false):
            return .single(.primary(title: "Undo", action: .undo(c)))

        default:
            return .none
        }
    }
}
```

## 4.2 Full matrix (every supported combination)

| Tab | Status | Scan inv? | Layout | Buttons |
|---|---|---|---|---|
| To-Do | Upcoming | any | single | primary: **Open Task** |
| To-Do | Snoozed (explicit or `snoozedUntil > now`) | any | single | primary: **Open Task** |
| In Progress | UserInProgress | no | pair | secondary: **Open Task** • primary: **Mark as complete** |
| In Progress | UserInProgress | **yes** | pairWithLink | secondary: **Open Task** • primary: **Mark as complete** • red link: **Reset inventory** |
| In Progress | InProgress / matchingInProgress | any | single | primary: **Open Task** |
| Done | Completed | no | single | primary: **Undo** |
| Done | Completed | **yes** | single | primary: **Reset inventory** |
| any | Skipped | any | none | — (filtered out upstream) |

## 4.3 Rendering

`TaskRowButtons` is ~30 lines — one switch on `layout`:

```swift
struct TaskRowButtons: View {
    let layout: TaskRowButtonLayout
    let onAction: (TaskAction) -> Void

    var body: some View {
        switch layout {
        case .none:
            EmptyView()
        case .single(let btn):
            render(btn)
        case .pair(let a, let b):
            HStack(spacing: 12) { render(a); render(b) }
        case .pairWithLink(let a, let b, let link):
            VStack(spacing: 12) {
                HStack(spacing: 12) { render(a); render(b) }
                render(link)
            }
        }
    }

    @ViewBuilder private func render(_ btn: TaskRowButton) -> some View { ... }
}
```

Adding a new button case in the future = one new `case` in `layout(for:)` + whatever new action enum case. No giant view refactor.

---

# Section 5 — Destructive Actions & Confirmation

## 5.1 The pattern

A single enum captures every destructive confirmation the tab can show:

```swift
enum PendingConfirmation: Identifiable {
    case resetInventory(PeezyCard)

    var id: String {
        switch self {
        case .resetInventory(let c): return "reset-\(c.id)"
        }
    }
    var title: String { "Reset your inventory?" }
    var message: String {
        "This deletes every room scan and item you've submitted. You'll need to scan your home again from scratch. This can't be undone."
    }
    var confirmLabel: String { "Yes, reset everything" }
    var cancelLabel: String { "Keep my inventory" }
}
```

`TasksTabView` holds `@State private var pendingConfirm: PendingConfirmation?` and renders **one** `.confirmationDialog(...)` bound to it. Any action that should prompt for confirmation sets `pendingConfirm` instead of dispatching immediately:

```swift
case .resetInventory(let card):
    pendingConfirm = .resetInventory(card)
// user taps destructive button in dialog →
await store.dispatch(.resetInventory(card))
```

New destructive actions (future: "delete this task forever", "reset assessment") add a case to `PendingConfirmation` and a dialog branch — no new dialog machinery per call site.

## 5.2 Reset inventory specifics

```swift
extension TasksStore {
    func performInventoryReset(_ card: PeezyCard) async {
        guard card.isScanInventory else { return }
        pendingResetTaskIds.insert(card.id)
        defer { pendingResetTaskIds.remove(card.id) }

        // Optimistic local flip (listener will authoritatively confirm or correct).
        let prior = tasks.first(where: { $0.id == card.id })?.status ?? .completed
        if let i = tasks.firstIndex(where: { $0.id == card.id }) {
            tasks[i].status = .upcoming
            tasks[i].completedAt = nil
        }

        do {
            let manager = InventorySessionManager()
            try await manager.resetInventory()    // calls the CF
            ToastManager.shared.show("Inventory reset — ready to scan again", style: .success)
            PeezyHaptics.success()
            // No refetch. The listener will push the authoritative snapshot.
        } catch {
            if let i = tasks.firstIndex(where: { $0.id == card.id }) {
                tasks[i].status = prior    // revert
            }
            ToastManager.shared.show("Couldn't reset inventory — please try again", style: .error)
        }
    }
}
```

`ResetInventoryOverlay` is a lightweight view that observes `store.pendingResetTaskIds`; when non-empty it shows the existing "Resetting inventory..." progress overlay.

## 5.3 Why the stale-read bug cannot happen here

The old path was `CF finishes → sleep 600ms → getDocuments(source: .server) → stale snapshot overwrites local`. The new path has **no `getDocuments` call at all.** The listener is already attached and will emit the authoritative post-CF snapshot whenever Firestore's socket delivers it. The optimistic update covers the gap; the listener covers the truth.

---

# Section 6 — Errors & Offline

## 6.1 Offline-when-tapped

- **Markcomplete / Undo:** Firestore's offline SDK queues the write. `performWrite` sees no error, onSuccess fires, listener doesn't emit until reconnect, but our optimistic update is already visible. When device reconnects, the queued write commits and the listener emits a matching snapshot — a no-op for the UI. No user-visible difference. ✓
- **Reset inventory:** Cloud Function calls are **not** queued by Firestore's offline SDK — they fail fast. We catch the error in `performInventoryReset`, revert the optimistic update, and toast `"No connection — please try again when you're back online."` A small addition to `performInventoryReset`: if `error is NetworkError` (or URLError with `.notConnectedToInternet`), use that specific message.

## 6.2 Write fails mid-action

Always: revert optimistic local state, toast `.error`, no retry loop (user taps again). Never retry automatically — silent retries hide real problems.

## 6.3 Listener disconnects

`loadState = .failed(msg)` and a thin banner appears above the list: "Having trouble loading — [Tap to retry]". Old `tasks` stay rendered so the user can still see what they had. Tap calls `store.start()` which re-attaches.

## 6.4 Toast discipline

- Success toasts are **cheap** for destructive/unusual actions (undo, reset) but **suppressed** for mark-complete because confetti already signals success. Rule: if there's already a richer feedback (confetti, row animating away), skip the toast.
- Error toasts always fire.
- Never two toasts back-to-back for one action.

---

# Section 7 — Migration Plan

**Coexistence strategy:** The new view ships alongside the old one behind a compile-time swap in `PeezyMainContainer`. No feature flag; this is a single commit switchover. The old file stays in-tree but unreferenced until Batch 6 verification passes.

## Batch 1 — Data layer (no UI)

**Files:**
- Create: `Peezy 4.0/Tasks/Store/TasksStore.swift`
- Create: `Peezy 4.0/Tasks/Store/TaskAction.swift`
- Create: `Peezy 4.0/Tasks/Store/TaskGrouping.swift`
- Create: `Peezy 4.0/Tasks/Store/ConfettiBus.swift`
- Create: `Peezy 4.0/Tasks/Store/PeezyCardFirestoreMapper.swift` (extracted from `TimelineService`)

**Build checkpoint:** `xcodebuild ... build` passes. No UI changes yet.

## Batch 2 — View skeleton

**Files:**
- Create: `Peezy 4.0/Tasks/Views/TasksTabView.swift` (the new root, replacing `PeezyTaskStream`)
- Create: `Peezy 4.0/Tasks/Views/TasksHeader.swift`
- Create: `Peezy 4.0/Tasks/Views/TasksTabBar.swift`
- Create: `Peezy 4.0/Tasks/Views/TasksList.swift`
- Create: `Peezy 4.0/Tasks/Views/TaskSection.swift`
- Create: `Peezy 4.0/Tasks/Views/TaskRow.swift`
- Create: `Peezy 4.0/Tasks/Views/TaskRowHeader.swift`
- Create: `Peezy 4.0/Tasks/Views/TaskRowButtons.swift`
- Create: `Peezy 4.0/Tasks/Views/PendingConfirmation.swift`

Each view file is ≤120 lines. Previews use hardcoded `[PeezyCard]` samples and a mock `TasksStore` initialized with `init(preview:)`.

**Build checkpoint:** `xcodebuild` passes. Previews render in Xcode canvas.

## Batch 3 — Wire into container

**Files:**
- Modify: `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift` — swap `PeezyTaskStream(viewModel:userState:onNavigateToTask:onNavigateHome:)` for `TasksTabView(onNavigateToTask:onNavigateHome:)`. The new view doesn't take `viewModel`/`userState` — it reads from `TasksStore` directly, and reads `userState.name` from an environment injection (or keeps `userState` as a plain `let` parameter if that's simpler — pick whichever PeezyMainContainer already wires in cleanly without .pbxproj edits).
- Modify: `Peezy 4.0/Peezy_4_0App.swift` (or wherever app lifecycle lives) — call `TasksStore.shared.start()` on app launch.

**Build checkpoint:** `xcodebuild` + simulator run. Open Tasks tab, verify:
- Tasks load (listener emits initial snapshot within 1s).
- Pull-to-refresh is a no-op visually but does nothing harmful (the listener is already live; refreshable just calls `try? await Task.sleep(for: .seconds(0.5))` for the animation).
- Tabs switch.
- Rows expand.

## Batch 4 — Actions

**Files:**
- Modify: `TasksStore.swift` — implement `dispatch(_:)`, `performWrite`, `performInventoryReset`.

**Build checkpoint:** `xcodebuild` + manual test each action:
- Open Task (tap on a To-Do row) → navigates to Home, opens that task.
- Mark as complete (You're on it) → confetti, row moves to Done, no stale flip-back.
- Undo (Done) → row moves back to To-Do.
- Reset inventory (Done, scan_inventory) → confirmation → inventory collection emptied → row returns to To-Do → **verify bug is gone by tapping Tasks tab immediately after; no flip-back.**
- Reset inventory (You're on it, scan_inventory) via red link → same behavior.

## Batch 5 — Error paths

**Files:**
- Modify: `TasksStore.swift` — wire `loadState = .failed` banner, offline detection on CF call.
- Modify: `TasksTabView.swift` — render the retry banner when `loadState` is `.failed`.

**Manual test:** Airplane mode on, reset inventory → error toast, state reverts. Airplane mode on, mark complete → optimistic update persists, listener will later confirm on reconnect.

## Batch 6 — Delete old code

Once Batches 1-5 pass manual verification on simulator AND a real device:

**Files:**
- Delete: `Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift`
- Delete: `Peezy 4.0/PeezyTimeline/TimelineService.swift`  (only if `PeezyHomeViewModel` doesn't still reference it — grep first)
- Move: any still-in-use helpers (e.g. `SecondaryActionButton` if shared) into a shared location before deletion.

**Build checkpoint:** Full xcodebuild clean build passes. No references to `PeezyTaskStream` or `PeezyTimelineView`. Final simulator run, all 15 test scenarios in Section 8 pass.

## Coexistence answer

Yes, they can coexist during Batches 1-5. The new files live in `Peezy 4.0/Tasks/` and don't touch `PeezyTimeline/`. The swap in Batch 3 is a single callsite change; if we need to back out, we revert that one line. Batch 6 is the point of no return.

---

# Section 8 — Testing Strategy

## 8.1 Critical paths that MUST work on first ship

1. Tasks tab loads within 1s of opening with no "No tasks yet" flash.
2. Pull-to-refresh doesn't break anything (it's a visual no-op, but gesture works).
3. Marking a task complete shows confetti, task moves to Done, cannot flip back.
4. Undo from Done works and does not leave the task in a half-state.
5. Reset inventory (from Done, scan_inventory) runs CF, inventory is cleared, task returns to To-Do, **does not flip back to Done after any amount of waiting**.
6. Reset inventory (from You're on it, scan_inventory) via red link works identically.
7. Home tab + Tasks tab stay in sync: completing a task from Home immediately reflects in Tasks (no manual reload).
8. Sign out → tasks clear. Sign back in → tasks reappear.

## 8.2 Manual test scenarios (≥15)

Numbered so a tester can check them off:

1. Fresh install, sign in, open Tasks tab → spinner → tasks appear.
2. To-Do tab shows only non-completed/non-in-progress/non-snoozed tasks, sorted by urgency desc.
3. Snoozed task appears at the bottom of To-Do with "Snoozed" badge.
4. In Progress tab shows "You're on it" and "Peezy is on it" as two sections.
5. Done tab shows completed tasks.
6. Tap row → expands; tap same row → collapses.
7. Tap another row while one is expanded → first collapses, second expands.
8. In To-Do row, Open Task button → Home tab opens with that task's flow.
9. In You're on it row (non-inventory), two buttons side-by-side, both same width.
10. Mark as complete (You're on it, non-inventory) → confetti → row disappears from In Progress → appears in Done.
11. In Done row (non-inventory), Undo button returns task to To-Do.
12. scan_inventory in You're on it shows Open Task + Mark as complete + red "Reset inventory" link below.
13. scan_inventory in Done shows ONLY "Reset inventory" (no Undo).
14. Reset inventory confirmation dialog shows exact copy from spec, Keep button cancels cleanly.
15. Reset inventory → progress overlay → success toast → row returns to To-Do. **Wait 10 seconds.** Row stays in To-Do. No flip-back.
16. Complete a task from Home card stack → switch to Tasks tab → task already in Done without any reload.
17. Airplane mode on, mark complete → optimistic update persists visually; airplane mode off → no flicker, state confirmed.
18. Airplane mode on, reset inventory → error toast, row returns to previous state.
19. Sign out → Tasks tab empty. Sign in as different user → their tasks load.
20. Pull-to-refresh on To-Do → haptic + brief spinner + no state change.

## 8.3 Edge cases needing extra verification

- **Stale-read race** (the original bug): scenario 15 is the direct test. The architecture prevents it because (a) no `getDocuments` is called post-write, (b) the listener is the only reader, (c) the listener's emitted snapshots come from server truth (and any stale cached doc is superseded by the subsequent authoritative snapshot — with `includeMetadataChanges: false` we don't see the cached-only intermediate).
- **Rapid tapping**: tapping Mark Complete twice before the first write returns. Second dispatch finds `status == .completed` already (optimistic) — `performWrite` should be idempotent (`updateData` with same values is harmless).
- **Tab switch mid-action**: expand a row on Done, tap Undo, immediately switch to To-Do. Task appears in To-Do, no crash, no stuck expand state. The `expandedTaskId` resets on tab switch.
- **Deleted task mid-listener**: if a task is deleted from Firestore, the listener emits a snapshot without it; the row disappears. If the user was mid-dialog on that task, the dialog auto-dismisses when `pendingConfirm`'s underlying card is no longer in `tasks` (add a guard in `TasksTabView.body` that clears `pendingConfirm` if the card id isn't in `store.tasks`).
- **Auth change mid-listener**: `addStateDidChangeListener` handles this — old listener detaches, new one attaches, tasks wipe to [] and reload.

## 8.4 Unit tests (cheapest high-value tests)

Only one target is worth unit-testing given iOS sim test infra cost:

- `TaskGrouping.partition(_:now:)` with a table of `[PeezyCard]` → `Groups` expectations. ~8 cases covering each status and snooze-expiry behavior.
- `TaskRowButtons.layout(for:)` with a table of `(tab, status, isScanInventory)` → expected layout. ~12 cases (the full matrix).

These are pure functions, no mocks, no Firestore. They catch the most common class of regression (someone adds a new status and the matrix silently breaks).

---

# Section 9 — Out of Scope

This rebuild explicitly does **not** touch:
- `PeezyHomeView`, `PeezyHomeViewModel`, `PeezyStackViewModel` (Home tab stays as-is; it will later read from `TasksStore` but not in this plan).
- `InventoryScanner*`, `InventorySessionManager` — used as-is for the CF call.
- Any task flow files (`ArrangeParkingNewFlow`, etc.).
- `TaskFlowRouter` — the `.open` action hands off via the existing `onNavigateToTask` callback.
- Cloud Functions (`resetInventory`, `taskCatalog`, etc.) — treat as fixed.
- `PeezyCard` and `TaskStatus` types — **must not change.**
- Any assessment or onboarding code.

If any of these need changes during implementation, **stop and ask** rather than scope-creep.

---

# Section 10 — Open Questions

Resolve before or during Batch 1:

1. **Where does `TasksStore.shared.start()` get called?** Looks like `Peezy_4_0App.swift` or a root view's `.task {}`. Confirm the earliest safe point post-Firebase-configure.
2. **Does the existing `PeezyHomeViewModel` currently listen to the same Firestore collection?** Grep `users/").document(`. If yes, we eventually dedupe by routing it through `TasksStore`; if no, Home's current fetch can stay in place for this rebuild.
3. **`subscriptionManager` is currently injected into `PeezyTaskStream` but not used in that file** (confirmed by reading the file — only referenced in `@EnvironmentObject`, never read). Can we drop it from the new view? **Assumption: yes.**
4. **User name for the header** — currently from `userState?.name`. Confirm whether `UserState` is injected as an environment object or passed explicitly. The new view should accept it the same way the old one did to minimize call-site churn.
5. **Is `ConfettiView(isActive: $showConfetti, intensity: .high)` safe to drive from a singleton (`ConfettiBus`) or does it need a per-view binding?** If the former won't work, keep a local `@State var confetti = false` in `TasksTabView` and have `ConfettiBus` publish a Combine/Observation event that flips it.
6. **`PeezyHaptics.Style`** — does this type actually exist? I'm assuming `PeezyHaptics.light()/medium()/success()` are free functions. If so, `performWrite` takes a `Haptic` closure parameter instead of a style enum.
7. **`refreshable` semantics** — since the listener always has fresh data, pull-to-refresh is visual theater. Is that OK, or do we want it removed for honesty? **Recommendation: keep it for familiarity; implement as `try? await Task.sleep(for: .milliseconds(400))`.**
8. **Matching in progress vs InProgress** — the current code groups `.matchingInProgress` under "Peezy is on it" with a different badge label. Matrix preserves this; confirm no other status has special handling.
9. **`isSnoozedEffective`** — the current view has both `status == .snoozed` AND `snoozedUntil > now` as snoozed markers. `PeezyCard.isSnoozed` only checks the date. We need a small extension `PeezyCard.isSnoozedEffective: Bool { status == .snoozed || isSnoozed }` so the grouping and matrix match existing behavior.
10. **File layout under `Peezy 4.0/Tasks/`** — that directory exists and currently holds task flow files. Creating a `Tasks/Store/` and `Tasks/Views/` subfolder should be fine but will require Xcode "Add Files to Project" since we **do not modify .pbxproj** (per CLAUDE.md). Plan-executor needs to know this is a manual step at the start of Batch 1 and Batch 2.

---

# Summary of How the Five Problems Die

| Problem | Why it dies in this architecture |
|---|---|
| **1. Stale reads after writes** | We never call `getDocuments`. The snapshot listener emits only authoritative server snapshots. Optimistic updates cover the write window. |
| **2. Dual sources of truth** | `TasksStore.tasks` is the only array. Home tab will read from it too (future); Tasks tab reads from it now. |
| **3. Action routing split across files** | Every action is a `TaskAction` case. `TasksStore.dispatch` is the only handler. Views emit, store handles. |
| **4. Home/Tasks race conditions** | Both tabs observe the same `@Observable` store backed by the same listener. A mutation anywhere propagates everywhere automatically. |
| **5. Monolithic view struct** | The 800-line view becomes ~10 files, each ≤120 lines, each with one responsibility. Row button logic is a table, not a nested `if` tree. |
