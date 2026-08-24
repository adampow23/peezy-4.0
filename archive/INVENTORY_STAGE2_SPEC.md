# Inventory Video Pipeline — Stage 2 Build Spec (Wire Into Peezy)

## Purpose

Take the proven, isolated inventory pipeline from Stage 1 and wire it into the live Peezy app: Peezy theming, real navigation entry point, multi-room session management, music-guided capture, and task generation integration.

## Lessons Learned from Stage 1 (PREVENT THESE)

Every phase in this spec includes explicit prevention steps for bugs encountered during Stage 1:

1. **DIRECTORY CHECK**: This script MUST run from `~/Desktop/Peezy 4.0/` (the folder containing `Peezy 4.0.xcodeproj`). Before writing ANY file, verify: `ls Peezy\ 4.0.xcodeproj` succeeds. If not, STOP and report the error.

2. **INFO.PLIST ENTRIES**: Camera and mic permissions ALREADY exist in the Info.plist (added during Stage 1). Verify they exist at the start of Phase 1 — do NOT add duplicates. Check for `NSCameraUsageDescription` and `NSMicrophoneUsageDescription`.

3. **FIREBASE STORAGE RULES**: The `inventory/` path rule ALREADY exists (added during Stage 1). Do NOT add duplicate rules.

4. **FRAME EXTRACTION**: Stage 1 fixed the sharpness scoring — the current `FrameExtractionService.swift` returns all extracted frames without filtering. Do NOT reintroduce sharpness filtering.

5. **CAMERA PREVIEW**: Stage 1 fixed the blank preview issue. Do NOT rewrite the `UIViewRepresentable` camera wrapper — modify only styling/overlay elements.

6. **CLOUD FUNCTION**: `processInventory.js` works and is deployed. Do NOT modify it in Stage 2 unless explicitly stated.

7. **API KEY**: `ANTHROPIC_API_KEY` is configured in `functions/.env`. No action needed.

8. **AUTH.CURRENTUSER**: All inventory services already use `Auth.auth().currentUser?.uid`. Do NOT change auth patterns.

9. **NAVIGATION WIRING**: Stage 1 failed to wire the test harness into navigation. Every phase in Stage 2 that creates a view MUST specify exactly where it's presented and how the user reaches it. No orphan views.

10. **BUILD VERIFICATION**: Every phase MUST run xcodebuild with the EXACT command:
    ```
    xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
    ```
    If this fails, fix the error BEFORE marking the phase complete.

## Pre-Flight Check (Run Before Phase 1)

Before starting ANY phase, execute these checks and STOP if any fail:

```bash
# 1. Verify correct directory
ls "Peezy 4.0.xcodeproj" || { echo "WRONG DIRECTORY"; exit 1; }

# 2. Verify Stage 1 files exist
ls "Peezy 4.0/Inventory/Models/InventoryModels.swift" || { echo "Stage 1 not found"; exit 1; }
ls "Peezy 4.0/Inventory/Services/FrameExtractionService.swift" || { echo "Stage 1 not found"; exit 1; }
ls "Peezy 4.0/Inventory/Services/InventoryStorageService.swift" || { echo "Stage 1 not found"; exit 1; }
ls "Peezy 4.0/Inventory/Services/InventoryAPIClient.swift" || { echo "Stage 1 not found"; exit 1; }
ls "Peezy 4.0/Inventory/Views/RoomCaptureView.swift" || { echo "Stage 1 not found"; exit 1; }
ls "Peezy 4.0/Inventory/Views/InventoryReviewView.swift" || { echo "Stage 1 not found"; exit 1; }
ls "Peezy 4.0/Inventory/ViewModels/RoomCaptureViewModel.swift" || { echo "Stage 1 not found"; exit 1; }
ls "Peezy 4.0/Inventory/ViewModels/InventoryReviewViewModel.swift" || { echo "Stage 1 not found"; exit 1; }
ls "functions/processInventory.js" || { echo "Cloud function not found"; exit 1; }

# 3. Verify current build succeeds before making changes
xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | tail -1
```

