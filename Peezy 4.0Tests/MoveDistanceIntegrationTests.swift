//
//  MoveDistanceIntegrationTests.swift
//  Peezy 4.0Tests
//
// ============================================================================
// INTEGRATION TESTS: moveDistance and isInterstate via Real CLGeocoder
//
// DESIGN RATIONALE
// ────────────────
// This system has two independent axes that serve different purposes:
//
// moveDistance ("Local" vs "Long Distance") — 50-mile threshold
//   Controls whether users need NEW service providers (doctor, dentist,
//   gym, bank). Short moves = keep existing providers. Long moves = find
//   new ones. Threshold: < 50 miles → "Local", ≥ 50 miles → "Long Distance".
//
// isInterstate ("Yes" vs "No") — did you cross a state line?
//   Controls whether users need to update STATE-LEVEL registrations
//   (driver's license, vehicle title, voter registration). This is
//   independent of distance: a 5-minute move across a state border still
//   requires DMV paperwork.
//
// WHY THESE ARE SEPARATE AXES:
//   • Local + Interstate:   5-min drive across KS/MO border → need new
//     license (isInterstate=Yes) but keep gym/doctor (moveDistance=Local).
//   • Long Distance + Same State: 240-mile drive Houston→Dallas → need new
//     providers (moveDistance=Long Distance) but license is fine (isInterstate=No).
//
// IMPLEMENTATION NOTES:
//   • computeDistanceAndInterstate() lives on AssessmentDataManager (@MainActor).
//   • It reads self.currentAddress and self.newAddress, calls CLGeocoder
//     sequentially (required — shared internal state), then sets self.moveDistance
//     and self.isInterstate.
//   • Failure defaults: "Long Distance" / "Yes" (better to over-prepare).
//   • These tests hit Apple's geocoding servers — a 2-second delay between
//     cases avoids rate-limiting. Timeout is 15 seconds per test.
//
// CATALOG ALIGNMENT:
//   After the 4 geocoding tests, a separate synchronous test verifies that
//   TaskConditionParser fires the right tasks for each scenario based solely
//   on the moveDistance / isInterstate values those geocoding tests produce.
// ============================================================================

import XCTest
import CoreLocation
@testable import Peezy_4_0

// MARK: - Geocoding Integration Tests

final class MoveDistanceIntegrationTests: XCTestCase {

    // Generous timeout — geocoding depends on network round-trips to Apple.
    private let geocodeTimeout: TimeInterval = 15.0

    // MARK: - Test 1: Local + Same State
    // From: 9500 Nall Ave, Overland Park, KS 66207
    // To:   11950 College Blvd, Overland Park, KS 66210
    // Expected: moveDistance = "Local", isInterstate = "No"
    // Why: ~4 miles apart, both firmly in Kansas.
    func testLocalSameState() async throws {
        let manager = await AssessmentDataManager()
        await MainActor.run {
            manager.currentAddress = "9500 Nall Ave, Overland Park, KS 66207"
            manager.newAddress     = "11950 College Blvd, Overland Park, KS 66210"
        }

        await manager.computeDistanceAndInterstate()

        let moveDistance = await manager.moveDistance
        let isInterstate = await manager.isInterstate

        XCTAssertEqual(moveDistance, "Local",
            "Expect Local: addresses are ~4 miles apart within Overland Park, KS")
        XCTAssertEqual(isInterstate, "No",
            "Expect No interstate: both addresses are in Kansas")

        // Rate-limit buffer between geocoding tests
        try await Task.sleep(nanoseconds: 2_000_000_000)
    }

    // MARK: - Test 2: Local + Interstate
    // From: 500 State Ave, Kansas City, KS 66101
    // To:   400 Grand Blvd, Kansas City, MO 64106
    // Expected: moveDistance = "Local", isInterstate = "Yes"
    // Why: ~3 miles apart but crosses the KS/MO state line.
    //      Needs DMV updates (new license) but NOT new providers.
    func testLocalInterstate() async throws {
        let manager = await AssessmentDataManager()
        await MainActor.run {
            manager.currentAddress = "500 State Ave, Kansas City, KS 66101"
            manager.newAddress     = "400 Grand Blvd, Kansas City, MO 64106"
        }

        await manager.computeDistanceAndInterstate()

        let moveDistance = await manager.moveDistance
        let isInterstate = await manager.isInterstate

        XCTAssertEqual(moveDistance, "Local",
            "Expect Local: ~3 miles across the KS/MO border — close enough to keep providers")
        XCTAssertEqual(isInterstate, "Yes",
            "Expect Yes: Kansas City KS → Kansas City MO crosses a state line")

        try await Task.sleep(nanoseconds: 2_000_000_000)
    }

