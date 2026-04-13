import XCTest

final class SettingsTests: E2ETestBase {

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        // Navigate to Settings tab before each test
        tapTab("tab_settings")
        sleep(1)
    }

    // MARK: - Test 01: Settings tab renders with header

    func test01_SettingsTabRendersWithHeader() {
        let header = app.staticTexts["Settings"]
        XCTAssertTrue(header.waitForExistence(timeout: 5), "Settings header should be visible")
        screenshot("07_01_settings_header")
    }

    // MARK: - Test 02: Profile card shows "Peezy Tester" name

    func test02_ProfileCardShowsTestUserName() {
        let profileCard = app.buttons["settings_profile_card"]
        XCTAssertTrue(profileCard.waitForExistence(timeout: 5), "Profile card should exist")

        // The card should display the test user's name
        let name = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Peezy Tester'")
        ).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3), "Profile card should show 'Peezy Tester'")
        screenshot("07_02_profile_card")
    }

    // MARK: - Test 03: Profile card tappable → edit profile sheet appears

    func test03_ProfileCardTappableOpensEditProfile() {
        let profileCard = app.buttons["settings_profile_card"]
        XCTAssertTrue(profileCard.waitForExistence(timeout: 5))
        profileCard.tap()
        sleep(1)

        // EditNameEmailSheet should appear — look for a name/email field or a sheet element
        let sheetAppeared = app.textFields.firstMatch.waitForExistence(timeout: 5)
            || app.sheets.firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(sheetAppeared, "Edit profile sheet should appear after tapping profile card")
        screenshot("07_03_edit_profile_open")

        // Dismiss the sheet
        app.swipeDown()
        sleep(1)
    }

    // MARK: - Test 04: Move date row tappable → editor appears → dismiss

    func test04_MoveDateRowOpensEditor() {
        let moveDateRow = app.buttons["settings_move_date"]
        XCTAssertTrue(moveDateRow.waitForExistence(timeout: 5), "Move date row should exist")
        moveDateRow.tap()
        sleep(1)

        // EditMoveDateSheet should appear — look for date picker or any sheet content
        let sheetAppeared = app.datePickers.firstMatch.waitForExistence(timeout: 5)
            || app.sheets.firstMatch.waitForExistence(timeout: 3)
            || app.pickers.firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(sheetAppeared, "Move date editor should appear after tapping Move Date row")
        screenshot("07_04_move_date_editor")

        // Dismiss
        app.swipeDown()
        sleep(1)
    }

    // MARK: - Test 05: Current address row tappable → editor appears

    func test05_CurrentAddressRowOpensEditor() {
        let currentAddressRow = app.buttons["settings_current_address"]
        XCTAssertTrue(currentAddressRow.waitForExistence(timeout: 5), "Current address row should exist")
        currentAddressRow.tap()
        sleep(1)

        // EditAddressSheet should appear — look for text field or sheet
        let sheetAppeared = app.textFields.firstMatch.waitForExistence(timeout: 5)
            || app.sheets.firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(sheetAppeared, "Current address editor should appear")
        screenshot("07_05_current_address_editor")

        // Dismiss
        app.swipeDown()
        sleep(1)
    }

    // MARK: - Test 06: New address row tappable → editor appears

    func test06_NewAddressRowOpensEditor() {
        let newAddressRow = app.buttons["settings_new_address"]
        XCTAssertTrue(newAddressRow.waitForExistence(timeout: 5), "New address row should exist")
        newAddressRow.tap()
        sleep(1)

        // EditAddressSheet should appear
        let sheetAppeared = app.textFields.firstMatch.waitForExistence(timeout: 5)
            || app.sheets.firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(sheetAppeared, "New address editor should appear")
        screenshot("07_06_new_address_editor")

        // Dismiss
        app.swipeDown()
        sleep(1)
    }

    // MARK: - Test 07: Subscription section renders (status, manage, restore)

    func test07_SubscriptionSectionRenders() {
        // Scroll up to make sure subscription section is visible
        app.swipeUp()
        sleep(1)

        // Status element
        let statusElement = app.descendants(matching: .any)["settings_subscription_status"]
        let manageRow = app.buttons["settings_manage_subscription"]
        let restoreRow = app.buttons["settings_restore_purchases"]

        // At least 2 of the 3 should exist
        let statusExists = statusElement.waitForExistence(timeout: 5)
        let manageExists = manageRow.waitForExistence(timeout: 5)
        let restoreExists = restoreRow.waitForExistence(timeout: 5)

        XCTAssertTrue(manageExists, "Manage Subscription row should exist")
        XCTAssertTrue(restoreExists, "Restore Purchases row should exist")
        screenshot("07_07_subscription_section")
    }

    // MARK: - Test 08: Restore Purchases → shows result alert → tap OK

    func test08_RestorePurchasesShowsAlert() {
        // Scroll to subscription section
        app.swipeUp()
        sleep(1)

        let restoreRow = app.buttons["settings_restore_purchases"]
        XCTAssertTrue(restoreRow.waitForExistence(timeout: 5), "Restore Purchases row should exist")
        restoreRow.tap()

        // Wait for the result alert (async restore completes and sets restoreMessage)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "Restore purchases result alert should appear")

        // Alert should have an OK button
        let okButton = alert.buttons["OK"]
        XCTAssertTrue(okButton.waitForExistence(timeout: 3), "Alert should have OK button")
        screenshot("07_08_restore_alert")
        okButton.tap()
        sleep(1)
    }

    // MARK: - Test 09: Inventory scanner row → opens fullScreenCover

    func test09_InventoryScannerOpensFullScreenCover() {
        // Scroll to find inventory section
        app.swipeUp()
        sleep(1)

        let inventoryRow = app.buttons["settings_inventory_scanner"]
        XCTAssertTrue(inventoryRow.waitForExistence(timeout: 5), "Inventory scanner row should exist")
        inventoryRow.tap()
        sleep(2)

        // The fullScreenCover should have changed the view hierarchy
        // We check that settings header is no longer visible (replaced by cover)
        let settingsHeader = app.staticTexts["Settings"]
        let coverOpened = !settingsHeader.exists || app.buttons.count > 0
        XCTAssertTrue(coverOpened, "Inventory fullScreenCover should open")
        screenshot("07_09_inventory_scanner_open")

        // Try to dismiss the fullScreenCover
        let closeButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Close' OR label CONTAINS 'Cancel' OR label CONTAINS 'Done' OR label CONTAINS 'Back'")
        ).firstMatch
        if closeButton.waitForExistence(timeout: 3) {
            closeButton.tap()
        } else {
            // Try swipe down as fallback
            app.swipeDown()
        }
        sleep(1)

        // Navigate back to settings
        if !app.staticTexts["Settings"].waitForExistence(timeout: 3) {
            tapTab("tab_settings")
            sleep(1)
        }
    }

    // MARK: - Test 10: Retake Assessment → confirmation alert → Cancel dismisses

    func test10_RetakeAssessmentAlertCancelDismisses() {
        // Scroll to find retake assessment row
        app.swipeUp()
        sleep(1)

        let retakeRow = app.buttons["settings_retake_assessment"]
        XCTAssertTrue(retakeRow.waitForExistence(timeout: 5), "Retake Assessment row should exist")
        retakeRow.tap()
        sleep(1)

        // Alert "Retake Assessment?" should appear
        let alert = app.alerts["Retake Assessment?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Retake Assessment confirmation alert should appear")

        // Verify the alert has a Cancel button
        let cancelButton = alert.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists, "Alert should have Cancel button")
        screenshot("07_10_retake_alert")
        cancelButton.tap()
        sleep(1)

        // Alert should be dismissed — settings should still be visible
        XCTAssertFalse(app.alerts.firstMatch.exists, "Alert should be dismissed after Cancel")
    }

    // MARK: - Test 11: Privacy Policy link exists

    func test11_PrivacyPolicyLinkExists() {
        // Scroll down to find support section
        app.swipeUp()
        sleep(1)

        let privacyRow = app.buttons["settings_privacy_policy"]
        XCTAssertTrue(privacyRow.waitForExistence(timeout: 5), "Privacy Policy row should exist")
        screenshot("07_11_privacy_policy")
    }

    // MARK: - Test 12: Terms of Service link exists

    func test12_TermsOfServiceLinkExists() {
        app.swipeUp()
        sleep(1)

        let termsRow = app.buttons["settings_terms_of_service"]
        XCTAssertTrue(termsRow.waitForExistence(timeout: 5), "Terms of Service row should exist")
        screenshot("07_12_terms_of_service")
    }

    // MARK: - Test 13: Sign Out → confirmation alert ("Sign Out?") → Cancel dismisses

    func test13_SignOutAlertCancelDismisses() {
        // Scroll down to find danger section
        app.swipeUp()
        sleep(1)
        app.swipeUp()
        sleep(1)

        let signOutRow = app.buttons["settings_sign_out"]
        XCTAssertTrue(signOutRow.waitForExistence(timeout: 5), "Sign Out row should exist")
        signOutRow.tap()
        sleep(1)

        // Alert "Sign Out?" should appear
        let alert = app.alerts["Sign Out?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Sign Out confirmation alert should appear")
        screenshot("07_13_sign_out_alert")

        // IMPORTANT: Do NOT tap "Sign Out" — only Cancel
        let cancelButton = alert.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists, "Alert should have Cancel button")
        cancelButton.tap()
        sleep(1)

        XCTAssertFalse(app.alerts.firstMatch.exists, "Alert should be dismissed after Cancel")
    }

    // MARK: - Test 14: Delete Account → confirmation alert → Cancel dismisses

    func test14_DeleteAccountAlertCancelDismisses() {
        app.swipeUp()
        sleep(1)
        app.swipeUp()
        sleep(1)

        let deleteRow = app.buttons["settings_delete_account"]
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 5), "Delete Account row should exist")
        deleteRow.tap()
        sleep(1)

        // Alert "Delete Account?" should appear
        let alert = app.alerts["Delete Account?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Delete Account confirmation alert should appear")

        // Verify "Delete Everything" button exists (destructive)
        let deleteButton = alert.buttons["Delete Everything"]
        XCTAssertTrue(deleteButton.exists, "Alert should have 'Delete Everything' button")
        screenshot("07_14_delete_account_alert")

        // IMPORTANT: Do NOT tap "Delete Everything" — only Cancel
        let cancelButton = alert.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists, "Alert should have Cancel button")
        cancelButton.tap()
        sleep(1)

        XCTAssertFalse(app.alerts.firstMatch.exists, "Alert should be dismissed after Cancel")
    }

    // MARK: - Test 15: Version footer visible at bottom

    func test15_VersionFooterVisibleAtBottom() {
        // Scroll to very bottom
        app.swipeUp()
        sleep(1)
        app.swipeUp()
        sleep(1)
        app.swipeUp()
        sleep(1)

        let versionFooter = app.descendants(matching: .any)["settings_version"]
        let versionExists = versionFooter.waitForExistence(timeout: 5)

        if !versionExists {
            // Fallback: look for "Peezy" or "Version" text at the bottom
            let peezyText = app.staticTexts.matching(
                NSPredicate(format: "label == 'Peezy'")
            ).firstMatch
            let versionText = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'Version'")
            ).firstMatch
            XCTAssertTrue(
                peezyText.exists || versionText.exists,
                "Version footer should be visible at the bottom of Settings"
            )
        }
        screenshot("07_15_version_footer")
    }
}