If pre-flight fails, STOP and report which check failed. Do NOT proceed.

---

## Phase 1: Apply Peezy Theming to Capture View (files: 2 modify)

**READ FIRST:** `Peezy 4.0/Inventory/Views/RoomCaptureView.swift` and `Peezy 4.0/Inventory/ViewModels/RoomCaptureViewModel.swift`. Understand the current working implementation before modifying.

**CRITICAL:** Do NOT rewrite the camera preview UIViewRepresentable or the AVCaptureSession setup. Only modify the overlay UI elements and visual styling. The camera pipeline is proven and working.

**Modify:** `Peezy 4.0/Inventory/Views/RoomCaptureView.swift`

Apply the Peezy glass card aesthetic to the capture overlay:

- **Top bar:** Room name displayed in `PeezyTheme.Typography.headline`, deep ink text on a `.regularMaterial` blurred capsule background. Close button (X) in matching style, using `PeezyTheme.Colors.deepInk.opacity(0.6)`.

- **Recording indicator:** When recording, show a subtle red dot with pulse animation next to the elapsed time. Time displayed in `PeezyTheme.Typography.calloutMedium`, monospaced. Use `PeezyTheme.Colors.emotionalRed` for the dot.

- **Record button:** Large circular button at bottom center:
  - Not recording: White circle with red inner circle, 70pt outer / 54pt inner
  - Recording: Red rounded square (stop icon) with scale animation
  - Use `.shadow(color: PeezyTheme.Shadows.cardShadowColor, radius: PeezyTheme.Shadows.cardShadowRadius)`
  - Press animation: `.scaleEffect(isPressed ? PeezyTheme.Animation.pressScale : 1.0)`

- **Pacing guide overlay:** During recording, show a subtle ring around the record button that pulses in sync with the haptic (every 0.75s). Ring uses `PeezyTheme.Colors.brandYellow.opacity(0.3)`, animates scale from 1.0 to 1.15 and back using `PeezyTheme.Animation.spring`.

- **Bottom hint text:** Below the record button, show "Pan slowly around the room" in `PeezyTheme.Typography.footnote`, `PeezyTheme.Colors.deepInk.opacity(0.4)`. Fade out after recording starts.

- **Transitions:** Use `PeezyTheme.Animation.spring` for all state transitions (idle → recording → processing).

**Modify:** `Peezy 4.0/Inventory/ViewModels/RoomCaptureViewModel.swift`

Add a bundled audio pacing guide:
- Add a property `var playPacingAudio = true`
- On recording start, if `playPacingAudio`:
  - Play a subtle metronome-like tick sound using `AVAudioPlayer`
  - Use a short system sound or bundled audio file
  - If no audio file is available, use `AudioServicesPlaySystemSound(1057)` (a subtle "tock" sound) on each haptic pulse. This is the simplest approach that requires no bundled audio files.
  - Sync with the existing haptic timer (every 0.75s)
- On recording stop, stop the audio

**DO NOT CHANGE:**
- Camera setup code
- AVCaptureSession configuration
- Frame extraction call
- Permission handling logic
- The UIViewRepresentable camera preview wrapper

**Verification:** `xcodebuild` build succeeds. Read back the modified files and confirm camera setup code was not altered.

**Mark Phase 1 complete when verification passes.**

<!-- Phase 1: COMPLETE -->

---

## Phase 2: Apply Peezy Theming to Review View (files: 2 modify)

**READ FIRST:** `Peezy 4.0/Inventory/Views/InventoryReviewView.swift` and `Peezy 4.0/Inventory/ViewModels/InventoryReviewViewModel.swift`.

**Modify:** `Peezy 4.0/Inventory/Views/InventoryReviewView.swift`

Restyle the review screen to match Peezy's existing card design language:

- **Background:** Use `InteractiveBackground()` (same as PeezyHomeView).

