import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@Observable
final class InventorySessionManager {

    // MARK: - State

    enum FlowState {
        case intro
        case info
        case roomList
        case enteringRoomName
        case scanning(roomName: String)
        case processing(roomName: String, progress: String)
        case confirming(roomName: String, items: [InventoryItem], sessionId: String)
        case reviewing(roomName: String, items: [InventoryItem])
        case estimate
    }

    var state: FlowState = .intro
    var scannedRooms: [ScannedRoom] = []
    var error: String?
    var isProcessing = false

    /// Confidence threshold — furniture items below this go to user confirmation
    static let confidenceThreshold: Double = 0.9

    // MARK: - Services

    private let storageService = InventoryStorageService()
    private let apiClient = InventoryAPIClient()
    private var sessionListener: ListenerRegistration?

    // MARK: - Computed

    var totalItemCount: Int {
        scannedRooms.reduce(0) { $0 + $1.items.count }
    }

    var allItems: [InventoryItem] {
        scannedRooms.flatMap { $0.items }
    }

    var userId: String? {
        Auth.auth().currentUser?.uid
    }

    var stateDescription: String {
        switch state {
        case .intro: return "intro"
        case .info: return "info"
        case .roomList: return "roomList"
        case .enteringRoomName: return "enteringRoomName"
        case .scanning(let name): return "scanning-\(name)"
        case .processing(let name, _): return "processing-\(name)"
        case .confirming(let name, _, _): return "confirming-\(name)"
        case .reviewing(let name, _): return "reviewing-\(name)"
        case .estimate: return "estimate"
        }
    }

    // MARK: - Actions

    func startNewRoom(name: String) {
        state = .scanning(roomName: name)
    }

    func handleFramesExtracted(_ frames: [ExtractedFrame], roomName: String) async {
        guard let userId else {
            error = "You must be signed in to scan inventory"
            state = .roomList
            return
        }

        isProcessing = true
        state = .processing(roomName: roomName, progress: "Uploading frames...")

        do {
            // 1. Upload frames to Firebase Storage + create Firestore session doc
            let session = try await storageService.uploadFrames(frames, userId: userId, roomName: roomName)

            // 2. Trigger Cloud Function for AI processing
            state = .processing(roomName: roomName, progress: "Analyzing room...")
            try await apiClient.processInventory(
                userId: userId,
                sessionId: session.id,
                roomName: roomName,
                frameCount: session.frameCount
            )

            // 3. Observe Firestore session document for completion
            await observeSessionCompletion(userId: userId, sessionId: session.id, roomName: roomName)

        } catch {
            isProcessing = false
            self.error = error.localizedDescription
            state = .roomList
        }
    }

    /// Called when confirmation flow completes — items have been updated with user corrections
    func handleConfirmationCompleted(_ items: [InventoryItem], roomName: String) {
        state = .reviewing(roomName: roomName, items: items)
    }

    func handleReviewConfirmed(_ items: [InventoryItem], roomName: String) {
        let room = ScannedRoom(
            id: UUID().uuidString,
            name: roomName,
            items: items,
            scannedAt: Date()
        )
        scannedRooms.append(room)
        state = .roomList
    }

    func showEstimate() {
        state = .estimate
    }

    func deleteRoom(at offsets: IndexSet) {
        scannedRooms.remove(atOffsets: offsets)
    }

    /// Save inventory to Firestore and trigger admin notification email
    func saveAllToFirestore() async throws {
        guard let userId else {
            throw InventoryError.notAuthenticated
        }

        let db = Firestore.firestore()
        let batch = db.batch()

        for room in scannedRooms {
            let roomRef = db.collection("users").document(userId)
                .collection("inventory").document(room.id)

            let itemsData: [[String: Any]] = room.items.map { item in
                var dict: [String: Any] = [
                    "id": item.id,
                    "name": item.name,
                    "category": item.category,
                    "tier": item.tier,
                    "quantity": item.quantity,
                    "sizeEstimate": item.sizeEstimate,
                    "cubicFeet": item.cubicFeet,
                    "isFragile": item.isFragile,
                    "isHighValue": item.isHighValue,
                    "confidence": item.confidence,
                    "roomName": item.roomName,
                    "shouldMove": item.shouldMove,
                    "notes": item.notes
                ]

                if let frameIndex = item.frameIndex {
                    dict["frameIndex"] = frameIndex
                }

                if let bb = item.boundingBox {
                    dict["boundingBox"] = [
                        "x": bb.x,
                        "y": bb.y,
                        "width": bb.width,
                        "height": bb.height
                    ]
                }

                return dict
            }

            batch.setData([
                "id": room.id,
                "name": room.name,
                "items": itemsData,
                "scannedAt": Timestamp(date: room.scannedAt),
                "savedAt": FieldValue.serverTimestamp()
            ], forDocument: roomRef)
        }

        try await batch.commit()

        // Send admin notification — fire and forget, don't block the user
        Task {
            do {
                try await apiClient.packageInventory()
            } catch {
                #if DEBUG
                print("[InventorySessionManager] packageInventory failed: \(error.localizedDescription)")
                #endif
                // Non-fatal — inventory is saved, email just didn't send
            }
        }
    }

    func reset() {
        sessionListener?.remove()
        sessionListener = nil
        scannedRooms = []
        error = nil
        isProcessing = false
        state = .roomList
    }

    // MARK: - Private

    private func observeSessionCompletion(userId: String, sessionId: String, roomName: String) async {
        // Remove any previous listener
        sessionListener?.remove()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false

            sessionListener = storageService.observeSession(userId: userId, sessionId: sessionId) { [weak self] session in
                guard let self, !resumed else { return }

                switch session.status {
                case .complete:
                    resumed = true
                    self.isProcessing = false
                    self.sessionListener?.remove()
                    self.sessionListener = nil

                    // Check if any furniture-tier items need user confirmation
                    let needsConfirmation = session.items.contains { item in
                        item.tier == "furniture" && item.confidence < Self.confidenceThreshold
                    }

                    if needsConfirmation {
                        self.state = .confirming(
                            roomName: roomName,
                            items: session.items,
                            sessionId: sessionId
                        )
                    } else {
                        self.state = .reviewing(roomName: roomName, items: session.items)
                    }

                    continuation.resume()

                case .error:
                    resumed = true
                    self.isProcessing = false
                    self.error = session.errorMessage ?? "Processing failed"
                    self.state = .roomList
                    self.sessionListener?.remove()
                    self.sessionListener = nil
                    continuation.resume()

                case .uploading, .processing:
                    if session.status == .processing {
                        self.state = .processing(roomName: roomName, progress: "Analyzing room...")
                    }
                }
            }
        }
    }
}

// MARK: - ScannedRoom

struct ScannedRoom: Identifiable {
    let id: String
    let name: String
    var items: [InventoryItem]
    let scannedAt: Date
}
