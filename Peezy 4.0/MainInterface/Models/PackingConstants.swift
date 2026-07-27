import Foundation

/// Packing-plan constants. Room order is LOCKED by Spec 06; the workload
/// conversion is centralized here and remains pending field calibration.
enum PackingConstants {
    static let targetSessionMinutes = 40
    static let minimumSessionMinutes = 20
    static let minutesPerBoxEquivalent = 4
    static let cubicFeetPerBoxEquivalent = 3.0

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
}
