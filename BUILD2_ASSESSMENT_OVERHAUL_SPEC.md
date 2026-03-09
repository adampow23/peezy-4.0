# Assessment Overhaul Build 2 — Typewriter Rebuild, New Screens, Task Gen, Main Interface

## Purpose

12 remaining items: typewriter Category C rebuild, assessment intro restyle, two section explainer pages, financial/healthcare/fitness detail redesign, bedroom-to-roomlist wiring, task generation fix, assessment-to-app transition, welcome card swipe, and card fly-off animation.

## Lessons Learned (PREVENT THESE)

- LE-001: Script must run from `~/Desktop/Peezy 4.0/`
- LE-002: `unset CLAUDECODE` at top of build script
- LE-018: Bash 3.2 compatible
- LE-021: Simplest solution wins
- LE-022: Never skip understanding the system. Never write descriptive visual instructions.

## Pre-Flight Check

```bash
ls "Peezy 4.0.xcodeproj" || { echo "WRONG DIRECTORY"; exit 1; }
ls "Peezy 4.0/Assessment/AssessmentViews/Components/TypingText.swift" || { echo "Missing TypingText"; exit 1; }
ls "Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift" || { echo "Missing Coordinator"; exit 1; }
ls "Peezy 4.0/MainInterface/Views/PeezyHomeView.swift" || { echo "Missing HomeView"; exit 1; }
xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | tail -1
```

---

## Phase 1: Typewriter Rebuild — Category C (files: 1 replace)

**CATEGORY:** C — This bug survived 3+ fix attempts. The character-by-character string building approach is fundamentally flawed for centered/multi-line text.

**HISTORY:**
- Attempt 1: Added `.frame(maxWidth: .infinity, alignment: .leading)` — still shakes
- Attempt 2: Added `.animation(nil, value: displayedCount)` — still shakes on first line
- Attempt 3: Both combined — first line still shakes, center-to-left shift between lines, word wrap causes words to jump lines while centered

**READ FIRST:** `Peezy 4.0/Assessment/AssessmentViews/Components/TypingText.swift`

**Order of operations — how a typewriter MUST work:**
1. The complete text layout is computed ONCE, upfront — line breaks, word positions, everything
2. A timer advances a character count
3. Characters up to the count become visible. Characters after remain invisible.
4. The text frame, line breaks, and character positions NEVER change during the animation.
5. No parent animation contexts affect the visibility changes.

**The break:** The current implementation builds a NEW string on every tick via `String(fullText.prefix(n))`. This means SwiftUI computes a NEW text layout on every tick. With centered text, a shorter string centers differently than the final string. With proportional fonts, intermediate strings have different widths. With multi-line text, intermediate strings break at different points. This is WHY it shakes — the layout is recalculated 60+ times during the animation, and each layout is slightly different.

**The fix — fundamentally different mechanism:** Render the FULL text always, but use `AttributedString` to make unrevealed characters transparent. The text layout is computed once for the complete string and never changes. Only the foreground color of individual characters changes from `.clear` to the visible color. Per Apple's `AttributedString` documentation (iOS 15+), `foregroundColor` can be set per-character range.

**COMPLETE REPLACEMENT for `Peezy 4.0/Assessment/AssessmentViews/Components/TypingText.swift`:**

```swift
//
//  TypingText.swift
//  Peezy
//
//  One-shot typewriter text component.
//  Uses AttributedString to reveal characters by changing foreground color
//  from .clear to visible. The full text layout is computed once and never
//  changes — eliminating all layout shift, jitter, and alignment issues.
//

import SwiftUI

struct TypingText: View {
    let fullText: String
    let speed: Double
    var onComplete: (() -> Void)? = nil

    @State private var displayedCount: Int = 0
    @State private var timer: Timer?

    private var attributedText: AttributedString {
        var result = AttributedString(fullText)
        // Revealed characters: use the inherited foreground color from parent
        // (don't set anything — let the parent .foregroundColor() apply)
        
        // Unrevealed characters: transparent
        if displayedCount < fullText.count {
            let startIndex = result.index(result.startIndex, offsetByCharacters: displayedCount)
            result[startIndex..<result.endIndex].foregroundColor = .clear
        }
        return result
    }

    var body: some View {
        Text(attributedText)
            .accessibilityLabel(fullText)
            .onAppear {
                startTyping()
            }
            .onChange(of: fullText) { _, _ in
                displayedCount = 0
                timer?.invalidate()
                startTyping()
            }
            .onDisappear {
                timer?.invalidate()
            }
    }

    private func startTyping() {
        guard displayedCount < fullText.count else {
            onComplete?()
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: speed, repeats: true) { t in
            if displayedCount < fullText.count {
                displayedCount += 1
            }
            if displayedCount >= fullText.count {
                t.invalidate()
                onComplete?()
            }
        }
    }
}
```

