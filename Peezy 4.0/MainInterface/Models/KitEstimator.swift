import Foundation

nonisolated struct SupplyRates: Codable, Equatable {
    let smallBoxCents: Int
    let mediumBoxCents: Int
    let largeBoxCents: Int
    let xlBoxCents: Int
    let dishPackCents: Int
    let wardrobeCents: Int
    let pictureCartonCents: Int
    let packingPaper10lbCents: Int
    let bubbleRollCents: Int
    let tapeRollCents: Int
    let mattressBagCents: Int
    let stretchWrapCents: Int
    let markerCents: Int

    init?(configData data: [String: Any]) {
        guard let smallBoxCents = Self.cents(fromDollarValue: data["smallBox"]),
              let mediumBoxCents = Self.cents(fromDollarValue: data["mediumBox"]),
              let largeBoxCents = Self.cents(fromDollarValue: data["largeBox"]),
              let xlBoxCents = Self.cents(fromDollarValue: data["xlBox"]),
              let dishPackCents = Self.cents(fromDollarValue: data["dishPack"]),
              let wardrobeCents = Self.cents(fromDollarValue: data["wardrobe"]),
              let pictureCartonCents = Self.cents(fromDollarValue: data["pictureCarton"]),
              let packingPaper10lbCents = Self.cents(fromDollarValue: data["packingPaper10lb"]),
              let bubbleRollCents = Self.cents(fromDollarValue: data["bubbleRoll"]),
              let tapeRollCents = Self.cents(fromDollarValue: data["tapeRoll"]),
              let mattressBagCents = Self.cents(fromDollarValue: data["mattressBag"]),
              let stretchWrapCents = Self.cents(fromDollarValue: data["stretchWrap"]),
              let markerCents = Self.cents(fromDollarValue: data["marker"])
        else { return nil }

        self.smallBoxCents = smallBoxCents
        self.mediumBoxCents = mediumBoxCents
        self.largeBoxCents = largeBoxCents
        self.xlBoxCents = xlBoxCents
        self.dishPackCents = dishPackCents
        self.wardrobeCents = wardrobeCents
        self.pictureCartonCents = pictureCartonCents
        self.packingPaper10lbCents = packingPaper10lbCents
        self.bubbleRollCents = bubbleRollCents
        self.tapeRollCents = tapeRollCents
        self.mattressBagCents = mattressBagCents
        self.stretchWrapCents = stretchWrapCents
        self.markerCents = markerCents
    }

    init?(persistedCents data: [String: Any]) {
        guard let smallBoxCents = Self.nonnegativeInt(data["smallBox"]),
              let mediumBoxCents = Self.nonnegativeInt(data["mediumBox"]),
              let largeBoxCents = Self.nonnegativeInt(data["largeBox"]),
              let xlBoxCents = Self.nonnegativeInt(data["xlBox"]),
              let dishPackCents = Self.nonnegativeInt(data["dishPack"]),
              let wardrobeCents = Self.nonnegativeInt(data["wardrobe"]),
              let pictureCartonCents = Self.nonnegativeInt(data["pictureCarton"]),
              let packingPaper10lbCents = Self.nonnegativeInt(data["packingPaper10lb"]),
              let bubbleRollCents = Self.nonnegativeInt(data["bubbleRoll"]),
              let tapeRollCents = Self.nonnegativeInt(data["tapeRoll"]),
              let mattressBagCents = Self.nonnegativeInt(data["mattressBag"]),
              let stretchWrapCents = Self.nonnegativeInt(data["stretchWrap"]),
              let markerCents = Self.nonnegativeInt(data["marker"])
        else { return nil }

        self.smallBoxCents = smallBoxCents
        self.mediumBoxCents = mediumBoxCents
        self.largeBoxCents = largeBoxCents
        self.xlBoxCents = xlBoxCents
        self.dishPackCents = dishPackCents
        self.wardrobeCents = wardrobeCents
        self.pictureCartonCents = pictureCartonCents
        self.packingPaper10lbCents = packingPaper10lbCents
        self.bubbleRollCents = bubbleRollCents
        self.tapeRollCents = tapeRollCents
        self.mattressBagCents = mattressBagCents
        self.stretchWrapCents = stretchWrapCents
        self.markerCents = markerCents
    }

    var persistedCents: [String: Int] {
        [
            "smallBox": smallBoxCents,
            "mediumBox": mediumBoxCents,
            "largeBox": largeBoxCents,
            "xlBox": xlBoxCents,
            "dishPack": dishPackCents,
            "wardrobe": wardrobeCents,
            "pictureCarton": pictureCartonCents,
            "packingPaper10lb": packingPaper10lbCents,
            "bubbleRoll": bubbleRollCents,
            "tapeRoll": tapeRollCents,
            "mattressBag": mattressBagCents,
            "stretchWrap": stretchWrapCents,
            "marker": markerCents
        ]
    }

    private static func cents(fromDollarValue value: Any?) -> Int? {
        guard let dollars = (value as? NSNumber)?.doubleValue,
              dollars.isFinite,
              dollars >= 0
        else { return nil }
        return Int((dollars * 100).rounded())
    }

    private static func nonnegativeInt(_ value: Any?) -> Int? {
        guard let result = (value as? NSNumber)?.intValue, result >= 0 else { return nil }
        return result
    }
}

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
    var xl: Int
    var wardrobe: Int
    var dishPack: Int
    var tape: Int
    var paper: Int
    var wrap: Int
    var mattressBags: Int
    var deliveryBy: Date?
    let supplyRates: SupplyRates

    init(
        small: Int,
        medium: Int,
        large: Int,
        xl: Int = 0,
        wardrobe: Int,
        dishPack: Int,
        tape: Int,
        paper: Int,
        wrap: Int,
        mattressBags: Int,
        deliveryBy: Date?,
        supplyRates: SupplyRates
    ) {
        self.small = small
        self.medium = medium
        self.large = large
        self.xl = xl
        self.wardrobe = wardrobe
        self.dishPack = dishPack
        self.tape = tape
        self.paper = paper
        self.wrap = wrap
        self.mattressBags = mattressBags
        self.deliveryBy = deliveryBy
        self.supplyRates = supplyRates
    }

    private enum CodingKeys: String, CodingKey {
        case small, medium, large, xl, wardrobe, dishPack, tape, paper, wrap
        case mattressBags, deliveryBy, supplyRates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        small = try container.decode(Int.self, forKey: .small)
        medium = try container.decode(Int.self, forKey: .medium)
        large = try container.decode(Int.self, forKey: .large)
        xl = try container.decodeIfPresent(Int.self, forKey: .xl) ?? 0
        wardrobe = try container.decode(Int.self, forKey: .wardrobe)
        dishPack = try container.decode(Int.self, forKey: .dishPack)
        tape = try container.decode(Int.self, forKey: .tape)
        paper = try container.decode(Int.self, forKey: .paper)
        wrap = try container.decode(Int.self, forKey: .wrap)
        mattressBags = try container.decode(Int.self, forKey: .mattressBags)
        deliveryBy = try container.decodeIfPresent(Date.self, forKey: .deliveryBy)
        supplyRates = try container.decode(SupplyRates.self, forKey: .supplyRates)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(small, forKey: .small)
        try container.encode(medium, forKey: .medium)
        try container.encode(large, forKey: .large)
        try container.encode(xl, forKey: .xl)
        try container.encode(wardrobe, forKey: .wardrobe)
        try container.encode(dishPack, forKey: .dishPack)
        try container.encode(tape, forKey: .tape)
        try container.encode(paper, forKey: .paper)
        try container.encode(wrap, forKey: .wrap)
        try container.encode(mattressBags, forKey: .mattressBags)
        try container.encodeIfPresent(deliveryBy, forKey: .deliveryBy)
        try container.encode(supplyRates, forKey: .supplyRates)
    }

    var totalBoxes: Int { small + medium + large + xl + wardrobe + dishPack }

    var totalPriceCents: Int {
        small * supplyRates.smallBoxCents
            + medium * supplyRates.mediumBoxCents
            + large * supplyRates.largeBoxCents
            + xl * supplyRates.xlBoxCents
            + wardrobe * supplyRates.wardrobeCents
            + dishPack * supplyRates.dishPackCents
            + tape * supplyRates.tapeRollCents
            + paper * supplyRates.packingPaper10lbCents
            + wrap * supplyRates.bubbleRollCents
            + mattressBags * supplyRates.mattressBagCents
    }

    var itemizedSummary: String {
        var lines = [
            "\(small) small", "\(medium) medium", "\(large) large",
            "\(wardrobe) wardrobe", "\(dishPack) dish pack", "\(tape) tape",
            "\(paper) paper", "\(wrap) wrap", "\(mattressBags) mattress bags"
        ]
        if xl > 0 {
            lines.insert("\(xl) extra large", at: 3)
        }
        return lines.joined(separator: ", ")
    }

    mutating func clampToNonnegative() {
        small = max(small, 0)
        medium = max(medium, 0)
        large = max(large, 0)
        xl = max(xl, 0)
        wardrobe = max(wardrobe, 0)
        dishPack = max(dishPack, 0)
        tape = max(tape, 0)
        paper = max(paper, 0)
        wrap = max(wrap, 0)
        mattressBags = max(mattressBags, 0)
    }

    mutating func apply(_ allocation: PackingSupplyAllocation) {
        small = allocation[.small].purchase
        medium = allocation[.medium].purchase
        large = allocation[.large].purchase
        xl = allocation[.xl].purchase
    }
}

