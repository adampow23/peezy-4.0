//
//  T02_WelcomeAndGreetingTests.swift
//  Peezy 4.0UITests
//
//  Phase 4: Welcome card (3-page swipe) and greeting card tests.
//  State machine: firstTimeWelcome → dailyGreeting → returningMidDay
//

import XCTest

final class WelcomeAndGreetingTests: E2ETestBase {

    // MARK: - Test 1: Welcome card or greeting appears after login

    func test01_WelcomeOrGreetingAppearsAfterLogin() {
        // After login, the home tab must show one of the known entry states
        let welcomed = exists("welcome_card")
        let greeted = exists("greeting_start_button")
        let returning = exists("returning_continue_button")
        let taskCard = exists("task_card")
        let allDone = exists("all_complete_view")
        let dailyDone = exists("daily_complete_view")

        XCTAssertTrue(
            welcomed || greeted || returning || taskCard || allDone || dailyDone,
            "Home tab should show welcome card, greeting, returning card, task card, or complete state"
        )
        screenshot("02_home_initial_state")
    }

    // MARK: - Test 2: Welcome card 3-page swipe navigation

    func test02_WelcomeCardThreePageSwipe() {
        guard exists("welcome_card", timeout: 3) else {
            // Welcome already dismissed — skip with informational note
            XCTContext.runActivity(named: "welcome_card not present — user has already seen it") { _ in }
            return
        }

        let card = app.otherElements["welcome_card"]
        XCTAssertTrue(card.exists, "Welcome card container should exist")

        // Page 0: dot 0 filled, dot 1 and 2 dimmed
        XCTAssertTrue(exists("welcome_dot_0"), "Dot 0 should exist on page 0")
        XCTAssertTrue(exists("welcome_swipe_hint"), "Swipe hint should be visible on page 0")

        screenshot("02_welcome_page_0")

        // Swipe to page 1
        card.swipeLeft()
        sleep(1)

        XCTAssertTrue(exists("welcome_dot_1"), "Dot 1 should still exist after swipe")
        XCTAssertTrue(exists("welcome_swipe_hint"), "Swipe hint should still be visible on page 1")
        screenshot("02_welcome_page_1")

        // Swipe to page 2
        card.swipeLeft()
        sleep(1)

        // On page 2, "Let's do this" button appears instead of swipe hint
        XCTAssertTrue(exists("welcome_start_button"), "Start button should appear on page 2")
        XCTAssertFalse(exists("welcome_swipe_hint", timeout: 1), "Swipe hint should not be visible on page 2")
        screenshot("02_welcome_page_2")
    }

    // MARK: - Test 3: Swipe right goes back through welcome pages

    func test03_WelcomeCardSwipeRightGoesBack() {
        guard exists("welcome_card", timeout: 3) else {
            XCTContext.runActivity(named: "welcome_card not present — skipping") { _ in }
            return
        }

        let card = app.otherElements["welcome_card"]

        // Advance to page 2
        card.swipeLeft()
        sleep(1)
        card.swipeLeft()
        sleep(1)

        XCTAssertTrue(exists("welcome_start_button"), "Should be on page 2 with start button")

        // Swipe back to page 1
        card.swipeRight()
        sleep(1)

        XCTAssertTrue(exists("welcome_swipe_hint"), "Swipe hint should reappear after swiping back")
        XCTAssertFalse(exists("welcome_start_button", timeout: 1), "Start button should be gone on page 1")
        screenshot("02_welcome_swipe_back")
    }

    // MARK: - Test 4: Can't swipe past page boundaries

    func test04_WelcomeCardBoundaryEnforcement() {
        guard exists("welcome_card", timeout: 3) else {
            XCTContext.runActivity(named: "welcome_card not present — skipping") { _ in }
            return
        }

        let card = app.otherElements["welcome_card"]

        // On page 0 — swipe right should do nothing (still on page 0)
        card.swipeRight()
        sleep(1)

        XCTAssertTrue(exists("welcome_swipe_hint"), "Swipe hint should still be visible — still on page 0")
        XCTAssertFalse(exists("welcome_start_button", timeout: 1), "Should not advance past page 0 boundary")
        screenshot("02_welcome_left_boundary")

        // Advance to page 2 and try swiping further left
        card.swipeLeft()
        sleep(1)
        card.swipeLeft()
        sleep(1)

        XCTAssertTrue(exists("welcome_start_button"), "Should be on page 2")

        card.swipeLeft()
        sleep(1)

        // Still on page 2 — start button still visible
        XCTAssertTrue(exists("welcome_start_button"), "Start button should remain visible — still on page 2")
        screenshot("02_welcome_right_boundary")
    }

