# Inventory Video Pipeline — Stage 1 Build Spec (Proof-of-Life)

## Purpose

Build a standalone video-to-inventory pipeline within the existing Peezy project. The user records a room-by-room video guided by soft music, the app extracts sharp frames, uploads them to Firebase Storage, calls a Cloud Function that sends frames to Claude's vision API, and displays the AI-generated inventory for the user to review and edit.

Stage 1 is a proof-of-life. It creates isolated files that DO NOT wire into the main Peezy navigation. A temporary test harness view (`InventoryTestHarness.swift`) lets you launch the full pipeline on a real device. Once validated, Stage 2 (separate spec) wires the proven components into the real app.

## Architecture Decisions (LOCKED — Do Not Deviate)

- **Frame extraction happens on-device** using AVFoundation's `AVAssetImageGenerator`. The app records video, then extracts ~8-10 JPEG frames at fixed intervals. Only sharp frames (Laplacian variance > threshold) are kept.
- **Frames upload to Firebase Storage** at path `inventory/{userId}/{sessionId}/frame_{index}.jpg`. Compressed JPEG quality 0.7 at 720p max dimension.
- **Cloud Function is `onCall` (v2)**, NOT a Storage trigger. Called explicitly with `{userId, sessionId, roomName, frameCount}`. This matches existing patterns and avoids firing on unrelated uploads.
- **Cloud Function uses the Anthropic SDK** (already in `package.json`) to call Claude Sonnet with multi-image input. Returns structured JSON inventory.
- **Firestore document at `users/{userId}/inventorySessions/{sessionId}`** tracks processing status. iOS observes this document with a snapshot listener.
- **The user is the QA layer.** The LLM is prompted to bias toward recall (include uncertain items). The review screen lets the user delete false positives and add missed items.
- **No music file is bundled in Stage 1.** The capture UI uses a metronome-style haptic pulse at ~80 BPM to guide pacing. Music is a Stage 2 enhancement.

## Data Contracts

### Swift: `InventoryItem` (Codable)

```swift
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
```

### Swift: `InventoryScanSession` (Codable)

```swift
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
}
```

### Firestore Document: `users/{userId}/inventorySessions/{sessionId}`

```json
{
  "id": "session-uuid",
  "userId": "firebase-uid",
  "roomName": "Living Room",
  "status": "processing",
  "frameCount": 8,
  "items": [],
  "errorMessage": null,
  "createdAt": "Timestamp",
  "completedAt": null
}
```

When Cloud Function completes, it updates `status` to `"complete"` and populates `items` array with inventory JSON.

### Cloud Function Request (onCall):

```json
{
  "userId": "firebase-uid",
  "sessionId": "session-uuid",
  "roomName": "Living Room",
  "frameCount": 8
}
```

### Cloud Function → Claude API Prompt:

```
You are analyzing photos of a room in someone's home to create a moving inventory.
These {frameCount} images show the same room ({roomName}) from different angles during a slow pan.

INSTRUCTIONS:
1. Identify every distinct piece of furniture, appliance, and significant item visible.
2. Do NOT double-count items visible from multiple angles — deduplicate carefully.
3. For each item, estimate: category, quantity, size, whether it's fragile, whether it's high-value.
4. When uncertain, INCLUDE the item with a lower confidence score. The user will review.
5. Ignore: walls, floors, ceilings, built-in fixtures, small items under 1 cubic foot (pens, books, etc.).

Return ONLY a JSON array. No markdown, no explanation, no preamble. Example:
[
  {"name": "Sectional Sofa", "category": "furniture", "quantity": 1, "sizeEstimate": "oversized", "isFragile": false, "isHighValue": true, "confidence": 0.95},
  {"name": "Floor Lamp", "category": "decor", "quantity": 2, "sizeEstimate": "medium", "isFragile": true, "isHighValue": false, "confidence": 0.8}
]

Valid categories: furniture, electronics, boxes, appliance, decor, other
Valid sizes: small, medium, large, oversized
Confidence: 0.0 to 1.0 (1.0 = absolutely certain)
```

