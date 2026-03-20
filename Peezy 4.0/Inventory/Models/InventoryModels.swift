import Foundation

struct InventoryItem: Codable, Identifiable {
    var id: String                    // UUID string
    var name: String                  // "Sofa", "Dining Table", "Books (approx 50)", etc.
    var category: String              // "furniture", "electronics", "boxes", "appliance", "decor", "other"
    var tier: String                  // "furniture" = movers handle individually, "boxable" = aggregate for box estimate
    var quantity: Int                 // Count (default 1)
    var sizeEstimate: String          // "small", "medium", "large", "oversized"
    var cubicFeet: Double             // Estimated cubic footage per unit
    var isFragile: Bool               // LLM's assessment
    var isHighValue: Bool             // LLM's assessment
    var confidence: Double            // 0.0-1.0 from LLM
    var frameIndex: Int?              // Which frame this item is most visible in (0-based)
    var boundingBox: BoundingBox?     // Normalized coordinates for cropping from source frame
    var roomName: String              // Which room this was scanned in
    var shouldMove: Bool              // User toggle, default true
    var notes: String                 // User-editable notes, default ""
}

struct BoundingBox: Codable {
    var x: Double      // Left edge, 0.0-1.0 normalized
    var y: Double      // Top edge, 0.0-1.0 normalized
    var width: Double   // Width, 0.0-1.0 normalized
    var height: Double  // Height, 0.0-1.0 normalized
}

struct InventoryScanSession: Codable, Identifiable {
    var id: String                    // Session UUID
    var userId: String
    var roomName: String
    var status: ScanStatus            // .uploading, .processing, .complete, .error
    var frameCount: Int
    var items: [InventoryItem]        // Empty until processing completes
    var errorMessage: String?
    var createdAt: Date
    var completedAt: Date?

    enum ScanStatus: String, Codable {
        case uploading, processing, complete, error
    }

    static func newSession(userId: String, roomName: String) -> InventoryScanSession {
        InventoryScanSession(
            id: UUID().uuidString,
            userId: userId,
            roomName: roomName,
            status: .uploading,
            frameCount: 0,
            items: [],
            errorMessage: nil,
            createdAt: Date(),
            completedAt: nil
        )
    }
}
