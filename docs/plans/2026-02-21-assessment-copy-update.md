# Assessment Question Copy Update Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace all assessment question screen copy with new warm, confident copy as specified.

**Architecture:** Copy lives in TWO places. (1) `AssessmentCoordinator.inputContext()` provides `header`/`subheader` that typewriters in via `AssessmentInputWrapper`. (2) Individual question view files have their own `questionText` displayed via `AssessmentContentArea` or custom layouts. The `inputContext()` source is the CANONICAL source for the new copy — the individual view `questionText` is a legacy redundancy that still renders. IMPORTANT: The individual view files still render their own `questionText` as a large bold heading inside the content area. Both need to be updated where they differ. Additionally, some screens need option/tile label changes, and MoveDate/MoveDateType need conditional copy based on previous answers.

**Tech Stack:** Swift/SwiftUI, AssessmentCoordinator.inputContext(), individual question view files

---

## Understanding the Display Architecture

Each question screen shows:
1. **Top zone** (from `AssessmentInputWrapper` via `inputContext()`): typewriter-animated header + optional subheader
2. **Middle zone** (from each view's own code): large bold `questionText` in `AssessmentContentArea` OR custom layout

The new copy spec provides ONE header per screen. This means:
- Update `inputContext()` header → this replaces the top-zone header
- The individual view's `questionText` in `AssessmentContentArea` / custom layout ALSO shows and is often redundant/duplicative. Per the spec and architecture note "Context header/subheader is handled by AssessmentInputWrapper", the view files should ideally not show their own question text when the wrapper handles it. However, looking at the views, MANY of them render their own question independently (not via `AssessmentContentArea`). The safe approach: update both the coordinator copy AND the individual view questionText to match, so nothing is stale or contradictory.

---

### Task 1: Update AssessmentIntroView.swift

**Files:**
- Modify: `Peezy 4.0/Assessment/AssessmentViews/Onboarding/AssessmentIntroView.swift`

Changes:
- Icon: change `"list.clipboard.fill"` → `"wand.and.stars"`
- Header text: `"Let's build your moving plan"` → `"Welcome to the easy part"`
- Body text: `"Answer 15 quick questions..."` → `"You're in! Take a deep breath—we've got the heavy lifting from here. To build your perfect game plan, we just need to grab a few quick details about your move."`
- Clock info line: `"Takes about 2 minutes"` → `"Just a quick 90 second setup"`
- Button: `"Start Assessment"` → `"Take the first step"`

No test needed — visual-only change. Build to verify.

---

### Task 2: Update AssessmentCoordinator.inputContext() — Section 1 (Basics)

**Files:**
- Modify: `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift`

Changes to `inputContext(for:)`:

**userName:**
```swift
case .userName:
    return InputContext(
        header: "Love it. Let's get to know each other. What's your first name?",
        subheader: nil
    )
```

**moveConcerns:**
```swift
case .moveConcerns:
    return InputContext(
        header: "Nice to meet you, \(dataManager.userName). I'm Peezy! I'll be handling the entire move so you don't have to, but I want to know where your head is at. What's taking up the most mental energy right now?",
        subheader: "Pick your biggest headaches below."
    )
```

**moveDate** (conditional based on moveConcerns):
```swift
case .moveDate:
    let firstLine: String
    if dataManager.moveConcerns.isEmpty {
        firstLine = "No major stress? I like your style, \(dataManager.userName). Let's keep it that way."
    } else {
        firstLine = "Say no more. That is exactly the stuff I'm built to take off your plate. Take a deep breath—I've got it from here."
    }
    return InputContext(
        header: firstLine,
        subheader: "Next up: when are we moving? If it's not 100% official yet, just drop your best guess below!"
    )
```

**moveDateType** (conditional based on move date):
```swift
case .moveDateType:
    let days = Calendar.current.dateComponents([.day], from: Date(), to: dataManager.moveDate).day ?? 0
    let firstLine: String
    if days < 7 {
        firstLine = "Less than a week? No sweat. This is exactly why I'm here. Let's put this into high gear."
    } else if days <= 14 {
        firstLine = "Two weeks out! That's the perfect amount of time for me to get everything locked in without a scramble."
    } else if days <= 30 {
        firstLine = "A month away! I love it. We're going to have this whole thing handled with plenty of time to spare."
    } else {
        firstLine = "Awesome, we've got loads of time. Getting this sorted early means zero stress as the big day gets closer."
    }
    return InputContext(
        header: firstLine,
        subheader: "Now, how set in stone is that date?"
    )
```

---

### Task 3: Update AssessmentCoordinator.inputContext() — Section 2 (Current Home)

**Files:**
- Modify: `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift`

**currentRentOrOwn:**
```swift
case .currentRentOrOwn:
    return InputContext(
        header: "Alright, let's talk about your current place. Are you renting or do you own?",
        subheader: "This helps me figure out things like lease breaks, security deposits, or listing prep."
    )
```

**currentDwellingType:**
```swift
case .currentDwellingType:
    return InputContext(
        header: "What kind of place is it?",
        subheader: nil
    )
```

**currentAddress:**
```swift
case .currentAddress:
    return InputContext(
        header: "What's the address?",
        subheader: "I'll use this for mail forwarding, utilities, change of address—all the stuff you'd normally have to chase down yourself."
    )
```

**currentFloorAccess:**
```swift
case .currentFloorAccess:
    return InputContext(
        header: "What floor are you on?",
        subheader: "This helps me plan the move-out logistics."
    )
```

**currentBedrooms:**
```swift
case .currentBedrooms:
    return InputContext(
        header: "How many bedrooms?",
        subheader: nil
    )
```

**currentSquareFootage:**
```swift
case .currentSquareFootage:
    return InputContext(
        header: "Roughly how big is the place?",
        subheader: "Don't overthink it—a ballpark is perfect."
    )
```

**currentFinishedSqFt:**
```swift
case .currentFinishedSqFt:
    return InputContext(
        header: "How much finished living space are we working with?",
        subheader: "Ballpark is totally fine."
    )
```

---

### Task 4: Update AssessmentCoordinator.inputContext() — Section 3 (New Home)

**Files:**
- Modify: `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift`

**newRentOrOwn:**
```swift
case .newRentOrOwn:
    return InputContext(
        header: "Now let's talk about where you're headed. Renting or buying?",
        subheader: nil
    )
```

**newDwellingType:**
```swift
case .newDwellingType:
    return InputContext(
        header: "What kind of place is the new one?",
        subheader: nil
    )
```

**newAddress:**
```swift
case .newAddress:
    return InputContext(
        header: "What's the new address?",
        subheader: "Same deal—I'll use it to get utilities, internet, and everything else set up before you even walk in the door."
    )
```

**newFloorAccess:**
```swift
case .newFloorAccess:
    return InputContext(
        header: "What floor is the new place?",
        subheader: "Helps me plan the move-in side."
    )
```

**newBedrooms:**
```swift
case .newBedrooms:
    return InputContext(
        header: "How many bedrooms at the new place?",
        subheader: nil
    )
```

**newSquareFootage:**
```swift
case .newSquareFootage:
    return InputContext(
        header: "Roughly how big is the new place?",
        subheader: nil
    )
```

**newFinishedSqFt:**
```swift
case .newFinishedSqFt:
    return InputContext(
        header: "How much finished living space at the new place?",
        subheader: nil
    )
```

---

### Task 5: Update AssessmentCoordinator.inputContext() — Section 4 (People + Storage)

**Files:**
- Modify: `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift`

**hasStorage:**
```swift
case .hasStorage:
    return InputContext(
        header: "Do you have a storage unit that needs to be dealt with?",
        subheader: nil
    )
```

**storageSize:**
```swift
case .storageSize:
    return InputContext(
        header: "How big is the unit?",
        subheader: nil
    )
```

**storageFullness:**
```swift
case .storageFullness:
    return InputContext(
        header: "How full is it?",
        subheader: nil
    )
```

**childrenInSchool:**
```swift
case .childrenInSchool:
    return InputContext(
        header: "Any kids in school?",
        subheader: "I'll handle the enrollment transfers and records requests so you don't have to sit on hold."
    )
```

**childrenInDaycare:**
```swift
case .childrenInDaycare:
    return InputContext(
        header: "Any little ones in daycare?",
        subheader: "I'll help with the provider search at the new place."
    )
```

**hasVet:**
```swift
case .hasVet:
    return InputContext(
        header: "Got any pets that see a vet?",
        subheader: "I'll transfer records and find a new vet near the new place if you need one."
    )
```

**hasVehicles:**
```swift
case .hasVehicles:
    return InputContext(
        header: "Any vehicles that need registration or title updates?",
        subheader: "State lines mean paperwork—I'll handle it."
    )
```

---

### Task 6: Update AssessmentCoordinator.inputContext() — Section 5 (Services)

**Files:**
- Modify: `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift`

**hireMovers:**
```swift
case .hireMovers:
    return InputContext(
        header: "Are you interested in getting quotes for professional movers, or are you planning to handle the move yourself?",
        subheader: "Either way works—I'll build the plan around your choice."
    )
```

**hirePackers:**
```swift
case .hirePackers:
    return InputContext(
        header: "Would you like quotes for professional packing help, or are you planning to pack everything yourself?",
        subheader: "Pro tip: packers can do a full house in a day. Just saying."
    )
```

**hireCleaners:**
```swift
case .hireCleaners:
    return InputContext(
        header: "Would you like quotes for a professional move-out cleaning, or are you going to handle that yourself?",
        subheader: "A good deep clean can be the difference between getting your deposit back and leaving money on the table."
    )
```

---

### Task 7: Update AssessmentCoordinator.inputContext() — Section 6 (Accounts) + Wrap-up

**Files:**
- Modify: `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift`

**financialInstitutions:**
```swift
case .financialInstitutions:
    return InputContext(
        header: "Let's make sure your money follows you. Which of these do you need to update your address with?",
        subheader: "Tap all that apply."
    )
```

**financialDetails:**
```swift
case .financialDetails:
    return InputContext(
        header: "Which ones specifically?",
        subheader: "Start typing and I'll help you find them."
    )
```

**healthcareProviders:**
```swift
case .healthcareProviders:
    return InputContext(
        header: "What about healthcare? Who needs your new info?",
        subheader: "Tap all that apply."
    )
```

**healthcareDetails:**
```swift
case .healthcareDetails:
    return InputContext(
        header: "Which ones specifically?",
        subheader: nil
    )
```

**fitnessWellness:**
```swift
case .fitnessWellness:
    return InputContext(
        header: "Any memberships or subscriptions we should cancel or transfer?",
        subheader: "Gyms love to keep charging after you leave. Tap all that apply."
    )
```

**fitnessDetails:**
```swift
case .fitnessDetails:
    return InputContext(
        header: "Which ones specifically?",
        subheader: nil
    )
```

**howHeard:**
```swift
case .howHeard:
    return InputContext(
        header: "Last one, \(dataManager.userName)—how'd you find us?",
        subheader: nil
    )
```

---

### Task 8: Update MoveConcerns.swift — option labels

**Files:**
- Modify: `Peezy 4.0/Assessment/AssessmentViews/Questions/MoveConcerns.swift`

Change the `concerns` array from current labels to:
```swift
let concerns = [
    ("Knowing what to do and when", "list.bullet.clipboard"),
    ("Finding time to actually pack", "shippingbox.fill"),
    ("Dealing with moving companies", "person.2.fill"),
    ("The fear of forgetting something important", "calendar"),
    ("Something else", "ellipsis")
]
```

Also update the "Other" references in the body:
- `concern.0 == "Other"` → `concern.0 == "Something else"`
- `selectedConcerns.contains("Other")` → `selectedConcerns.contains("Something else")` (both places)
- `concernsToSave.removeAll { $0 == "Other" }` → `concernsToSave.removeAll { $0 == "Something else" }`
- `concernsToSave.append("Other: \(otherText)")` → `concernsToSave.append("Something else: \(otherText)")`
- In `.onAppear`: `concern.hasPrefix("Other: ")` → `concern.hasPrefix("Something else: ")` and `concern.dropFirst(7)` → `concern.dropFirst("Something else: ".count)`

Also remove the redundant header from the view (the spec says header is in `inputContext()` now) — remove the `VStack` containing `Text("Biggest concerns?")` and `Text("Tap all that apply")` since `inputContext()` now provides the header and "Pick your biggest headaches below." as the subheader. The view should use `AssessmentContentArea` or just remove the custom question block since the wrapper handles it.

WAIT — looking at the architecture again: `AssessmentFlowView` wraps each question view in `AssessmentInputWrapper`, which already handles the header/subheader from `inputContext()`. The individual view's own question text ALSO renders. These views currently render BOTH. The spec says copy lives in `inputContext()` — the individual view's questionText is redundant.

For MoveConcerns, the view has its own custom question + subtext layout that doesn't use `AssessmentContentArea`. The right approach: keep the view rendering just the tiles (no extra question text). However, removing the large question text would change the layout significantly and could break things. The SAFE approach per the task: only update the copy that is shown, don't restructure the layout.

Decision: Update `inputContext()` (which already shows in the wrapper above the view) AND update any in-view questionText to keep them in sync. For screens where the in-view questionText duplicates the header, it will show twice — but that's the current state and not asked to fix here.

For MoveConcerns specifically: the view has its own `"Biggest concerns?"` title inline. This will duplicate the new header from inputContext. Update the in-view question text to match the new header OR remove it since the wrapper already shows it. Looking at other views (UserName, MoveDate) — they also have their own `Text("Your name?")` etc. inside. The `AssessmentFlowView` comment says "These views contain ONLY input controls" but the reality is they also render question text.

The safest approach that matches the task: update `inputContext()` as the authoritative source, AND update the in-view questionText in each view to match the new copy. This way no screen shows stale copy.

---

### Task 9: Update MoveDateType.swift — option labels + in-view questionText

**Files:**
- Modify: `Peezy 4.0/Assessment/AssessmentViews/Questions/MoveDateType.swift`

Change the `options` array:
```swift
let options = ["Strict (same-day swap)", "Flexible (I have wiggle room)"]
```

Update `iconMap`:
```swift
let iconMap: [String: String] = [
    "Strict (same-day swap)": "arrow.left.arrow.right",
    "Flexible (I have wiggle room)": "checkmark.circle"
]
```

⚠️ IMPORTANT: The coordinator's `interstitialComment(after: .moveDateType)` and other places switch on `dataManager.moveDateType.lowercased()` values. The current labels are `"Same Day"`, `"Out Before In"`, `"In Before Out"`. These new labels are completely different. Check all coordinator switch statements for moveDateType and update them too.

Actually — re-reading the spec more carefully: the new options are just `"Strict (same-day swap)"` and `"Flexible (I have wiggle room)"`. This removes the 3-way split. Need to update the interstitialComment switch for moveDateType to handle the new values.

Also update the `questionText` in `AssessmentContentArea` from `"What's the plan?"` → keep it consistent or remove since wrapper handles it.

---

### Task 10: Update individual view questionText strings

**Files:**
- Modify multiple files in `Peezy 4.0/Assessment/AssessmentViews/Questions/`

These views render their own `questionText` via `AssessmentContentArea` or custom layouts. Update each to remove stale copy. Since `AssessmentInputWrapper` already shows the new header above, the individual view's questionText creates duplication. The approach: update questionText in each view to be blank or match the header, OR simply remove the question text from views and let the wrapper handle it.

Looking at the code: `UserName`, `MoveDate`, `MoveConcerns` all have custom layout with inline question text. The `AssessmentContentArea`-using views (`MoveDateType`, `CurrentRentOrOwn`, etc.) pass `questionText` explicitly.

The fix: for views using `AssessmentContentArea`, update `questionText` to match or leave blank (empty string would hide it since the wrapper already shows it). For views with custom layouts (`UserName`, `MoveDate`, `MoveConcerns`), update inline text to match.

---

### Task 11: Build verification

Run xcodebuild to confirm zero compile errors:
```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

---

## Execution Order

1. Read AssessmentCoordinator.swift fully before editing (already done in planning)
2. Task 1: AssessmentIntroView.swift
3. Tasks 2-7: AssessmentCoordinator.swift inputContext() (all in one edit pass)
4. Task 8: MoveConcerns.swift option labels
5. Task 9: MoveDateType.swift option labels + coordinator interstitial update
6. Task 10: Individual view questionText updates (can scan and update in bulk)
7. Task 11: Build verification

## Files That Will Change

1. `Peezy 4.0/Assessment/AssessmentViews/Onboarding/AssessmentIntroView.swift`
2. `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift` (inputContext + interstitialComment for new moveDateType labels)
3. `Peezy 4.0/Assessment/AssessmentViews/Questions/MoveConcerns.swift`
4. `Peezy 4.0/Assessment/AssessmentViews/Questions/MoveDateType.swift`
5. Possibly: Individual question view files if their inline questionText needs updating (UserName, MoveDate, CurrentRentOrOwn, etc.)