### Claude API Image Format:

Each frame is sent as a content block with `type: "image"`, `source.type: "base64"`, `source.media_type: "image/jpeg"`, `source.data: "<base64string>"`.

---

## Phase 1: Data Models (files: 2)

**Create:** `Peezy 4.0/Inventory/Models/InventoryModels.swift`

This file contains `InventoryItem` and `InventoryScanSession` structs exactly as defined in the Data Contracts above. Both must conform to `Codable` and `Identifiable`. `InventoryItem` must have `var` properties (user edits them in the review screen). `InventoryScanSession` must have `var` properties (status changes during pipeline).

Add a convenience initializer on `InventoryScanSession`:
```swift
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
```

**Create:** `Peezy 4.0/Inventory/Models/FrameExtractionResult.swift`

```swift
struct ExtractedFrame {
    let image: UIImage
    let timestamp: TimeInterval    // Position in video
    let index: Int                 // Frame number (0-based)
    let sharpnessScore: Double     // Laplacian variance (higher = sharper)
}
```

This is a local-only struct (not Codable) — used between frame extraction and upload.

**Verification:** `xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build`

**Mark Phase 1 complete in this file when verification passes.**

---

## Phase 2: Frame Extraction Service (files: 1)

**Create:** `Peezy 4.0/Inventory/Services/FrameExtractionService.swift`

This service takes a local video URL and returns an array of `ExtractedFrame`. It must:

1. Use `AVAsset` and `AVAssetImageGenerator` to extract frames.
2. Accept a `frameInterval: TimeInterval` parameter (default 2.5 seconds).
3. Use `generateCGImagesAsynchronously(forTimes:)` to pull frames at calculated times.
4. For each extracted `CGImage`, convert to `UIImage`, then compute a sharpness score using Core Image's Laplacian variance:
   - Create `CIImage` from the `CGImage`
   - Apply `CIFilter(name: "CILaplacian")` (or manually compute variance of Laplacian)
   - If `CILaplacian` is not available, use an alternative: convert to grayscale, apply a 3x3 Laplacian kernel via `CIConvolution3X3`, compute the variance of pixel values. The key metric is: blurry frames have LOW variance, sharp frames have HIGH variance.
   - NOTE: The simpler approach — use `vImage` or just compute standard deviation of a small central crop — is acceptable for Stage 1. Exact method doesn't matter as long as blurry frames score lower than sharp ones.
5. Filter out frames below a sharpness threshold (default: 100.0 — calibrate on real device).
6. Resize frames to max 720p (longest edge ≤ 1280px) to reduce upload size.
7. Return `[ExtractedFrame]` sorted by timestamp.

Method signature:
```swift
@Observable
final class FrameExtractionService {
    var isExtracting = false
    var progress: Double = 0.0  // 0.0 to 1.0
    var extractedFrames: [ExtractedFrame] = []

    func extractFrames(
        from videoURL: URL,
        interval: TimeInterval = 2.5,
        sharpnessThreshold: Double = 100.0,
        maxDimension: CGFloat = 1280
    ) async throws -> [ExtractedFrame]
}
```

Error handling:
- If video URL is invalid or unreadable: throw descriptive error
- If video has zero duration: throw error
- If ALL frames are below sharpness threshold: return the top 3 sharpest frames anyway (never return empty)
- If `AVAssetImageGenerator` fails for a specific time: skip that frame, continue to next

**Verification:** `xcodebuild` build succeeds. No runtime test possible in simulator (no real video), but the code must compile cleanly.

**Mark Phase 2 complete in this file when verification passes.**

---

## Phase 3: Video Capture View + ViewModel (files: 2)

**Create:** `Peezy 4.0/Inventory/Views/RoomCaptureView.swift`

SwiftUI view for recording a room video. Layout:

