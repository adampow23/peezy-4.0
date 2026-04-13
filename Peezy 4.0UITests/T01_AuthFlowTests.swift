//
//  T01_AuthFlowTests.swift
//  Peezy 4.0UITests
//

import XCTest

final class AuthFlowTests: E2ETestBase {
    override var needsLogin: Bool { false }

    override func setUp() {
        super.setUp()
        signOutFirst()
    }

    // MARK: - Helpers

    func signOutFirst() {
        let homeTab = app.buttons["tab_home"]
        // Firebase can take 40s to init — wait generously before checking auth state
        guard homeTab.waitForExistence(timeout: 40) else { return }
        // Already in main app — go to settings and sign out
        app.buttons["tab_settings"].tap()
        sleep(1)
        // Find and tap sign out, then confirm
        let signOut = app.buttons["settings_sign_out"]
        if signOut.waitForExistence(timeout: 5) {
            signOut.tap()
            sleep(1)
            // Tap "Sign Out" in the confirmation alert
            let confirm = app.buttons["Sign Out"]
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
            sleep(3)
        }
    }

    // MARK: - Tests

    // Test 1: Auth screen shows all sign-in options
    func test01_AuthScreenShowsAllOptions() {
        let loginLink = app.buttons["auth_login_link"]
        XCTAssertTrue(loginLink.waitForExistence(timeout: 10),
            "Auth screen should appear with login link")
        XCTAssertTrue(exists("auth_email_signup"), "Email sign up button should exist")
        // Apple and Google are on the same screen
        screenshot("01_auth_screen")
    }

    // Test 2: Navigate to Sign Up screen — all fields exist, button disabled when empty
    func test02_NavigateToSignUpFieldsExist() {
        let emailSignup = app.buttons["auth_email_signup"]
        XCTAssertTrue(emailSignup.waitForExistence(timeout: 10))
        emailSignup.tap()

        let emailField = app.textFields["signup_email_field"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "Email field should exist")

        let pwField = app.secureTextFields["signup_password_field"]
        XCTAssertTrue(pwField.waitForExistence(timeout: 3), "Password field should exist")

        let confirmField = app.secureTextFields["signup_confirm_password_field"]
        XCTAssertTrue(confirmField.waitForExistence(timeout: 3), "Confirm password field should exist")

        // Submit button disabled when fields are empty
        let submitBtn = app.buttons["signup_submit_button"]
        if submitBtn.waitForExistence(timeout: 3) {
            XCTAssertFalse(submitBtn.isEnabled, "Sign Up button should be disabled when fields are empty")
        }
        screenshot("01_signup_screen")
    }