- **Header area:** Room name + item count in Peezy typography. "12 items in Living Room" using `PeezyTheme.Typography.title2` for the count, `PeezyTheme.Typography.callout` for the label. Subtle confetti animation on first appearance (reuse `ConfettiView` if it exists in the project — check `Peezy 4.0/` for ConfettiView.swift).

- **Item cards:** Each inventory item displayed as a glass card:
  - Use `.regularMaterial` background with `RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)`
  - White overlay at 0.15 opacity (matching `PeezyHomeView.glassCard` pattern)
  - Shadow: `PeezyTheme.Shadows.subtleShadowColor`
  - Item name in `PeezyTheme.Typography.bodyMedium`
  - Category icon: SF Symbols in `PeezyTheme.Colors.deepInk.opacity(0.5)`, size 20
  - Quantity stepper: custom stepper matching Peezy's rounded style, not the default SwiftUI `Stepper`
  - Confidence dot: small circle, colored using `PeezyTheme.Colors.successGreen` (≥0.8), `PeezyTheme.Colors.brandYellow` (≥0.5), `PeezyTheme.Colors.warningOrange` (<0.5)
  - "Moving this" toggle: use `PeezyTheme.Colors.infoBlue` for the on state
  - Swipe to delete with `PeezyTheme.Colors.emotionalRed` background

- **Add Item button:** Rounded capsule with `+` icon, uses `.regularMaterial` background with `PeezyTheme.Colors.infoBlue` tint. Triggers a sheet for manual item entry.

- **Confirm button:** Full-width at bottom, "Looks Good — {count} items" text. Background: `PeezyTheme.Gradients.brandYellow`. Text: `PeezyTheme.Colors.deepInk`. Corner radius: `PeezyTheme.Layout.cornerRadiusPill`. Shadow: `PeezyTheme.Shadows.buttonShadowColor`. Press effect: `.scaleEffect(pressed ? PeezyTheme.Animation.pressScale : 1.0)`.

- **List animations:** Items appear with staggered spring animation on load. Deletions use `.transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))`.

**Modify:** `Peezy 4.0/Inventory/ViewModels/InventoryReviewViewModel.swift`

Add these computed properties for the themed UI:
```swift
var summaryText: String {
    let count = items.count
    return "\(count) item\(count == 1 ? "" : "s") in \(roomName)"
}

var confirmButtonText: String {
    let moveCount = itemsToMove.count
    return "Looks Good — \(moveCount) item\(moveCount == 1 ? "" : "s")"
}
```

**Verification:** `xcodebuild` build succeeds.

**Mark Phase 2 complete when verification passes.**

<!-- Phase 2: COMPLETE -->

---

## Phase 3: Multi-Room Session Manager (files: 2 create)

**Create:** `Peezy 4.0/Inventory/Models/InventorySessionManager.swift`

This is the central coordinator for the entire inventory scanning experience. It manages scanning multiple rooms and aggregating results.

```swift
import FirebaseAuth
import FirebaseFirestore

@Observable
final class InventorySessionManager {
    // State
    enum FlowState {
        case roomList            // Viewing list of scanned rooms
        case enteringRoomName    // Typing a new room name
        case scanning(roomName: String)  // In RoomCaptureView
        case processing(roomName: String, progress: String)  // Uploading + AI processing
        case reviewing(roomName: String, items: [InventoryItem])  // InventoryReviewView
    }

    var state: FlowState = .roomList
    var scannedRooms: [ScannedRoom] = []  // Completed rooms
    var error: String?
    var isProcessing = false

    // Services
    private let storageService = InventoryStorageService()
    private let apiClient = InventoryAPIClient()
    private var sessionListener: Any?  // ListenerRegistration

    // Computed
    var totalItemCount: Int {
        scannedRooms.reduce(0) { $0 + $1.items.count }
    }

    var allItems: [InventoryItem] {
        scannedRooms.flatMap { $0.items }
    }

    var userId: String? {
        Auth.auth().currentUser?.uid
    }

    // Actions
    func startNewRoom(name: String) { ... }
    func handleFramesExtracted(_ frames: [ExtractedFrame], roomName: String) async { ... }
    func handleReviewConfirmed(_ items: [InventoryItem], roomName: String) { ... }
    func deleteRoom(at offsets: IndexSet) { ... }
    func saveAllToFirestore() async throws { ... }
    func reset() { ... }
}

struct ScannedRoom: Identifiable {
    let id: String  // UUID
    let name: String
    var items: [InventoryItem]
    let scannedAt: Date
}
```

