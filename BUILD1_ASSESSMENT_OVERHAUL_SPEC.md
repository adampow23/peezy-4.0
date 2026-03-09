# Assessment Overhaul Build 1 — Copy, Layout & Cleanup

## Purpose

Batch of 22 assessment fixes: copy changes, layout spacing, question removals, new question additions, icon swaps, and main interface polish. These are all Category A (deterministic, verifiable by compilation + code inspection) except the layout spacing items which are Category B (visual).

## Lessons Learned (PREVENT THESE)

- LE-001: Script must run from `~/Desktop/Peezy 4.0/` — check for `Peezy 4.0.xcodeproj`
- LE-002: `unset CLAUDECODE` at top of build script
- LE-018: Bash 3.2 compatibility — no `declare -A` or `${!var}`
- LE-021: Simplest solution wins — do NOT refactor layouts or restructure files beyond what's specified

## Pre-Flight Check

```bash
ls "Peezy 4.0.xcodeproj" || { echo "WRONG DIRECTORY"; exit 1; }
ls "Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift" || { echo "Missing AssessmentCoordinator"; exit 1; }
ls "Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift" || { echo "Missing AssessmentDataManager"; exit 1; }
ls "Peezy 4.0/Assessment/AssessmentModels/AssessmentFlowView.swift" || { echo "Missing AssessmentFlowView"; exit 1; }
xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | tail -1
```

---

## Phase 1: Sequence Changes — Remove SqFt, Add AnyKids, Remove PromoCode (files: 3 modify)

**CATEGORY:** A (Logic — enum and sequence changes, verifiable by compilation)

**READ FIRST:**
- `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift` — the `AssessmentInputStep` enum AND the `buildSequence()` method
- `Peezy 4.0/Assessment/AssessmentModels/AssessmentFlowView.swift` — the `questionView(for:)` switch
- `Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift` — properties list

**Changes to `AssessmentCoordinator.swift`:**

1. Add a new enum case in `AssessmentInputStep`:
```swift
// Section 4: People  
case anyKids        // NEW — before childrenInSchool
case childrenInSchool
case childrenInDaycare
```

2. In `buildSequence()`, make these changes:

**Remove from Section 2 (Current Home):** Remove `addStep(.currentSquareFootage)` AND `addStep(.currentFinishedSqFt)` from BOTH the apartment/condo branch AND the house/townhouse branch. Keep `currentBedrooms` in both branches.

**Remove from Section 3 (New Home):** Same — remove `addStep(.newSquareFootage)` AND `addStep(.newFinishedSqFt)` from both branches. Keep `newBedrooms`.

**Add to Section 4 (People):** Before `addStep(.childrenInSchool)`, add:
```swift
addStep(.anyKids)
if dataManager.anyKids.lowercased() == "yes" {
    addStep(.childrenInSchool)
    addStep(.childrenInDaycare)
}
```
Remove the existing standalone `addStep(.childrenInSchool)` and `addStep(.childrenInDaycare)` that were there before.

**Remove from Wrap-up:** Remove `addStep(.promoCode)`.

3. In `isBranchingStep()`, add `.anyKids` to the switch:
```swift
case .currentDwellingType, .newDwellingType,
     .hasStorage, .hireMovers, .hasDeclutter,
     .financialInstitutions, .healthcareProviders, .fitnessWellness,
     .anyKids:  // NEW
    return true
```

**Changes to `AssessmentDataManager.swift`:**

1. Add property: `@Published var anyKids: String = ""`
2. Add to `getAllAssessmentData()`: `data["anyKids"] = anyKids`
3. Add to `reset()`: `anyKids = ""`
4. Do NOT remove sqft properties from DataManager yet — they can stay as unused properties. Removing them risks breaking other references. We'll clean those up in a later build.

**Changes to `AssessmentFlowView.swift`:**

1. Add to the `questionView(for:)` switch, in Section 4:
```swift
case .anyKids:               AnyKids()
```

