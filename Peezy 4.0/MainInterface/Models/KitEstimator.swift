import Foundation

/// Placeholder retail assumptions. LOCKED-pending-calibration: the box-return
/// loop and signed supplier rate card replace these values, not UI literals.
enum KitConstants {
    static let headroomPercent = 12
    static let headroomMultiplier = 1.12

    static let smallBoxCubicFeet = 1.5
    static let mediumBoxCubicFeet = 3.0
    static let largeBoxCubicFeet = 4.5
    static let hangingItemsPerWardrobe = 20
    static let boxesPerTapeRoll = 10
    static let smallBoxesPerPaperPack = 5
    static let mixedBoxesPerWrapRoll = 8

    static let smallBoxPriceCents = 200
    static let mediumBoxPriceCents = 275
    static let largeBoxPriceCents = 400
    static let wardrobePriceCents = 1_600
    static let dishPackPriceCents = 1_500
    static let tapePriceCents = 400
    static let paperPriceCents = 1_200
    static let wrapPriceCents = 1_800
    static let mattressBagPriceCents = 800
}

struct KitInventoryItem: Equatable {
    let name: String
    let category: String
    let roomName: String
    let tier: String
    let sizeEstimate: String
    let quantity: Int
    let cubicFeet: Double
    let isFragile: Bool

    init(
        name: String,
        category: String = "other",
        roomName: String = "",
        tier: String = "boxable",
        sizeEstimate: String = "medium",
        quantity: Int = 1,
        cubicFeet: Double = 0,
        isFragile: Bool = false
    ) {
        self.name = name
        self.category = category
        self.roomName = roomName
        self.tier = tier
        self.sizeEstimate = sizeEstimate
        self.quantity = max(quantity, 1)
        self.cubicFeet = max(cubicFeet, 0)
        self.isFragile = isFragile
    }
}

struct SuppliesKit: Codable, Equatable, Identifiable {
    nonisolated static let taskId = "PACKING_SUPPLIES_KIT"

    nonisolated var id: String { Self.taskId }

    var small: Int
    var medium: Int
    var large: Int
    var wardrobe: Int
    var dishPack: Int
    var tape: Int
    var paper: Int
    var wrap: Int
    var mattressBags: Int
    var deliveryBy: Date?

    var totalBoxes: Int { small + medium + large + wardrobe + dishPack }

    var totalPriceCents: Int {
        small * KitConstants.smallBoxPriceCents
            + medium * KitConstants.mediumBoxPriceCents
            + large * KitConstants.largeBoxPriceCents
            + wardrobe * KitConstants.wardrobePriceCents
            + dishPack * KitConstants.dishPackPriceCents
            + tape * KitConstants.tapePriceCents
            + paper * KitConstants.paperPriceCents
            + wrap * KitConstants.wrapPriceCents
            + mattressBags * KitConstants.mattressBagPriceCents
    }

    var itemizedSummary: String {
        [
            "\(small) small", "\(medium) medium", "\(large) large",
            "\(wardrobe) wardrobe", "\(dishPack) dish pack", "\(tape) tape",
            "\(paper) paper", "\(wrap) wrap", "\(mattressBags) mattress bags"
        ].joined(separator: ", ")
    }

    mutating func clampToNonnegative() {
        small = max(small, 0)
        medium = max(medium, 0)
        large = max(large, 0)
        wardrobe = max(wardrobe, 0)
        dishPack = max(dishPack, 0)
        tape = max(tape, 0)
        paper = max(paper, 0)
        wrap = max(wrap, 0)
        mattressBags = max(mattressBags, 0)
    }
}

/// Pure inventory-cube + item-mix estimator for the one-bundle kit offer.
enum KitEstimator {
    private enum BoxSize {
        case small, medium, large
    }