    // MARK: - Test 3: Long Distance + Same State
    // From: 1000 Main St, Houston, TX 77002
    // To:   1000 Commerce St, Dallas, TX 75202
    // Expected: moveDistance = "Long Distance", isInterstate = "No"
    // Why: ~240 miles apart but both in Texas.
    //      Needs new providers but NOT DMV registration updates.
    func testLongDistanceSameState() async throws {
        let manager = await AssessmentDataManager()
        await MainActor.run {
            manager.currentAddress = "1000 Main St, Houston, TX 77002"
            manager.newAddress     = "1000 Commerce St, Dallas, TX 75202"
        }

        await manager.computeDistanceAndInterstate()

        let moveDistance = await manager.moveDistance
        let isInterstate = await manager.isInterstate

        XCTAssertEqual(moveDistance, "Long Distance",
            "Expect Long Distance: Houston→Dallas is ~240 miles, well above the 50-mile threshold")
        XCTAssertEqual(isInterstate, "No",
            "Expect No interstate: both cities are in Texas")

        try await Task.sleep(nanoseconds: 2_000_000_000)
    }

    // MARK: - Test 4: Long Distance + Interstate
    // From: 350 5th Ave, New York, NY 10118
    // To:   200 N Spring St, Los Angeles, CA 90012
    // Expected: moveDistance = "Long Distance", isInterstate = "Yes"
    // Why: ~2,800 miles and crosses state lines.
    //      Needs new providers AND full DMV/registration updates.
    func testLongDistanceInterstate() async throws {
        let manager = await AssessmentDataManager()
        await MainActor.run {
            manager.currentAddress = "350 5th Ave, New York, NY 10118"
            manager.newAddress     = "200 N Spring St, Los Angeles, CA 90012"
        }

        await manager.computeDistanceAndInterstate()

        let moveDistance = await manager.moveDistance
        let isInterstate = await manager.isInterstate

        XCTAssertEqual(moveDistance, "Long Distance",
            "Expect Long Distance: NY→LA is ~2,800 miles, far above the 50-mile threshold")
        XCTAssertEqual(isInterstate, "Yes",
            "Expect Yes: New York → California is unambiguously interstate")
    }
}

// MARK: - Catalog Condition Alignment Tests

// Verifies that TaskConditionParser fires tasks correctly for each of the
// 4 move scenarios based on moveDistance and isInterstate values.
// No geocoding, no network — tests pure condition-evaluation logic.
final class CatalogConditionAlignmentTests: XCTestCase {

    // MARK: - Scenario Data
    //
    // Each dict represents what getAllAssessmentData() would return after
    // computeDistanceAndInterstate() has populated moveDistance and isInterstate.

    /// Scenario 1 — Local + Same State (Overland Park within KS)
    private let localSameState: [String: Any] = [
        "moveDistance": "Local",
        "isInterstate": "No"
    ]

    /// Scenario 2 — Local + Interstate (Kansas City KS → MO)
    private let localInterstate: [String: Any] = [
        "moveDistance": "Local",
        "isInterstate": "Yes"
    ]

    /// Scenario 3 — Long Distance + Same State (Houston → Dallas, TX)
    private let longDistanceSameState: [String: Any] = [
        "moveDistance": "Long Distance",
        "isInterstate": "No"
    ]

    /// Scenario 4 — Long Distance + Interstate (NY → LA)
    private let longDistanceInterstate: [String: Any] = [
        "moveDistance": "Long Distance",
        "isInterstate": "Yes"
    ]

    // MARK: - isInterstate task: UPDATE_DRIVERS_LICENSE_STATE
    // Condition: {isInterstate: ["Yes"]}
    // Should fire only for scenarios that cross a state line.

    func testInterstateTaskFiresOnlyForInterstateScenarios() {
        let condition: [String: Any] = ["isInterstate": ["Yes"]]

        // Scenario 1 — Local + Same State: should NOT fire
        XCTAssertFalse(
            TaskConditionParser.evaluateConditions(condition, against: localSameState),
            "UPDATE_DRIVERS_LICENSE_STATE must NOT fire for a local same-state move"
        )

        // Scenario 2 — Local + Interstate: SHOULD fire (crossed state line)
        XCTAssertTrue(
            TaskConditionParser.evaluateConditions(condition, against: localInterstate),
            "UPDATE_DRIVERS_LICENSE_STATE MUST fire even for a local move if it's interstate"
        )

        // Scenario 3 — Long Distance + Same State: should NOT fire
        XCTAssertFalse(
            TaskConditionParser.evaluateConditions(condition, against: longDistanceSameState),
            "UPDATE_DRIVERS_LICENSE_STATE must NOT fire for a long distance same-state move"
        )

        // Scenario 4 — Long Distance + Interstate: SHOULD fire
        XCTAssertTrue(
            TaskConditionParser.evaluateConditions(condition, against: longDistanceInterstate),
            "UPDATE_DRIVERS_LICENSE_STATE MUST fire for a long distance interstate move"
        )
    }

