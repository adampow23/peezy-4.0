# Assessment & Home Screen Bug Fixes — Spec

## Purpose

Fix 6 bugs discovered during fresh assessment testing: zero tasks generated, typewriter text shaking, text field pages cramped, financial text field disappearing under keyboard, white bar behind home screen tab bar, and floating tab bar height.

## Lessons Learned (PREVENT THESE)

1. DIRECTORY CHECK: Must run from `~/Desktop/Peezy 4.0/` (contains `Peezy 4.0.xcodeproj`)
2. BUILD VERIFICATION: Every phase uses exact xcodebuild command
3. `@Observable` not `ObservableObject` — BUT NOTE: AssessmentCoordinator and AssessmentDataManager currently use `@Published`/`ObservableObject`. Do NOT convert them in this build — that's a separate refactor. Work within the existing pattern for assessment files.
4. READ FIRST before modifying — understand the existing code
5. Do NOT modify files not listed in each phase
6. Do NOT restructure, refactor, or "improve" code beyond the specific fix
7. Do NOT modify .pbxproj files
8. Cloud Functions are NOT involved in this build — do not touch `functions/`

## Pre-Flight Check

```bash
# Verify correct directory
ls "Peezy 4.0.xcodeproj" || { echo "WRONG DIRECTORY"; exit 1; }

# Verify key files exist
ls "Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift" || { echo "Missing AssessmentCoordinator"; exit 1; }
ls "Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift" || { echo "Missing AssessmentDataManager"; exit 1; }
ls "Peezy 4.0/Assessment/AssessmentModels/TaskGenerationService.swift" || { echo "Missing TaskGenerationService"; exit 1; }

# Verify current build
xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | tail -1
```

---

## Phase 1: Fix Zero Tasks Generated (files: 2-3 read, 1-2 modify)

**SYMPTOM:** Fresh assessment completes successfully, `completeAssessment()` runs, but zero tasks are written to `users/{userId}/tasks/`. The task list and card stack are empty.

**LIKELY ROOT CAUSES (investigate in this order):**

1. **Assessment data mapping mismatch.** `getAllAssessmentData()` in `AssessmentDataManager.swift` returns keys/values that don't match what `taskCatalogData.json` conditions expect. For example, conditions check `hireMovers: ["Yes"]` but the assessment might store the raw label like `"Get Me Quotes"` instead of mapping it to `"Yes"`. Check the exact mapping logic.

2. **Geocoding timeout killing task generation.** `completeAssessment()` races geocoding against a 5-second timeout. If geocoding is cancelled, `moveDistance` and `isInterstate` stay as empty strings. ~40 catalog tasks depend on `moveDistance`. If the condition parser sees an empty string for `moveDistance` when it expects `"Local"` or `"Long Distance"`, those tasks fail condition checks.

3. **Task catalog not seeded.** The Firestore `taskCatalog` collection might be empty or contain stale data. Verify by running `cd functions && node seedTaskCatalog.js` as part of the fix.

**DIAGNOSTIC APPROACH — DO THIS FIRST:**

Read these files and trace the data flow:

1. **READ** `Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift` — find the `getAllAssessmentData()` method. Print/log every key-value pair it returns. Look at how `hireMovers`, `hireCleaners`, `moveDistance`, and `isInterstate` are computed. These are the most common condition keys in the catalog.

2. **READ** `Peezy 4.0/Assessment/AssessmentModels/TaskGenerationService.swift` — look at the debug prints in `#if DEBUG`. They show which tasks pass/fail conditions and why. Make sure these prints are enabled and comprehensive.

3. **READ** `functions/taskCatalogData.json` — look at the first 5-10 tasks and their conditions. Cross-reference with what `getAllAssessmentData()` returns.

4. **READ** `Peezy 4.0/Assessment/AssessmentModels/TaskConditionerParser.swift` — understand how it evaluates conditions. Remember: AND across keys, OR within value arrays, case-insensitive key lookup.

**FIX APPROACH:**

After reading all four files, identify the exact mismatch. The most common patterns:

- If `hireMovers` stores raw UI text like `"Get Me Quotes"` or `"Handle It Myself"`, add mapping logic in `getAllAssessmentData()` to convert to `"Yes"` / `"No"`:
  ```swift
  // Map hiring preferences to Yes/No for condition matching
  let hireMoversRaw = hireMovers.lowercased()
  if hireMoversRaw.contains("quote") || hireMoversRaw.contains("professional") || hireMoversRaw.contains("get me") {
      result["hireMovers"] = "Yes"
  } else if !hireMovers.isEmpty {
      result["hireMovers"] = "No"
  }
  ```

