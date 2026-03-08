# Inventory Video Pipeline — Stage 2 Outline (Wire Into Peezy)

> **Do NOT execute Stage 2 until Stage 1 is validated on a real device.**
> You should have successfully recorded a room, processed it through the pipeline,
> and reviewed an accurate inventory list before proceeding.

## What Stage 2 Does

Takes the proven, isolated inventory pipeline from Stage 1 and wires it into the live Peezy app:
navigation, theming, task generation integration, and persistent storage.

## Phase 1: Apply Peezy Theming to Inventory Views

- Update `RoomCaptureView.swift` with the glass card aesthetic, liquid glass overlays, Peezy branding
- Update `InventoryReviewView.swift` with branded item cards, PeezyTheme colors throughout
- Add spring animations (PeezyTheme.Animation.spring) to all state transitions
- Replace the haptic-only pacing with bundled ambient music track + synced haptics

## Phase 2: Add "Scan Rooms" to Peezy Navigation

- Add a new `PeezyDestination.inventory` case to the menu
- Wire into `PeezyMainContainer.swift` with a new tab/menu option
- OR: Surface inventory scanning as a task card in the card stack (e.g., "Create your moving inventory")
- Add the inventory entry point to the task catalog as a new task type with `actionType: "inventory-scan"`

## Phase 3: Multi-Room Session Management

- Create `InventorySessionManager` that tracks all rooms scanned for a move
- Room list view showing completed rooms with item counts
- "Add Room" flow that loops back to capture after each room confirmation
- Aggregate inventory view across all rooms
- Persistent storage in Firestore at `users/{userId}/rooms/{roomId}/inventory`

## Phase 4: Task Generation Integration

- Use aggregate inventory data to influence task generation:
  - Total cubic feet → truck size recommendation task
  - Fragile item count → packing supplies task
  - High-value item count → moving insurance task
  - Room count → cleaning estimate task
- Create new catalog tasks that only generate when inventory data exists
- Condition key: `hasInventory: ["Yes"]`

## Phase 5: ISP & Vendor Integration

- Use inventory volume data in vendor workflow qualifying (e.g., mover quotes)
- Pre-fill mover quote requests with room-by-room item counts
- Surface inventory summary in relevant workflow cards

## Phase 6: Polish & Production Hardening

- Add `enforceAppCheck: true` to the Cloud Function
- Implement Storage lifecycle rules to auto-delete frame images after 30 days
- Add cost tracking/limits (max frames per session, max sessions per user)
- Firebase security rules for `inventorySessions` collection
- Error analytics and retry logic
- Accessibility: VoiceOver labels on all inventory UI elements