The `handleFramesExtracted` method implements the full pipeline:
1. Set state to `.processing(roomName:, progress: "Uploading frames...")`
2. Call `storageService.uploadFrames(frames, userId:, roomName:)`
3. Update progress to "Analyzing room..."
4. Call `apiClient.processInventory(userId:, sessionId:, roomName:, frameCount:)`
5. Observe Firestore session document for completion
6. When complete: set state to `.reviewing(roomName:, items:)`
7. On error: set `self.error` and state to `.roomList`

The `saveAllToFirestore` method writes finalized inventory to permanent storage at `users/{userId}/inventory/rooms/{roomId}` with the full item array. This is SEPARATE from the temporary `inventorySessions` collection used during processing.

**Create:** `Peezy 4.0/Inventory/Views/RoomListView.swift`

The room list hub view showing all scanned rooms:

- Background: `InteractiveBackground()`
- Header: "Your Inventory" in `PeezyTheme.Typography.title`, centered
- Subtitle: "{totalItemCount} items across {roomCount} rooms" in `PeezyTheme.Typography.callout`
- Each scanned room displayed as a glass card row:
  - Room name in `PeezyTheme.Typography.bodyMedium`
  - Item count badge on the right
  - Tap to view items for that room
  - Swipe to delete room (with confirmation alert)
- "Scan Another Room" button: large, centered, `PeezyTheme.Colors.brandYellow` background, camera icon
- "Done — Save Inventory" button: appears when at least 1 room is scanned. Full width, `PeezyTheme.Gradients.brandYellow`. This calls `saveAllToFirestore()` and dismisses the inventory flow.
- Empty state (no rooms scanned): friendly illustration/icon + "Scan your first room to start building your inventory" + large scan button

**Navigation:** This view is the TOP-LEVEL entry point for the inventory feature. It is presented as a `.fullScreenCover` from wherever the user launches inventory scanning.

**Verification:** `xcodebuild` build succeeds.

**Mark Phase 3 complete when verification passes.**

<!-- Phase 3: COMPLETE -->

---

## Phase 4: Inventory Flow Container + Navigation Wiring (files: 2 create, 1 modify)

**Create:** `Peezy 4.0/Inventory/Views/InventoryFlowView.swift`

A container view that manages the entire inventory scanning flow based on `InventorySessionManager.state`:

```swift
struct InventoryFlowView: View {
    @State private var sessionManager = InventorySessionManager()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            switch sessionManager.state {
            case .roomList:
                RoomListView(
                    sessionManager: sessionManager,
                    onDismiss: { dismiss() }
                )

            case .enteringRoomName:
                // Room name entry overlay/sheet

            case .scanning(let roomName):
                RoomCaptureView(
                    roomName: roomName,
                    onComplete: { frames in
                        Task {
                            await sessionManager.handleFramesExtracted(frames, roomName: roomName)
                        }
                    },
                    onCancel: {
                        sessionManager.state = .roomList
                    }
                )

            case .processing(_, let progress):
                // Theatrical processing view with typewriter text
                InventoryProcessingView(progressMessage: progress)

            case .reviewing(let roomName, let items):
                InventoryReviewView(
                    items: items,
                    roomName: roomName,
                    onConfirm: { confirmedItems in
                        sessionManager.handleReviewConfirmed(confirmedItems, roomName: roomName)
                    }
                )
            }
        }
        .animation(PeezyTheme.Animation.spring, value: String(describing: sessionManager.state))
    }
}
```