- Full-screen camera preview (use `AVCaptureVideoPreviewLayer` wrapped in `UIViewRepresentable`)
- Top bar: room name label (passed as parameter), close button (X)
- Bottom: large circular record button (red dot when recording, pulse animation)
- During recording: elapsed time label, subtle haptic pulse every ~750ms (80 BPM pacing guide)
- When recording stops: brief "Processing frames..." overlay with `ProgressView`, then navigation to review

The view receives `roomName: String` and an `onComplete: ([ExtractedFrame]) -> Void` callback.

Flow:
1. View appears → request camera + microphone permissions
2. If permissions denied → show alert with "Open Settings" button
3. User taps record → start `AVCaptureSession` recording to temp `.mp4` file
4. Haptic pulse begins (using `UIImpactFeedbackGenerator(.light)` on a timer)
5. User taps stop → stop recording → call `FrameExtractionService.extractFrames(from:)` → call `onComplete` with frames

Use `PeezyTheme.Colors` for text colors and `PeezyTheme.Typography` for fonts. The record button should use `PeezyTheme.Colors.emotionalRed`.

**Create:** `Peezy 4.0/Inventory/ViewModels/RoomCaptureViewModel.swift`

`@Observable` class managing AVCaptureSession state:

```swift
@Observable
final class RoomCaptureViewModel: NSObject {
    var isRecording = false
    var recordingDuration: TimeInterval = 0
    var permissionGranted = false
    var permissionDenied = false
    var isProcessingFrames = false
    var extractedFrames: [ExtractedFrame] = []
    var error: String?

    private var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var tempVideoURL: URL?
    private var recordingTimer: Timer?
    private var hapticTimer: Timer?
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    private let frameService = FrameExtractionService()

    func requestPermissions() async
    func setupCaptureSession() throws
    func startRecording()
    func stopRecording() async  // Stops recording, extracts frames, sets extractedFrames
    func cleanup()              // Removes temp video file, stops session
}
```

Must conform to `AVCaptureFileOutputRecordingDelegate` (NSObject subclass) for `fileOutput(_:didFinishRecordingTo:from:error:)`.

The haptic timer fires every 0.75 seconds (80 BPM). Use `hapticGenerator.prepare()` before starting and `hapticGenerator.impactOccurred()` on each tick.

**Verification:** `xcodebuild` build succeeds.

**Mark Phase 3 complete in this file when verification passes.**

---

## Phase 4: Firebase Storage Upload Service (files: 1)

**Create:** `Peezy 4.0/Inventory/Services/InventoryStorageService.swift`

Uploads extracted frames to Firebase Storage and manages Firestore session documents.

```swift
@Observable
final class InventoryStorageService {
    var uploadProgress: Double = 0.0  // 0.0 to 1.0 (aggregate across all frames)
    var isUploading = false

    /// Upload frames to Storage, create Firestore session doc, return session
    func uploadFrames(
        _ frames: [ExtractedFrame],
        userId: String,
        roomName: String
    ) async throws -> InventoryScanSession

    /// Observe a session document for status changes (processing → complete)
    func observeSession(
        userId: String,
        sessionId: String,
        onChange: @escaping (InventoryScanSession) -> Void
    ) -> ListenerRegistration  // Firestore listener — caller must hold reference
}
```

`uploadFrames` implementation:
1. Generate session ID: `UUID().uuidString`
2. Create Firestore document at `users/{userId}/inventorySessions/{sessionId}` with status `.uploading`
3. For each `ExtractedFrame`:
   a. Compress to JPEG: `frame.image.jpegData(compressionQuality: 0.7)`
   b. Upload to Storage path: `inventory/{userId}/{sessionId}/frame_{index}.jpg`
   c. Update `uploadProgress` incrementally: `Double(completedCount) / Double(totalCount)`
4. Update Firestore document: set `frameCount` and `status` to `.processing`
5. Return the `InventoryScanSession` object

Use `FirebaseStorage` framework. Import `FirebaseFirestore` for document operations. Use `async/await` wrappers — `StorageReference.putDataAsync()` and `Firestore.firestore().collection(...).document(...).setData(...)`.