- If `moveDistance` is empty string, add a fallback in `getAllAssessmentData()`:
  ```swift
  // Ensure moveDistance has a value even if geocoding timed out
  if moveDistance.isEmpty {
      result["moveDistance"] = "Local"  // Safe default
  }
  ```

- If `hireCleaners` has a similar raw-value-vs-Yes/No problem, apply the same mapping pattern.

**IMPORTANT:** Look at what the `hireMovers` assessment screen (`HireMovers.swift`) actually stores. Read that file too. The options shown to the user determine the raw value. The mapping in `getAllAssessmentData()` must convert those exact strings to what the catalog expects.

After fixing:
1. Run `cd functions && node seedTaskCatalog.js` to ensure the catalog is freshly seeded
2. Build and verify

**DO NOT CHANGE:**
- `TaskConditionerParser.swift` — the parser logic is correct
- `TaskGenerationService.swift` — the generation logic is correct (unless debug logging needs enhancement)
- `taskCatalogData.json` — the catalog is the source of truth
- Any UI files

**Verification:**
1. `xcodebuild` build succeeds
2. `cd functions && node seedTaskCatalog.js` completes successfully
3. Add a temporary debug enhancement to `completeAssessment()` if needed: after `taskService.generateTasksForUser()` returns, print the count. Confirm the return value would be > 0 for typical assessment data.

**Mark Phase 1 complete when verification passes.**

<!-- Phase 1: COMPLETE -->

---

## Phase 2: Fix Typewriter Text Horizontal Shaking (files: 1 modify)

**SYMPTOM:** During assessment, as the typewriter text animates character by character, the text shakes/jitters horizontally. The typing itself looks great — it's just the lateral movement that needs smoothing.

**READ FIRST:** `Peezy 4.0/Assessment/AssessmentComponents/TypingText.swift`

**ROOT CAUSE:** The `TypingText` component uses a `ZStack(alignment: .topLeading)` with a hidden full-text backing view to reserve space. However, as characters are added to the visible text, SwiftUI may be recalculating the text layout frame-by-frame, causing micro-shifts — especially with proportional fonts where character widths vary.

The hidden backing text prevents *vertical* jumps (height changes), but horizontal alignment can still shift because:
- The visible `Text(String(fullText.prefix(displayedCount)))` may have slightly different width than the hidden full text on each frame
- SwiftUI's text rendering may cause sub-pixel alignment differences between the hidden and visible text

**FIX:** `Peezy 4.0/Assessment/AssessmentComponents/TypingText.swift`

Apply these changes to eliminate horizontal jitter:

1. Force the visible text to occupy the same width as the hidden text by using a `.frame()` modifier that matches the hidden text's width:

```swift
var body: some View {
    ZStack(alignment: .topLeading) {
        // Hidden full text reserves layout space
        Text(fullText)
            .hidden()
            .accessibilityHidden(true)

        // Visible typed text — fixed to same frame to prevent horizontal jitter
        Text(String(fullText.prefix(displayedCount)))
            .frame(maxWidth: .infinity, alignment: .leading)  // Pin to leading edge
    }
    .accessibilityLabel(fullText)
    // ... rest unchanged
}
```

2. If that alone doesn't fix it, also add `.animation(nil, value: displayedCount)` to the visible Text to prevent SwiftUI from animating the text frame changes:

```swift
Text(String(fullText.prefix(displayedCount)))
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(nil, value: displayedCount)  // Prevent implicit animation on text changes
```

The key insight: the text content change should NOT trigger any layout animation. Only the parent container's reveal animations should be animated.

**DO NOT CHANGE:**
- The typing speed or batch size
- The `onComplete` callback logic
- The `onChange(of: fullText)` reset logic
- `AssessmentInputWrapper.swift`
- `ConversationalInterstitialView.swift`

**Verification:** `xcodebuild` build succeeds.

**Mark Phase 2 complete when verification passes.**

<!-- Phase 2: COMPLETE -->

---

## Phase 3: Fix Text Field Pages Cramped at Top (files: 1 modify)

**SYMPTOM:** On assessment pages that use text fields (name entry, address, etc.), after the typewriter header animates and the input controls appear, the title is pressed against the top of the screen and the text field is jammed right underneath it with no breathing room.

**READ FIRST:** `Peezy 4.0/Assessment/AssessmentComponents/AssessmentInputWrapper.swift`

