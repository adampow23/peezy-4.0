import SwiftUI

@Observable
final class InventoryReviewViewModel {
    var items: [InventoryItem]
    var roomName: String
    var isEditing = false
    var showAddItem = false

    init(items: [InventoryItem], roomName: String) {
        self.items = items
        self.roomName = roomName
    }

    func deleteItem(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    func toggleShouldMove(for item: InventoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].shouldMove.toggle()
    }

    func updateQuantity(for item: InventoryItem, newQuantity: Int) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].quantity = max(1, newQuantity)
    }

    func addManualItem(name: String, category: String, size: String, tier: String) {
        let item = InventoryItem(
            id: UUID().uuidString,
            name: name,
            category: category,
            tier: tier,
            quantity: 1,
            sizeEstimate: size,
            cubicFeet: 0,
            isFragile: false,
            isHighValue: false,
            confidence: 1.0,
            frameIndex: nil,
            boundingBox: nil,
            roomName: roomName,
            shouldMove: true,
            notes: ""
        )
        items.append(item)
    }

    // MARK: - Tier-based filtering

    var furnitureItems: [InventoryItem] {
        items.filter { $0.tier == "furniture" }
    }

    var boxableItems: [InventoryItem] {
        items.filter { $0.tier == "boxable" }
    }

    var furnitureToMove: [InventoryItem] {
        furnitureItems.filter { $0.shouldMove }
    }

    var boxableToMove: [InventoryItem] {
        boxableItems.filter { $0.shouldMove }
    }

    // MARK: - Box estimate for this room's boxable items

    var boxableCubicFeet: Double {
        boxableToMove.reduce(0.0) { total, item in
            let cf = item.cubicFeet > 0 ? item.cubicFeet : fallbackCubicFeet(for: item.sizeEstimate)
            return total + (cf * Double(item.quantity))
        }
    }

    var boxEstimateLow: Int {
        max(1, Int((boxableCubicFeet / 3.0 * 0.85).rounded()))
    }

    var boxEstimateHigh: Int {
        max(1, Int((boxableCubicFeet / 3.0 * 1.15).rounded(.up)))
    }

    var boxEstimateDescription: String {
        if boxableToMove.isEmpty { return "No boxes needed" }
        if boxEstimateLow == boxEstimateHigh {
            return "~\(boxEstimateLow) box\(boxEstimateLow == 1 ? "" : "es")"
        }
        return "~\(boxEstimateLow)–\(boxEstimateHigh) boxes"
    }

    // MARK: - Counts

    var itemsToMove: [InventoryItem] { items.filter { $0.shouldMove } }
    var totalItemCount: Int { items.reduce(0) { $0 + $1.quantity } }

    var summaryText: String {
        let count = items.count
        return "\(count) item\(count == 1 ? "" : "s") in \(roomName)"
    }

    var confirmButtonText: String {
        let moveCount = itemsToMove.count
        return "Looks Good — \(moveCount) item\(moveCount == 1 ? "" : "s")"
    }

    // MARK: - Helpers

    private func fallbackCubicFeet(for size: String) -> Double {
        switch size {
        case "small": return 3.0
        case "medium": return 12.0
        case "large": return 40.0
        case "oversized": return 70.0
        default: return 12.0
        }
    }
}
