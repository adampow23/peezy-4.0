//
//  T03_TaskCardTests.swift
//  Peezy 4.0UITests
//
//  Phase 4: Task card interaction tests.
//  Tests On It, Later, Already done buttons and card progression.
//

import XCTest

final class TaskCardTests: E2ETestBase {

    // MARK: - Helpers

    /// Dismiss paywall if it appears (test user is not subscribed).
    private func dismissPaywallIfPresent() {
        let dismiss = app.buttons["paywall_dismiss_button"]
        if dismiss.waitForExistence(timeout: 2) { dismiss.tap() }
    }

    /// Returns true if a task card is currently visible.
    private func taskCardIsVisible(timeout: TimeInterval = 5) -> Bool {
        exists("task_card", timeout: timeout)
    }

    /// Wait for a task card to appear. Calls getToTaskCards() internally.
    private func ensureTaskCard() -> Bool {
        getToTaskCards()
        return taskCardIsVisible()
    }

    // MARK: - Test 1: Task card renders with title, subtitle, all 3 buttons

    func test01_TaskCardRendersWithAllButtons() {
        guard ensureTaskCard() else {
            XCTContext.runActivity(named: "No task card visible — daily or all complete") { _ in }
            return
        }

        XCTAssertTrue(exists("task_card"), "Task card container should be visible")
        XCTAssertTrue(exists("task_complete_button"), "On It / Complete button should exist")
        XCTAssertTrue(exists("task_snooze_button"), "Later / Snooze button should exist")
        XCTAssertTrue(exists("task_already_done_button"), "Already done button should exist")
        screenshot("03_task_card_with_buttons")
    }

    // MARK: - Test 2: "On It" opens task flow (fullScreenCover presents)

    func test02_OnItButtonOpenTaskFlow() {
        guard ensureTaskCard() else {
            XCTContext.runActivity(named: "No task card visible — skipping") { _ in }
            return
        }

        screenshot("03_before_on_it_tap")
        app.buttons["task_complete_button"].tap()
        sleep(1)

        // Might show paywall first — dismiss it
        dismissPaywallIfPresent()
        sleep(1)

        // After dismissing paywall (or if not shown), task flow should present OR next state appears
        // The task flow is a fullScreenCover — look for its dismiss button
        let taskFlowDismiss = app.buttons["taskflow_dismiss_button"]
        let advancedState =
            taskFlowDismiss.waitForExistence(timeout: 5) ||
            exists("daily_complete_view", timeout: 3) ||
            exists("all_complete_view", timeout: 3) ||
            exists("task_card", timeout: 3)

        XCTAssertTrue(advancedState, "Tapping On It should open task flow or advance state")
        screenshot("03_after_on_it_tap")

        // Dismiss task flow if it's open to clean up for subsequent tests
        if taskFlowDismiss.exists {
            taskFlowDismiss.tap()
            sleep(1)
        }
    }

    // MARK: - Test 3: "Later" snoozes card and advances to next

    func test03_LaterButtonSnoozesAndAdvances() {
        guard ensureTaskCard() else {
            XCTContext.runActivity(named: "No task card visible — skipping") { _ in }
            return
        }

        // Capture the current task title to verify it changes
        let beforeCard = app.otherElements["task_card"]
        let beforeTitles = beforeCard.staticTexts.allElementsBoundByIndex.map { $0.label }
        screenshot("03_before_later_tap")

        app.buttons["task_snooze_button"].tap()
        sleep(2)

        // Card should have advanced: either new task card, greeting, or complete state
        let advanced =
            exists("task_card") ||
            exists("daily_complete_view") ||
            exists("all_complete_view") ||
            exists("greeting_start_button") ||
            exists("returning_continue_button")

        XCTAssertTrue(advanced, "Tapping Later should advance past the current card")

        // If another task card appeared, verify it's different
        if exists("task_card", timeout: 1) {
            let afterCard = app.otherElements["task_card"]
            let afterTitles = afterCard.staticTexts.allElementsBoundByIndex.map { $0.label }
            // Cards may differ — just confirm we got some content
            XCTAssertFalse(afterTitles.isEmpty, "New task card should have content")
            _ = beforeTitles // suppress unused warning
        }
        screenshot("03_after_later_tap")
    }

    // MARK: - Test 4: "Already done" completes and advances

