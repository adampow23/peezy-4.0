# RoomPlan Inventory System - Integration Guide

## Overview

This guide shows how to integrate the new RoomPlan inventory system with your existing room scanning flow.

## System Components

### 1. Data Model (`InventoryItem.swift`)
- **InventoryItem**: Main model with 3D spatial data, moving logistics, and metadata
- **Dimensions**: Width, height, depth in meters (with cubic feet conversion)
- **Position3D**: X, Y, Z coordinates in AR space
- **ItemType**: Enum with all supported furniture types
- **ItemSource**: Tracks whether item came from RoomPlan or manual tap

### 2. Parser Service (`RoomPlanParser.swift`)
- **parseInventory()**: Main entry point - takes CapturedRoom and returns [InventoryItem]
- Automatically infers subtypes from dimensions (e.g., bed width → Queen/King)
- Groups similar items and combines counts
- Preserves full 3D spatial data and confidence scores

### 3. Views
- **ReceiptCheckView**: Confirmation UI with edit controls
- **TapToTagARView**: AR interface for adding missed items
- **Supporting Components**: InventoryItemRow, ToggleChip, ItemPickerSheet, QuickAddChip

### 4. Firebase Service (`InventoryFirebaseService.swift`)
- **saveItems()**: Batch save all items
- **fetchItems()**: Get all items for a room
- **updateItem()**: Update single item
- **deleteItem()**: Remove item
- **Queries**: fetchItemsToMove(), calculateTotalVolume()

## Integration Steps

### Step 1: When RoomPlan Scan Completes

In your existing RoomPlan completion handler (likely in RoomScanCoordinator or similar):

```swift
import RoomPlan

// In your RoomPlan capture completion handler
func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
    guard error == nil else {
        // Handle error
        return
    }

    // Get the final CapturedRoom
    let capturedRoom = data.finalize()

    // 🆕 Parse RoomPlan results into inventory items
    let inventoryItems = RoomPlanParser.parseInventory(
        from: capturedRoom,
        roomId: currentRoomId, // Your existing room ID
        roomName: currentRoomName // Your existing room name
    )

    // 🆕 Present the receipt check view
    presentReceiptCheck(items: inventoryItems, capturedRoom: capturedRoom)
}
```

### Step 2: Present ReceiptCheckView

```swift
@State private var inventoryItems: [InventoryItem] = []
@State private var showReceiptCheck = false

func presentReceiptCheck(items: [InventoryItem], capturedRoom: CapturedRoom) {
    self.inventoryItems = items
    self.showReceiptCheck = true
}

// In your view body
.sheet(isPresented: $showReceiptCheck) {
    ReceiptCheckView(
        items: $inventoryItems,
        roomId: currentRoom.id,
        roomName: currentRoom.name,
        capturedRoom: capturedRoom,
        onConfirm: { confirmedItems in
            // Items are already saved to Firebase by ReceiptCheckView
            print("✅ User confirmed \(confirmedItems.count) items")

            // Update room as scanned
            currentRoom.isScanned = true

            // Navigate to next step or dismiss
            dismiss()
        }
    )
}
```

### Step 3: Access Inventory Data Later

When you need to show or use the inventory (e.g., in a room detail view):

```swift
@State private var inventoryService = InventoryFirebaseService()

// Fetch inventory for a room
Task {
    await inventoryService.fetchItems(roomId: room.id)

    // Use inventoryService.items
    let itemCount = inventoryService.items.count
    let totalVolume = inventoryService.items.reduce(0) { $0 + $1.volumeCubicFeet }
}
```

### Step 4: Calculate Moving Estimates

Use the inventory data for moving calculations:

```swift
// Get all items that should be moved (not skipped or sold)
let itemsToMove = inventoryItems.filter { $0.shouldMove }

// Calculate total cubic feet
let totalCubicFeet = itemsToMove.reduce(0) { total, item in
    total + (item.volumeCubicFeet * Float(item.count))
}

// Estimate truck size (example logic)
let truckSize: String
if totalCubicFeet < 300 {
    truckSize = "Small truck (10-14 ft)"
} else if totalCubicFeet < 600 {
    truckSize = "Medium truck (16-20 ft)"
} else if totalCubicFeet < 1000 {
    truckSize = "Large truck (24-26 ft)"
} else {
    truckSize = "Multiple trucks needed"
}

// Count fragile/high-value items for moving prep
let fragileCount = itemsToMove.filter { $0.isFragile }.count
let highValueCount = itemsToMove.filter { $0.isHighValue }.count
```

## Example: Complete Integration in RoomScanCoordinator

Here's a complete example of how your RoomScanCoordinator might look:

