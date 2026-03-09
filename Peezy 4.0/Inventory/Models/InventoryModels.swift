import Foundation

struct InventoryItem: Codable, Identifiable {
    var id: String                    // UUID string
    var name: String                  // "Sofa", "Dining Table", etc.
    var category: String              // "furniture", "electronics", "boxes", "appliance", "decor", "other"
    var quantity: Int                  // Count (default 1)
    var sizeEstimate: String          // "small", "medium", "large", "oversized"
    var isFragile: Bool               // LLM's assessment
    var isHighValue: Bool             // LLM's assessment
    var confidence: Double            // 0.0-1.0 from LLM
    var roomName: String              // Which room this was scanned in
    var shouldMove: Bool              // User toggle, default true
    var notes: String                 // User-editable notes, default ""
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