2. Remove from the switch (these views still exist as files but won't be reachable):
```swift
case .currentSquareFootage:  CurrentSquareFootage()
case .currentFinishedSqFt:   CurrentFinishedSqFt()
case .newSquareFootage:      NewSquareFootage()
case .newFinishedSqFt:       NewFinishedSqFt()
case .promoCode:             PromoCode()
```
Keep the enum cases (to avoid breaking other references) but remove them from the switch. Add a `default: EmptyView()` at the bottom of the switch if needed to handle unreachable cases.

**BLAST RADIUS:** AssessmentFlowView and AssessmentCoordinator are tightly coupled but only through the enum. No other files import AssessmentInputStep directly for branching logic.

**DO NOT CHANGE:**
- `TaskConditionerParser.swift`
- `TaskGenerationService.swift`
- Any existing question view files
- The `completeAssessment()` method
- The `inputContext()` method (that's Phase 2)

**Verification:** `xcodebuild` succeeds. Note: AnyKids.swift doesn't exist yet — create it as an empty placeholder to prevent build failure:

```swift
// Peezy 4.0/Assessment/AssessmentViews/Questions/AnyKids.swift
import SwiftUI

struct AnyKids: View {
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    @State private var showContent = false
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    let options = ["Yes", "No"]

    var body: some View {
        VStack(spacing: 0) {
            AssessmentContentArea {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        SelectionTile(title: option, icon: nil, isSelected: assessmentData.anyKids == option, onTap: {
                            assessmentData.anyKids = option
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                lightHaptic.impactOccurred()
                                coordinator.goToNext()
                            }
                        })
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 30)
                        .animation(.easeOut(duration: 0.5).delay(0.5 + Double(index) * 0.1), value: showContent)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            withAnimation { showContent = true }
        }
    }
}
```

Place this file at `Peezy 4.0/Assessment/AssessmentViews/Questions/AnyKids.swift`.

**Mark Phase 1 complete when xcodebuild succeeds.**

---

## Phase 2: All Copy Changes in inputContext (files: 1 modify)

**CATEGORY:** A (Text changes — verifiable by compilation and code inspection)

**READ FIRST:** `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift` — the entire `inputContext(for:)` method

**Changes to `AssessmentCoordinator.swift` — `inputContext(for:)` method:**

Find and replace these cases. Leave ALL other cases unchanged.

**Item 4 — moveConcerns:**
```swift
case .moveConcerns:
    return InputContext(
        header: "What are you most hoping Peezy can help you with?",
        subheader: nil
    )
```

**Item 11 — hasStorage:**
```swift
case .hasStorage:
    return InputContext(
        header: "Are there any items in storage that will be making the move as well?",
        subheader: nil
    )
```

**Item 14 (NEW) — anyKids:** Add this new case:
```swift
case .anyKids:
    return InputContext(
        header: "Will any children be making the move with you?",
        subheader: nil
    )
```

**Item 15 — childrenInSchool:**
```swift
case .childrenInSchool:
    return InputContext(
        header: "Will any of them need to transfer schools?",
        subheader: nil
    )
```

**Item 16 — childrenInDaycare:**
```swift
case .childrenInDaycare:
    return InputContext(
        header: "What about any in daycare?",
        subheader: nil
    )
```

**Item 17 — hasVet:**
```swift
case .hasVet:
    return InputContext(
        header: "Got any pets that see a vet?",
        subheader: nil
    )
```

**Item 18 — hasVehicles:**
```swift
case .hasVehicles:
    return InputContext(
        header: "How many vehicles will be moving with you?",
        subheader: nil
    )
```

**Item 20 — hireMovers:**
```swift
case .hireMovers:
    return InputContext(
        header: "Would you like quotes for professional movers?",
        subheader: nil
    )
```

**Item 22 — hasDeclutter (add visual break):**
```swift
case .hasDeclutter:
    return InputContext(
        header: "Any items you're planning to part with before the move?",
        subheader: "Clothes, furniture, electronics — anything you don't want making the trip."
    )
```

**Item 23 — wantToSell:**
```swift
case .wantToSell:
    return InputContext(
        header: "Are you planning to sell any of those items?",
        subheader: "We can assist with that process as well as plan b if they don't sell."
    )
```

**Item 24 — hireCleaners:**
```swift
case .hireCleaners:
    return InputContext(
        header: "And for the final deep clean of your current home, would you like to get some quotes for professional cleaners?",
        subheader: nil
    )
```

**Item 26 — financialInstitutions:**
```swift
case .financialInstitutions:
    return InputContext(
        header: "Let's start with finance related accounts you might have.",
        subheader: "Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you."
    )
```

**Item 28 — healthcareProviders:**
```swift
case .healthcareProviders:
    return InputContext(
        header: "Now for any health-related accounts?",
        subheader: "Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you."
    )
```

**Item 30a — fitnessWellness:**
```swift
case .fitnessWellness:
    return InputContext(
        header: "And lastly, do you have any wellness-related memberships?",
        subheader: "Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you."
    )
```

**Item 30b — howHeard:**
```swift
case .howHeard:
    return InputContext(
        header: "Before we get to the fun stuff, we'd love to know what put Peezy on your radar?",
        subheader: nil
    )
```

**BLAST RADIUS:** inputContext is read-only data — it returns strings. No other files depend on the exact copy. Zero blast radius.

**DO NOT CHANGE:**
- Any case not listed above
- The `buildSequence()` method (changed in Phase 1)
- Any question view files
- Any other files

**Verification:** `xcodebuild` succeeds.

**Mark Phase 2 complete when verification passes.**

---

## Phase 3: Question View Modifications (files: 3-4 modify)

**CATEGORY:** A (Option changes — verifiable by compilation)

**READ FIRST:**
- `Peezy 4.0/Assessment/AssessmentViews/Questions/HasVehicles.swift`
- `Peezy 4.0/Assessment/AssessmentViews/Questions/HireMovers.swift`
- `Peezy 4.0/Assessment/AssessmentViews/Questions/HowHeard.swift`
- `Peezy 4.0/Assessment/AssessmentViews/Questions/MoveConcerns.swift`

**Changes to `HasVehicles.swift`:**
Change the options array to: `["None", "One", "Two", "Three+"]`
Update the `iconMap` dictionary appropriately (use car-related SF Symbols or nil).
The selected value should be stored in `assessmentData.hasVehicles`.

**Changes to `HireMovers.swift`:**
Change options to just: `["Yes", "No"]`
This simplifies from the previous multi-option approach. Store in `assessmentData.hireMovers`.

**Changes to `HowHeard.swift`:**
Add `"Moving Company"` to the options array. Keep all existing options.

**Changes to `MoveConcerns.swift`:**
Change the continue button text from whatever it currently says to `"Continue"`.

**BLAST RADIUS:**
- HasVehicles: `assessmentData.hasVehicles` is used in `getAllAssessmentData()` and potentially in task conditions. The new values ("None", "One", "Two", "Three+") must match any catalog conditions. Check `taskCatalogData.json` for conditions referencing `hasVehicles`. If conditions use "Yes"/"No", add a mapping in `getAllAssessmentData()`.
- HireMovers: Changing to "Yes"/"No" actually IMPROVES condition matching since the catalog uses "Yes"/"No". This is good.

**DO NOT CHANGE:**
- AnyKids.swift (created in Phase 1)
- AssessmentCoordinator.swift (modified in Phases 1-2)
- Any other question views not listed

**Verification:** `xcodebuild` succeeds.

**Mark Phase 3 complete when verification passes.**

---

## Phase 4: Address Icon Change (files: 2 modify)

**CATEGORY:** B (Visual change)

**READ FIRST:**
- `Peezy 4.0/Assessment/AssessmentViews/Questions/CurrentAddress.swift`
- `Peezy 4.0/Assessment/AssessmentViews/Questions/NewAddress.swift`

**AIM FOR THIS:** A faint pencil icon (SF Symbol `"pencil"`) sitting in the main content area of the address container, replacing the current pencil-in-box icon inside a circle.

**AVOID THIS:** The old circled pencil-in-box icon. Any icon that looks heavy or dominant.

**Fix:** In both files, find the icon rendering. Replace:
- The SF Symbol name from `"square.and.pencil"` (or whatever circled variant is used) to just `"pencil"`
- Remove any `.background(Circle())` or circle wrapper around the icon
- Make the icon faint: `.foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.15))` or similar low opacity
- Keep the icon size reasonable — `font(.system(size: 28))` or similar

**BLAST RADIUS:** None — these are self-contained view files.

**DO NOT CHANGE:**
- The address input logic, autocomplete, or data binding
- The keyboard handling
- Any other assessment files

**Verification:** `xcodebuild` succeeds.

**Mark Phase 4 complete when verification passes.**

---

## Phase 5: Layout Spacing Fixes — Text Fields + Date Picker (files: 2-3 modify)

**CATEGORY:** B (Visual — spacing and layout)

**AIM FOR THIS:** Equal visual spacing between elements on text field pages (username, addresses) and the date picker page. When keyboard is present: progress bar at top with normal padding → question copy → equal space → text field → equal space → button → equal space → keyboard.

**AVOID THIS:** Elements crammed together at the top. Text field disappearing under keyboard. Uneven spacing between elements.

**READ FIRST:**
- `Peezy 4.0/Assessment/AssessmentViews/Questions/UserName.swift` (or whatever the username entry view is called)
- `Peezy 4.0/Assessment/AssessmentViews/Questions/MoveDate.swift`
- `Peezy 4.0/Assessment/AssessmentViews/Questions/CurrentAddress.swift`
- `Peezy 4.0/Assessment/AssessmentViews/Questions/NewAddress.swift`
- `Peezy 4.0/Assessment/AssessmentModels/AssessmentInputWrapper.swift`

**Fix approach — SIMPLEST SOLUTION:**

For text field pages (UserName, CurrentAddress, NewAddress):
- These views live inside `AssessmentInputWrapper` which handles the header/subheader
- The content area (text field + button) needs proper spacing
- Look at how the views handle the keyboard. There's a `KeyboardObserver` pattern in the codebase.
- Ensure the text field and button have equal padding between them and between the button and keyboard
- The progress bar should remain visible when keyboard is present — check if `AssessmentInputWrapper` has `.ignoresSafeArea(.keyboard)`. If yes, that's by design. The individual views need to handle keyboard offset.

For the date picker (MoveDate):
- Add more space between the date picker and the continue button
- Use consistent padding (e.g., 24pt) between last copy line and picker, and between picker and button

**DO NOT CHANGE:**
- The typewriter animation (that's Build 2)
- The morph animation
- The AssessmentInputWrapper animation logic
- Any question logic or data binding

**Verification:** `xcodebuild` succeeds.

**WHAT ADAM SHOULD SEE:** Even spacing on text field pages. Date picker has breathing room above the button. Progress bar visible when keyboard is up.
**WHAT ADAM SHOULD NOT SEE:** Cramped elements. Hidden text fields. Touching elements.

**Mark Phase 5 complete when verification passes.**

---

## Phase 6: Rent/Own Extra Space + Storage Icon Sizes + Fullness Pie Icons (files: 4-5 modify)

**CATEGORY:** B (Visual modifications)

**READ FIRST:**
- `Peezy 4.0/Assessment/AssessmentViews/Questions/CurrentRentOrOwn.swift`
- `Peezy 4.0/Assessment/AssessmentViews/Questions/NewRentOrOwn.swift`
- `Peezy 4.0/Assessment/AssessmentViews/Questions/StorageSize.swift`
- `Peezy 4.0/Assessment/AssessmentViews/Questions/StorageFullness.swift`

**Item 10 — Rent/Own spacing:**
For both CurrentRentOrOwn and NewRentOrOwn, the question header needs extra visual separation before the question text. The `inputContext` header should feel like it has a clear break between the setup text and the actual question. This is handled by the copy itself — ensure the copy in `inputContext` creates a natural pause. If the issue is visual spacing, add `.padding(.top, 8)` to the selection tiles area.

**Item 12 — Storage Size icons:**
Replace the icons for Small/Medium/Large storage options with a basic square icon (`"square"` SF Symbol) at increasing sizes:
- Small: `.font(.system(size: 20))`
- Medium: `.font(.system(size: 28))`
- Large: `.font(.system(size: 36))`
Same icon, different size. This visually communicates the size difference.

**Item 13 — Storage Fullness pie icons:**
Replace the icons with pie chart representations:
- 1/4 full: `"chart.pie"` with a quarter fill (use `"circle.lefthalf.filled"` rotated, or custom approach). Simplest: use SF Symbol `"chart.pie"` if available in iOS 17, otherwise use `"circle"` with an overlay arc.
- Actually simplest approach: Use the same `"chart.pie"` SF Symbol for all but vary the label text to show the percentage. OR use `"circle.dotted"` variants. READ the file first to see what icons are currently used and what SF Symbols are available.

**DO NOT CHANGE:** Any logic, data binding, or navigation in these files.

**Verification:** `xcodebuild` succeeds.

**Mark Phase 6 complete when verification passes.**

---

## Phase 7: Main Interface — Welcome Card + Tab Bar (files: 2 modify)

**CATEGORY:** B (Visual)

**READ FIRST:**
- `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift` — find the `firstTimeWelcomeCard` section
- `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift` — find the tab bar

**Item 34 — Welcome card subtext centering:**
In the welcome card view, the subtext (body text) needs to be vertically centered between the line under the header and the 3 dot indicators above the button. Look for the VStack layout inside the card and adjust spacing so the body text is centered in the available space between header divider and dots.

**Item 37 — Tab bar: remove titles, fix background:**
In the tab bar (floating bar at bottom):
- Remove the text labels under the icons. Keep only the icons.
- Find what's causing a white/opaque bar behind the floating tab at the very bottom of the screen. This is likely a `.background()` modifier on a container or the tab bar itself having a background that doesn't match the InteractiveBackground. Ensure the InteractiveBackground extends fully behind and below the tab bar with `.ignoresSafeArea()`.

**AIM FOR THIS:** Clean tab bar with only icons, no white gap behind it. Welcome card body text vertically centered in its space.
**AVOID THIS:** Text labels under tab icons. White bar at screen bottom. Body text crammed at top of card.

**DO NOT CHANGE:**
- Tab navigation logic
- Card stack behavior
- Welcome card page content or button behavior

**Verification:** `xcodebuild` succeeds.

**Mark Phase 7 complete when verification passes.**

---

## Files Summary

### Created
| Phase | File | What |
|-------|------|------|
| 1 | `Peezy 4.0/Assessment/AssessmentViews/Questions/AnyKids.swift` | New yes/no question view |

### Modified
| Phase | File | What Changed |
|-------|------|-------------|
| 1 | `AssessmentCoordinator.swift` | Enum + buildSequence: remove sqft, add anyKids, remove promo |
| 1 | `AssessmentDataManager.swift` | Add anyKids property |
| 1 | `AssessmentFlowView.swift` | Update switch for new/removed cases |
| 2 | `AssessmentCoordinator.swift` | inputContext copy changes (15 cases) |
| 3 | `HasVehicles.swift` | New options: None/One/Two/Three+ |
| 3 | `HireMovers.swift` | Simplified to Yes/No |
| 3 | `HowHeard.swift` | Added "Moving Company" option |
| 3 | `MoveConcerns.swift` | Button text to "Continue" |
| 4 | `CurrentAddress.swift` | Icon change to plain pencil |
| 4 | `NewAddress.swift` | Icon change to plain pencil |
| 5 | `UserName.swift` (or equiv) | Layout spacing with keyboard |
| 5 | `MoveDate.swift` | Date picker spacing |
| 5 | `CurrentAddress.swift` | Layout spacing with keyboard |
| 5 | `NewAddress.swift` | Layout spacing with keyboard |
| 6 | `CurrentRentOrOwn.swift` | Spacing adjustment |
| 6 | `NewRentOrOwn.swift` | Spacing adjustment |
| 6 | `StorageSize.swift` | Square icons at different sizes |
| 6 | `StorageFullness.swift` | Pie chart icons |
| 7 | `PeezyHomeView.swift` | Welcome card subtext centering |
| 7 | `PeezyMainContainer.swift` | Tab bar: remove titles, fix bg |

### NOT Modified (Confirm at end)
- `TaskConditionerParser.swift` — UNTOUCHED
- `TaskGenerationService.swift` — UNTOUCHED
- `taskCatalogData.json` — UNTOUCHED
- `functions/` — ENTIRE DIRECTORY UNTOUCHED
- `Peezy 4.0/Inventory/` — ENTIRE DIRECTORY UNTOUCHED
- `TypingText.swift` — UNTOUCHED (Build 2)
- `AssessmentInputWrapper.swift` animation logic — UNTOUCHED (Build 2)