**Create:** `Peezy 4.0/Inventory/Views/InventoryProcessingView.swift`

Theatrical loading screen shown during upload + AI processing:

- Background: `InteractiveBackground()`
- Center: Animated scanning icon (use SF Symbol `viewfinder` with rotation animation)
- Below: typewriter-style text that cycles through messages:
  - "Uploading frames..."
  - "Identifying furniture..."
  - "Counting items..."
  - "Checking for fragile items..."
  - "Almost done..."
- Use `PeezyTheme.Typography.title2` for the message, `PeezyTheme.Colors.deepInk`
- Subtle pulsing `PeezyTheme.Colors.brandYellow` glow behind the icon
- Use the `TypewriterText` component if it exists in the project (check for TypewriterText.swift or TypingText.swift). If it exists, USE IT. If not, implement a simple character-by-character animation.

**Modify:** `Peezy 4.0/Inventory/Views/RoomCaptureView.swift`

Add an `onCancel: () -> Void` callback parameter so the user can back out of recording and return to the room list. Add a close/back button in the top-left corner that calls `onCancel`. Ensure this does NOT break the existing `onComplete` callback flow.

**NAVIGATION WIRING — CRITICAL:**

**Modify:** `PeezySettingsView.swift`

Replace the existing `#if DEBUG` "Test Inventory Scanner" button (from Stage 1) with a production-ready entry point:

```swift
// In the support section or as its own section, ADD:
settingsRow(icon: "camera.viewfinder", label: "Scan Room Inventory", color: PeezyTheme.Colors.infoBlue) {
    showInventoryScanner = true
}

// Add state variable at the top of PeezySettingsView:
@State private var showInventoryScanner = false

// Add sheet modifier to the outermost ZStack:
.fullScreenCover(isPresented: $showInventoryScanner) {
    InventoryFlowView()
}
```

This is NOT behind a `#if DEBUG` flag — it's a real feature entry point accessible from Settings. ALSO keep the `#if DEBUG` test harness button separately if it exists, but the new production button is in addition to it.

**WHY fullScreenCover and not sheet:** The camera requires full screen. Sheet presentation clips the camera preview and causes layout issues on devices with home indicators.

**Verification:**
1. `xcodebuild` build succeeds
2. Read `PeezySettingsView.swift` and confirm both the `@State` variable and `.fullScreenCover` modifier exist
3. Read `InventoryFlowView.swift` and confirm it handles ALL five `FlowState` cases

**Mark Phase 4 complete when ALL verifications pass.**

<!-- Phase 4: COMPLETE -->

---

## Phase 5: Update Task Catalog with Inventory Task (files: 2 modify)

**Modify:** `functions/taskCatalogData.json`

Add a new task entry to the JSON array for the inventory scanning feature. This task replaces the existing `INVENTORY_BELONGINGS` task (which tells users to manually take photos). Find the `INVENTORY_BELONGINGS` entry and REPLACE it with:

```json
{
  "taskId": "INVENTORY_BELONGINGS",
  "title": "Create moving inventory",
  "actionCategory": "document-record",
  "category": "packing",
  "actionType": "in-app-inventory",
  "conditions": {
    "hireMovers": ["Yes"]
  },
  "desc": "Scan each room with your camera to build a complete inventory of everything you're moving. This helps movers give accurate quotes and protects you if anything is damaged.",
  "estHours": 0.5,
  "tips": "Go room by room — it takes about 20 seconds per room. Pan slowly and the AI will identify your furniture and belongings automatically.",
  "urgencyPercentage": 55,
  "whyNeeded": "An accurate inventory prevents surprise charges on moving day and gives you documentation for insurance claims if anything is lost or damaged."
}
```

Note: `actionType` is `"in-app-inventory"` — a new action type that the iOS app will recognize to launch the inventory scanner instead of a workflow or off-app task.

