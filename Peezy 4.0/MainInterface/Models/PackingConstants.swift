import Foundation

nonisolated struct PackingConfiguration: Equatable {
    let targetSessionMinutes: Int
    let minimumSessionMinutes: Int
    let cubicFeetPerHour: Double
    let boxEquivalentCubicFeet: Double
    let moveDayBufferDays: Int
    let suppliesDeliveryBufferDays: Int
    let behindPaceSessionsPerDay: Double
    let minimumRoomMinutesByType: [String: Int]
    let sequencingWeights: [String: Int]

    var minutesPerBoxEquivalent: Int {
        max(Int(ceil((boxEquivalentCubicFeet / cubicFeetPerHour) * 60)), 1)
    }

    init?(firestoreData data: [String: Any]) {
        guard let targetSessionMinutes = Self.int(data["targetSessionMinutes"]),
              let minimumSessionMinutes = Self.int(data["minimumSessionMinutes"]),
              let cubicFeetPerHour = Self.double(data["cubicFeetPerHour"]),
              let boxEquivalentCubicFeet = Self.double(data["boxEquivalentCubicFeet"]),
              let moveDayBufferDays = Self.int(data["moveDayBufferDays"]),
              let suppliesDeliveryBufferDays = Self.int(data["suppliesDeliveryBufferDays"]),
              let behindPaceSessionsPerDay = Self.double(data["behindPaceSessionsPerDay"]),
              let rawMinimums = data["minimumRoomMinutesByType"] as? [String: Any],
              let rawWeights = data["sequencingWeights"] as? [String: Any]
        else { return nil }

        let minimums = rawMinimums.compactMapValues(Self.int)
        let weights = rawWeights.compactMapValues(Self.int)
        let requiredMinimums = Set(["kitchen", "garage", "bedroom", "bathroom"])
        let requiredWeights = Set([
            "storageSeasonal", "decorBooks", "guestSpare", "garage",
            "secondaryBedroom", "kitchenNonEssentials", "primaryBedroom",
            "bathrooms", "kitchenEssentials"
        ])

        guard targetSessionMinutes > 0,
              minimumSessionMinutes > 0,
              cubicFeetPerHour > 0,
              boxEquivalentCubicFeet > 0,
              moveDayBufferDays >= 0,
              suppliesDeliveryBufferDays >= 0,
              behindPaceSessionsPerDay > 0,
              requiredMinimums.isSubset(of: minimums.keys),
              requiredWeights.isSubset(of: weights.keys)
        else { return nil }

        self.targetSessionMinutes = targetSessionMinutes
        self.minimumSessionMinutes = minimumSessionMinutes
        self.cubicFeetPerHour = cubicFeetPerHour
        self.boxEquivalentCubicFeet = boxEquivalentCubicFeet
        self.moveDayBufferDays = moveDayBufferDays
        self.suppliesDeliveryBufferDays = suppliesDeliveryBufferDays
        self.behindPaceSessionsPerDay = behindPaceSessionsPerDay
        self.minimumRoomMinutesByType = minimums
        self.sequencingWeights = weights
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}

/// Non-numeric packing classification rules. Every workload, scheduling, and
/// sequence tuning value is supplied by `appConfig/packing`.
enum PackingConstants {
    /// Decoder-only sentinel for legacy documents missing `estMinutes`.
    /// Generated sessions always receive the Firestore-configured value.
    static let targetSessionMinutes = 0

    static let storageRoomKeywords = ["storage", "attic", "basement", "cellar", "closet", "seasonal"]
    static let guestRoomKeywords = ["guest", "spare"]
    static let garageRoomKeywords = ["garage", "shed", "workshop"]
    static let secondaryBedroomKeywords = ["bedroom", "bed room", "kids", "kid's", "child", "nursery"]
    static let primaryBedroomKeywords = ["primary", "master"]
    static let bathroomKeywords = ["bathroom", "bath room", "powder", "restroom"]
    static let kitchenKeywords = ["kitchen", "pantry"]

    static let kitchenEssentialKeywords = [
        "coffee", "kettle", "toaster", "mug", "plate", "bowl", "glass", "cup",
        "fork", "spoon", "knife", "pan", "pot", "food", "snack", "water"
    ]

    static let firstNightKeywords = [
        "medication", "medicine", "charger", "toiletry", "toothbrush", "towel",
        "pajama", "clothes", "document", "pet food", "coffee"
    ]

    static let firstNightFallback =
        "Medications, chargers, toiletries, clothes, and move-day documents"

    static func minimumRoomMinutes(
        for roomName: String,
        configuration: PackingConfiguration
    ) -> Int {
        let normalized = roomName.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        )
        if kitchenKeywords.contains(where: normalized.localizedCaseInsensitiveContains) {
            return configuration.minimumRoomMinutesByType["kitchen"] ?? 0
        }
        if garageRoomKeywords.contains(where: normalized.localizedCaseInsensitiveContains) {
            return configuration.minimumRoomMinutesByType["garage"] ?? 0
        }
        if bathroomKeywords.contains(where: normalized.localizedCaseInsensitiveContains) {
            return configuration.minimumRoomMinutesByType["bathroom"] ?? 0
        }
        if primaryBedroomKeywords.contains(where: normalized.localizedCaseInsensitiveContains)
            || secondaryBedroomKeywords.contains(where: normalized.localizedCaseInsensitiveContains) {
            return configuration.minimumRoomMinutesByType["bedroom"] ?? 0
        }
        return 0
    }
}
