import XCTest

final class EstimateIntegrityPhaseCUITests: XCTestCase {
    func testPhysicalHoursGateShowsLockedConciergeCard() {
        let app = XCUIApplication()
        app.launchArguments = ["--estimate-integrity-phase-c"]
        app.launch()

        let card = app.otherElements["movers.quote.concierge"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["movers.quote.title"].label, "This is a big one.")
        XCTAssertEqual(
            app.staticTexts["movers.quote.body"].label,
            "Big moves deserve a hand-built quote — we'll have yours within a day."
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "estimate_integrity_phase_c_concierge_gate"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
