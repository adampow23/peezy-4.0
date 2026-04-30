//
//  InventorySessionManager.swift
//  Peezy 4.0
//
//  Hardened against Swift Concurrency crashes during scanner processing.
//
//  Architecture notes:
//  - @MainActor isolated. All observable state mutations happen on main actor.
//  - Firestore listener callbacks (which arrive on Firebase's gRPC thread) hop
//    to MainActor via Task { @MainActor in ... } before touching state.
//  - The processing task is owned by the manager, not by transient views.
//    This prevents "Task spawned from view closure outliving the view" crashes.
//  - State transitions are idempotent. Even if Firestore emits the same status
//    multiple times in succession, only the first one transitions state.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
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

    /// Firestore listener for the session document we're currently observing.
    /// Removed whenever we transition out of .processing or reset.
    private var sessionListener: ListenerRegistration?

    /// The session ID currently being observed. Used to ignore stale listener
    /// callbacks if the user has moved on (e.g., cancelled mid-processing,
    /// then started a new scan that produced a new sessionId).
    private var observedSessionId: String?

    /// The processing pipeline task. Owned by the manager so it survives
    /// view-tree changes. Cancelled on reset or when user navigates away.
    private var processingTask: Task<Void, Never>?

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

    // MARK: - Lifecycle
        //
        // Note: no custom deinit. Swift's strict concurrency forbids touching
        // @MainActor-isolated properties from deinit (which can run on any
        // thread). Cleanup is handled explicitly via reset() and
        // teardownActiveProcessing() during normal flow. When the manager
        // does deallocate, the Firestore listener becomes unreachable from
        // its [weak self] callback and is effectively dead, and the
        // processingTask is cancelled implicitly when its last reference
        // (this manager) is released.

    // MARK: - Loading

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

            // The class is @MainActor so direct assignment is already main-isolated.
            self.submissionStatus = loadedStatus
            self.scannedRooms = rooms
        } catch {
            self.submissionStatus = loadedStatus
            #if DEBUG
            print("[InventorySessionManager] Failed to load existing inventory: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Flow control

    func startNewRoom(name: String) {
        state = .scanning(roomName: name)
    }

    /// Hand off frames extracted from a scan. Fire-and-forget from the caller's
    /// perspective. The manager owns the processing Task internally so it
    /// survives the camera view being deallocated.
    func handleFramesExtracted(_ frames: [ExtractedFrame], roomName: String) {
        guard let userId else {
            error = "You must be signed in to scan inventory"
            state = .roomList
            return
        }

        // Cancel any previous in-flight processing and tear down its listener
        // before starting a new one. (Defensive — shouldn't happen in normal
        // flow but cheap to handle.)
        teardownActiveProcessing()

        isProcessing = true
        state = .processing(roomName: roomName, progress: "Uploading frames...")

        // Capture only what we need. `self` is captured weakly so the Task
        // doesn't keep the manager alive past its natural lifetime.
        processingTask = Task { @MainActor [weak self] in
            await self?.runProcessingPipeline(
                frames: frames,
                userId: userId,
                roomName: roomName
            )
        }
    }

    /// Internal pipeline. Owns the upload + Cloud Function call, then installs
    /// the Firestore listener and returns. State transitions out of .processing
    /// are driven by the listener (handleSessionUpdate), not by awaiting here.
    private func runProcessingPipeline(
        frames: [ExtractedFrame],
        userId: String,
        roomName: String
    ) async {
        do {
            // Phase 1 — upload frames to Storage + create session doc
            let session = try await storageService.uploadFrames(
                frames,
                userId: userId,
                roomName: roomName
            )

            // Bail out if the user moved on while we were uploading.
            guard !Task.isCancelled else { return }

            state = .processing(roomName: roomName, progress: "Analyzing room...")

            // Phase 2 — kick off Cloud Function
            try await apiClient.processInventory(
                userId: userId,
                sessionId: session.id,
                roomName: roomName,
                frameCount: session.frameCount
            )

            guard !Task.isCancelled else { return }

            // Phase 3 — install Firestore listener and return.
            // State transitions out of .processing happen in handleSessionUpdate.
            installSessionListener(
                userId: userId,
                sessionId: session.id,
                roomName: roomName
            )

        } catch {
            // Caught here on upload failure or Cloud Function failure.
            // Listener errors are handled in handleSessionUpdate.
            self.isProcessing = false
            self.error = error.localizedDescription
            self.state = .roomList
        }
    }

    /// Install the Firestore listener for a session. The callback may fire
    /// on a Firebase gRPC thread; we hop to MainActor before mutating state.
    /// Idempotent — repeated "complete" snapshots only transition once
    /// because we clear `observedSessionId` on the first transition.
    private func installSessionListener(
        userId: String,
        sessionId: String,
        roomName: String
    ) {
        observedSessionId = sessionId

        sessionListener = storageService.observeSession(
            userId: userId,
            sessionId: sessionId
        ) { [weak self] session in
            // Hop to MainActor before touching any observable state.
            // self is captured weakly so a stale callback after manager
            // deallocation is a no-op.
            Task { @MainActor [weak self] in
                self?.handleSessionUpdate(session, roomName: roomName)
            }
        }
    }

    /// Handle a Firestore session snapshot update. Runs on MainActor.
    /// Idempotent — only the first terminal status (complete or error) for
    /// a given observedSessionId triggers a state transition; subsequent
    /// snapshots are ignored.
    private func handleSessionUpdate(
        _ session: InventoryScanSession,
        roomName: String
    ) {
        // Ignore stale callbacks for sessions we're no longer observing.
        guard session.id == observedSessionId else { return }

        switch session.status {
        case .complete:
            // Transition once, then stop observing this session.
            observedSessionId = nil
            sessionListener?.remove()
            sessionListener = nil
            isProcessing = false

            let needsConfirmation = session.items.contains { item in
                item.tier == "furniture" && item.confidence < Self.confidenceThreshold
            }

            if needsConfirmation {
                state = .confirming(
                    roomName: roomName,
                    items: session.items,
                    sessionId: session.id
                )
            } else {
                state = .reviewing(roomName: roomName, items: session.items)
            }

        case .error:
            observedSessionId = nil
            sessionListener?.remove()
            sessionListener = nil
            isProcessing = false
            error = session.errorMessage ?? "Processing failed"
            state = .roomList

        case .processing:
            // Cosmetic: keep the user informed while we wait.
            state = .processing(roomName: roomName, progress: "Analyzing room...")

        case .uploading:
            // Already shown by runProcessingPipeline. No-op.
            break
        }
    }

    /// Tear down the active processing pipeline. Cancels in-flight Task,
    /// removes Firestore listener, clears observed session token.
    private func teardownActiveProcessing() {
        processingTask?.cancel()
        processingTask = nil

        sessionListener?.remove()
        sessionListener = nil

        observedSessionId = nil
    }

    // MARK: - Confirmation / review handoffs

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

    // MARK: - Persistence

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

        self.submissionStatus = .draft
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

        self.submissionStatus = .submitted
    }

    func reset() {
        teardownActiveProcessing()
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

        let snapshot = try await inventoryRef.getDocuments()
        if !snapshot.documents.isEmpty {
            let batch = db.batch()
            for doc in snapshot.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
        }

        // Class is @MainActor so reset() runs main-isolated.
        self.reset()
    }

    // MARK: - Private helpers

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
}

// MARK: - ScannedRoom

struct ScannedRoom: Identifiable {
    let id: String
    let name: String
    var items: [InventoryItem]
    let scannedAt: Date
}