    // MARK: - Test 5: "Let's do this" on page 3 dismisses welcome

    func test05_WelcomeStartButtonDismissesCard() {
        guard exists("welcome_card", timeout: 3) else {
            XCTContext.runActivity(named: "welcome_card not present — skipping") { _ in }
            return
        }

        let card = app.otherElements["welcome_card"]

        // Navigate to page 2
        card.swipeLeft()
        sleep(1)
        card.swipeLeft()
        sleep(1)

        let startBtn = app.buttons["welcome_start_button"]
        XCTAssertTrue(startBtn.waitForExistence(timeout: 3), "Start button must exist on page 2")
        startBtn.tap()
        sleep(2)

        // Welcome card should be gone; next state should appear
        XCTAssertFalse(exists("welcome_card", timeout: 2), "Welcome card should be dismissed after tapping start")
        screenshot("02_after_welcome_dismissed")
    }

    // MARK: - Test 6: Greeting card renders with time-based text and user name

    func test06_GreetingCardRendersWithContent() {
        // Dismiss welcome if present to reach greeting
        dismissWelcomeIfPresent()

        let greetingCard = app.otherElements["daily_greeting_card"]
        let returningCard = app.otherElements["returning_card"]
        let greetingBtn = app.buttons["greeting_start_button"]
        let returningBtn = app.buttons["returning_continue_button"]

        let hasGreeting = greetingCard.waitForExistence(timeout: 3)
        let hasReturning = returningCard.waitForExistence(timeout: 1)

        guard hasGreeting || hasReturning else {
            // User already past greeting state (task cards or complete state)
            XCTContext.runActivity(named: "Greeting/returning card not present — user already past this state") { _ in }
            return
        }

        if hasGreeting {
            XCTAssertTrue(greetingBtn.exists, "Get started button should exist on greeting card")

            // Verify the greeting contains a time-based salutation
            let greetingTexts = app.staticTexts.allElementsBoundByIndex
            let hasGreetingText = greetingTexts.contains { element in
                let text = element.label
                return text.contains("morning") || text.contains("afternoon") ||
                       text.contains("evening") || text.contains("Hey")
            }
            XCTAssertTrue(hasGreetingText, "Greeting should contain time-based text (morning/afternoon/evening)")
            screenshot("02_greeting_card")
        } else {
            XCTAssertTrue(returningBtn.exists, "Returning card continue button should exist")
            screenshot("02_returning_card")
        }
    }

    // MARK: - Test 7: Greeting button advances to first task

    func test07_GreetingButtonAdvancesToTask() {
        dismissWelcomeIfPresent()

        let greetingBtn = app.buttons["greeting_start_button"]
        let returningBtn = app.buttons["returning_continue_button"]

        if greetingBtn.waitForExistence(timeout: 3) {
            greetingBtn.tap()
        } else if returningBtn.waitForExistence(timeout: 3) {
            returningBtn.tap()
        } else {
            // Already past greeting — nothing to tap
            XCTContext.runActivity(named: "No greeting button present — already past greeting state") { _ in }
            return
        }

        sleep(2)

        // After tapping, should see task flow, task card, complete state, or active loading
        let advancedPastGreeting =
            exists("task_card", timeout: 5) ||
            exists("all_complete_view", timeout: 3) ||
            exists("daily_complete_view", timeout: 3) ||
            app.otherElements["taskflow_dismiss_button"].exists ||
            app.buttons["paywall_dismiss_button"].exists ||
            app.staticTexts["Loading your task..."].exists

        XCTAssertTrue(advancedPastGreeting, "Tapping greeting button should advance past the greeting state")
        screenshot("02_after_greeting_tapped")
    }
}
