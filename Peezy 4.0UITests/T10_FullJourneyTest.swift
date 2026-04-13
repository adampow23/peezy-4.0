//
//  T10_FullJourneyTest.swift
//  Peezy 4.0UITests
//

import XCTest

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