`observeSession` implementation:
1. Add snapshot listener on `users/{userId}/inventorySessions/{sessionId}`
2. On each snapshot, decode into `InventoryScanSession` and call `onChange`
3. Return the `ListenerRegistration` so the caller can remove it

Error handling:
- If any frame upload fails: continue uploading remaining frames, log the failure, set session `frameCount` to actual uploaded count
- If Firestore write fails: throw with descriptive error — upload is wasted without the session doc
- If zero frames provided: throw immediately, don't create any Firestore document

**Verification:** `xcodebuild` build succeeds.

**Mark Phase 4 complete in this file when verification passes.**

---

## Phase 5: Cloud Function — processInventory (files: 2)

**Create:** `functions/processInventory.js`

A new `onCall` (v2) Cloud Function. Structure:

```javascript
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const Anthropic = require('@anthropic-ai/sdk');

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY  // Set via firebase functions:secrets:set
});

exports.processInventory = onCall(
  {
    timeoutSeconds: 120,    // Vision API calls can take 30-60s
    memory: '1GiB',         // Image processing needs more memory
    cors: true,
    enforceAppCheck: false   // Stage 1 — tighten in production
  },
  async (request) => {
    // 1. Validate auth
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be authenticated');
    }

    // 2. Extract parameters
    const { userId, sessionId, roomName, frameCount } = request.data;
    if (!userId || !sessionId || !roomName || !frameCount) {
      throw new HttpsError('invalid-argument', 'Missing required fields');
    }

    // 3. Verify requesting user matches userId (security)
    if (request.auth.uid !== userId) {
      throw new HttpsError('permission-denied', 'Cannot process another user inventory');
    }

    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const sessionRef = db.collection('users').doc(userId)
                        .collection('inventorySessions').doc(sessionId);

    try {
      // 4. Download frames from Storage
      const framePromises = [];
      for (let i = 0; i < frameCount; i++) {
        const filePath = `inventory/${userId}/${sessionId}/frame_${i}.jpg`;
        framePromises.push(
          bucket.file(filePath).download().then(([buffer]) => ({
            index: i,
            base64: buffer.toString('base64')
          }))
        );
      }
      const frames = await Promise.all(framePromises);
      frames.sort((a, b) => a.index - b.index);

      // 5. Build Claude API request with multi-image input
      const imageContent = frames.map(frame => ({
        type: 'image',
        source: {
          type: 'base64',
          media_type: 'image/jpeg',
          data: frame.base64
        }
      }));

      const prompt = `You are analyzing photos of a room in someone's home to create a moving inventory.
These ${frameCount} images show the same room (${roomName}) from different angles during a slow pan.

INSTRUCTIONS:
1. Identify every distinct piece of furniture, appliance, and significant item visible.
2. Do NOT double-count items visible from multiple angles — deduplicate carefully.
3. For each item, estimate: category, quantity, size, whether it's fragile, whether it's high-value.
4. When uncertain, INCLUDE the item with a lower confidence score. The user will review.
5. Ignore: walls, floors, ceilings, built-in fixtures, small items under 1 cubic foot.

Return ONLY a valid JSON array. No markdown, no explanation, no preamble, no backticks. Example:
[{"name":"Sectional Sofa","category":"furniture","quantity":1,"sizeEstimate":"oversized","isFragile":false,"isHighValue":true,"confidence":0.95}]