    // MARK: - Long Distance task: SETUP_NEW_DOCTOR
    // Condition: {moveDistance: ["Long Distance"]}
    // Should fire only when user will need new providers (≥ 50 miles).

    func testLongDistanceTaskFiresOnlyForLongDistanceScenarios() {
        let condition: [String: Any] = ["moveDistance": ["Long Distance"]]

        // Scenario 1 — Local + Same State: should NOT fire (keep existing providers)
        XCTAssertFalse(
            TaskConditionParser.evaluateConditions(condition, against: localSameState),
            "SETUP_NEW_DOCTOR must NOT fire for a local move — user keeps their doctor"
        )

        // Scenario 2 — Local + Interstate: should NOT fire (3 miles, keep providers)
        XCTAssertFalse(
            TaskConditionParser.evaluateConditions(condition, against: localInterstate),
            "SETUP_NEW_DOCTOR must NOT fire for a local interstate move — distance is key"
        )

        // Scenario 3 — Long Distance + Same State: SHOULD fire
        XCTAssertTrue(
            TaskConditionParser.evaluateConditions(condition, against: longDistanceSameState),
            "SETUP_NEW_DOCTOR MUST fire for Houston→Dallas — 240 miles requires new providers"
        )

        // Scenario 4 — Long Distance + Interstate: SHOULD fire
        XCTAssertTrue(
            TaskConditionParser.evaluateConditions(condition, against: longDistanceInterstate),
            "SETUP_NEW_DOCTOR MUST fire for NY→LA — 2800 miles requires new providers"
        )
    }

    // MARK: - Local task: UPDATE_EXISTING_BANK
    // Condition: {moveDistance: ["Local"]}
    // Should fire only when user is staying close (< 50 miles) — update address, keep account.

    func testLocalTaskFiresOnlyForLocalScenarios() {
        let condition: [String: Any] = ["moveDistance": ["Local"]]

        // Scenario 1 — Local + Same State: SHOULD fire (short move, update address at bank)
        XCTAssertTrue(
            TaskConditionParser.evaluateConditions(condition, against: localSameState),
            "UPDATE_EXISTING_BANK MUST fire for a local same-state move"
        )

        // Scenario 2 — Local + Interstate: SHOULD fire (still close enough to keep bank)
        XCTAssertTrue(
            TaskConditionParser.evaluateConditions(condition, against: localInterstate),
            "UPDATE_EXISTING_BANK MUST fire for a local interstate move — bank is still nearby"
        )

        // Scenario 3 — Long Distance + Same State: should NOT fire (too far, need new bank)
        XCTAssertFalse(
            TaskConditionParser.evaluateConditions(condition, against: longDistanceSameState),
            "UPDATE_EXISTING_BANK must NOT fire for Houston→Dallas — too far for same branch"
        )

        // Scenario 4 — Long Distance + Interstate: should NOT fire
        XCTAssertFalse(
            TaskConditionParser.evaluateConditions(condition, against: longDistanceInterstate),
            "UPDATE_EXISTING_BANK must NOT fire for NY→LA — user needs a new bank"
        )
    }

    // MARK: - Combined task: REGISTER_VEHICLE_NEW_STATE
    // Condition: {isInterstate: ["Yes"], moveDistance: ["Long Distance"]}
    // Should fire only for Scenario 4 (both axes triggered).

    func testCombinedConditionFiresOnlyWhenBothAxesMatch() {
        let condition: [String: Any] = [
            "isInterstate": ["Yes"],
            "moveDistance": ["Long Distance"]
        ]

        // Scenario 1 — Local + Same State: neither axis matches
        XCTAssertFalse(
            TaskConditionParser.evaluateConditions(condition, against: localSameState),
            "REGISTER_VEHICLE_NEW_STATE must NOT fire: not interstate, not long distance"
        )

        // Scenario 2 — Local + Interstate: interstate but NOT long distance
        XCTAssertFalse(
            TaskConditionParser.evaluateConditions(condition, against: localInterstate),
            "REGISTER_VEHICLE_NEW_STATE must NOT fire: interstate but move is local"
        )

        // Scenario 3 — Long Distance + Same State: long distance but NOT interstate
        XCTAssertFalse(
            TaskConditionParser.evaluateConditions(condition, against: longDistanceSameState),
            "REGISTER_VEHICLE_NEW_STATE must NOT fire: long distance but same state"
        )

        // Scenario 4 — Long Distance + Interstate: SHOULD fire (both conditions met)
        XCTAssertTrue(
            TaskConditionParser.evaluateConditions(condition, against: longDistanceInterstate),
            "REGISTER_VEHICLE_NEW_STATE MUST fire for NY→LA: long distance AND interstate"
        )
    }
}