enum PackingSupplyBoxSize: String, CaseIterable, Identifiable {
    case small, medium, large, xl

    var id: String { rawValue }
}

struct PackingSupplyBreakdown: Equatable {
    struct ReserveReason: Equatable, Identifiable {
        let reason: String
        let count: Int

        var id: String { "\(reason):\(count)" }
    }

    let assigned: Int
    let reserve: Int
    let purchase: Int
    let reasons: [ReserveReason]
}

/// Valid only when the move aggregate is complete, internally consistent, and
/// stamped with the exact revision of the inventory documents read by the
/// client. Any malformed, stale, partial, or reasonless reserve data is
/// rejected so the caller can preserve the legacy formula unchanged.
struct PackingSupplyAllocation: Equatable {
    private let breakdowns: [PackingSupplyBoxSize: PackingSupplyBreakdown]

    subscript(size: PackingSupplyBoxSize) -> PackingSupplyBreakdown {
        breakdowns[size] ?? PackingSupplyBreakdown(
            assigned: 0,
            reserve: 0,
            purchase: 0,
            reasons: []
        )
    }

    init?(
        aggregateData: [String: Any],
        inventoryDocuments: [PackingV2InventoryDocument]
    ) {
        guard aggregateData["status"] as? String == "complete",
              aggregateData["clientGuardReady"] as? Bool == true,
              let aggregateRevision = aggregateData["inventoryRevision"] as? String,
              !aggregateRevision.isEmpty,
              aggregateRevision == PackingV2InventoryRevision.aggregate(
                  inventoryDocuments: inventoryDocuments
              ),
              let expectedRoomIDs = aggregateData["expectedRoomIds"] as? [String],
              let includedRoomIDs = aggregateData["includedRoomIds"] as? [String]
        else { return nil }

        let currentRoomIDs = inventoryDocuments.map(\.id).sorted()
        guard expectedRoomIDs == currentRoomIDs,
              includedRoomIDs == currentRoomIDs,
              let planned = Self.counts(aggregateData["plannedBySize"]),
              let reserve = Self.counts(aggregateData["reserveBySize"]),
              let purchase = Self.counts(aggregateData["purchaseBySize"]),
              let rawReasons = aggregateData["reserveReasonsBySize"] as? [String: Any]
        else { return nil }

        var decoded: [PackingSupplyBoxSize: PackingSupplyBreakdown] = [:]
        for size in PackingSupplyBoxSize.allCases {
            guard let assignedCount = planned[size],
                  let reserveCount = reserve[size],
                  let purchaseCount = purchase[size],
                  purchaseCount == assignedCount + reserveCount,
                  let reasons = Self.reasons(rawReasons[size.rawValue]),
                  reasons.reduce(0, { $0 + $1.count }) == reserveCount
            else { return nil }

            decoded[size] = PackingSupplyBreakdown(
                assigned: assignedCount,
                reserve: reserveCount,
                purchase: purchaseCount,
                reasons: reasons
            )
        }
        breakdowns = decoded
    }

