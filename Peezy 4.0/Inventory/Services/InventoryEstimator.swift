import Foundation

struct MovingEstimate {
    // Overall move
    let totalCubicFeet: Double
    let recommendedTruckSize: String
    let estimatedLaborHours: Double

    // Box estimate (boxable tier only)
    let boxEstimateLow: Int
    let boxEstimateHigh: Int
    let packingHoursLow: Double
    let packingHoursHigh: Double
    let totalBoxableCubicFeet: Double

    // Furniture (furniture tier only)
    let furnitureItems: [FurnitureSummaryItem]
    let totalFurnitureCubicFeet: Double

    // Counts
    let fragileItemCount: Int
    let highValueItemCount: Int
    let totalItemCount: Int
    let roomCount: Int

    /// Formatted box range string, e.g. "12–18 boxes"
    var boxRangeDescription: String {
        if boxEstimateLow == boxEstimateHigh {
            return "\(boxEstimateLow) boxes"
        }
        return "\(boxEstimateLow)–\(boxEstimateHigh) boxes"
    }

    /// Formatted packing time range, e.g. "3–5 hours"
    var packingTimeDescription: String {
        let low = formatHours(packingHoursLow)
        let high = formatHours(packingHoursHigh)
        if low == high {
            return "\(low) hours"
        }
        return "\(low)–\(high) hours"
    }

    private func formatHours(_ hours: Double) -> String {
        let rounded = (hours * 2).rounded() / 2  // Round to nearest 0.5
        if rounded == rounded.rounded() {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }
}

/// Individual furniture item for the summary list
struct FurnitureSummaryItem {
    let name: String
    let quantity: Int
    let cubicFeet: Double
    let isFragile: Bool
    let isHighValue: Bool
    let roomName: String
}

enum InventoryEstimator {

    // Average cubic feet per standard moving box
    // Medium box (~3 cu ft) is the most common packing box
    static let cubicFeetPerBox: Double = 3.0

    // Packing speed: average person packs 4-6 boxes per hour
    // We use the range for low/high estimates
    static let boxesPerHourFast: Double = 6.0
    static let boxesPerHourSlow: Double = 4.0

    // Variance applied to box count for low/high range
    // Accounts for person-to-person packing density differences
    static let boxVarianceLow: Double = 0.85   // 15% under midpoint
    static let boxVarianceHigh: Double = 1.15   // 15% over midpoint

    // Fallback cubic feet by size when Sonnet didn't provide cubicFeet
    static let fallbackCubicFeetPerSize: [String: Double] = [
        "small": 3.0,
        "medium": 12.0,
        "large": 40.0,
        "oversized": 70.0
    ]

    // Minimum box estimate — even a nearly empty apartment has some packing
    static let minimumBoxEstimate: Int = 3

    static func estimate(from rooms: [ScannedRoom]) -> MovingEstimate {
        let allItems = rooms.flatMap { $0.items }.filter { $0.shouldMove }

        // Split by tier
        let furnitureItems = allItems.filter { $0.tier == "furniture" }
        let boxableItems = allItems.filter { $0.tier == "boxable" }

        // --- Furniture cubic feet ---
        let furnitureCF = furnitureItems.reduce(0.0) { total, item in
            let cf = cubicFeetForItem(item)
            return total + (cf * Double(item.quantity))
        }

        // --- Boxable cubic feet ---
        let boxableCF = boxableItems.reduce(0.0) { total, item in
            let cf = cubicFeetForItem(item)
            return total + (cf * Double(item.quantity))
        }

        // --- Total cubic feet with packing efficiency ---
        let rawTotalCF = furnitureCF + boxableCF
        // Furniture doesn't compress; boxable items lose ~20% space to packing gaps
        let adjustedCF = furnitureCF + (boxableCF / 0.80)

        // --- Truck recommendation based on total adjusted cubic feet ---
        let truck: String
        switch adjustedCF {
        case ..<150:    truck = "Pickup truck or cargo van"
        case ..<300:    truck = "10-ft truck"
        case ..<500:    truck = "15-ft truck"
        case ..<800:    truck = "20-ft truck"
        case ..<1200:   truck = "26-ft truck"
        default:        truck = "Multiple trucks needed"
        }

        // --- Box estimate from boxable cubic feet ---
        let midpointBoxes = boxableCF / cubicFeetPerBox
        let rawLow = Int((midpointBoxes * boxVarianceLow).rounded())
        let rawHigh = Int((midpointBoxes * boxVarianceHigh).rounded(.up))
        let boxLow = max(minimumBoxEstimate, rawLow)
        let boxHigh = max(minimumBoxEstimate, rawHigh)

        // --- Packing time estimate ---
        // Low estimate: fewer boxes packed faster. High estimate: more boxes packed slower.
        let packLow = Double(boxLow) / boxesPerHourFast
        let packHigh = Double(boxHigh) / boxesPerHourSlow

        // --- Moving labor hours (loading/unloading/driving, not packing) ---
        // Base 2 hours + 0.5hr per 100 adjusted cubic feet
        let laborHours = 2.0 + (adjustedCF / 100.0 * 0.5)

        // --- Build furniture summary list ---
        let furnitureSummary: [FurnitureSummaryItem] = furnitureItems.map { item in
            FurnitureSummaryItem(
                name: item.name,
                quantity: item.quantity,
                cubicFeet: cubicFeetForItem(item) * Double(item.quantity),
                isFragile: item.isFragile,
                isHighValue: item.isHighValue,
                roomName: item.roomName
            )
        }

        return MovingEstimate(
            totalCubicFeet: adjustedCF.rounded(),
            recommendedTruckSize: truck,
            estimatedLaborHours: (laborHours * 2).rounded() / 2,
            boxEstimateLow: boxLow,
            boxEstimateHigh: boxHigh,
            packingHoursLow: (packLow * 2).rounded() / 2,
            packingHoursHigh: (packHigh * 2).rounded() / 2,
            totalBoxableCubicFeet: boxableCF.rounded(),
            furnitureItems: furnitureSummary,
            totalFurnitureCubicFeet: furnitureCF.rounded(),
            fragileItemCount: allItems.filter { $0.isFragile }.count,
            highValueItemCount: allItems.filter { $0.isHighValue }.count,
            totalItemCount: allItems.reduce(0) { $0 + $1.quantity },
            roomCount: rooms.count
        )
    }

    /// Get cubic feet for an item, preferring Sonnet's estimate, falling back to size lookup
    private static func cubicFeetForItem(_ item: InventoryItem) -> Double {
        if item.cubicFeet > 0 {
            return item.cubicFeet
        }
        return fallbackCubicFeetPerSize[item.sizeEstimate] ?? 12.0
    }
}