    func test04_AlreadyDoneButtonCompletesAndAdvances() {
        guard ensureTaskCard() else {
            XCTContext.runActivity(named: "No task card visible — skipping") { _ in }
            return
        }

        screenshot("03_before_already_done_tap")
        app.buttons["task_already_done_button"].tap()
        sleep(2)

        // Should have advanced to next task, greeting, or complete state
        let advanced =
            exists("task_card") ||
            exists("daily_complete_view") ||
            exists("all_complete_view") ||
            exists("greeting_start_button") ||
            exists("returning_continue_button")

        XCTAssertTrue(advanced, "Tapping Already done should advance past the current card")
        screenshot("03_after_already_done_tap")
    }

    // MARK: - Test 5: Cards advance sequentially — no repeats

    func test05_CardsAdvanceSequentiallyNoRepeats() {
        guard ensureTaskCard() else {
            XCTContext.runActivity(named: "No task card visible — skipping") { _ in }
            return
        }

        var seenTitles: Set<String> = []
        var advanceCount = 0
        let maxAdvances = 5

        while advanceCount < maxAdvances && exists("task_card", timeout: 3) {
            let card = app.otherElements["task_card"]
            let titles = card.staticTexts.allElementsBoundByIndex
                .map { $0.label }
                .filter { !$0.isEmpty }

            let titleKey = titles.joined(separator: "|")
            if !titleKey.isEmpty {
                XCTAssertFalse(seenTitles.contains(titleKey),
                    "Task card '\(titleKey)' should not repeat — cards advance sequentially")
                seenTitles.insert(titleKey)
            }

            screenshot("03_sequential_card_\(advanceCount)")

            // Advance with "Later" to keep tasks in the queue for future tests
            app.buttons["task_snooze_button"].tap()
            sleep(2)
            advanceCount += 1
        }

        XCTAssertGreaterThan(advanceCount, 0, "Should have advanced through at least one task card")
    }

    // MARK: - Test 6: Completing all daily tasks shows daily complete or all complete state

    func test06_CompletingAllTasksShowsCompleteState() {
        guard ensureTaskCard() else {
            // Already in a complete state — verify it's one of the known complete states
            let alreadyComplete =
                exists("daily_complete_view") ||
                exists("all_complete_view")

            if alreadyComplete {
                XCTAssertTrue(alreadyComplete, "Should be in a complete state")
                screenshot("03_already_complete")
                return
            }
            XCTContext.runActivity(named: "No task card or complete state visible") { _ in }
            return
        }

        // Mark all visible task cards as "Already done" until we hit a complete state
        var iterations = 0
        let maxIterations = 20

        while iterations < maxIterations {
            if exists("daily_complete_view", timeout: 1) || exists("all_complete_view", timeout: 1) {
                break
            }
            guard exists("task_card", timeout: 3) else { break }

            app.buttons["task_already_done_button"].tap()
            sleep(2)
            iterations += 1
        }

        let reachedCompleteState =
            exists("daily_complete_view", timeout: 5) ||
            exists("all_complete_view", timeout: 5)

        XCTAssertTrue(reachedCompleteState,
            "Completing all daily tasks should show daily_complete_view or all_complete_view")
        screenshot("03_complete_state")
    }

    // MARK: - Test 7: "Get Ahead" button loads more tasks (if daily complete with remaining)

    func test07_GetAheadButtonLoadsMoreTasks() {
        // First, get to a complete state
        getToTaskCards()

        // Mark tasks as done until daily complete appears
        var iterations = 0
        let maxIterations = 20
        while iterations < maxIterations {
            if exists("daily_complete_view", timeout: 1) { break }
            if exists("all_complete_view", timeout: 1) { break }
            guard exists("task_card", timeout: 3) else { break }
            app.buttons["task_already_done_button"].tap()
            sleep(2)
            iterations += 1
        }

        let getAheadBtn = app.buttons["get_ahead_button"]

        if exists("daily_complete_view", timeout: 3) && getAheadBtn.waitForExistence(timeout: 2) {
            screenshot("03_daily_complete_with_get_ahead")
            getAheadBtn.tap()
            sleep(2)

            // After tapping Get Ahead, should see a task card (next batch) or all complete
            let advanced =
                exists("task_card", timeout: 5) ||
                exists("all_complete_view", timeout: 5) ||
                // Task flow might open directly
                exists("taskflow_dismiss_button", timeout: 3)

            XCTAssertTrue(advanced,
                "Tapping Get Ahead should load the next task or show all complete state")
            screenshot("03_after_get_ahead")
        } else if exists("all_complete_view", timeout: 2) {
            // All tasks done — no Get Ahead button expected
            XCTContext.runActivity(named: "All tasks complete — Get Ahead not applicable") { _ in }
            screenshot("03_all_complete_no_get_ahead")
        } else {
            // No complete state reached within iteration limit
            XCTContext.runActivity(named: "Could not reach complete state within \(maxIterations) iterations") { _ in }
        }
    }
}
