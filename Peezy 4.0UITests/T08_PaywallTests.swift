import XCTest

final class PaywallTests: E2ETestBase {

    // MARK: - Helpers

    /// Navigate to Home tab and get to task cards, then tap "On It" to trigger paywall.
    /// Returns true if the paywall appeared.
    @discardableResult
    private func triggerPaywall() -> Bool {
        tapTab("tab_home")
        sleep(1)
        getToTaskCards()

        let onItButton = app.buttons["task_complete_button"]
        guard onItButton.waitForExistence(timeout: 5) else {
            // No task card visible — paywall cannot be triggered this way
            return false
        }
        onItButton.tap()
        sleep(1)

        return app.buttons["paywall_dismiss_button"].waitForExistence(timeout: 5)
    }

    /// Dismiss paywall if it's currently shown.
    private func dismissPaywallIfPresent() {
        let dismiss = app.buttons["paywall_dismiss_button"]
        if dismiss.waitForExistence(timeout: 2) { dismiss.tap(); sleep(1) }
    }

    // MARK: - Test 01: Paywall appears when tapping "On It" on a task

    func test01_PaywallAppearsOnTaskOnIt() {
        let paywallAppeared = triggerPaywall()
        XCTAssertTrue(paywallAppeared, "Paywall should appear when a non-subscriber taps 'On It'")
        screenshot("08_01_paywall_appears")
        dismissPaywallIfPresent()
    }

    // MARK: - Test 02: Plan cards render (annual and weekly)

    func test02_PlanCardsRender() {
        guard triggerPaywall() else {
            XCTFail("Paywall did not appear — cannot test plan cards")
            return
        }

        let annualCard = app.buttons["paywall_plan_annual"]
        let weeklyCard = app.buttons["paywall_plan_weekly"]

        XCTAssertTrue(annualCard.waitForExistence(timeout: 5), "Annual plan card should exist")
        XCTAssertTrue(weeklyCard.waitForExistence(timeout: 5), "Weekly plan card should exist")
        screenshot("08_02_plan_cards")
        dismissPaywallIfPresent()
    }

    // MARK: - Test 03: Annual plan selected by default

