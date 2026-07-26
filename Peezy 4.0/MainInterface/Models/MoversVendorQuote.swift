//
//  MoversVendorQuote.swift
//  Peezy 4.0
//

import Foundation

struct MoversVendorQuote: Identifiable, Equatable {
    let vendor: Vendor
    let estimate: PriceEstimate
    let valuationTier: VendorValuationTier

    var id: String { vendor.vendorId }

    func comparisonModel(arrivalWindow: String, priceBasis: String) -> ComparisonCardModel {
        ComparisonCardModel(
            id: id,
            providerName: vendor.name,
            priceRange: "\(estimate.range.low.formatted(.currency(code: "USD").precision(.fractionLength(0))))–\(estimate.range.high.formatted(.currency(code: "USD").precision(.fractionLength(0))))",
            durationAndTeam: "\(estimate.typicalHours.formatted(.number.precision(.fractionLength(1)))) hours · \(estimate.crew)-person team",
            arrivalWindow: arrivalWindow,
            insuranceTier: valuationTier.label,
            why: estimate.why,
            priceBasis: priceBasis
        )
    }
}
