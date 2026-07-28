import Testing
@testable import Peezy_4_0

@MainActor
struct EstimateIntegrityPhaseCTests {
    @Test func largestPositiveActiveVendorCrewDrivesTheGate() {
        let cards = [
            CrewHourlyRates(two: 145, three: 185, four: 0),
            CrewHourlyRates(two: 150, three: 190, four: 220)
        ]
        #expect(cards.compactMap(\.largestAvailableCrewSize).max() == 4)

        let exact = scope(cubicFeet: 1_230, driveMinutes: 480)
        let above = scope(cubicFeet: 1_230.205, driveMinutes: 0)
        #expect(PricingEngine.physicalHours(for: exact, crew: 4) == 6)
        #expect(PricingEngine.quoteRoute(
            scope: exact,
            largestAvailableCrewSize: 4
        ) == .instantComparison)
        #expect(PricingEngine.quoteRoute(
            scope: above,
            largestAvailableCrewSize: 4
        ) == .conciergeQuote)
    }

    @Test func estimateAndWhyLineCannotEscapeTheCeiling() throws {
        let card = PricingRateCard(
            hourlyByCrew: [2: 145, 3: 185, 4: 220],
            tripCharge: 129,
            minimumHours: 2
        )
        let exact = scope(cubicFeet: 1_230, driveMinutes: 600)
        let above = scope(cubicFeet: 1_230.205, driveMinutes: 0)

        let estimate = try #require(PricingEngine.estimate(scope: exact, rateCard: card))
        #expect(estimate.why == "Sized so your move wraps in one solid morning — not a marathon.")
        #expect(PricingEngine.physicalHours(for: exact, crew: estimate.crew) <= 6)
        #expect(PricingEngine.estimate(scope: above, rateCard: card) == nil)
    }

    @Test func unavailableCrewAndLockedConciergeCopy() {
        #expect(CrewHourlyRates(two: 145, three: 185, four: 0).largestAvailableCrewSize == 3)
        #expect(CrewHourlyRates(two: 0, three: 0, four: 0).largestAvailableCrewSize == nil)
        #expect(MoversConciergeReason.physicalHours.copy == MoversConciergeCopy(
            title: "This is a big one.",
            body: "Big moves deserve a hand-built quote — we'll have yours within a day."
        ))
    }

    private func scope(cubicFeet: Double, driveMinutes: Double) -> MoveScope {
        MoveScope(
            cubicFeet: cubicFeet,
            driveMinutes: driveMinutes,
            originAccess: .ground,
            destAccess: .ground,
            packedStatus: .packed,
            cubeSource: .inventoryScan
        )
    }
}
