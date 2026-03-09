import Foundation

struct MovingEstimate {
    let totalCubicFeet: Double
    let estimatedBoxes: Int
    let recommendedTruckSize: String  // "Pickup truck", "10-ft", "15-ft", "20-ft", "26-ft"
    let estimatedLaborHours: Double
    let fragileItemCount: Int
    let highValueItemCount: Int
    let totalItemCount: Int
    let roomCount: Int
}

enum InventoryEstimator {

    // Size → cubic feet mapping
    static let cubicFeetPerSize: [String: Double] = [
        "small": 3.0,      // Lamp, small table, box
        "medium": 12.0,    // Dresser, desk, armchair
        "large": 40.0,     // Sofa, dining table, bookshelf
        "oversized": 70.0  // Sectional, piano, large armoire
    ]

    static func estimate(from rooms: [ScannedRoom]) -> MovingEstimate {
        let allItems = rooms.flatMap { $0.items }.filter { $0.shouldMove }

        // Calculate cubic feet
        let totalCF = allItems.reduce(0.0) { total, item in
            let cfPerItem = cubicFeetPerSize[item.sizeEstimate] ?? 12.0
            return total + (cfPerItem * Double(item.quantity))
        }

        // Packing efficiency factor (80% — items don't pack perfectly)
        let adjustedCF = totalCF / 0.80

        // Truck recommendation based on adjusted cubic feet
        let truck: String
        switch adjustedCF {
        case ..<150:    truck = "Pickup truck or cargo van"
        case ..<300:    truck = "10-ft truck"
        case ..<500:    truck = "15-ft truck"
        case ..<800:    truck = "20-ft truck"
        case ..<1200:   truck = "26-ft truck"
        default:        truck = "Multiple trucks needed"
        }

        // Box estimate: ~1 box per small item, larger items don't go in boxes
        let boxes = allItems.reduce(0) { total, item in
            let boxesPerItem: Int
            switch item.sizeEstimate {
            case "small": boxesPerItem = 1
            case "medium": boxesPerItem = 0
            case "large": boxesPerItem = 0
            case "oversized": boxesPerItem = 0
            default: boxesPerItem = 1
            }
            return total + (boxesPerItem * item.quantity)
        }
        // Add ~30% for miscellaneous items not captured in scan (clothes, kitchen, etc.)
        let adjustedBoxes = Int(Double(max(boxes, 5)) * 1.3)

        // Labor hours: base 2hrs + 0.5hr per 100 cubic feet
        let laborHours = 2.0 + (adjustedCF / 100.0 * 0.5)

        return MovingEstimate(
            totalCubicFeet: adjustedCF.rounded(),
            estimatedBoxes: adjustedBoxes,
            recommendedTruckSize: truck,
            estimatedLaborHours: (laborHours * 2).rounded() / 2,  // Round to nearest 0.5
            fragileItemCount: allItems.filter { $0.isFragile }.count,
            highValueItemCount: allItems.filter { $0.isHighValue }.count,
            totalItemCount: allItems.reduce(0) { $0 + $1.quantity },
            roomCount: rooms.count
        )
    }
}