    private static func counts(_ value: Any?) -> [PackingSupplyBoxSize: Int]? {
        guard let raw = value as? [String: Any] else { return nil }
        var result: [PackingSupplyBoxSize: Int] = [:]
        for size in PackingSupplyBoxSize.allCases {
            guard let count = (raw[size.rawValue] as? NSNumber)?.intValue,
                  count >= 0
            else { return nil }
            result[size] = count
        }
        return result
    }

    private static func reasons(_ value: Any?) -> [PackingSupplyBreakdown.ReserveReason]? {
        guard let rawReasons = value as? [[String: Any]] else { return nil }
        var reasons: [PackingSupplyBreakdown.ReserveReason] = []
        for raw in rawReasons {
            guard let reason = raw["reason"] as? String,
                  !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let count = (raw["count"] as? NSNumber)?.intValue,
                  count > 0
            else { return nil }
            reasons.append(PackingSupplyBreakdown.ReserveReason(reason: reason, count: count))
        }
        return reasons
    }
}

/// Pure inventory-cube + item-mix estimator for the one-bundle kit offer.
enum KitEstimator {
    private enum BoxSize {
        case small, medium, large
    }

    static func estimate(
        items: [KitInventoryItem],
        supplyRates: SupplyRates
    ) -> SuppliesKit {
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
            deliveryBy: nil,
            supplyRates: supplyRates
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
