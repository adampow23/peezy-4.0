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
