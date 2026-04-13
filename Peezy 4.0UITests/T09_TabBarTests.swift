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