    // Test 3: Password mismatch shows error
    func test03_PasswordMismatchShowsError() {
        let emailSignup = app.buttons["auth_email_signup"]
        XCTAssertTrue(emailSignup.waitForExistence(timeout: 10))
        emailSignup.tap()

        let emailField = app.textFields["signup_email_field"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText("test@example.com")

        let pwField = app.secureTextFields["signup_password_field"]
        pwField.tap()
        pwField.typeText("password1")

        let confirmField = app.secureTextFields["signup_confirm_password_field"]
        confirmField.tap()
        confirmField.typeText("password2")

        // Inline mismatch error should appear
        XCTAssertTrue(
            app.staticTexts["Passwords do not match"].waitForExistence(timeout: 3),
            "Password mismatch error should appear"
        )
        screenshot("01_password_mismatch")
    }

    // Test 4: Valid form enables Sign Up button
    func test04_ValidFormEnablesSignUpButton() {
        let emailSignup = app.buttons["auth_email_signup"]
        XCTAssertTrue(emailSignup.waitForExistence(timeout: 10))
        emailSignup.tap()

        let emailField = app.textFields["signup_email_field"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText("valid@example.com")

        let pwField = app.secureTextFields["signup_password_field"]
        pwField.tap()
        pwField.typeText("password123")

        let confirmField = app.secureTextFields["signup_confirm_password_field"]
        confirmField.tap()
        confirmField.typeText("password123")

        let submitBtn = app.buttons["signup_submit_button"]
        if submitBtn.waitForExistence(timeout: 3) {
            XCTAssertTrue(submitBtn.isEnabled, "Sign Up button should be enabled with valid, matching inputs")
        }
        screenshot("01_valid_form")
    }

    // Test 5: Navigate to Log In screen — all fields and buttons exist
    func test05_NavigateToLoginFieldsExist() {
        let loginLink = app.buttons["auth_login_link"]
        XCTAssertTrue(loginLink.waitForExistence(timeout: 10))
        loginLink.tap()

        XCTAssertTrue(app.textFields["login_email_field"].waitForExistence(timeout: 5),
            "Email field should exist on login screen")
        XCTAssertTrue(app.secureTextFields["login_password_field"].waitForExistence(timeout: 3),
            "Password field should exist on login screen")
        XCTAssertTrue(exists("login_submit_button"), "Log In button should exist")
        XCTAssertTrue(exists("login_forgot_password"), "Forgot Password button should exist")
        screenshot("01_login_screen")
    }

    // Test 6: Close (X) on login dismisses back to auth
    func test06_CloseLoginDismissesToAuth() {
        let loginLink = app.buttons["auth_login_link"]
        XCTAssertTrue(loginLink.waitForExistence(timeout: 10))
        loginLink.tap()

        XCTAssertTrue(app.textFields["login_email_field"].waitForExistence(timeout: 5))

        let closeBtn = app.buttons["login_close_button"]
        if closeBtn.waitForExistence(timeout: 3) {
            closeBtn.tap()
        } else {
            // Fallback: tap the xmark in the navigation bar
            app.navigationBars.buttons.firstMatch.tap()
        }

        XCTAssertTrue(app.buttons["auth_login_link"].waitForExistence(timeout: 5),
            "Should return to auth screen after closing login")
        screenshot("01_after_login_close")
    }

    // Test 7: Round-trip navigation Sign Up ↔ Log In
    func test07_RoundTripSignUpAndLogin() {
        // Go to Sign Up
        let emailSignup = app.buttons["auth_email_signup"]
        XCTAssertTrue(emailSignup.waitForExistence(timeout: 10))
        emailSignup.tap()
        XCTAssertTrue(app.textFields["signup_email_field"].waitForExistence(timeout: 5),
            "Should land on Sign Up screen")

        // Dismiss Sign Up back to auth
        let signupLoginLink = app.buttons["signup_login_link"]
        if signupLoginLink.waitForExistence(timeout: 3) {
            signupLoginLink.tap()
        } else {
            app.navigationBars.buttons.firstMatch.tap()
        }

        // Back on auth screen
        XCTAssertTrue(app.buttons["auth_login_link"].waitForExistence(timeout: 5),
            "Should return to auth screen after dismissing sign up")

        // Go to Log In
        app.buttons["auth_login_link"].tap()
        XCTAssertTrue(app.textFields["login_email_field"].waitForExistence(timeout: 5),
            "Should land on Log In screen")

        // Dismiss Log In back to auth
        let loginSignupLink = app.buttons["login_signup_link"]
        if loginSignupLink.waitForExistence(timeout: 3) {
            loginSignupLink.tap()
        } else {
            app.navigationBars.buttons.firstMatch.tap()
        }

        // Back on auth screen
        XCTAssertTrue(app.buttons["auth_login_link"].waitForExistence(timeout: 5),
            "Should return to auth screen after dismissing login")
        screenshot("01_roundtrip_complete")
    }

    // Test 8: Forgot Password shows alert with Cancel
    func test08_ForgotPasswordShowsAlert() {
        let loginLink = app.buttons["auth_login_link"]
        XCTAssertTrue(loginLink.waitForExistence(timeout: 10))
        loginLink.tap()

        // Enter email first — "Forgot Password" requires a non-empty email
        let emailField = app.textFields["login_email_field"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText("test@example.com")

        let forgotBtn = app.buttons["login_forgot_password"]
        XCTAssertTrue(forgotBtn.waitForExistence(timeout: 3))
        forgotBtn.tap()

        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3),
            "Forgot Password alert should appear")
        app.alerts.buttons["Cancel"].firstMatch.tap()
        screenshot("01_forgot_password_alert")
    }

    // Test 9: Successful login with test credentials
    func test09_SuccessfulLogin() {
        let loginLink = app.buttons["auth_login_link"]
        XCTAssertTrue(loginLink.waitForExistence(timeout: 10))
        loginLink.tap()

        let emailField = app.textFields["login_email_field"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(testEmail)

        let pwField = app.secureTextFields["login_password_field"]
        pwField.tap()
        pwField.typeText(testPassword)

        app.buttons["login_submit_button"].tap()

        XCTAssertTrue(app.buttons["tab_home"].waitForExistence(timeout: 15),
            "Main app should load after successful login with test credentials")
        screenshot("01_after_successful_login")
    }
}