**Modify:** `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift`

READ THIS FILE FIRST. Find where the view model handles different `actionType` values to determine what happens when a user taps a task card. Add handling for the new `"in-app-inventory"` action type:

- When a task card with `actionType == "in-app-inventory"` is tapped/started, set a published flag that the view can observe to present the inventory scanner
- Add: `var showInventoryScanner = false`
- In whatever method handles task card actions (look for where `actionType` is checked — it might be in `startWorkflowForCurrentTask()` or a similar method), add:
  ```swift
  if task.actionType == "in-app-inventory" {
      showInventoryScanner = true
      return
  }
  ```

**Modify:** `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift`

READ THIS FILE FIRST. Add a `.fullScreenCover` modifier that observes `viewModel.showInventoryScanner`:

```swift
.fullScreenCover(isPresented: $viewModel.showInventoryScanner) {
    InventoryFlowView()
}
```

Place this modifier on the outermost container in the body (same level as other sheet/fullScreenCover modifiers). When the inventory flow is dismissed, the task card should still be visible — the user can mark it complete after reviewing their inventory.

**ALSO:** After the inventory flow is dismissed, check if `InventorySessionManager` saved inventory data. If rooms were scanned, auto-complete the task:
```swift
.fullScreenCover(isPresented: $viewModel.showInventoryScanner, onDismiss: {
    // Check if inventory was actually created
    // If so, mark the current task as complete
    if let task = viewModel.currentTask, task.actionType == "in-app-inventory" {
        viewModel.completeCurrentTask()
    }
})
```

Read PeezyHomeViewModel to find the correct method name for completing tasks — it might be `completeCurrentTask()` or `markCurrentTaskComplete()` or similar. Use the actual method name.

**Verification:**
1. `xcodebuild` build succeeds
2. Read `taskCatalogData.json` and confirm `INVENTORY_BELONGINGS` has `actionType: "in-app-inventory"`
3. Read `PeezyHomeViewModel.swift` and confirm `showInventoryScanner` property exists
4. Read `PeezyHomeView.swift` and confirm `.fullScreenCover` for inventory exists

**After build verification, re-seed the task catalog:**
```bash
cd functions && node seedTaskCatalog.js
```

**Mark Phase 5 complete when ALL verifications pass.**

<!-- Phase 5: COMPLETE -->

---

## Phase 6: Inventory Data → Moving Estimates (files: 1 create)

**Create:** `Peezy 4.0/Inventory/Services/InventoryEstimator.swift`

A pure calculation service that converts inventory items into moving logistics estimates. This is where the `sizeEstimate` values become meaningful.