    static func estimate(items: [KitInventoryItem]) -> SuppliesKit {
        let movingItems = items.filter { $0.quantity > 0 }
        let boxable = movingItems.filter { $0.tier.lowercased() != "furniture" }

        var cubeBySize: [BoxSize: Double] = [.small: 0, .medium: 0, .large: 0]
        for item in boxable {
            let unitCube = item.cubicFeet > 0 ? item.cubicFeet : fallbackCube(for: item.sizeEstimate)
            cubeBySize[boxSize(for: item), default: 0] += unitCube * Double(item.quantity)
        }

        let small = headedCount(cube: cubeBySize[.small, default: 0], capacity: KitConstants.smallBoxCubicFeet)
        let medium = headedCount(cube: cubeBySize[.medium, default: 0], capacity: KitConstants.mediumBoxCubicFeet)
        let large = headedCount(cube: cubeBySize[.large, default: 0], capacity: KitConstants.largeBoxCubicFeet)

        let hangingCount = movingItems
            .filter { isHangingClothing($0) }
            .reduce(0) { $0 + $1.quantity }
        let wardrobe = hangingCount == 0
            ? 0
            : Int(ceil(Double(hangingCount) / Double(KitConstants.hangingItemsPerWardrobe)))

        let bedCount = movingItems
            .filter { isBedOrMattress($0) }
            .reduce(0) { $0 + $1.quantity }
        let kitchenPresent = movingItems.contains { item in
            normalized("\(item.roomName) \(item.name) \(item.category)").contains("kitchen")
        }

        let regularBoxCount = small + medium + large
        let fragileUnits = movingItems.filter(\.isFragile).reduce(0) { $0 + $1.quantity }
        let tape = regularBoxCount == 0
            ? 0
            : Int(ceil(Double(regularBoxCount) / Double(KitConstants.boxesPerTapeRoll)))
        let paper = small == 0 && fragileUnits == 0
            ? 0
            : max(1, Int(ceil(Double(small) / Double(KitConstants.smallBoxesPerPaperPack))))
        let wrapBase = small + large + fragileUnits
        let wrap = wrapBase == 0
            ? 0
            : max(1, Int(ceil(Double(wrapBase) / Double(KitConstants.mixedBoxesPerWrapRoll))))

        return SuppliesKit(
            small: small,
            medium: medium,
            large: large,
            wardrobe: wardrobe,
            dishPack: kitchenPresent ? 1 : 0,
            tape: tape,
            paper: paper,
            wrap: wrap,
            mattressBags: bedCount,
            deliveryBy: nil
        )
    }

    private static func headedCount(cube: Double, capacity: Double) -> Int {
        guard cube > 0 else { return 0 }
        return Int(ceil((cube / capacity) * KitConstants.headroomMultiplier))
    }

    private static func boxSize(for item: KitInventoryItem) -> BoxSize {
        let value = normalized("\(item.name) \(item.category)")
        if item.isFragile || containsAny(value, smallKeywords) { return .small }
        if containsAny(value, largeKeywords) || ["large", "oversized"].contains(item.sizeEstimate.lowercased()) {
            return .large
        }
        return .medium
    }

    private static func isHangingClothing(_ item: KitInventoryItem) -> Bool {
        containsAny(normalized("\(item.name) \(item.category)"), hangingKeywords)
    }

    private static func isBedOrMattress(_ item: KitInventoryItem) -> Bool {
        let value = normalized(item.name)
        return value.contains("mattress")
            || value == "bed"
            || value.hasPrefix("bed ")
            || value.hasSuffix(" bed")
            || value.contains("bed frame")
    }

    private static func fallbackCube(for size: String) -> Double {
        switch size.lowercased() {
        case "small": return 3
        case "large": return 40
        case "oversized": return 70
        default: return 12
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private static func containsAny(_ value: String, _ keywords: [String]) -> Bool {
        keywords.contains { value.contains($0) }
    }

    private static let smallKeywords = [
        "book", "record", "dish", "plate", "glass", "mug", "kitchen",
        "tool", "electronics", "computer", "cable", "decor"
    ]
    private static let largeKeywords = [
        "linen", "bedding", "blanket", "pillow", "comforter", "toy", "lamp", "shade"
    ]
    private static let hangingKeywords = [
        "hanging", "hanger", "dress", "shirt", "jacket", "coat", "suit"
    ]
}
