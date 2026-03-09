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

    func addManualItem(name: String, category: String, size: String) {
        let item = InventoryItem(
            id: UUID().uuidString,
            name: name,
            category: category,
            quantity: 1,
            sizeEstimate: size,
            isFragile: false,
            isHighValue: false,
            confidence: 1.0,
            roomName: roomName,
            shouldMove: true,
            notes: ""
        )
        items.append(item)
    }

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
}