```swift
struct MovingEstimate {
    let totalCubicFeet: Double
    let estimatedBoxes: Int
    let recommendedTruckSize: String  // "Pickup truck", "10-ft", "15-ft", "20-ft", "26-ft"
    let estimatedLaborHours: Double
    let fragileItemCount: Int
    let highValueItemCount: Int
    let totalItemCount: Int
    let roomCount: Int
}

enum InventoryEstimator {

    // Size → cubic feet mapping
    static let cubicFeetPerSize: [String: Double] = [
        "small": 3.0,      // Lamp, small table, box
        "medium": 12.0,    // Dresser, desk, armchair
        "large": 40.0,     // Sofa, dining table, bookshelf
        "oversized": 70.0  // Sectional, piano, large armoire
    ]

    static func estimate(from rooms: [ScannedRoom]) -> MovingEstimate {
        let allItems = rooms.flatMap { $0.items }.filter { $0.shouldMove }

        // Calculate cubic feet
        let totalCF = allItems.reduce(0.0) { total, item in
            let cfPerItem = cubicFeetPerSize[item.sizeEstimate] ?? 12.0
            return total + (cfPerItem * Double(item.quantity))
        }

        // Packing efficiency factor (80% — items don't pack perfectly)
        let adjustedCF = totalCF / 0.80

        // Truck recommendation based on adjusted cubic feet
        let truck: String
        switch adjustedCF {
        case ..<150:    truck = "Pickup truck or cargo van"
        case ..<300:    truck = "10-ft truck"
        case ..<500:    truck = "15-ft truck"
        case ..<800:    truck = "20-ft truck"
        case ..<1200:   truck = "26-ft truck"
        default:        truck = "Multiple trucks needed"
        }

        // Box estimate: ~3.5 cubic feet per medium box, roughly 1 box per small item, 0.5 per medium
        let boxes = allItems.reduce(0) { total, item in
            let boxesPerItem: Int
            switch item.sizeEstimate {
            case "small": boxesPerItem = 1
            case "medium": boxesPerItem = 0  // Medium items don't go in boxes
            case "large": boxesPerItem = 0
            case "oversized": boxesPerItem = 0
            default: boxesPerItem = 1
            }
            return total + (boxesPerItem * item.quantity)
        }
        // Add ~30% for miscellaneous items not captured in scan (clothes, kitchen, etc.)
        let adjustedBoxes = Int(Double(max(boxes, 5)) * 1.3)

        // Labor hours: base 2hrs + 0.5hr per 100 cubic feet
        let laborHours = 2.0 + (adjustedCF / 100.0 * 0.5)

        return MovingEstimate(
            totalCubicFeet: adjustedCF.rounded(),
            estimatedBoxes: adjustedBoxes,
            recommendedTruckSize: truck,
            estimatedLaborHours: (laborHours * 2).rounded() / 2,  // Round to nearest 0.5
            fragileItemCount: allItems.filter { $0.isFragile }.count,
            highValueItemCount: allItems.filter { $0.isHighValue }.count,
            totalItemCount: allItems.reduce(0) { $0 + $1.quantity },
            roomCount: rooms.count
        )
    }
}
```

**Verification:** `xcodebuild` build succeeds.

**Mark Phase 6 complete when verification passes.**

<!-- Phase 6: COMPLETE -->

---

## Phase 7: Moving Estimate Summary View (files: 1 create, 1 modify)

**Create:** `Peezy 4.0/Inventory/Views/InventoryEstimateView.swift`

A summary card shown after all rooms are scanned and confirmed, before saving. This is the "wow" moment — the user sees what their inventory means for their move.

Layout:
- Background: `InteractiveBackground()`
- Top section: "Your Moving Estimate" in `PeezyTheme.Typography.title`
- Main stat cards in a 2x2 grid, each as a glass card:
  - **Truck:** icon `truck.box.fill`, recommended truck size, `PeezyTheme.Colors.infoBlue`
  - **Volume:** icon `cube.fill`, total cubic feet, `PeezyTheme.Colors.brandYellow`
  - **Boxes:** icon `shippingbox.fill`, estimated box count, `PeezyTheme.Colors.successGreen`
  - **Labor:** icon `clock.fill`, estimated hours, `PeezyTheme.Colors.supportPurple`
- Below grid: warning badges if applicable:
  - "{count} fragile items — consider specialty packing" (if fragileItemCount > 0)
  - "{count} high-value items — consider moving insurance" (if highValueItemCount > 0)
- Disclaimer text: "Estimates are based on your scanned inventory. Actual costs depend on distance, access, and seasonal pricing." in `PeezyTheme.Typography.footnote`, muted.
- "Save & Finish" button: `PeezyTheme.Gradients.brandYellow`, calls `onSave`
- "Scan More Rooms" button: secondary style, calls `onScanMore`

**Modify:** `Peezy 4.0/Inventory/Views/RoomListView.swift`

When the user taps "Done — Save Inventory", instead of immediately saving and dismissing, first navigate to `InventoryEstimateView` to show the moving estimate summary. The estimate view's "Save & Finish" button then triggers the actual save and dismiss.

Update the flow in `InventoryFlowView.swift` — add a new state case if needed:
- After all rooms are confirmed → show `InventoryEstimateView`
- "Save & Finish" → `sessionManager.saveAllToFirestore()` → dismiss