```swift
import SwiftUI
import RoomPlan

@Observable
class RoomScanCoordinator {
    var currentRoom: Room?
    var capturedRoom: CapturedRoom?
    var inventoryItems: [InventoryItem] = []
    var showReceiptCheck = false

    // Called when RoomPlan scanning completes
    func handleScanCompletion(_ data: CapturedRoomData) {
        let finalizedRoom = data.finalize()
        self.capturedRoom = finalizedRoom

        guard let room = currentRoom else { return }

        // Parse RoomPlan results
        inventoryItems = RoomPlanParser.parseInventory(
            from: finalizedRoom,
            roomId: room.id,
            roomName: room.name
        )

        // Show receipt check
        showReceiptCheck = true
    }

    // Called when user confirms items in receipt check
    func handleInventoryConfirmation(_ items: [InventoryItem]) {
        print("✅ User confirmed \(items.count) items")

        // Mark room as scanned
        currentRoom?.isScanned = true

        // Items are already saved to Firebase
        // You can now show a success message or navigate
    }
}

// In your view:
struct RoomScanView: View {
    @State private var coordinator = RoomScanCoordinator()

    var body: some View {
        // Your RoomPlan view here
        RoomCaptureView()
            .sheet(isPresented: $coordinator.showReceiptCheck) {
                if let room = coordinator.currentRoom {
                    ReceiptCheckView(
                        items: $coordinator.inventoryItems,
                        roomId: room.id,
                        roomName: room.name,
                        capturedRoom: coordinator.capturedRoom,
                        onConfirm: coordinator.handleInventoryConfirmation
                    )
                }
            }
    }
}
```

## Data Flow Diagram

```
RoomPlan Scan
     ↓
CapturedRoom Data
     ↓
RoomPlanParser.parseInventory()
     ↓
[InventoryItem] Array
     ↓
ReceiptCheckView (user reviews/edits)
     ├─ User can adjust subtypes, counts, flags
     ├─ User can add more items via TapToTagARView
     └─ User clicks "Looks Good"
         ↓
InventoryFirebaseService.saveItems()
     ↓
Firestore: users/{userId}/rooms/{roomId}/inventory/{itemId}
```

## Firebase Schema

```
users/
  {userId}/
    rooms/
      {roomId}/
        inventory/
          {itemId}/
            - id: String
            - type: String (bed, sofa, table, etc.)
            - subtype: String (Queen, 3-Seat, etc.)
            - count: Int
            - roomId: String
            - roomName: String
            - dimensions: {width, height, depth}
            - position: {x, y, z}
            - confidence: Float
            - skipMoving: Bool
            - alreadySold: Bool
            - isFragile: Bool
            - isHighValue: Bool
            - source: String (roomplan, manual_tap)
            - createdAt: Timestamp
            - updatedAt: Timestamp
```

## Advanced Features

### Custom Item Types

To add new item types, edit `ItemType` enum in `InventoryItem.swift`:

```swift
case newType

var displayName: String {
    case .newType: return "New Type"
}

var icon: String {
    case .newType: return "icon.name"
}

var subtypes: [String] {
    case .newType: return ["Subtype 1", "Subtype 2"]
}
```

### Dimension-Based Logic

The system automatically infers subtypes from dimensions. To customize this logic, edit `ItemType.inferredSubtype()`:

```swift
case .yourType:
    let widthFeet = dims.widthFeet
    if widthFeet < 3.0 { return "Small" }
    else if widthFeet < 6.0 { return "Medium" }
    else { return "Large" }
```

### AR Improvements

For more accurate item sizing in TapToTagARView:

1. Use depth data from ARKit to estimate bounding box
2. Let user adjust size with pinch gestures
3. Show visual preview of item size in AR

See `TapToTagARView.swift` comments for implementation notes.

## Troubleshooting

### Items not appearing in ReceiptCheckView
- Check that RoomPlan actually detected objects (try scanning in good lighting)
- Verify `RoomPlanParser.mapSurfaceCategory()` and `mapObjectCategory()` are returning ItemTypes
- Add debug prints to see what RoomPlan detected

### AR tap not working
- Ensure device has LiDAR scanner (iPhone 12 Pro or later)
- Check camera permissions in Info.plist
- Verify ARKit session is running with `.sceneReconstruction = .meshWithClassification`

### Firebase errors
- Confirm user is authenticated (`Auth.auth().currentUser != nil`)
- Check Firebase rules allow writes to `users/{userId}/rooms/{roomId}/inventory`
- Verify InventoryItem conforms to Codable correctly

## Next Steps

1. **Integrate with task generation**: Use inventory data to create moving tasks
   - Pack X boxes for Y items
   - Hire movers based on total volume
   - Schedule furniture disassembly for large items

2. **Add 3D visualization**: Show items in a 3D room view using their position data

3. **ML improvements**: Use RoomPlan confidence scores to prompt user for low-confidence items

4. **Moving day checklist**: Generate item-by-item checklist from inventory

## Support

All components follow your existing Peezy design patterns:
- ✅ Brand yellow accent color (RGB: 0.98, 0.85, 0.29)
- ✅ Haptic feedback (light/medium/success)
- ✅ Spring animations (response: 0.3-0.6, damping: 0.6-0.8)
- ✅ Firebase integration matching your schema patterns
- ✅ @Observable pattern for view models
- ✅ SwiftUI best practices

For questions or issues, refer to individual file comments or this guide.
