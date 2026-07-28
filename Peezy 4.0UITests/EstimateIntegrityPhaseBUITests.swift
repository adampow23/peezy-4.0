import XCTest

final class EstimateIntegrityPhaseBUITests: XCTestCase {
    func testCoverageStripAndActions() {
        let app = XCUIApplication()
        app.launchArguments = ["--estimate-integrity-phase-b"]
        app.launch()

        let scanned = app.staticTexts["coverage.scanned"]
        let notSeen = app.staticTexts["coverage.not_seen"]
        XCTAssertTrue(scanned.waitForExistence(timeout: 20))
        XCTAssertTrue(notSeen.exists)
        XCTAssertTrue(app.buttons["coverage.add_clip.bedroom-2"].exists)
        XCTAssertTrue(app.buttons["coverage.nothing_there.basement"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "estimate_integrity_phase_b_coverage_strip"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["coverage.nothing_there.basement"].tap()
        XCTAssertFalse(app.buttons["coverage.nothing_there.basement"].exists)

        app.buttons["coverage.add_clip.bedroom-2"].tap()
        let roomField = app.textFields["coverage.room_name"]
        XCTAssertTrue(roomField.waitForExistence(timeout: 5))
        XCTAssertEqual(roomField.value as? String, "Bedroom 2")
    }
}
