import XCTest

final class EstimateIntegrityPhaseDUITests: XCTestCase {
    func testStorageStopQuestionAndOptionalAddressProgressivelyRender() {
        let app = XCUIApplication()
        app.launchArguments = ["--estimate-integrity-phase-d"]
        app.launch()

        let hasStorage = app.switches["movers.refinement.has_storage"]
        XCTAssertTrue(hasStorage.waitForExistence(timeout: 20))

        let stop = app.switches["movers.refinement.storage_stop"]
        let address = app.textFields["movers.refinement.storage_address"]
        XCTAssertFalse(stop.exists)
        XCTAssertFalse(address.exists)

        hasStorage.tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertEqual(stop.label, "Is your storage unit a stop on moving day?")
        XCTAssertFalse(address.exists)

        stop.tap()
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.75)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "estimate_integrity_phase_d_storage_stop"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
