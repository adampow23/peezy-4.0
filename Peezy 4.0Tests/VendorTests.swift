import Foundation
import Testing
@testable import Peezy_4_0

struct VendorTests {

    @Test func moverRateCardDecodesFromSeedSchema() throws {
        let json = #"""
        {
          "vendorId": "test_mover_a",
          "name": "Test Mover A",
          "vertical": "movers",
          "serviceRadius": { "center": "Kansas City, MO", "miles": 35 },
          "rateCard": {
            "hourlyByCrew": { "2": 145, "3": 185, "4": 220 },
            "tripChargeModel": { "kind": "flat", "amount": 129 },
            "minimumHours": 2,
            "clockPolicy": "portal_to_portal",
            "materials": { "included": false, "boxBundle": 42, "packingPaperBundle": 24 },
            "valuationTiers": [
              { "id": "standard", "label": "Standard valuation", "coveragePerPound": 0.6, "additionalCost": 0 }
            ],
            "surcharges": { "weekend": 0.1, "monthEnd": 0.08, "peakSeason": 0.12 },
            "blackoutDates": ["2026-12-25"]
          },
          "accountability": { "standardsVersion": "v1", "strikes": 0 },
          "active": true
        }
        """#

        let vendor = try JSONDecoder().decode(Vendor.self, from: Data(json.utf8))

        #expect(vendor.vendorId == "test_mover_a")
        #expect(vendor.vertical == .movers)
        #expect(vendor.rateCard.hourlyByCrew.rate(for: 3) == 185)
        #expect(vendor.rateCard.minimumHours == 2)
        #expect(vendor.rateCard.tripChargeModel == VendorTripCharge(kind: .flat, amount: 129))
        #expect(vendor.rateCard.surcharges.peakSeason == 0.12)
    }

    @Test func inactiveVendorNeverSurfacesFromStoreFilter() {
        let active = fixture(vendorId: "active", active: true)
        let inactive = fixture(vendorId: "inactive", active: false)

        let visible = VendorStore.active([inactive, active], for: .movers)

        #expect(visible.map(\.vendorId) == ["active"])
    }

    private func fixture(vendorId: String, active: Bool) -> Vendor {
        Vendor(
            vendorId: vendorId,
            name: vendorId,
            vertical: .movers,
            serviceRadius: VendorServiceRadius(center: "Kansas City, MO", miles: 35),
            rateCard: VendorRateCard(
                hourlyByCrew: CrewHourlyRates(two: 145, three: 185, four: 220),
                tripChargeModel: VendorTripCharge(kind: .flat, amount: 129),
                minimumHours: 2,
                clockPolicy: "portal_to_portal",
                materials: VendorMaterials(included: false, boxBundle: 42, packingPaperBundle: 24),
                valuationTiers: [],
                surcharges: VendorSurcharges(weekend: 0.1, monthEnd: 0.08, peakSeason: 0.12),
                blackoutDates: []
            ),
            accountability: VendorAccountability(standardsVersion: "v1", strikes: 0),
            active: active
        )
    }
}
