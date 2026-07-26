//
//  ComparisonCardModel.swift
//  Peezy 4.0
//

import Foundation

/// Vertical-neutral display data for the reusable comparison card.
struct ComparisonCardModel: Identifiable, Equatable {
    let id: String
    let providerName: String
    let priceRange: String
    let durationAndTeam: String
    let arrivalWindow: String
    let insuranceTier: String
    let why: String
    let priceBasis: String
    let detailNotes: [String]
}