**Why this works:** The `Text(attributedText)` always contains the complete string. SwiftUI computes the layout — line breaks, centering, everything — once. On each timer tick, `displayedCount` changes, which changes the `AttributedString` color ranges, which makes more characters visible. But the string content never changes, so the layout never changes. No jitter is structurally possible.

**What this removes:** The hidden backing Text, the ZStack, the `.frame()` modifiers, the `.animation(nil)` — all of it. None of that is needed because the layout is inherently stable.

**AIM FOR THIS:** Text appears character by character. Zero movement. Zero shake. Lines stay in place. Centered text stays centered. Multi-line text never reflows.
**AVOID THIS:** Any horizontal shake, wobble, blur, alignment shift, or word jumping between lines.
**BLAST RADIUS:** TypingText is used by AssessmentInputWrapper for headers and subheaders. The API is unchanged (same init params, same onComplete callback), so no other files need changes.
**DO NOT CHANGE:** AssessmentInputWrapper.swift, any other files.
**FALLBACK:** If AttributedString foregroundColor doesn't properly inherit from parent modifiers, switch to explicitly passing the color as a parameter to TypingText and setting revealed characters to that color.

**Verification:** `xcodebuild` succeeds.

**Mark Phase 1 complete when verification passes.**

---

## Phase 2: Assessment Intro Page Restyle (files: 1 modify)

**CATEGORY:** A (Logic + layout change)

**READ FIRST:** `Peezy 4.0/Assessment/AssessmentViews/Onboarding/AssessmentIntroView.swift`