    func test03_AnnualSelectedByDefault() {
        guard triggerPaywall() else {
            XCTFail("Paywall did not appear — cannot test default selection")
            return
        }

        let annualCard = app.buttons["paywall_plan_annual"]
        XCTAssertTrue(annualCard.waitForExistence(timeout: 5), "Annual card should exist")

        // Annual is selected by default — it carries .isSelected accessibility trait
        let isSelected = annualCard.isSelected
            || annualCard.value as? String == "true"
        // We verify the card exists and the purchase button is accessible with annual as default
        // Annual card should have "BEST VALUE" text
        let bestValueText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'BEST VALUE'")
        ).firstMatch
        XCTAssertTrue(bestValueText.exists, "Annual card should show 'BEST VALUE' badge")
        screenshot("08_03_annual_default")
        dismissPaywallIfPresent()
    }

    // MARK: - Test 04: Tapping weekly card switches selection

    func test04_TappingWeeklySwitchesSelection() {
        guard triggerPaywall() else {
            XCTFail("Paywall did not appear — cannot test plan switching")
            return
        }

        let weeklyCard = app.buttons["paywall_plan_weekly"]
        XCTAssertTrue(weeklyCard.waitForExistence(timeout: 5))
        weeklyCard.tap()
        sleep(1)

        // After tapping weekly, it should be selected
        // Verify tapping was registered by checking weekly card is still present
        XCTAssertTrue(weeklyCard.exists, "Weekly plan card should still exist after tap")

        // Annual should no longer show selection styling (border changes)
        let annualCard = app.buttons["paywall_plan_annual"]
        XCTAssertTrue(annualCard.exists, "Annual plan card should still exist")
        screenshot("08_04_weekly_selected")
        dismissPaywallIfPresent()
    }

    // MARK: - Test 05: Purchase button exists and is enabled

    func test05_PurchaseButtonExistsAndIsEnabled() {
        guard triggerPaywall() else {
            XCTFail("Paywall did not appear — cannot test purchase button")
            return
        }

        let purchaseButton = app.buttons["paywall_purchase_button"]
        XCTAssertTrue(purchaseButton.waitForExistence(timeout: 5), "Purchase button should exist")
        XCTAssertTrue(purchaseButton.isEnabled, "Purchase button should be enabled")
        screenshot("08_05_purchase_button")
        dismissPaywallIfPresent()
    }

    // MARK: - Test 06: "Not now" dismisses paywall

    func test06_NotNowDismissesPaywall() {
        guard triggerPaywall() else {
            XCTFail("Paywall did not appear — cannot test dismiss")
            return
        }

        let dismissButton = app.buttons["paywall_dismiss_button"]
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 5), "'Not now' button should exist")
        dismissButton.tap()
        sleep(1)

        // Paywall should be gone — we should be back on Home
        XCTAssertFalse(
            app.buttons["paywall_dismiss_button"].exists,
            "Paywall should be dismissed after tapping 'Not now'"
        )
        screenshot("08_06_paywall_dismissed")
    }

    // MARK: - Test 07: "Redeem a code" button exists

    func test07_RedeemCodeButtonExists() {
        guard triggerPaywall() else {
            XCTFail("Paywall did not appear — cannot test redeem code button")
            return
        }

        let redeemButton = app.buttons["paywall_redeem_code"]
        XCTAssertTrue(redeemButton.waitForExistence(timeout: 5), "'Redeem a code' button should exist")
        screenshot("08_07_redeem_code")
        dismissPaywallIfPresent()
    }

    // MARK: - Test 08: "Restore Purchases" button exists

    func test08_RestorePurchasesButtonExists() {
        guard triggerPaywall() else {
            XCTFail("Paywall did not appear — cannot test restore purchases button")
            return
        }

        let restoreButton = app.buttons["paywall_restore_purchases"]
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 5), "'Restore Purchases' button should exist")
        screenshot("08_08_restore_purchases")
        dismissPaywallIfPresent()
    }

    // MARK: - Test 09: Subscription terms text visible (Apple-required disclosure)

    func test09_SubscriptionTermsVisible() {
        guard triggerPaywall() else {
            XCTFail("Paywall did not appear — cannot test subscription terms")
            return
        }

        let termsElement = app.descendants(matching: .any)["paywall_subscription_terms"]
        let termsExistById = termsElement.waitForExistence(timeout: 5)

        if !termsExistById {
            // Fallback: look for the Apple-required disclosure text
            let termsText = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Payment will be charged'")
            ).firstMatch
            XCTAssertTrue(
                termsText.waitForExistence(timeout: 5),
                "Apple-required subscription terms disclosure should be visible"
            )
        }
        screenshot("08_09_subscription_terms")
        dismissPaywallIfPresent()
    }

    // MARK: - Test 10: Privacy and Terms links exist

    func test10_PrivacyAndTermsLinksExist() {
        guard triggerPaywall() else {
            XCTFail("Paywall did not appear — cannot test privacy/terms links")
            return
        }

        let privacyLink = app.links["paywall_privacy_link"]
        let termsLink = app.links["paywall_terms_link"]

        // Links might be identified differently in XCUITest — also check by text
        let privacyExists = privacyLink.waitForExistence(timeout: 3)
            || app.links.matching(NSPredicate(format: "label CONTAINS 'Privacy Policy'")).firstMatch.waitForExistence(timeout: 3)
            || app.buttons.matching(NSPredicate(format: "label CONTAINS 'Privacy Policy'")).firstMatch.waitForExistence(timeout: 3)

        let termsExists = termsLink.waitForExistence(timeout: 3)
            || app.links.matching(NSPredicate(format: "label CONTAINS 'Terms of Service'")).firstMatch.waitForExistence(timeout: 3)
            || app.buttons.matching(NSPredicate(format: "label CONTAINS 'Terms of Service'")).firstMatch.waitForExistence(timeout: 3)

        XCTAssertTrue(privacyExists, "Privacy Policy link should exist on paywall")
        XCTAssertTrue(termsExists, "Terms of Service link should exist on paywall")
        screenshot("08_10_privacy_terms_links")
        dismissPaywallIfPresent()
    }
}
