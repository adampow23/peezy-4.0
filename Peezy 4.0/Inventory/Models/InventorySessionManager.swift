//
//  InventorySessionManager.swift
//  Peezy 4.0
//

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

    enum SubmissionStatus: String {
        case draft
        case submitted
    }

    var state: FlowState = .intro
    var scannedRooms: [ScannedRoom] = []
    var submissionStatus: SubmissionStatus = .draft
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

    /// String key for animating state transitions
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

    func loadExistingInventory() async {
        guard let userId else { return }

        let db = Firestore.firestore()
        var loadedStatus: SubmissionStatus = .draft

        do {
            let metadataDoc = try await db.collection("users").document(userId)
                .collection("inventory").document("_metadata")
                .getDocument()

            if let data = metadataDoc.data(),
               let statusRaw = data["submissionStatus"] as? String,
               let status = SubmissionStatus(rawValue: statusRaw) {
                loadedStatus = status
            }
        } catch {
            loadedStatus = .draft
        }

        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("inventory")
                .getDocuments()

            var rooms: [ScannedRoom] = []
            for doc in snapshot.documents where doc.documentID != "_metadata" {
                let data = doc.data()
                let roomName = data["name"] as? String ?? data["roomName"] as? String
                guard let roomName else { continue }

                let itemsData = data["items"] as? [[String: Any]] ?? []
                let items = itemsData.compactMap { InventoryItem.from(dict: $0) }
                let scannedAt = (data["scannedAt"] as? Timestamp)?.dateValue() ?? Date()

                rooms.append(ScannedRoom(
                    id: data["id"] as? String ?? doc.documentID,
                    name: roomName,
                    items: items,
                    scannedAt: scannedAt
                ))
            }

            await MainActor.run {
                self.submissionStatus = loadedStatus
                self.scannedRooms = rooms
            }
        } catch {
            await MainActor.run {
                self.submissionStatus = loadedStatus
            }
            #if DEBUG
            print("[InventorySessionManager] Failed to load existing inventory: \(error.localizedDescription)")
            #endif
        }
    }

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

    func removeItem(_ item: InventoryItem) {
        for roomIndex in scannedRooms.indices {
            scannedRooms[roomIndex].items.removeAll { $0.id == item.id }
        }
    }

    /// Finish later — saves progress but keeps the scanner unlocked.
    func saveDraft() async throws {
        guard let userId else {
            throw InventoryError.notAuthenticated
        }

        let db = Firestore.firestore()
        let batch = db.batch()

        addRoomWrites(to: batch, db: db, userId: userId)

        let metaRef = db.collection("users").document(userId)
            .collection("inventory").document("_metadata")
        batch.setData([
            "submissionStatus": SubmissionStatus.draft.rawValue,
            "updatedAt": Timestamp(date: Date())
        ], forDocument: metaRef, merge: true)

        try await batch.commit()

        await MainActor.run {
            self.submissionStatus = .draft
        }
    }

    /// Final submit — saves progress and locks the inventory.
    func submitFinal() async throws {
        guard let userId else {
            throw InventoryError.notAuthenticated
        }

        let db = Firestore.firestore()
        let batch = db.batch()

        addRoomWrites(to: batch, db: db, userId: userId)

        let metaRef = db.collection("users").document(userId)
            .collection("inventory").document("_metadata")
        batch.setData([
            "submissionStatus": SubmissionStatus.submitted.rawValue,
            "submittedAt": Timestamp(date: Date())
        ], forDocument: metaRef, merge: true)

        try await batch.commit()

        await MainActor.run {
            self.submissionStatus = .submitted
        }
    }

    func reset() {
        sessionListener?.remove()
        sessionListener = nil
        scannedRooms = []
        submissionStatus = .draft
        error = nil
        isProcessing = false
        state = .intro
    }

    /// Wipe the user's inventory state both locally and in Firestore.
    /// Used when the user taps "Reset inventory" on a completed scan_inventory task.
    /// Throws if not signed in or if the Firestore deletion fails.
    func resetInventory() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "InventorySessionManager",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Not signed in"]
            )
        }

        let db = Firestore.firestore()
        let inventoryRef = db.collection("users").document(userId).collection("inventory")

        // Fetch all room docs and delete them in a single batch.
        let snapshot = try await inventoryRef.getDocuments()
        if !snapshot.documents.isEmpty {
            let batch = db.batch()
            for doc in snapshot.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
        }

        // Clear local state so the next scan starts fresh.
        await MainActor.run {
            self.reset()
        }
    }

    // MARK: - Private

    private func addRoomWrites(to batch: WriteBatch, db: Firestore, userId: String) {
        for room in scannedRooms {
            let roomRef = db.collection("users").document(userId)
                .collection("inventory").document(room.id)

            batch.setData([
                "id": room.id,
                "name": room.name,
                "items": room.items.map { $0.toDict() },
                "scannedAt": Timestamp(date: room.scannedAt),
                "savedAt": FieldValue.serverTimestamp()
            ], forDocument: roomRef)
        }
    }

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