**Item 1:** Restyle the intro page to match the typewriter pattern of question pages: icon appears first with a sparkling/scaling effect, then the copy typewriters in, then the button appears. No morph needed (text stays centered, doesn't move to top-left).

**Changes to `AssessmentIntroView.swift`:**

Replace the body with this approach:
1. Icon appears with a scale-up + sparkle animation (use SF Symbol `"wand.and.stars"` with `.symbolEffect(.variableColor.iterative)` for the sparkle — this is Apple's built-in symbol animation, iOS 17+)
2. After icon settles (~0.8s delay), header text typewriters in using `TypingText`
3. After header completes, description text typewriters in using `TypingText`
4. After description completes, time estimate and button fade in

The key structural change: replace the static `Text("Welcome to the easy part")` and `Text("You're in! Take a deep breath...")` with `TypingText` components that type in sequentially. Keep the same copy. Keep the same layout.

The icon sparkle: use `.symbolEffect(.variableColor.iterative.reversing, options: .repeating)` on the SF Symbol. This is an Apple-native animation that requires zero custom code.

The button should appear AFTER all text has finished typing, not simultaneously.

**DO NOT CHANGE:** The navigation logic (`showAssessment = true` on button tap). The copy text. The overall layout structure.
**BLAST RADIUS:** None — self-contained view.

**Verification:** `xcodebuild` succeeds.

**Mark Phase 2 complete when verification passes.**

---

## Phase 3: Services Explainer Page + Address Change Explainer Page (files: 3-4 modify/create)

**CATEGORY:** A (New screens + sequence changes)

**READ FIRST:**
- `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift` — `buildSequence()` and `inputContext()`
- `Peezy 4.0/Assessment/AssessmentModels/AssessmentFlowView.swift` — `questionView(for:)`

**Item 19:** Add an explainer page before the services section (before hireMovers). Icon: hard hat or toolbox. Copy explains that we'll ask about professional services they might want quotes for. Continue button reveals like normal assessment controls.

**Item 25:** Add an explainer page before the address change section (before financialInstitutions). Icon: envelope or mailbox. Copy explains they'll need to update addresses with certain companies and we can help with cancellations/finding new providers. Continue button same pattern.

**Implementation:**

1. Add two new enum cases in `AssessmentInputStep`:
```swift
case servicesIntro      // Before hireMovers
case addressChangeIntro // Before financialInstitutions
```

2. In `buildSequence()`, insert:
```swift
// Before services section:
addStep(.servicesIntro)
addStep(.hireMovers)
// ...

// Before accounts section:
addStep(.addressChangeIntro)
addStep(.financialInstitutions)
// ...
```

3. In `inputContext()`, add:
```swift
case .servicesIntro:
    return InputContext(
        header: "Now let's talk about any professional help you might need.",
        subheader: "We'll ask about services you're planning to hire or even just interested in receiving quotes from — movers, packers, cleaners, and more."
    )

case .addressChangeIntro:
    return InputContext(
        header: "Time to make sure everyone knows where to find you.",
        subheader: "You'll need to update your address with certain companies. We can help with that — and if you need to cancel something or find a new provider in your area, we've got you covered."
    )
```

4. In `questionView(for:)`, add:
```swift
case .servicesIntro:       ExplainerPage(icon: "hammer.fill", onContinue: { coordinator.goToNext() })
case .addressChangeIntro:  ExplainerPage(icon: "envelope.fill", onContinue: { coordinator.goToNext() })
```

5. Create `Peezy 4.0/Assessment/AssessmentViews/Questions/ExplainerPage.swift`:

```swift
import SwiftUI

struct ExplainerPage: View {
    let icon: String
    let onContinue: () -> Void
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @State private var showButton = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Spacer()
            // Button appears after the typewriter text finishes in the wrapper
            PeezyAssessmentButton("Continue") {
                onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showButton ? 1 : 0)
            .animation(.easeOut(duration: 0.35).delay(0.3), value: showButton)
        }
        .onAppear {
            // Delay button reveal to let typewriter in wrapper finish
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                showButton = true
            }
        }
    }
}
```

Note: The icon and header/subheader text are already handled by `AssessmentInputWrapper` via `inputContext()`. The `ExplainerPage` only needs to provide the Continue button. The icon from the `icon` parameter should be displayed by adding it to the `inputContext` or by showing it in the ExplainerPage body above the wrapper text. READ `AssessmentInputWrapper` to determine the best approach — if the wrapper already supports an icon display, use that. If not, the simplest approach is to show the icon in the ExplainerPage body before the spacers.

**DO NOT CHANGE:** Any existing question views. The morph animation logic. The branching logic.
**BLAST RADIUS:** Adding enum cases to AssessmentInputStep affects the switch in questionView — ensure the new cases are handled.

**Verification:** `xcodebuild` succeeds.

**Mark Phase 3 complete when verification passes.**

---

## Phase 4: Financial/Healthcare/Fitness Details — One-at-a-Time Redesign (files: 3 modify)

**CATEGORY:** A (Logic redesign with UI changes)

**READ FIRST:**
- `Peezy 4.0/Assessment/AssessmentViews/Questions/FinancialDetails.swift`
- `Peezy 4.0/Assessment/AssessmentViews/Questions/HealthcareDetails.swift`
- `Peezy 4.0/Assessment/AssessmentViews/Questions/FitnessDetails.swift`

**Item 27, 29, 30:** Replace the batch entry (all fields on one scrollable page) with one entry at a time. If user tapped credit card x2, bank/credit union, and student loans, they get 4 sequential pages:
- "What company do you have this credit card with?" (page 1)
- "What company do you have this credit card with?" (page 2)
- "What company do you have this bank/credit union account with?" (page 1)
- "What company do you have this student loan with?" (page 1)

Each page has the same autocomplete `SuggestiveTextField` as the current implementation, just one at a time instead of all at once. Continue button advances to next entry or calls `coordinator.goToNext()` on the last one.

**Implementation approach (simplest):**
Add a `@State private var currentEntryIndex: Int = 0` to each details view. Show only `fieldEntries[currentEntryIndex]`. Continue button increments the index or advances to next assessment step. This keeps all changes within the existing files — no new views needed.

The header copy for each should be: "What company do you have this [category] with?" where category is "credit card", "bank/credit union", etc.

Also fix the hard cut / glow clipping issue (item 27) — this is likely a `.clipped()` modifier on the ScrollView or its container. Since we're removing the ScrollView (one entry at a time doesn't need scrolling), this fixes itself.

**DO NOT CHANGE:** The `SuggestiveTextField` component. The data binding to `assessmentData`. The `fieldEntries` computed property logic.
**BLAST RADIUS:** None — these are self-contained views that save to assessmentData and call coordinator.goToNext().

**Verification:** `xcodebuild` succeeds.

**Mark Phase 4 complete when verification passes.**

---

## Phase 5: Bedroom Count → Room List for Scanning (files: 1-2 modify)

**CATEGORY:** A (Data wiring)

**READ FIRST:**
- `Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift` — find where `currentBedrooms` is stored
- `Peezy 4.0/Inventory/Models/InventorySessionManager.swift` — understand how rooms are managed

**Item 8:** When the user submits their bedroom count, generate an auto-populated room list for the inventory scanner. For example, 3 bedrooms → ["Living Room", "Kitchen", "Bedroom 1", "Bedroom 2", "Bedroom 3", "Bathroom", "Garage"].

**Implementation:**
In `AssessmentDataManager`, add a computed property:
```swift
var autoRoomList: [String] {
    let bedroomCount = Int(currentBedrooms) ?? 0
    var rooms = ["Living Room", "Kitchen"]
    for i in 1...max(bedroomCount, 1) {
        rooms.append(bedroomCount == 1 ? "Bedroom" : "Bedroom \(i)")
    }
    rooms.append("Bathroom")
    rooms.append("Garage")
    return rooms
}
```

Include this in `getAllAssessmentData()`:
```swift
data["autoRoomList"] = autoRoomList
```

This data will be available for the inventory scanner to read. The scanner integration (reading this list and pre-populating rooms) can be wired in a future build. For now, the data just needs to exist.

**DO NOT CHANGE:** The bedroom question view. The inventory scanner files. Any other assessment data.
**BLAST RADIUS:** None — adding a computed property and a dictionary key.

**Verification:** `xcodebuild` succeeds.

**Mark Phase 5 complete when verification passes.**

---

## Phase 6: Task Generation + Transition Fixes (files: 2-3 modify)

**CATEGORY:** A (Logic)

**READ FIRST:**
- `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift` — `completeAssessment()`
- `Peezy 4.0/Assessment/AssessmentViews/Onboarding/CompletionFlowView.swift` — stage machine
- `Peezy 4.0/Assessment/AssessmentViews/Onboarding/GeneratingView.swift` — task count fetch

**Item 32 — Zero tasks:**
The previous bugfix batch seeded the task catalog and added geocoding fallbacks. If it STILL shows 0 tasks, the issue is timing: `completeAssessment()` sets `isComplete = true` (showing CompletionFlowView) and `isSaving = true` simultaneously. GeneratingView watches `isSaving`. When `isSaving` flips to false, it calls `fetchTaskCount()`. But if there's a race condition where `isSaving` is already false by the time GeneratingView appears, it might query before tasks are written.

Fix: In `GeneratingView`, add an `onChange(of: isSaving)` observer that triggers `fetchTaskCount()` when `isSaving` transitions from `true` to `false`. Also add a small delay (0.5s) before the fetch to ensure Firestore batch write has committed.

Additionally, ensure the task catalog is seeded by adding to the pre-flight check:
```bash
cd functions && node seedTaskCatalog.js && cd ..
```

**Item 33 — Promo page flash during transition:**
The `routeToMainApp()` method in `CompletionFlowView` hides content, sets `coordinator.isComplete = false` (which dismisses the fullScreenCover), then posts `.assessmentCompleted`. If there's a brief flash of another view, it's because the fullScreenCover dismissal animation reveals whatever's underneath momentarily.

Fix: In `routeToMainApp()`, post the `.assessmentCompleted` notification BEFORE setting `coordinator.isComplete = false`. This way the main app state updates before the cover dismisses. Also ensure `showContent = false` with zero animation duration so nothing is visible during the dismiss.

**DO NOT CHANGE:** TaskGenerationService.swift. TaskConditionerParser.swift. The GeneratingView UI (spinner, messages).
**BLAST RADIUS:** CompletionFlowView and GeneratingView are only used in the completion flow. Changes don't affect the main app.

**Verification:** `xcodebuild` succeeds.

**Mark Phase 6 complete when verification passes.**

---

## Phase 7: Welcome Card Swipe + Card Fly-Off Animation (files: 1 modify)

**CATEGORY:** B (Visual/behavioral)

**READ FIRST:** `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift` — the `firstTimeWelcomeCard` section

**Item 35 — Swipe instead of button for welcome card pages:**

The welcome card currently has a "Continue" button to advance through 3 pages and a "Start My First Task" button on page 3. Replace pages 1-2 navigation with horizontal swipe gesture. Keep the "Start My First Task" button on page 3 only.

**Complete replacement for the action area of firstTimeWelcomeCard:**

Replace the PeezyAssessmentButton section with:
```swift
// Swipe gesture for pages 0-1, button for page 2
if welcomePage < 2 {
    // Swipe hint
    Text("Swipe to continue")
        .font(.caption)
        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.3))
        .padding(.bottom, 30)
} else {
    PeezyAssessmentButton("Start My First Task") {
        viewModel.dismissFirstTimeWelcome()
    }
    .padding(.horizontal, 30)
    .padding(.bottom, 30)
}
```

Add a drag gesture to the card content area:
```swift
.gesture(
    DragGesture(minimumDistance: 50)
        .onEnded { gesture in
            let horizontal = gesture.translation.width
            if horizontal < -50 && welcomePage < 2 {
                // Swipe left → next page
                withAnimation(.easeInOut(duration: 0.3)) {
                    welcomePage += 1
                }
            } else if horizontal > 50 && welcomePage > 0 {
                // Swipe right → previous page
                withAnimation(.easeInOut(duration: 0.3)) {
                    welcomePage -= 1
                }
            }
        }
)
```

**Item 36 — Card fly-off animation:**

This applies to the task cards (InteractiveHomeTaskCard), not the welcome card. When a task is completed or snoozed, the card should fly off screen to the left or right with a realistic feel.

Read `InteractiveHomeTaskCard` in `PeezyHomeView.swift`. Look for how card dismissal currently works. Add an `.offset(x:)` animation that moves the card off-screen when the success state triggers:

When complete → card flies off to the right: `withAnimation(.easeIn(duration: 0.3)) { dismissOffset = UIScreen.main.bounds.width }`
When skip/snooze → card flies off to the left: `withAnimation(.easeIn(duration: 0.3)) { dismissOffset = -UIScreen.main.bounds.width }`

Add `@State private var dismissOffset: CGFloat = 0` to InteractiveHomeTaskCard and apply `.offset(x: dismissOffset)` to the card container. Add a slight rotation for realism: `.rotationEffect(.degrees(Double(dismissOffset) / 30))`.

**AIM FOR THIS:** Welcome card pages navigate by swiping left/right. Swiping back works. Page 3 has a button. Task cards fly off screen with rotation when dismissed.
**AVOID THIS:** Button-based navigation on welcome pages 1-2. Cards that just disappear without animation.
**BLAST RADIUS:** PeezyHomeView only. No other files affected.
**DO NOT CHANGE:** The card content. The view model logic. The task completion/skip logic (only add the visual animation).
**FALLBACK:** If the drag gesture conflicts with other gestures in the view hierarchy, use `simultaneousGesture` or `highPriorityGesture` instead of `.gesture`.

**Verification:** `xcodebuild` succeeds.

**Mark Phase 7 complete when verification passes.**

---

## Files Summary

### Created
| Phase | File | What |
|-------|------|------|
| 3 | `ExplainerPage.swift` | Reusable explainer page with icon + continue button |

### Modified
| Phase | File | What Changed |
|-------|------|-------------|
| 1 | `TypingText.swift` | FULL REBUILD — AttributedString approach replaces string building |
| 2 | `AssessmentIntroView.swift` | Typewriter text + symbol effect for icon |
| 3 | `AssessmentCoordinator.swift` | servicesIntro + addressChangeIntro enum + sequence + inputContext |
| 3 | `AssessmentFlowView.swift` | New switch cases for explainer pages |
| 4 | `FinancialDetails.swift` | One-at-a-time entry redesign |
| 4 | `HealthcareDetails.swift` | One-at-a-time entry redesign |
| 4 | `FitnessDetails.swift` | One-at-a-time entry redesign |
| 5 | `AssessmentDataManager.swift` | autoRoomList computed property |
| 6 | `GeneratingView.swift` | Timing fix for task count fetch |
| 6 | `CompletionFlowView.swift` | Transition ordering fix |
| 7 | `PeezyHomeView.swift` | Welcome card swipe + card fly-off animation |

### NOT Modified (Confirm at end)
- `TaskConditionerParser.swift` — UNTOUCHED
- `TaskGenerationService.swift` — UNTOUCHED
- `AssessmentInputWrapper.swift` — UNTOUCHED
- `functions/` — UNTOUCHED (except seedTaskCatalog in pre-flight)
- `Peezy 4.0/Inventory/` — UNTOUCHED
