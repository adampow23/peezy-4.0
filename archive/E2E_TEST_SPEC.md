# E2E Test Suite — Spec

## Purpose

Build a comprehensive XCUITest suite that creates a real Firebase test user, logs in, and pushes every button in the app. No mocks. Real data. Real pipeline.

## Current State

- `Peezy 4.0UITests/` target exists in the project but contains no test files
- No accessibility identifiers on interactive elements (XCUITest can't find them reliably)
- No test user infrastructure
- Task catalog is seeded via `functions/seedTaskCatalog.js`

## Lessons Learned

- **LE-002:** `unset CLAUDECODE` required at top of build scripts for nested sessions
- **LE-018:** Bash 3.2 only — no `declare -A` or `${!var}`
- **LE-019:** Fresh Claude Code session per phase prevents context decay
- **LE-032:** Claude Code makes undirected changes to files it reads — diff after every phase

## Pre-Flight Check

```bash
# Verify correct directory
test -f "Peezy 4.0.xcodeproj/project.pbxproj" || exit 1

# Verify spec and CLAUDE.md
test -f "E2E_TEST_SPEC.md" || exit 1
test -f "CLAUDE.md" || exit 1

# Verify Firebase service account
test -f "functions/serviceAccountKey.json" || exit 1

# Seed task catalog
cd functions && node seedTaskCatalog.js && cd ..

# Verify build compiles
xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" \
  -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  build 2>&1 | grep "BUILD SUCCEEDED"
```

## Test User Credentials (used by ALL test files)

```
Email:    peezy-test-bot@test.peezyapp.com
Password: PeezyTest2026!
Name:     Peezy Tester
```

---

## Phase 1: Create Test Profile Scripts (files: 2 create)

**READ FIRST:**
- `functions/seedTaskCatalog.js` — understand the seed pattern and Firebase Admin init
- `functions/taskCatalogData.json` — understand condition keys used in the catalog
- `Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift` — the `getAllAssessmentData()` method, specifically the computed condition keys (`moveDistance`, `isInterstate`, `hireMovers`, `hireCleaners`, `hasVehicles`)

**What to build:**

Create `functions/testProfile/` directory with two files:

### `functions/testProfile/seedTestUser.js`

Creates a complete test user for E2E testing:

1. **Firebase Auth user** — email: `peezy-test-bot@test.peezyapp.com`, password: `PeezyTest2026!`, displayName: `Peezy Tester`, emailVerified: true. If user already exists, reuse their UID and clean old data.

2. **Assessment data** written to BOTH `users/{uid}/user_assessments/{auto-ID}` AND `userKnowledge/{uid}`. Use these exact values to maximize catalog condition matches:

```javascript
const ASSESSMENT_DATA = {
    userName: "Peezy Tester",
    moveDate: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 30*24*60*60*1000)),
    moveDateType: "Exact",
    moveConcerns: ["Forgetting something", "Cost"],
    currentRentOrOwn: "Rent",
    currentDwellingType: "Apartment",
    currentAddress: "100 E 14th St, Kansas City, MO 64106",
    currentUnitNumber: "4B",
    currentFloorAccess: "Elevator",
    currentBedrooms: "2",
    currentSquareFootage: "950",
    currentFinishedSqFt: "",
    newRentOrOwn: "Rent",
    newDwellingType: "House",
    newAddress: "3600 Broadway Blvd, Kansas City, MO 64111",
    newUnitNumber: "",
    newFloorAccess: "",
    newBedrooms: "3",
    newSquareFootage: "",
    newFinishedSqFt: "1400",
    anyKids: "Yes",
    childrenInSchool: "Yes",
    childrenInDaycare: "No",
    hasVet: "Yes",
    hasVehiclesDetail: "Yes",
    hasVehicles: "Yes",
    hasStorage: "No",
    storageSize: "",
    storageFullness: "",
    hireMovers: "Yes",
    hireMoversDetail: "Yes",
    hirePackers: "No",
    hireCleaners: "Yes",
    hireCleanersDetail: "Yes",
    wantsTruckRental: "No",
    hasDeclutter: "Yes",
    wantToSell: "No",
    financialInstitutions: ["Bank Account", "Credit Card"],
    healthcareProviders: ["Primary Care Doctor", "Dentist", "Health Insurance"],
    fitnessWellness: ["Gym"],
    financialDetails: { "Bank Account": "Chase", "Credit Card": "Amex" },
    healthcareDetails: { "Primary Care Doctor": "Dr. Smith", "Dentist": "Aspen Dental" },
    fitnessDetails: { "Gym": "Planet Fitness" },
    financialCounts: { "Bank Account": 1, "Credit Card": 1 },
    healthcareCounts: { "Primary Care Doctor": 1, "Dentist": 1, "Health Insurance": 1 },
    fitnessCounts: { "Gym": 1 },
    howHeard: "Friend",
    referralCode: "",
    promoCode: "",
    moveDistance: "Local",
    isInterstate: "No",
    autoRoomList: ["Living Room", "Kitchen", "Bedroom 1", "Bedroom 2", "Bathroom", "Garage"],
};
```

3. **Task generation** — read all docs from `taskCatalog` collection, evaluate conditions against the assessment data (AND across keys, OR within value arrays, case-insensitive key lookup), write matching tasks to `users/{uid}/tasks/{docId}`. Copy the exact condition evaluation logic from `seedTaskCatalog.js` patterns. Calculate due dates: `dueDate = today + totalDays * (1 - urgency/100)`.

4. **Test state modifications** — after generating tasks, modify 4 tasks for test coverage:
   - Task 0: set `status: "Completed"`, add `completedAt` timestamp (for Done tab)
   - Task 1: set `status: "In Progress"` (for In Progress tab)
   - Task 2: set `snoozedUntil` to yesterday, `lastSnoozedAt` to 3 days ago (returns in Later tab)
   - Task 3: set `status: "User In Progress"`, add `userInProgressDate` (for In Progress sub-section)

5. **Support chat messages** — write 2 messages to `users/{uid}/supportChat/`:
   - User message: "Hey, I have a question about my move date." (2 hours ago, read: true)
   - Support message: "Of course! What's going on with your move date?" (1.5 hours ago, read: false — triggers unread badge)

6. **User profile doc** — write to `users/{uid}` with name, email, assessmentCompleted: true, moveDate, addresses, distance fields.

7. **Print summary** — UID, email, password, task count, ready message.

Firebase init: use `require("../serviceAccountKey.json")` with `admin.credential.cert()`.

### `functions/testProfile/teardownTestUser.js`

Deletes everything:
1. Look up user by email
2. Delete subcollections: tasks, user_assessments, supportChat, miniAssessments, workflowResponses, inventory
3. Delete `users/{uid}` profile doc
4. Delete `userKnowledge/{uid}` doc
5. Delete Firebase Auth user
6. Print confirmation

**After creating both files, run:**
```bash
cd functions && node testProfile/seedTestUser.js && cd ..
```
Report the output: how many tasks generated, the test user UID.

**BLAST RADIUS:** NONE — these are new standalone Node.js scripts
**DO NOT CHANGE:** Any Swift files, any existing JS files, .pbxproj
**Verification:** Both scripts run without errors. seedTestUser.js reports task count > 0.

---

## Phase 2: Add Accessibility Identifiers (files: 9 modify)

**READ FIRST:**
- `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift` — find `PeezyFloatingTabBar` and each tab button
- `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift` — find welcome card, greeting cards, task card buttons, complete states
- `Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift` — find sub-tab buttons, task rows, empty states
- `Peezy 4.0/MainInterface/Views/SupportChatView.swift` — find header, empty state, input bar, send button
- `Peezy 4.0/Menu/PeezySettingsView.swift` — find every `settingsRow()` call and profile card
- `Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift` — find plan cards, buttons, links
- `Peezy 4.0/Auth/AuthView.swift` — find sign-in buttons (if this file exists; if auth is in a different file, read that)
- `Peezy 4.0/Auth/SignUpView.swift` — find form fields and buttons
- `Peezy 4.0/Auth/LogInView.swift` — find form fields, buttons, forgot password
- `Peezy 4.0/Assessment/AssessmentModels/AssessmentFlowView.swift` — find back button, progress bar, step counter

**What to build:**

Add `.accessibilityIdentifier("id")` to every interactive element listed below. This is the ONLY change — do NOT modify any layout, styling, colors, fonts, spacing, animations, or behavior.

For each file, read it, find the exact element, add the modifier ADJACENT to the element (on the same view chain), then move to the next.

### PeezyMainContainer.swift — `PeezyFloatingTabBar`

Find each tab `Button` inside the `ForEach(PeezyTab.allCases)` loop. Add to the button:
```swift
.accessibilityIdentifier("tab_\(tab.rawValue)")
```

Find the unread dot indicator (the small circle that appears for chat unread). Add:
```swift
.accessibilityIdentifier("chat_unread_badge")
```

### PeezyHomeView.swift

Find each of these views/buttons and add the identifier:

| Element | How to find it | Identifier |
|---------|---------------|------------|
| Welcome card | `firstTimeWelcomeCard` — the outer glassCard container | `"welcome_card"` |
| Welcome dot indicators | Each `Circle()` in the dot `ForEach` | `"welcome_dot_\(i)"` |
| "Start My First Task" button | `PeezyAssessmentButton("Start My First Task")` | `"welcome_start_button"` |
| "Swipe to continue" text | `Text("Swipe to continue")` | `"welcome_swipe_hint"` |
| Daily greeting card | `dailyGreetingCard` — the outer glassCard | `"daily_greeting_card"` |
| "Get started" button | `PeezyAssessmentButton("Get started")` | `"greeting_start_button"` |
| Returning card | `returningMidDayCard` — the outer glassCard | `"returning_card"` |
| "Pick up where I left off" button | `PeezyAssessmentButton("Pick up where I left off")` | `"returning_continue_button"` |
| All complete view | The VStack with "You're all set" text | `"all_complete_view"` |
| Daily complete view | The daily complete state container | `"daily_complete_view"` |
| "Get Ahead" button | The get ahead button (if it exists in the daily complete state) | `"get_ahead_button"` |

For the **task card** (InteractiveHomeTaskCard or equivalent), find the action buttons:
| Button | Identifier |
|--------|------------|
| Complete / "On It" button | `"task_complete_button"` |
| Snooze / "Later" button | `"task_snooze_button"` |
| "Already done" button | `"task_already_done_button"` |
| Task card container | `"task_card"` |

### PeezyTimelineView.swift

Find the `ForEach(TaskTab.allCases)` loop with the sub-tab buttons. Add to each button:
```swift
.accessibilityIdentifier("timeline_tab_\(tab.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))")
```

The actual identifiers should be: `"timeline_tab_to-do"`, `"timeline_tab_in_progress"`, `"timeline_tab_later"`, `"timeline_tab_done"` — match the raw values of the `TaskTab` enum exactly (read the enum to confirm).

For empty state text views, add `"timeline_empty_state"`.

### SupportChatView.swift

| Element | Identifier |
|---------|------------|
| "Support" header Text | `"support_header"` |
| Empty state VStack | `"chat_empty_state"` |
| Input TextField | `"chat_input_field"` |
| Send button (arrow.up.circle.fill) | `"chat_send_button"` |

### PeezySettingsView.swift

Add to each `settingsRow()` call or button. Find them by their `label:` parameter:

| Row label | Identifier |
|-----------|------------|
| Profile card (the tappable Button at top) | `"settings_profile_card"` |
| Move date row | `"settings_move_date"` |
| Current address row | `"settings_current_address"` |
| New address row | `"settings_new_address"` |
| Subscription status row | `"settings_subscription_status"` |
| "Manage Subscription" | `"settings_manage_subscription"` |
| "Restore Purchases" | `"settings_restore_purchases"` |
| Inventory scanner row | `"settings_inventory_scanner"` |
| "Retake Assessment" | `"settings_retake_assessment"` |
| "Privacy Policy" | `"settings_privacy_policy"` |
| "Terms of Service" | `"settings_terms_of_service"` |
| "Sign Out" | `"settings_sign_out"` |
| "Delete Account" | `"settings_delete_account"` |
| Version footer VStack | `"settings_version"` |

### PaywallGateView.swift

| Element | Identifier |
|---------|------------|
| Annual plan card (the `planCard(for: .annual)` button) | `"paywall_plan_annual"` |
| Weekly plan card | `"paywall_plan_weekly"` |
| "Let's do this" button (`PeezyAssessmentButton`) | `"paywall_purchase_button"` |
| "Not now" button | `"paywall_dismiss_button"` |
| "Redeem a code" button | `"paywall_redeem_code"` |
| "Restore Purchases" button | `"paywall_restore_purchases"` |
| Subscription terms text | `"paywall_subscription_terms"` |
| Privacy Policy link | `"paywall_privacy_link"` |
| Terms of Service link | `"paywall_terms_link"` |

### Auth Views (AuthView.swift, SignUpView.swift, LogInView.swift)

Read each file first to find the exact elements. Add:

**AuthView.swift** (or wherever the initial auth screen lives):
- Apple Sign In: `"auth_apple_signin"`
- Google Sign In: `"auth_google_signin"`
- Email sign up button: `"auth_email_signup"`
- Login link: `"auth_login_link"`

**SignUpView.swift:**
- Name field: `"signup_name_field"`
- Email field: `"signup_email_field"`
- Password field: `"signup_password_field"`
- Confirm password field: `"signup_confirm_password_field"`
- Sign Up button: `"signup_submit_button"`
- "Already have account" link: `"signup_login_link"`

**LogInView.swift:**
- Email field: `"login_email_field"`
- Password field: `"login_password_field"`
- Log In button: `"login_submit_button"`
- Forgot Password: `"login_forgot_password"`
- "Don't have account" link: `"login_signup_link"`
- Close (X) button: `"login_close_button"`

### AssessmentFlowView.swift

- Back chevron button: `"assessment_back_button"`
- Step counter text: `"assessment_step_counter"`
- Progress bar: `"assessment_progress_bar"`

### TaskFlow Templates (TaskFlowStack.swift, TaskFlowSummaryCard.swift, TaskFlowTilesCard.swift, TaskFlowInfoCard.swift)

Read each file and add:

- `TaskFlowStack` dismiss/X button: `"taskflow_dismiss_button"`
- `TaskFlowSummaryCard` primary button: `"taskflow_summary_primary"`
- `TaskFlowSummaryCard` back button: `"taskflow_summary_back"`
- `TaskFlowTilesCard` continue button: `"taskflow_tiles_continue"`
- `TaskFlowTilesCard` back button: `"taskflow_tiles_back"`
- `TaskFlowInfoCard` primary button: `"taskflow_info_primary"`
- `TaskFlowInfoCard` back button: `"taskflow_info_back"`

For tile options, add to each tile button in the ForEach:
```swift
.accessibilityIdentifier("taskflow_tile_\(option.id)")
```

**BLAST RADIUS:** These views are used throughout the app — adding identifiers has ZERO functional impact but verify with xcodebuild.
**DO NOT CHANGE:** Any view's layout, colors, fonts, spacing, animations, padding, frame sizes, or behavior. ONLY add `.accessibilityIdentifier()`. Do NOT restructure any view hierarchy. Do NOT rename variables. Do NOT "improve" anything.
**Verification:** `xcodebuild build` succeeds. Run `git diff` on each modified file — verify ONLY `.accessibilityIdentifier()` lines were added. If any other changes appear, revert them.

---

## Phase 3: Test Infrastructure + Tab Bar Tests (files: 2 create)

**READ FIRST:**
- `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift` — the `PeezyTab` enum and `PeezyFloatingTabBar`
- Phase 2's accessibility identifiers (they should now be in place)

**Create:** `Peezy 4.0UITests/E2ETestBase.swift`

```swift
import XCTest

class E2ETestBase: XCTestCase {
    var app: XCUIApplication!
    let testEmail = "peezy-test-bot@test.peezyapp.com"
    let testPassword = "PeezyTest2026!"
    let testName = "Peezy Tester"
    var needsLogin: Bool { true }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        if needsLogin { loginIfNeeded() }
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func loginIfNeeded() {
        let homeTab = app.buttons["tab_home"]
        if homeTab.waitForExistence(timeout: 3) { return }

        let loginLink = app.buttons["auth_login_link"]
        if !loginLink.waitForExistence(timeout: 5) {
            // Might be loading — wait longer for tab bar
            XCTAssertTrue(homeTab.waitForExistence(timeout: 15),
                "Should see auth screen or main app within 15s")
            return
        }

        // Navigate to login
        loginLink.tap()

        let emailField = app.textFields["login_email_field"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 3))
        emailField.tap()
        emailField.typeText(testEmail)

        let passwordField = app.secureTextFields["login_password_field"]
        passwordField.tap()
        passwordField.typeText(testPassword)

        app.buttons["login_submit_button"].tap()

        XCTAssertTrue(homeTab.waitForExistence(timeout: 15),
            "Main app should load after login")
    }

    func waitFor(_ id: String, timeout: TimeInterval = 5) -> XCUIElement {
        let el = app.descendants(matching: .any)[id]
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "'\(id)' should exist")
        return el
    }

    func exists(_ id: String, timeout: TimeInterval = 3) -> Bool {
        app.descendants(matching: .any)[id].waitForExistence(timeout: timeout)
    }

    func tapTab(_ id: String) {
        waitFor(id).tap()
    }

    func screenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func dismissWelcomeIfPresent() {
        let card = app.otherElements["welcome_card"]
        guard card.waitForExistence(timeout: 3) else { return }
        card.swipeLeft(); sleep(1)
        card.swipeLeft(); sleep(1)
        let btn = app.buttons["welcome_start_button"]
        if btn.waitForExistence(timeout: 2) { btn.tap() }
        sleep(1)
    }

    func dismissGreetingIfPresent() {
        let g = app.buttons["greeting_start_button"]
        if g.waitForExistence(timeout: 2) { g.tap(); return }
        let r = app.buttons["returning_continue_button"]
        if r.waitForExistence(timeout: 2) { r.tap() }
    }

    func getToTaskCards() {
        dismissWelcomeIfPresent()
        dismissGreetingIfPresent()
    }
}
```

**Create:** `Peezy 4.0UITests/T09_TabBarTests.swift`

```swift
import XCTest

final class TabBarTests: E2ETestBase {

    func test01_AllFourTabsExist() {
        XCTAssertTrue(exists("tab_home"))
        XCTAssertTrue(exists("tab_tasks"))
        XCTAssertTrue(exists("tab_chat"))
        XCTAssertTrue(exists("tab_settings"))
        screenshot("09_tab_bar")
    }

    func test02_HomeSelectedByDefault() {
        // Home content should be visible on launch
        let homeContent = app.buttons["greeting_start_button"].exists
            || app.otherElements["welcome_card"].exists
            || app.buttons["task_complete_button"].exists
            || app.otherElements["all_complete_view"].exists
        XCTAssertTrue(homeContent, "Home tab content should be visible")
    }

    func test03_TasksTabSwitchesContent() {
        tapTab("tab_tasks")
        XCTAssertTrue(exists("timeline_tab_to-do") || exists("timeline_tab_To-Do"),
            "Timeline sub-tabs should appear")
        screenshot("09_tasks_tab")
    }

    func test04_ChatTabSwitchesContent() {
        tapTab("tab_chat")
        XCTAssertTrue(exists("support_header"))
        screenshot("09_chat_tab")
    }

    func test05_SettingsTabSwitchesContent() {
        tapTab("tab_settings")
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
        screenshot("09_settings_tab")
    }

    func test06_HomeTabReturns() {
        tapTab("tab_tasks")
        tapTab("tab_home")
        let homeContent = exists("greeting_start_button")
            || exists("welcome_card")
            || exists("task_complete_button")
            || exists("all_complete_view")
            || exists("returning_continue_button")
        XCTAssertTrue(homeContent)
    }

    func test07_RapidSwitchingNoBlankScreens() {
        for tab in ["tab_tasks", "tab_chat", "tab_settings", "tab_home",
                     "tab_chat", "tab_tasks", "tab_home", "tab_settings"] {
            tapTab(tab)
            usleep(300_000) // 0.3s between taps
        }
        // If we get here without a crash, pass
        screenshot("09_rapid_switch_final")
    }
}
```

**BLAST RADIUS:** NONE — new test files only
**DO NOT CHANGE:** Any production Swift files, any JS files, .pbxproj
**Verification:** `xcodebuild -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build` succeeds (test files compile).

---

## Phase 4: Welcome, Greeting, and Task Card Tests (files: 2 create)

**READ FIRST:**
- `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift` — understand the state machine: firstTimeWelcome → dailyGreeting → returningMidDay → activeTask → dailyComplete → allComplete
- `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift` — understand `startNextTask()`, `completeTaskFlow()`, `dismissTaskFlow()`, snooze logic

**Create:** `Peezy 4.0UITests/T02_WelcomeAndGreetingTests.swift`

Test the first-time welcome card (3 pages with swipe) and greeting cards. 7 tests:
1. Welcome card or greeting appears on Home tab after login
2. Welcome card 3-page swipe navigation (if welcome card present)
3. Swipe right goes back through welcome pages
4. Can't swipe past page boundaries
5. "Start My First Task" on page 3 dismisses welcome
6. Greeting card renders with time-based text and user name
7. Greeting button advances to first task

**Create:** `Peezy 4.0UITests/T03_TaskCardTests.swift`

Test task card interactions. 7 tests:
1. Task card renders with title, subtitle, all 3 buttons (On It, Later, Already done)
2. "On It" opens task flow (fullScreenCover presents)
3. "Later" snoozes card and advances to next
4. "Already done" completes and advances
5. Cards advance sequentially — no repeats (track titles)
6. Completing all daily tasks shows daily complete or all complete state
7. "Get Ahead" button loads more tasks (if daily complete with remaining tasks)

Each test must use `getToTaskCards()` helper to bypass welcome/greeting first. Use `screenshot()` at key moments.

**BLAST RADIUS:** NONE — new test files only
**DO NOT CHANGE:** Any production files, .pbxproj
**Verification:** `xcodebuild build` succeeds

---

## Phase 5: Task Flow Tests (files: 1 create)

**READ FIRST:**
- `Peezy 4.0/Tasks/TaskFlows/Templates/TaskFlowStack.swift` — the container with dismiss button and progress
- `Peezy 4.0/Tasks/TaskFlows/Templates/TaskFlowTilesCard.swift` — single-select auto-advance, multi-select with continue
- `Peezy 4.0/Tasks/TaskFlows/Templates/TaskFlowSummaryCard.swift` — primary/back buttons
- `Peezy 4.0/Tasks/TaskFlows/Templates/TaskFlowInfoCard.swift` — info display with primary/back
- `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift` — `newFlowId(for:)` to understand how tasks route to flows

**Create:** `Peezy 4.0UITests/T04_TaskFlowTests.swift`

11 tests covering flow navigation, tile interactions, and completion:
1. Task flow presents as fullScreenCover with dismiss button
2. Navigate forward through cards (tap primary button)
3. Back navigation returns to previous card
4. Back navigation preserves tile selections
5. Single-select tile auto-advances after 0.3s
6. Multi-select: tapping tiles doesn't auto-advance, continue button appears
7. Deselect toggle — tap selected tile deselects it
8. Summary card renders with primary action button
9. Summary primary button completes flow and dismisses
10. Dismiss (X) cancels flow, returns to Home, task card returns to stack
11. Progress indicator updates as you advance

Important: the test user is NOT subscribed, so tapping "On It" may show the paywall first. Handle this: if paywall appears, tap "Not now" to dismiss it before testing the flow. Add a helper method:
```swift
func dismissPaywallIfPresent() {
    let dismiss = app.buttons["paywall_dismiss_button"]
    if dismiss.waitForExistence(timeout: 2) { dismiss.tap() }
}
```

**BLAST RADIUS:** NONE — new test file only
**DO NOT CHANGE:** Any production files, .pbxproj
**Verification:** `xcodebuild build` succeeds

---

## Phase 6: Timeline + Support Chat Tests (files: 2 create)

**READ FIRST:**
- `Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift` — the `TaskTab` enum (read exact rawValues for identifier matching), tab content, task rows, empty states
- `Peezy 4.0/MainInterface/Views/SupportChatView.swift` — header, empty state, input bar, send logic

**Create:** `Peezy 4.0UITests/T05_TimelineTests.swift`

12 tests:
1. Timeline tab renders with header
2. Four sub-tabs exist (match exact identifiers from TaskTab enum)
3. To-Do tab shows upcoming tasks
4. In Progress tab shows at least 1 task (seeded in Phase 1)
5. Later tab shows snoozed task (seeded in Phase 1)
6. Done tab shows completed task (seeded in Phase 1)
7. Tab count badges match content
8. Tap task row expands it (expanded content visible)
9. Tap again collapses
10. Start button navigates to Home tab
11. Empty states render per tab (for tabs with no items)
12. Home icon button in header navigates to Home tab

**Create:** `Peezy 4.0UITests/T06_SupportChatTests.swift`

7 tests:
1. Chat tab renders with "Support" header and subtitle
2. Existing seeded messages appear (user on right, support on left)
3. Input bar renders with text field and send button
4. Typing enables send button (disabled when empty)
5. Send clears input and adds new bubble
6. Empty input cannot be sent (send stays disabled)
7. Unread badge on tab bar before visiting chat, gone after visiting

**BLAST RADIUS:** NONE — new test files only
**DO NOT CHANGE:** Any production files, .pbxproj
**Verification:** `xcodebuild build` succeeds

---

## Phase 7: Settings + Paywall Tests (files: 2 create)

**READ FIRST:**
- `Peezy 4.0/Menu/PeezySettingsView.swift` — every settingsRow, alert, sheet, and navigation
- `Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift` — plan cards, buttons, links, terms

**Create:** `Peezy 4.0UITests/T07_SettingsTests.swift`

15 tests covering every button and row:
1. Settings tab renders with header
2. Profile card shows "Peezy Tester" name
3. Profile card tappable → edit profile appears
4. Move date row tappable → editor appears → dismiss
5. Current address row tappable → editor appears
6. New address row tappable → editor appears
7. Subscription section renders (status, manage, restore)
8. Restore Purchases → shows result alert → tap OK
9. Inventory scanner row → opens fullScreenCover
10. Retake Assessment → confirmation alert ("Retake Assessment?") → Cancel dismisses
11. Privacy Policy link exists
12. Terms of Service link exists
13. Sign Out → confirmation alert ("Sign Out?") → Cancel dismisses
14. Delete Account → confirmation alert ("Delete Account?") with "Delete Everything" → Cancel dismisses
15. Version footer visible at bottom

**IMPORTANT:** Do NOT actually tap "Sign Out" confirm or "Delete Everything" confirm — only test that the alerts appear and Cancel works. Actually signing out or deleting would break subsequent tests.

**Create:** `Peezy 4.0UITests/T08_PaywallTests.swift`

10 tests:
1. Paywall appears when tapping "On It" on a task (test user is not subscribed)
2. Plan cards render (annual and weekly)
3. Annual selected by default
4. Tapping weekly switches selection
5. Purchase button exists and is enabled
6. "Not now" dismisses paywall
7. "Redeem a code" button exists
8. "Restore Purchases" button exists
9. Subscription terms text visible (Apple-required disclosure)
10. Privacy and Terms links exist

For test 1, get to task cards first (`getToTaskCards()`), then tap "On It" (`task_complete_button`).

**BLAST RADIUS:** NONE — new test files only
**DO NOT CHANGE:** Any production files, .pbxproj
**Verification:** `xcodebuild build` succeeds

---

## Phase 8: Auth + Full Journey Tests (files: 2 create)

**READ FIRST:**
- `Peezy 4.0/Auth/AuthView.swift` (or wherever the initial auth screen is)
- `Peezy 4.0/Auth/SignUpView.swift`
- `Peezy 4.0/Auth/LogInView.swift`

**Create:** `Peezy 4.0UITests/T01_AuthFlowTests.swift`

This test class does NOT auto-login. Override `needsLogin`:
```swift
final class AuthFlowTests: E2ETestBase {
    override var needsLogin: Bool { false }
    // ...
}
```

**IMPORTANT:** The test user is already logged in from prior tests (session persists on simulator). These tests must first SIGN OUT if the app goes straight to the main app. Add a `signOutFirst()` helper:
```swift
func signOutFirst() {
    let homeTab = app.buttons["tab_home"]
    guard homeTab.waitForExistence(timeout: 3) else { return }
    // Already in main app — go to settings and sign out
    app.buttons["tab_settings"].tap()
    sleep(1)
    // Find and tap sign out, then confirm
    let signOut = app.buttons["settings_sign_out"]
    if signOut.waitForExistence(timeout: 3) {
        signOut.tap()
        sleep(1)
        // Tap "Sign Out" in the confirmation alert
        let confirm = app.buttons["Sign Out"]
        if confirm.waitForExistence(timeout: 2) { confirm.tap() }
        sleep(2)
    }
}
```

Call `signOutFirst()` in `setUp()` before running auth tests.

9 tests:
1. Auth screen shows all sign-in options (Apple, Google, email, login link)
2. Navigate to Sign Up screen — all fields exist, button disabled when empty
3. Password mismatch shows error
4. Valid form enables Sign Up button
5. Navigate to Log In screen — all fields and buttons exist
6. Close (X) on login dismisses back to auth
7. Round-trip navigation Sign Up ↔ Log In
8. Forgot Password shows alert with Cancel
9. Successful login with test credentials (login → main app loads)

**Create:** `Peezy 4.0UITests/T10_FullJourneyTest.swift`

1 comprehensive test simulating a complete user session:
```swift
final class FullJourneyTest: E2ETestBase {
    func test01_CompleteUserSession() {
        // 1. Home tab loaded (login handled by base class)
        screenshot("journey_01_home")

        // 2. Dismiss welcome/greeting
        getToTaskCards()
        screenshot("journey_02_task_cards")

        // 3. Interact with a task ("On It" → paywall → "Not now")
        if exists("task_complete_button") {
            waitFor("task_complete_button").tap()
            if exists("paywall_dismiss_button", timeout: 2) {
                waitFor("paywall_dismiss_button").tap()
            }
        }
        screenshot("journey_03_after_task")

        // 4. Switch to Tasks tab
        tapTab("tab_tasks")
        screenshot("journey_04_tasks_tab")

        // 5. Switch to Chat tab, send a message
        tapTab("tab_chat")
        let input = app.textFields["chat_input_field"]
        if input.waitForExistence(timeout: 3) {
            input.tap()
            input.typeText("E2E test message")
            let send = app.buttons["chat_send_button"]
            if send.isEnabled { send.tap() }
        }
        screenshot("journey_05_chat")

        // 6. Switch to Settings, scroll through
        tapTab("tab_settings")
        app.swipeUp()
        screenshot("journey_06_settings")

        // 7. Back to Home
        tapTab("tab_home")
        screenshot("journey_07_home_return")

        // If we reach here: no crashes, no dead ends, no blank screens
    }
}
```

**BLAST RADIUS:** NONE — new test files only
**DO NOT CHANGE:** Any production files, .pbxproj
**Verification:** `xcodebuild build` succeeds

---

## Phase 9: Run Full Test Suite (files: 0)

**This is a bash-only verification phase.** No file creation.

Run:
```bash
xcodebuild test \
    -project "Peezy 4.0.xcodeproj" \
    -scheme "Peezy 4.0" \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
    2>&1 | grep -E "(Test Case|Tests|Passed|Failed|error:)"
```

Report:
- Total tests run
- Total passed
- Total failed
- Name of each failing test
- For each failure: what assertion failed and why

If tests fail due to timing issues (element not found within timeout), increase the timeout in that specific test — do NOT change production code.

If tests fail due to incorrect accessibility identifiers (element exists but with different ID), read the production file to find the correct identifier and fix the test.

**DO NOT CHANGE:** Any production files. Fix the TESTS, not the app (unless the app has a genuine bug).

---

## Files Summary

### Created (Phase 1):
- `functions/testProfile/seedTestUser.js`
- `functions/testProfile/teardownTestUser.js`

### Modified (Phase 2 — accessibility identifiers ONLY):
- `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift`
- `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift`
- `Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift`
- `Peezy 4.0/MainInterface/Views/SupportChatView.swift`
- `Peezy 4.0/Menu/PeezySettingsView.swift`
- `Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift`
- `Peezy 4.0/Auth/SignUpView.swift`
- `Peezy 4.0/Auth/LogInView.swift`
- `Peezy 4.0/Assessment/AssessmentModels/AssessmentFlowView.swift`
- TaskFlow template files (TaskFlowStack, TaskFlowSummaryCard, TaskFlowTilesCard, TaskFlowInfoCard)
- Auth view (AuthView.swift or equivalent — read to confirm filename)

### Created (Phases 3-8 — test files):
- `Peezy 4.0UITests/E2ETestBase.swift`
- `Peezy 4.0UITests/T01_AuthFlowTests.swift`
- `Peezy 4.0UITests/T02_WelcomeAndGreetingTests.swift`
- `Peezy 4.0UITests/T03_TaskCardTests.swift`
- `Peezy 4.0UITests/T04_TaskFlowTests.swift`
- `Peezy 4.0UITests/T05_TimelineTests.swift`
- `Peezy 4.0UITests/T06_SupportChatTests.swift`
- `Peezy 4.0UITests/T07_SettingsTests.swift`
- `Peezy 4.0UITests/T08_PaywallTests.swift`
- `Peezy 4.0UITests/T09_TabBarTests.swift`
- `Peezy 4.0UITests/T10_FullJourneyTest.swift`

### NOT Modified:
- `.pbxproj` — NEVER
- `PeezyHomeViewModel.swift` — no changes
- `PeezyCard.swift` — no changes
- `AssessmentCoordinator.swift` — no changes
- `AssessmentDataManager.swift` — no changes
- Any TaskFlow `.swift` files (except templates for accessibility IDs)
- `SubscriptionManager.swift` — no changes
- `SupportChatService.swift` — no changes
- `AuthViewModel.swift` — no changes
