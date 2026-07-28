import XCTest

final class EstimateIntegrityPhaseFUITests: XCTestCase {
    func testFinalBillAppearsOnlyForBookedVendorCheckIn() {
        let bookedApp = XCUIApplication()
        bookedApp.launchArguments = ["--estimate-integrity-phase-f-booked"]
        bookedApp.launch()

        let finalBill = bookedApp.textFields["checkin.final_bill"]
        XCTAssertTrue(finalBill.waitForExistence(timeout: 20))
        XCTAssertEqual(
            bookedApp.staticTexts["checkin.estimated_range"].label,
            "Peezy estimate: $1,200–$1,600"
        )
        for _ in 0..<4 where !finalBill.isHittable {
            bookedApp.swipeUp()
        }
        XCTAssertTrue(finalBill.isHittable)
        let bookedScreenshot = XCTAttachment(screenshot: bookedApp.screenshot())
        bookedScreenshot.name = "estimate_integrity_phase_f_booked_checkin"
        bookedScreenshot.lifetime = .keepAlways
        add(bookedScreenshot)
        bookedApp.terminate()

        let generalApp = XCUIApplication()
        generalApp.launchArguments = ["--estimate-integrity-phase-f-general"]
        generalApp.launch()

        let generalTitle = generalApp.staticTexts["checkin.title"]
        XCTAssertTrue(generalTitle.waitForExistence(timeout: 20))
        XCTAssertEqual(generalTitle.label, "How did moving day go?")
        XCTAssertFalse(generalApp.textFields["checkin.final_bill"].exists)
        for _ in 0..<4 {
            generalApp.swipeUp()
        }
        let generalScreenshot = XCTAttachment(screenshot: generalApp.screenshot())
        generalScreenshot.name = "estimate_integrity_phase_f_general_checkin"
        generalScreenshot.lifetime = .keepAlways
        add(generalScreenshot)
    }
}