**ROOT CAUSE:** `AssessmentInputWrapper` has a `VStack(alignment: .leading, spacing: 0)` with the header area getting `.padding(.top, 24)` and `.padding(.bottom, 24)`. When the header shrinks into its final position and the controls appear, there's minimal vertical spacing. The `content()` (which is the text field view) appears immediately below with whatever spacing it brings.

The issue is compounded because text field question views (like `FloatingTextInput`) have their own layout with `Spacer(minLength: 0)` that compresses when there's not enough room.

**FIX:** `Peezy 4.0/Assessment/AssessmentComponents/AssessmentInputWrapper.swift`

Increase the spacing between the header/subheader area and the controls area:

1. Change the `.padding(.bottom, 24)` on the context VStack to `.padding(.bottom, 40)` to give more breathing room below the header text before controls appear.

2. Add a `Spacer(minLength: 20)` between the context area and the `content()` to ensure there's always at least 20pt of space even when the content view doesn't provide its own:

```swift
VStack(alignment: .leading, spacing: 0) {
    // Context area — header typewriters in, subtext types after
    VStack(alignment: .leading, spacing: 8) {
        // ... header and subheader TypingText (unchanged)
    }
    .padding(.horizontal, 24)
    .padding(.top, 24)
    .padding(.bottom, 40)  // INCREASED from 24

    // Input controls
    if showControls {
        content()
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    Spacer(minLength: 0)
}
```

3. If the text field views themselves (FloatingTextInput) use `Spacer(minLength: 0)` between elements, those spacers compress to zero when the keyboard is absent. Check if adding `minLength: 16` or `minLength: 20` to the spacers within `FloatingTextInput.swift` would help. BUT — only modify `FloatingTextInput.swift` if the wrapper padding increase alone doesn't solve it. Prefer fixing in one place.