Valid categories: furniture, electronics, boxes, appliance, decor, other
Valid sizes: small, medium, large, oversized
Confidence: 0.0 to 1.0`;

      const response = await anthropic.messages.create({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 4096,
        messages: [{
          role: 'user',
          content: [
            ...imageContent,
            { type: 'text', text: prompt }
          ]
        }]
      });

      // 6. Parse response — extract JSON from text content
      const textContent = response.content.find(c => c.type === 'text');
      if (!textContent) {
        throw new Error('No text response from Claude');
      }

      let rawItems;
      try {
        // Strip any accidental markdown fencing
        let jsonStr = textContent.text.trim();
        if (jsonStr.startsWith('```')) {
          jsonStr = jsonStr.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
        }
        rawItems = JSON.parse(jsonStr);
      } catch (parseErr) {
        console.error('Failed to parse Claude response:', textContent.text);
        throw new Error('Claude returned invalid JSON');
      }

      if (!Array.isArray(rawItems)) {
        throw new Error('Claude response is not an array');
      }

      // 7. Validate and normalize each item
      const validCategories = ['furniture', 'electronics', 'boxes', 'appliance', 'decor', 'other'];
      const validSizes = ['small', 'medium', 'large', 'oversized'];

      const items = rawItems.map((item, idx) => ({
        id: `${sessionId}-item-${idx}`,
        name: String(item.name || 'Unknown Item'),
        category: validCategories.includes(item.category) ? item.category : 'other',
        quantity: Math.max(1, Math.round(Number(item.quantity) || 1)),
        sizeEstimate: validSizes.includes(item.sizeEstimate) ? item.sizeEstimate : 'medium',
        isFragile: Boolean(item.isFragile),
        isHighValue: Boolean(item.isHighValue),
        confidence: Math.min(1, Math.max(0, Number(item.confidence) || 0.5)),
        roomName: roomName,
        shouldMove: true,
        notes: ''
      }));

      // 8. Update Firestore session document
      await sessionRef.update({
        status: 'complete',
        items: items,
        completedAt: admin.firestore.FieldValue.serverTimestamp()
      });

      console.log(`processInventory: ${items.length} items found for session ${sessionId}`);

      return { success: true, itemCount: items.length };

    } catch (error) {
      console.error('processInventory error:', error);

      // Update session with error status
      await sessionRef.update({
        status: 'error',
        errorMessage: error.message || 'Unknown processing error'
      }).catch(e => console.error('Failed to update error status:', e));

      throw new HttpsError('internal', error.message || 'Processing failed');
    }
  }
);
```

**Modify:** `functions/index.js`

Add this single line after the existing require statements at the top:
```javascript
const { processInventory } = require('./processInventory');
```

Add this single line at the bottom with the other exports:
```javascript
exports.processInventory = processInventory;
```

Do NOT modify any other code in index.js. Do NOT refactor existing functions.

**Environment setup note:** The Anthropic API key must be set. Check if `process.env.ANTHROPIC_API_KEY` is already available from the existing peezyBrain setup. If peezyBrain reads the key differently (check `peezyBrain.js` for how it initializes the Anthropic client), use the same pattern. Do NOT hardcode any API key.

**Verification:**
1. `cd functions && node -e "require('./processInventory')"` — must not throw
2. `cd functions && node -e "require('./index')"` — must not throw (ensures index.js still loads)

**Mark Phase 5 complete in this file when verification passes.**

---

## Phase 6: Inventory API Client (files: 1)

**Create:** `Peezy 4.0/Inventory/Services/InventoryAPIClient.swift`

Calls the `processInventory` Cloud Function from iOS. Uses Firebase Functions SDK callable pattern:

```swift
import FirebaseFunctions

final class InventoryAPIClient {
    private let functions = Functions.functions()

    /// Trigger inventory processing for an uploaded session
    func processInventory(
        userId: String,
        sessionId: String,
        roomName: String,
        frameCount: Int
    ) async throws {
        let data: [String: Any] = [
            "userId": userId,
            "sessionId": sessionId,
            "roomName": roomName,
            "frameCount": frameCount
        ]

        do {
            let result = try await functions.httpsCallable("processInventory").call(data)
            // Result contains {success: true, itemCount: N} but we don't need it —
            // the iOS app observes the Firestore document for the actual items
            if let response = result.data as? [String: Any],
               let success = response["success"] as? Bool, !success {
                throw InventoryError.processingFailed("Server returned success=false")
            }
        } catch let error as NSError {
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)
                switch code {
                case .unauthenticated:
                    throw InventoryError.notAuthenticated
                case .invalidArgument:
                    throw InventoryError.invalidRequest(error.localizedDescription)
                default:
                    throw InventoryError.processingFailed(error.localizedDescription)
                }
            }
            throw InventoryError.networkError(error)
        }
    }
}

