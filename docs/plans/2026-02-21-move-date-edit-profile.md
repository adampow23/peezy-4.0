# Move Date in Edit Profile Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a move date picker to the Edit Profile sheet that saves to Firestore and immediately updates `UserState` so the profile card, timeline, and all other views reflect the new date without restarting the app.

**Architecture:** `EditProfileSheet` already loads from `users/{uid}/user_assessments/{doc}` and saves back to it. `moveDate` in Firestore is stored as a `Timestamp` (set by `AssessmentDataManager.getAllAssessmentData()` at line 90). `UserState` is a plain struct created once in `AppRootView.checkAssessmentStatus()` — it has NO Firestore listener, so saving alone is NOT enough. We must also update `UserState` in-place after save. `UserState` is passed as `var userState: UserState?` through the chain, which means we need to add a callback or `Binding` to propagate the mutation back to `AppRootView`. The cleanest approach (matching the existing `onSave` callback pattern) is to pass the updated `Date` in the existing `onSave` callback and update `userState` in `AppRootView`.

**Tech Stack:** SwiftUI, Swift 5.9+, iOS 17+, `@Observable` (Observation framework), Firebase Firestore, `FirebaseFirestore.Timestamp`

---

## What We Know (Read Before Implementing)

**Firestore format:** `AssessmentDataManager.getAllAssessmentData()` saves `moveDate` as:
```swift
data["moveDate"] = Timestamp(date: moveDate)  // line 90
```
`UserState.init(userId:from:)` loads it as (lines 152–155):
```swift
if let date = assessment["moveDate"] as? Timestamp {
    self.moveDate = date.dateValue()
} else if let date = assessment["moveDate"] as? Date {
    self.moveDate = date
}
```
**Conclusion:** We must save as `Timestamp(date: selectedDate)` — NOT as a String.

**Current `onSave` callback signature:** `var onSave: (String) -> Void` — delivers the updated name.

**UserState propagation:** `AppRootView` holds `@State private var userState: UserState?` and passes it as `PeezyMainContainer(userState: userState)`. `PeezyMainContainer` holds `var userState: UserState?` and passes it as `PeezySettingsView(userState: userState)`. `PeezySettingsView` holds `var userState: UserState?` and passes it as `EditProfileSheet(userState: userState)`. **None of these are `@Binding` — they are value-type `var` copies.** To propagate the updated `moveDate` back up to `AppRootView`, we need `Binding` at each link, OR we widen the `onSave` callback to include the updated date.

**Chosen approach:** Widen `onSave` callback to pass `(String, Date?)` — name + optional new move date. `PeezySettingsView` already handles `onSave` and can update a local `@State var userState` copy. But the root problem is `AppRootView` holds the source-of-truth `userState`. We'll use a `Binding<UserState?>` chain — it's 3 small file changes and guarantees immediate propagation.

**Files to change:**
1. `Peezy 4.0/Menu/PeezySettingsView.swift` — `EditProfileSheet` (add date picker, update load/save) + `PeezySettingsView` (pass binding)
2. `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift` — change `userState` from `var` to `@Binding`
3. `Peezy 4.0/MainInterface/Views/AppRootView.swift` — pass `$userState` instead of `userState`

**DO NOT TOUCH:** `AssessmentDataManager.swift`, `UserState.swift`, `TaskGenerationService.swift`, `TimelineService.swift`, `.pbxproj` files.

---

### Task 1: Change `PeezyMainContainer` to use `@Binding var userState`

**Files:**
- Modify: `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift`

**Why:** `PeezyMainContainer` currently has `var userState: UserState?` (value copy). To allow `EditProfileSheet` deep inside to mutate it and have `AppRootView` see the change, we need `@Binding`.

**Step 1: Update the property declaration**

In `PeezyMainContainer.swift`, change line 25:
```swift
// BEFORE
var userState: UserState?

// AFTER
@Binding var userState: UserState?
```

