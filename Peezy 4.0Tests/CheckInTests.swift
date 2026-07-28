import Foundation
import Testing
@testable import Peezy_4_0

@MainActor
struct CheckInTests {
    @Test func bookedContextParsesStoredVendorRangeAndScope() throws {
        let vendor: [String: Any] = [
            "vendorId": "test_mover_a",
            "name": "Test Mover A"
        ]
        let estimate: [String: Any] = [
            "low": 1_200.0,
            "high": 1_600.0,
            "typicalHours": 5.5
        ]
        let scope: [String: Any] = [
            "cubicFeet": 980.0,
            "driveMinutes": 45.0,
            "packedStatus": "mostlyPacked"
        ]
        let response: [String: Any] = [
            "answers": [
                "workflowId": "book_movers",
                "answers": [
                    "chosen_vendor": [try json(vendor)],
                    "estimate": [try json(estimate)],
                    "scope": [try json(scope)],
                    "quoteRequest": ["false"]
                ]
            ]
        ]

        let context = CheckInService.bookingContext(fromWorkflowResponse: response)

        #expect(context?.vendorId == "test_mover_a")
        #expect(context?.vendorName == "Test Mover A")
        #expect(context?.estimatedRange == CheckInEstimatedRange(low: 1_200, high: 1_600))
        #expect((context?.scopeSnapshot["cubicFeet"] as? NSNumber)?.doubleValue == 980)
        #expect(context?.scopeSnapshot["packedStatus"] as? String == "mostlyPacked")
    }

    @Test func quoteOnlyOrMalformedStoredResponseHasNoBookedContext() throws {
        let validVendor = try json([
            "vendorId": "test_mover_a",
            "name": "Test Mover A"
        ])
        let validEstimate = try json(["low": 1_200, "high": 1_600])
        let validScope = try json(["cubicFeet": 980, "driveMinutes": 45])

        #expect(CheckInService.bookingContext(fromWorkflowResponse: [:]) == nil)
        #expect(CheckInService.bookingContext(fromWorkflowResponse: [
            "answers": ["answers": [
                "chosen_vendor": [validVendor],
                "estimate": [validEstimate],
                "scope": [validScope],
                "quoteRequest": ["true"]
            ]]
        ]) == nil)
        #expect(CheckInService.bookingContext(fromWorkflowResponse: [
            "answers": ["answers": [
                "chosen_vendor": [validVendor],
                "estimate": ["{}"],
                "scope": [validScope],
                "quoteRequest": ["false"]
            ]]
        ]) == nil)
        #expect(CheckInService.bookingContext(fromWorkflowResponse: [
            "answers": ["answers": [
                "chosen_vendor": [validVendor],
                "estimate": [validEstimate],
                "scope": ["{}"],
                "quoteRequest": ["false"]
            ]]
        ]) == nil)
    }

    @Test func booleanNumericBookingFieldsAreMalformed() throws {
        let validVendor = try json([
            "vendorId": "test_mover_a",
            "name": "Test Mover A"
        ])
        let validEstimate = try json(["low": 1_200, "high": 1_600])
        let validScope = try json(["cubicFeet": 980, "driveMinutes": 45])

        for malformedEstimate in [
            try json(["low": true, "high": 1_600]),
            try json(["low": 1_200, "high": true])
        ] {
            #expect(CheckInService.bookingContext(fromWorkflowResponse: [
                "answers": ["answers": [
                    "chosen_vendor": [validVendor],
                    "estimate": [malformedEstimate],
                    "scope": [validScope],
                    "quoteRequest": ["false"]
                ]]
            ]) == nil)
        }

        for malformedScope in [
            try json(["cubicFeet": true, "driveMinutes": 45]),
            try json(["cubicFeet": 980, "driveMinutes": false])
        ] {
            #expect(CheckInService.bookingContext(fromWorkflowResponse: [
                "answers": ["answers": [
                    "chosen_vendor": [validVendor],
                    "estimate": [validEstimate],
                    "scope": [malformedScope],
                    "quoteRequest": ["false"]
                ]]
            ]) == nil)
        }
    }

    @Test func finalBillPayloadIsOptionalAndCarriesNoClientCalibrationContext() {
        let facts = MoveCheckInAnswers(
            arrivedInWindow: true,
            crewWorkedSteadily: true,
            costMoreThanQuoted: false,
            damaged: false,
            note: "  all good  ",
            finalBill: 1_432.18
        )
        let withBill = facts.payload
        let withoutBill = MoveCheckInAnswers(
            arrivedInWindow: true,
            crewWorkedSteadily: true,
            costMoreThanQuoted: false,
            damaged: false,
            note: "",
            finalBill: nil
        ).payload

        #expect((withBill["finalBill"] as? NSNumber)?.doubleValue == 1_432.18)
        #expect(withBill["note"] as? String == "all good")
        #expect(withBill["vendorId"] == nil)
        #expect(withBill["estimatedRange"] == nil)
        #expect(withBill["scopeSnapshot"] == nil)
        #expect(withoutBill["finalBill"] == nil)
    }

    @Test func finalBillTextAcceptsPositiveMoneyOnly() {
        #expect(CheckInService.finalBill(from: "") == nil)
        #expect(CheckInService.finalBill(from: "1,432.18") == 1_432.18)
        #expect(CheckInService.finalBill(from: "$1,432.18") == 1_432.18)
        #expect(CheckInService.finalBill(from: "0") == nil)
        #expect(CheckInService.finalBill(from: "-12") == nil)
        #expect(CheckInService.finalBill(from: "not money") == nil)
    }

    private func json(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