enum InventoryError: LocalizedError {
    case notAuthenticated
    case invalidRequest(String)
    case processingFailed(String)
    case networkError(Error)
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to scan inventory"
        case .invalidRequest(let msg): return "Invalid request: \(msg)"
        case .processingFailed(let msg): return "Processing failed: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .uploadFailed(let msg): return "Upload failed: \(msg)"
        }
    }
}
```

**Verification:** `xcodebuild` build succeeds.

**Mark Phase 6 complete in this file when verification passes.**

---

## Phase 7: Inventory Review View (files: 2)

**Create:** `Peezy 4.0/Inventory/ViewModels/InventoryReviewViewModel.swift`

```swift
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

    func deleteItem(at offsets: IndexSet) { ... }
    func toggleShouldMove(for item: InventoryItem) { ... }
    func updateQuantity(for item: InventoryItem, newQuantity: Int) { ... }
    func addManualItem(name: String, category: String, size: String) { ... }

    var itemsToMove: [InventoryItem] { items.filter { $0.shouldMove } }
    var totalItemCount: Int { items.reduce(0) { $0 + $1.quantity } }
}
```

**Create:** `Peezy 4.0/Inventory/Views/InventoryReviewView.swift`

SwiftUI view displaying the AI-generated inventory for user review. Layout:

- Top: room name, item count summary ("12 items found in Living Room")
- Scrollable list of items, each showing:
  - Item name (editable on tap in edit mode)
  - Category icon (SF Symbol: `sofa.fill` for furniture, `tv.fill` for electronics, `shippingbox.fill` for boxes, `refrigerator.fill` for appliance, `lamp.desk.fill` for decor, `questionmark.circle` for other)
  - Quantity stepper (- / count / +)
  - Size badge (small/medium/large/oversized)
  - Confidence indicator: green circle if ≥0.8, yellow if ≥0.5, orange if <0.5
  - Toggle: "Moving this" (bound to `shouldMove`)
  - Swipe-to-delete
- Bottom: "Add Item" button (manual entry sheet) and "Looks Good" confirmation button
- "Looks Good" triggers `onConfirm: ([InventoryItem]) -> Void` callback

Style using `PeezyTheme.Colors`, `PeezyTheme.Typography`, `PeezyTheme.Layout`. Cards use `.peezyGlassBackground()` or simple white rounded rects with subtle shadow. Confirmation button uses `PeezyTheme.Colors.brandYellow` background.

**Verification:** `xcodebuild` build succeeds.

**Mark Phase 7 complete in this file when verification passes.**

---

## Phase 8: Test Harness + End-to-End Wiring (files: 1)

**Create:** `Peezy 4.0/Inventory/InventoryTestHarness.swift`

This is the test harness view that ties the entire pipeline together. It manages the full flow:

```
Room name entry → Video capture → Frame extraction → Upload → Processing → Review
```

```swift
@Observable
final class InventoryTestHarnessViewModel {
    // Pipeline state
    enum PipelineState {
        case idle
        case enterRoomName
        case capturing
        case extractingFrames
        case uploading(progress: Double)
        case processing
        case reviewing(items: [InventoryItem])
        case complete
        case error(String)
    }

    var state: PipelineState = .idle
    var roomName: String = ""
    var session: InventoryScanSession?

    private let storageService = InventoryStorageService()
    private let apiClient = InventoryAPIClient()
    private var sessionListener: ListenerRegistration?

    func startCapture(roomName: String) { ... }

