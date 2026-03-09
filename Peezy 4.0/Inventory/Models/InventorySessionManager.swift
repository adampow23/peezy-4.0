import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@Observable
final class InventorySessionManager {

    // MARK: - State

    enum FlowState {
        case roomList
        case enteringRoomName
        case scanning(roomName: String)
        case processing(roomName: String, progress: String)
        case reviewing(roomName: String, items: [InventoryItem])
        case estimate
    }

    var state: FlowState = .roomList
    var scannedRooms: [ScannedRoom] = []
    var error: String?
    var isProcessing = false

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
                [
                    "id": item.id,
                    "name": item.name,
                    "category": item.category,
                    "quantity": item.quantity,
                    "sizeEstimate": item.sizeEstimate,
                    "isFragile": item.isFragile,
                    "isHighValue": item.isHighValue,
                    "confidence": item.confidence,
                    "roomName": item.roomName,
                    "shouldMove": item.shouldMove,
                    "notes": item.notes
                ]
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
                    self.state = .reviewing(roomName: roomName, items: session.items)
                    self.sessionListener?.remove()
                    self.sessionListener = nil
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
                    // Still in progress — update progress message
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