**DO NOT CHANGE:**
- The typewriter speed or reveal animation timing
- The `showControls` conditional logic
- Selection tile layouts (they're fine)
- `AssessmentFlowView.swift`

**Verification:** `xcodebuild` build succeeds.

**Mark Phase 3 complete when verification passes.**

<!-- Phase 3: COMPLETE -->

---

## Phase 4: Fix Financial Text Field Disappearing Under Keyboard (files: 1-2 modify)

**SYMPTOM:** On the financial details page, after selecting institutions and moving to the text entry screen, tapping the text field to type causes the keyboard to push the text field off screen. The user can't see what they're typing.

**READ FIRST:**
- `Peezy 4.0/Assessment/AssessmentComponents/AssessmentInputWrapper.swift`
- `Peezy 4.0/Assessment/AssessmentComponents/FloatingTextInput.swift`
- `Peezy 4.0/Assessment/AssessmentPages/FinancialDetails.swift` (if it exists — check the actual file name)

**ROOT CAUSE:** SwiftUI's automatic keyboard avoidance is either:
1. Not working because the view hierarchy prevents it (e.g., `GeometryReader` or explicit `Spacer` layout absorbing the keyboard avoidance)
2. Working but pushing the entire view up, causing the top content to go off screen while the text field stays hidden

**FIX:**

Wrap the content in a `ScrollView` so the keyboard can push the view up while the user can still scroll to see the text field:

In `AssessmentInputWrapper.swift`, wrap the entire `VStack` content in a `ScrollViewReader` + `ScrollView`:

```swift
var body: some View {
    let context = coordinator.inputContext(for: step)

    ZStack {
        InteractiveBackground()

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Context area (header + subheader) — unchanged
                    VStack(alignment: .leading, spacing: 8) {
                        // ... existing header/subheader code ...
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 40)

                    // Input controls
                    if showControls {
                        content()
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .id("inputControls")  // For scroll targeting
                    }

                    // Bottom padding to ensure content isn't hidden behind keyboard
                    Spacer(minLength: 200)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
```

**CRITICAL:** Adding `ScrollView` can change how selection tiles layout. Test that non-text-field assessment pages (like Yes/No selections, multi-select tiles) still look correct. The `Spacer(minLength: 200)` at the bottom ensures the text field can scroll above the keyboard.

If adding `ScrollView` to the wrapper breaks selection tile layouts, use a CONDITIONAL approach instead — only wrap in ScrollView when the step is a text field step:

```swift
// Check if this step uses a text field
let isTextField = step.usesTextField  // Add this computed property to AssessmentInputStep
```

But first try the universal ScrollView approach — it's simpler and usually works.

**DO NOT CHANGE:**
- The typewriter animation logic
- The `showControls` reveal timing
- Any selection tile views

**Verification:** `xcodebuild` build succeeds.

**Mark Phase 4 complete when verification passes.**

<!-- Phase 4: COMPLETE -->

---

## Phase 5: Fix White Bar at Bottom of Home Screen (files: 1 modify)

**SYMPTOM:** On the home screen (PeezyHomeView), there's a ~1-inch white bar at the very bottom of the screen, behind/below the floating tab bar area. The InteractiveBackground doesn't extend all the way to the bottom edge.

**READ FIRST:** `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift`

**ROOT CAUSE:** The `InteractiveBackground()` view likely doesn't have `.ignoresSafeArea()` applied, or it's placed inside a container that clips to the safe area. The bottom safe area (home indicator region) shows the default white/system background instead of the interactive background.

**FIX:** `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift`

Find where `InteractiveBackground()` is placed in the body. Ensure it has `.ignoresSafeArea()` or `.ignoresSafeArea(.all)` applied:

```swift
ZStack {
    InteractiveBackground()
        .ignoresSafeArea()  // Extend to ALL edges including bottom safe area

    // ... rest of content
}
```

If `InteractiveBackground()` already has `.ignoresSafeArea()`, the issue might be a second background layer. Look for any `.background(Color.white)` or `.background(.regularMaterial)` or similar modifier on a container view that's adding the white bar. Check the outermost `ZStack`, the `VStack`, and any padding/frame modifiers that might create a gap.

Also check `PeezyMainContainer.swift` — the tab bar container might have its own background that shows through at the bottom. Read it and look for background modifiers on the `Group` or outer `ZStack`.

**DO NOT CHANGE:**
- The card stack layout
- The floating tab bar itself (that's Phase 6)
- Any navigation logic
- `PeezyMainContainer.swift` (unless it's the source of the white bar — in which case, minimal fix only)

**Verification:** `xcodebuild` build succeeds.

**Mark Phase 5 complete when verification passes.**

<!-- Phase 5: COMPLETE -->

---

## Phase 6: Fix Floating Tab Bar Height (files: 1 modify)

**SYMPTOM:** The floating tab bar at the bottom of the home screen is taller than it needs to be. The icons are positioned too high, creating more empty space below the icons than above them. The tab bar needs to be shorter/more compact.

**READ FIRST:** Find the floating tab bar implementation. It might be in:
- `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift` (at the bottom of the body)
- `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift`
- A separate component file

Search for the tab bar by looking for: `HStack` with tab icons, references to `PeezyTheme.Layout.tabBarHeight`, or a view with a rounded material background at the bottom of the screen.

**FIX:**

1. **Reduce the overall height.** If there's an explicit `.frame(height:)` on the tab bar, reduce it. `PeezyTheme.Layout.tabBarHeight` is 70 — try 56 or 52. If the height isn't explicit, it's determined by internal padding — reduce vertical padding.

2. **Center the icons vertically.** If icons have more bottom padding than top padding, equalize them. Change asymmetric padding like `.padding(.top, 8).padding(.bottom, 16)` to symmetric like `.padding(.vertical, 10)`.

3. **Don't make it too small.** Apple HIG recommends minimum 44pt touch targets. The tab bar should be at least 50pt tall with icons centered.

**DO NOT CHANGE:**
- The tab bar's horizontal layout or icon selection
- The material/glass background style
- The navigation logic (selectedDestination switching)
- Any other views

**Verification:** `xcodebuild` build succeeds.

**Mark Phase 6 complete when verification passes.**

<!-- Phase 6: COMPLETE -->

---

## Files Summary

### Modified
| Phase | File | What Changed |
|-------|------|-------------|
| 1 | `AssessmentDataManager.swift` | Fix assessment data mapping for condition matching |
| 2 | `TypingText.swift` | Fix horizontal jitter during typewriter animation |
| 3 | `AssessmentInputWrapper.swift` | Increase spacing between header and controls |
| 4 | `AssessmentInputWrapper.swift` | Add ScrollView for keyboard avoidance |
| 5 | `PeezyHomeView.swift` | Fix InteractiveBackground not extending to bottom |
| 6 | Tab bar view (TBD) | Reduce height, center icons |

### NOT Modified (Confirm at end)
- `AssessmentCoordinator.swift` — UNTOUCHED (unless debug logging added)
- `TaskConditionerParser.swift` — UNTOUCHED
- `TaskGenerationService.swift` — UNTOUCHED
- `taskCatalogData.json` — UNTOUCHED
- `PeezyMainContainer.swift` — UNTOUCHED (unless it's the white bar source)
- `functions/` — ENTIRE DIRECTORY UNTOUCHED
- `Peezy 4.0/Inventory/` — ENTIRE DIRECTORY UNTOUCHED