    func handleFramesExtracted(_ frames: [ExtractedFrame]) async {
        // 1. Set state to .uploading
        // 2. Call storageService.uploadFrames
        // 3. Set state to .processing
        // 4. Call apiClient.processInventory
        // 5. Start observing Firestore session document
        // 6. When status == .complete → set state to .reviewing(items)
        // 7. When status == .error → set state to .error(message)
    }

    func handleReviewConfirmed(_ items: [InventoryItem]) {
        state = .complete
        // In Stage 2, this would save finalized items to permanent Firestore location
    }

    func reset() {
        sessionListener?.remove()
        state = .idle
        roomName = ""
        session = nil
    }
}

struct InventoryTestHarness: View {
    @State private var viewModel = InventoryTestHarnessViewModel()

    var body: some View {
        // Switch on viewModel.state to show appropriate view for each pipeline stage
        // .idle / .enterRoomName → text field for room name + "Start Scan" button
        // .capturing → RoomCaptureView
        // .extractingFrames → ProgressView with "Extracting frames..."
        // .uploading → ProgressView with percentage
        // .processing → Theatrical loading (typewriter text: "Peezy is scanning your room...")
        // .reviewing → InventoryReviewView
        // .complete → Success checkmark + "Scan Another Room" button
        // .error → Error message + "Try Again" button
    }
}
```

The processing state should show a loading animation that feels substantial (not a spinner). Use typewriter-style text cycling through messages: "Identifying furniture...", "Counting items...", "Checking for fragile items...", "Almost done...". Use `PeezyTheme.Animation.spring` for transitions between states.

**To test:** Temporarily modify `AppRootView.swift` to show `InventoryTestHarness()` instead of the normal app flow. Or add a debug button in `PeezySettingsView` that presents the test harness as a sheet. IMPORTANT: Do NOT permanently modify AppRootView — use a `#if DEBUG` flag or a sheet presentation.

**Verification:**
1. `xcodebuild` build succeeds
2. All 8 new Swift files compile without errors
3. `cd functions && node -e "require('./index')"` loads without errors
4. List all created files and confirm nothing outside `Peezy 4.0/Inventory/` was modified (except the 2-line addition to `functions/index.js`)

**Mark Phase 8 complete in this file when ALL verifications pass.**

---

## Files Created (Complete List)

| Phase | File | Purpose |
|-------|------|---------|
| 1 | `Peezy 4.0/Inventory/Models/InventoryModels.swift` | InventoryItem + InventoryScanSession |
| 1 | `Peezy 4.0/Inventory/Models/FrameExtractionResult.swift` | ExtractedFrame struct |
| 2 | `Peezy 4.0/Inventory/Services/FrameExtractionService.swift` | Video → sharp frames |
| 3 | `Peezy 4.0/Inventory/Views/RoomCaptureView.swift` | Camera UI with haptic pacing |
| 3 | `Peezy 4.0/Inventory/ViewModels/RoomCaptureViewModel.swift` | AVCaptureSession manager |
| 4 | `Peezy 4.0/Inventory/Services/InventoryStorageService.swift` | Upload frames + Firestore session |
| 5 | `functions/processInventory.js` | Cloud Function: frames → Claude → inventory |
| 5 | `functions/index.js` (modify) | Add 2 lines to export processInventory |
| 6 | `Peezy 4.0/Inventory/Services/InventoryAPIClient.swift` | Call Cloud Function from iOS |
| 7 | `Peezy 4.0/Inventory/ViewModels/InventoryReviewViewModel.swift` | Review screen logic |
| 7 | `Peezy 4.0/Inventory/Views/InventoryReviewView.swift` | Receipt check UI |
| 8 | `Peezy 4.0/Inventory/InventoryTestHarness.swift` | End-to-end test harness |

## Files NOT Modified (Confirm at end)

- AppRootView.swift (only DEBUG-guarded addition if needed for test access)
- PeezyMainContainer.swift — UNTOUCHED
- PeezyHomeView.swift — UNTOUCHED
- peezyBrain.js — UNTOUCHED
- All assessment files — UNTOUCHED
- All existing services — UNTOUCHED