**Step 2: Update the Preview at line 163**

```swift
// BEFORE
#Preview {
    PeezyMainContainer(userState: UserState(userId: "preview", name: "Adam"))
}

// AFTER
#Preview {
    PeezyMainContainer(userState: .constant(UserState(userId: "preview", name: "Adam")))
}
```

**Step 3: Build to check for errors**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: Compile error in `AppRootView.swift` about `userState` needing a binding. That's fine — Task 2 fixes it.

---

### Task 2: Update `AppRootView` to pass `$userState` binding

**Files:**
- Modify: `Peezy 4.0/MainInterface/Views/AppRootView.swift`

**Step 1: Update `PeezyMainContainer` call at line 45**

```swift
// BEFORE
PeezyMainContainer(userState: userState)

// AFTER
PeezyMainContainer(userState: $userState)
```

**Step 2: Build**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: Build succeeds (or errors move to `PeezySettingsView` — Task 3 fixes those if any).

---

### Task 3: Update `PeezySettingsView` to use `@Binding var userState`

**Files:**
- Modify: `Peezy 4.0/Menu/PeezySettingsView.swift`

**Why:** `PeezySettingsView` receives `userState` from `PeezyMainContainer`. Now that `PeezyMainContainer` holds a binding, we want `PeezySettingsView` to also be a binding so it can mutate `userState.moveDate` after a successful save in `EditProfileSheet`.

**Step 1: Change `PeezySettingsView` property declaration at line 22**

```swift
// BEFORE
var userState: UserState?

// AFTER
@Binding var userState: UserState?
```

**Step 2: Update the `EditProfileSheet` call in the `.sheet` modifier (around line 124–128)**

The existing sheet call:
```swift
.sheet(isPresented: $showEditProfile) {
    EditProfileSheet(userState: userState) { updatedName in
        toastMessage = "Profile updated"
    }
}
```

Update to pass a binding and capture the returned move date:
```swift
.sheet(isPresented: $showEditProfile) {
    EditProfileSheet(userState: userState) { updatedName, updatedMoveDate in
        if let date = updatedMoveDate {
            userState?.moveDate = date
        }
        toastMessage = "Profile updated"
    }
}
```

**Step 3: Update the Preview at line 734–740**

```swift
// BEFORE
#Preview {
    PeezySettingsView(
        userState: UserState(userId: "preview", name: "Adam")
    )
    .environmentObject(AuthViewModel())
    .environmentObject(SubscriptionManager.shared)
}

// AFTER
#Preview {
    PeezySettingsView(
        userState: .constant(UserState(userId: "preview", name: "Adam"))
    )
    .environmentObject(AuthViewModel())
    .environmentObject(SubscriptionManager.shared)
}
```

**Step 4: Build**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: Compile error in `EditProfileSheet` about `onSave` signature mismatch. Task 4 fixes it.

---

### Task 4: Add move date picker to `EditProfileSheet` and update save logic

**Files:**
- Modify: `Peezy 4.0/Menu/PeezySettingsView.swift` — `EditProfileSheet` struct only

**Full changes to `EditProfileSheet`:**

**Step 1: Update `onSave` callback signature**

Change line 535:
```swift
// BEFORE
var onSave: (String) -> Void

// AFTER
var onSave: (String, Date?) -> Void
```

**Step 2: Add `@State private var moveDate` state variable**

After the existing `@State private var newAddress: String = ""` (around line 541), add:
```swift
@State private var moveDate: Date = Date()
@State private var hasMoveDate: Bool = false
```

**Step 3: Add the DatePicker to the form body**

In the `ScrollView > VStack(spacing: 24)` block, add after the `fieldGroup(label: "Name")` block and before the `fieldGroup(label: "Current Address")` block:

```swift
// Move Date picker
fieldGroup(label: "Move Date") {
    DatePicker(
        "",
        selection: $moveDate,
        displayedComponents: .date
    )
    .datePickerStyle(.compact)
    .labelsHidden()
    .tint(.cyan)
}
```

