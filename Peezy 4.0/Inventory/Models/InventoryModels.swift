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

extension InventoryItem {
    func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "category": category,
            "tier": tier,
            "quantity": quantity,
            "sizeEstimate": sizeEstimate,
            "cubicFeet": cubicFeet,
            "isFragile": isFragile,
            "isHighValue": isHighValue,
            "confidence": confidence,
            "roomName": roomName,
            "shouldMove": shouldMove,
            "notes": notes
        ]

        if let frameIndex {
            dict["frameIndex"] = frameIndex
        }

        if let boundingBox {
            dict["boundingBox"] = [
                "x": boundingBox.x,
                "y": boundingBox.y,
                "width": boundingBox.width,
                "height": boundingBox.height
            ]
        }

        return dict
    }

    static func from(dict: [String: Any]) -> InventoryItem? {
        guard let name = dict["name"] as? String else { return nil }

        let boundingBox: BoundingBox?
        if let boundingBoxDict = dict["boundingBox"] as? [String: Any] {
            boundingBox = BoundingBox(
                x: doubleValue(for: boundingBoxDict["x"], defaultValue: 0),
                y: doubleValue(for: boundingBoxDict["y"], defaultValue: 0),
                width: doubleValue(for: boundingBoxDict["width"], defaultValue: 0),
                height: doubleValue(for: boundingBoxDict["height"], defaultValue: 0)
            )
        } else {
            boundingBox = nil
        }

        return InventoryItem(
            id: dict["id"] as? String ?? UUID().uuidString,
            name: name,
            category: dict["category"] as? String ?? "other",
            tier: dict["tier"] as? String ?? "boxable",
            quantity: intValue(for: dict["quantity"], defaultValue: 1),
            sizeEstimate: dict["sizeEstimate"] as? String ?? "medium",
            cubicFeet: doubleValue(for: dict["cubicFeet"], defaultValue: 0),
            isFragile: dict["isFragile"] as? Bool ?? false,
            isHighValue: dict["isHighValue"] as? Bool ?? false,
            confidence: doubleValue(for: dict["confidence"], defaultValue: 0.5),
            frameIndex: optionalIntValue(for: dict["frameIndex"]),
            boundingBox: boundingBox,
            roomName: dict["roomName"] as? String ?? "",
            shouldMove: dict["shouldMove"] as? Bool ?? true,
            notes: dict["notes"] as? String ?? ""
        )
    }

    private static func intValue(for value: Any?, defaultValue: Int) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return defaultValue
    }

    private static func optionalIntValue(for value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func doubleValue(for value: Any?, defaultValue: Double) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return defaultValue
    }
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
