//
//  VendorRateCard+Pricing.swift
//  Peezy 4.0
//

import Foundation

extension PricingRateCard {
    init(vendorRateCard: VendorRateCard) {
        self.init(
            hourlyByCrew: [
                2: vendorRateCard.hourlyByCrew.two,
                3: vendorRateCard.hourlyByCrew.three,
                4: vendorRateCard.hourlyByCrew.four
            ],
            tripCharge: vendorRateCard.tripChargeModel.amount,
            minimumHours: vendorRateCard.minimumHours,
            weekendSurcharge: vendorRateCard.surcharges.weekend,
            monthEndSurcharge: vendorRateCard.surcharges.monthEnd,
            peakSeasonSurcharge: vendorRateCard.surcharges.peakSeason,
            specialtyFees: vendorRateCard.specialtyFees.reduce(into: [:]) { result, entry in
                guard let item = SpecialtyItem(rawValue: entry.key) else { return }
                result[item] = entry.value
            }
        )
    }
}
