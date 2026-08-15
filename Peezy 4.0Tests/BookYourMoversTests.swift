import FirebaseFirestore
import Foundation
import Testing
@testable import Peezy_4_0

struct BookYourMoversTests {

    // MARK: - Atomic completion payload (plan A3 + round-4 finding 2)

    @Test func fullPayloadCarriesExactStatusContract() throws {
        let payload = MoversBookingDetails(
            company: "Acme Moving",
            moveDate: Date(timeIntervalSince1970: 1_787_000_000),
            arrivalWindow: "8–10 am",
            crewSize: 3,
            crewHourlyRate: 189
        ).completionPayload()

        // One atomic update: exact "Completed" (capital C — lowercase decodes
        // as .upcoming), completedAt, and the bookingDetails map together.
        #expect(Set(payload.keys) == ["status", "completedAt", "bookingDetails"])
        #expect(payload["status"] as? String == "Completed")
        #expect(payload["completedAt"] != nil)

        let details = try #require(payload["bookingDetails"] as? [String: Any])
        #expect(details["booked"] as? Bool == true)
        #expect(details["savedAt"] != nil)
        #expect(details["company"] as? String == "Acme Moving")
        #expect((details["moveDate"] as? Timestamp)?.dateValue()
                == Date(timeIntervalSince1970: 1_787_000_000))
        #expect(details["arrivalWindow"] as? String == "8–10 am")
        #expect((details["crewSize"] as? NSNumber)?.intValue == 3)
        #expect((details["crewHourlyRate"] as? NSNumber)?.doubleValue == 189)
    }

    @Test func minimalPayloadHasOnlyBookedAndSavedAt() throws {
        // Every capture field is optional; "yes" with nothing entered still
        // persists the required booked fact.
        let payload = MoversBookingDetails().completionPayload()
        let details = try #require(payload["bookingDetails"] as? [String: Any])
        #expect(Set(details.keys) == ["booked", "savedAt"])
        #expect(details["booked"] as? Bool == true)
        #expect(payload["status"] as? String == "Completed")
    }

    @Test func emptyStringsAreOmittedNotPersisted() throws {
        let payload = MoversBookingDetails(
            company: "",
            arrivalWindow: ""
        ).completionPayload()
        let details = try #require(payload["bookingDetails"] as? [String: Any])
        #expect(details["company"] == nil)
        #expect(details["arrivalWindow"] == nil)
    }

    @Test func crewSizeDecodesNSNumberSafely() throws {
        // Round-trip through the NSNumber-safe cast pattern the mapper uses.
        let payload = MoversBookingDetails(crewSize: 4).completionPayload()
        let details = try #require(payload["bookingDetails"] as? [String: Any])
        let decoded = (details["crewSize"] as? NSNumber)?.intValue
        #expect(decoded == 4)
    }
}
