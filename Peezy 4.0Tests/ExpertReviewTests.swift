import Foundation
import Testing
@testable import Peezy_4_0

struct ExpertReviewTests {

    // MARK: - Deterministic message composition (plan GOAL B)

    @Test func fullQuoteRendersCrewTotalRateAndManHours() {
        let message = ExpertReviewMessageComposer.message(
            quotes: [
                TaskQuote(company: "Acme Moving", notes: "", crew: 3, hours: 5, perManRate: 50, travelFee: 100)
            ],
            peezyManHours: 14.5
        )
        // Rate reports crew-total ($50/man × 3 = $150), never per-man;
        // man-hours are crew × hours (3 × 5 = 15).
        #expect(message == """
        Expert review request — my moving quotes:
        • Acme Moving: 3 crew, 5 hrs, $150/hr crew rate, $100 travel — 15 man-hours
        Peezy's estimate: 14.5 man-hours
        """)
    }

    @Test func fractionalValuesKeepOneDecimal() {
        let message = ExpertReviewMessageComposer.message(
            quotes: [
                TaskQuote(company: "Bravo", notes: "", crew: 2, hours: 5.5, perManRate: 62.5, travelFee: 0)
            ],
            peezyManHours: nil
        )
        #expect(message == """
        Expert review request — my moving quotes:
        • Bravo: 2 crew, 5.5 hrs, $125/hr crew rate, $0 travel — 11 man-hours
        """)
    }

    @Test func incompleteQuoteAndMissingPeezyEstimate() {
        let message = ExpertReviewMessageComposer.message(
            quotes: [
                TaskQuote(company: "Half Entered", notes: "waiting on callback"),
                TaskQuote(company: "Acme", notes: "", crew: 2, hours: 4, perManRate: 60, travelFee: 75)
            ],
            peezyManHours: nil
        )
        #expect(message == """
        Expert review request — my moving quotes:
        • Half Entered: details incomplete
        • Acme: 2 crew, 4 hrs, $120/hr crew rate, $75 travel — 8 man-hours
        """)
    }

    // MARK: - Durable send-state machine (round-5 finding 2 + round-6 finding 1)

    @Test func missingMarkerMeansNotSent() {
        #expect(ExpertReviewSendState.fromMarker(nil) == .notSent)
        // A marker without a messageId proves nothing.
        #expect(ExpertReviewSendState.fromMarker(["adminQueued": true]) == .notSent)
    }

    @Test func markerReconstructsQueuedAndPendingStates() {
        let pending = ExpertReviewSendState.fromMarker([
            "messageId": "m1", "adminQueued": false
        ])
        #expect(pending == .sent(adminQueued: false))
        #expect(pending.showsDeliveryPendingNotice)
        #expect(pending.buttonDisabled)

        let queued = ExpertReviewSendState.fromMarker([
            "messageId": "m1", "adminQueued": true
        ])
        #expect(queued == .sent(adminQueued: true))
        #expect(!queued.showsDeliveryPendingNotice)
        #expect(queued.buttonDisabled)
    }

    @Test func markerWithoutQueueFlagIsPendingNotQueued() {
        // Ambiguity resolves pessimistically: no confirmed delivery claim.
        #expect(ExpertReviewSendState.fromMarker(["messageId": "m1"]) == .sent(adminQueued: false))
    }

    @Test func onlyNotSentEnablesTheButton() {
        #expect(!ExpertReviewSendState.notSent.buttonDisabled)
        #expect(ExpertReviewSendState.sending.buttonDisabled)
        #expect(ExpertReviewSendState.sent(adminQueued: true).buttonDisabled)
        #expect(ExpertReviewSendState.sent(adminQueued: false).buttonDisabled)
    }
}