**Verification:** `xcodebuild` build succeeds.

**Mark Phase 7 complete when verification passes.**

<!-- Phase 7: COMPLETE -->

---

## Phase 8: Firestore Security Rules + Final Verification (files: 1 modify)

**Modify:** Firebase Firestore security rules

READ the current `firestore.rules` file first. Add a rule for the permanent inventory storage path:

```
match /users/{userId}/inventory/{document=**} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

This is for the permanent inventory data written by `saveAllToFirestore()`. The `inventorySessions` path should already have a rule from Stage 1 — verify it exists, add if missing:

```
match /users/{userId}/inventorySessions/{document=**} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

Deploy rules:
```bash
firebase deploy --only firestore:rules --project peezy-1ecrdl
```

**Final Verification Checklist:**

1. `xcodebuild` build succeeds
2. `cd functions && node -e "require('./index')"` — no errors
3. Verify these files were CREATED in Stage 2:
   - `Peezy 4.0/Inventory/Models/InventorySessionManager.swift`
   - `Peezy 4.0/Inventory/Views/RoomListView.swift`
   - `Peezy 4.0/Inventory/Views/InventoryFlowView.swift`
   - `Peezy 4.0/Inventory/Views/InventoryProcessingView.swift`
   - `Peezy 4.0/Inventory/Views/InventoryEstimateView.swift`
   - `Peezy 4.0/Inventory/Services/InventoryEstimator.swift`
4. Verify these files were MODIFIED in Stage 2:
   - `Peezy 4.0/Inventory/Views/RoomCaptureView.swift` (theming + onCancel)
   - `Peezy 4.0/Inventory/Views/InventoryReviewView.swift` (theming)
   - `Peezy 4.0/Inventory/ViewModels/InventoryReviewViewModel.swift` (computed properties)
   - `Peezy 4.0/Inventory/ViewModels/RoomCaptureViewModel.swift` (audio pacing)
   - `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift` (fullScreenCover for inventory)
   - `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift` (showInventoryScanner flag)
   - `PeezySettingsView.swift` (production scan button)
   - `functions/taskCatalogData.json` (INVENTORY_BELONGINGS updated)
5. Verify these files were NOT modified:
   - `functions/index.js`
   - `functions/peezyBrain.js`
   - `functions/processInventory.js`
   - `AppRootView.swift`
   - `PeezyMainContainer.swift`
   - All assessment files

**Mark Phase 8 complete when ALL verifications pass.**

<!-- Phase 8: COMPLETE -->

---

## Files Summary

### Created (6 files)
| File | Purpose |
|------|---------|
| `Peezy 4.0/Inventory/Models/InventorySessionManager.swift` | Multi-room session coordinator |
| `Peezy 4.0/Inventory/Views/RoomListView.swift` | Room list hub view |
| `Peezy 4.0/Inventory/Views/InventoryFlowView.swift` | Flow container managing all states |
| `Peezy 4.0/Inventory/Views/InventoryProcessingView.swift` | Theatrical loading screen |
| `Peezy 4.0/Inventory/Views/InventoryEstimateView.swift` | Moving estimate summary |
| `Peezy 4.0/Inventory/Services/InventoryEstimator.swift` | Cubic feet + logistics calculator |

### Modified (8 files)
| File | What Changed |
|------|-------------|
| `RoomCaptureView.swift` | Peezy theming + onCancel + pacing ring |
| `RoomCaptureViewModel.swift` | Audio pacing on record |
| `InventoryReviewView.swift` | Full Peezy glass card restyle |
| `InventoryReviewViewModel.swift` | Summary computed properties |
| `PeezyHomeView.swift` | fullScreenCover for inventory task |
| `PeezyHomeViewModel.swift` | showInventoryScanner + actionType handling |
| `PeezySettingsView.swift` | Production scan button |
| `taskCatalogData.json` | INVENTORY_BELONGINGS updated to in-app |