**Step 4: Load the move date in `loadCurrentValues()`**

In the `Task { }` block inside `loadCurrentValues()`, after setting `newAddress`, add:
```swift
// Load move date — stored as Timestamp in Firestore
if let timestamp = data["moveDate"] as? Timestamp {
    self.moveDate = timestamp.dateValue()
    self.hasMoveDate = true
} else if let dateValue = data["moveDate"] as? Date {
    self.moveDate = dateValue
    self.hasMoveDate = true
}
```

The full updated `loadCurrentValues()` `MainActor.run` block should be:
```swift
await MainActor.run {
    currentAddress = data["currentAddress"] as? String ?? ""
    newAddress = data["newAddress"] as? String ?? ""
    if let timestamp = data["moveDate"] as? Timestamp {
        self.moveDate = timestamp.dateValue()
        self.hasMoveDate = true
    } else if let dateValue = data["moveDate"] as? Date {
        self.moveDate = dateValue
        self.hasMoveDate = true
    }
}
```

**Step 5: Include move date in the save dictionary in `saveProfile()`**

In the `saveProfile()` function, after building `updates`:
```swift
var updates: [String: Any] = ["userName": trimmedName]
```

Add the move date:
```swift
var updates: [String: Any] = [
    "userName": trimmedName,
    "moveDate": Timestamp(date: moveDate)
]
```

**Step 6: Update the `onSave` call to pass the move date**

In `saveProfile()`, change:
```swift
// BEFORE
onSave(trimmedName)

// AFTER
onSave(trimmedName, moveDate)
```

**Step 7: Build**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

---

### Task 5: Verify profile card and commit

**Step 1: Confirm profile card updates**

The profile card in `PeezySettingsView.profileCard` (lines 202–230) reads `userState?.moveDate` and `userState?.daysUntilMove`. Since `daysUntilMove` is a computed property on `UserState` (line 91), it will recompute automatically when `moveDate` changes. No additional changes needed.

**Step 2: Final build**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && git add "Peezy 4.0/Menu/PeezySettingsView.swift" "Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift" "Peezy 4.0/MainInterface/Views/AppRootView.swift" && git commit -m "feat: add move date picker to Edit Profile sheet with live UserState update"
```

---

## Summary of All Changes

| File | Change |
|------|--------|
| `Peezy 4.0/Menu/PeezySettingsView.swift` | `PeezySettingsView.userState` → `@Binding`; update preview to `.constant()`; `EditProfileSheet.onSave` signature → `(String, Date?)`; add `@State moveDate`/`hasMoveDate`; add `DatePicker` fieldGroup after name; load `moveDate` from Firestore Timestamp in `loadCurrentValues`; save `moveDate` as `Timestamp` in `saveProfile`; call `onSave(name, moveDate)` |
| `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift` | `userState` → `@Binding var userState`; update preview to `.constant()` |
| `Peezy 4.0/MainInterface/Views/AppRootView.swift` | Pass `$userState` instead of `userState` to `PeezyMainContainer` |

**Data flow for `moveDate` after this change:**
1. Assessment saves `moveDate` as `Timestamp` → `users/{uid}/user_assessments/{doc}`
2. `AppRootView.checkAssessmentStatus()` reads that doc → builds `UserState(userId:from:)` → populates `userState.moveDate`
3. User opens Edit Profile → `loadCurrentValues()` reads `moveDate` as `Timestamp` → sets `@State moveDate`
4. User picks a new date → `saveProfile()` saves `Timestamp(date: moveDate)` to Firestore
5. `onSave(name, moveDate)` fires → `PeezySettingsView` sets `userState?.moveDate = date`
6. `AppRootView.$userState` binding receives the mutation → SwiftUI re-renders `PeezyMainContainer` → `PeezySettingsView.profileCard` shows updated date + recomputed `daysUntilMove` — **no app restart needed**
