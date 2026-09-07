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
protocol CoverageConfirmationPersisting {
    /// Atomically adds one stable expected-room ID, then returns the server
    /// value read back from the same metadata document.
    func insertConfirmedRoomID(_ roomID: String, userID: String) async throws -> Set<String>
}

@MainActor
struct FirestoreCoverageConfirmationStore: CoverageConfirmationPersisting {
    func insertConfirmedRoomID(_ roomID: String, userID: String) async throws -> Set<String> {
        let metadataRef = FirestoreRuntime.firestore().collection("users").document(userID)
            .collection("inventory").document("_metadata")
        try await metadataRef.setData([
            InventoryCoverage.confirmedMetadataKey: FieldValue.arrayUnion([roomID]),
            "updatedAt": Timestamp(date: Date())
        ], merge: true)

        let snapshot = try await metadataRef.getDocument()
        let readBack = InventoryCoverage.confirmedRoomIDs(
            fromMetadata: snapshot.data() ?? [:]
        )
        guard readBack.contains(roomID) else {
            throw CoveragePersistenceError.readBackMismatch
        }
        return readBack
    }
}

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
        case processing
        case submitted
    }

    var state: FlowState = .intro
    var scannedRooms: [ScannedRoom] = []
    var submissionStatus: SubmissionStatus = .draft
    var error: String?
    var isProcessing = false
    private(set) var movePassRequired = false
    private(set) var expectedCoverageRooms: [ExpectedCoverageRoom] = []
    private(set) var coverageConfirmedRoomIDs: Set<String> = []

    /// Confidence threshold — furniture items below this go to user confirmation
    static let confidenceThreshold: Double = 0.9

    // MARK: - Services

    private let storageService = InventoryStorageService()
    private let apiClient: any InventoryProcessingCalling
    private let coverageConfirmationStore: any CoverageConfirmationPersisting
    private let userIDProvider: () -> String?
    /// S4 (S4-CD7): the sole issuer of narration leases and the transfer registry. S7 attaches the one production
    /// owner; until then each manager holds a transitional owner over a permanently clear gate.
    private var artifactOwner = RoomCaptureArtifactOwner(gateSnapshot: { (.clear, GateGeneration(rawValue: 0)) })

    /// Owner wiring (S7): the one `RoomCaptureArtifactOwner`.
    func attachArtifactOwner(_ owner: RoomCaptureArtifactOwner) { artifactOwner = owner }

    init() {
        self.apiClient = InventoryAPIClient()
        self.coverageConfirmationStore = FirestoreCoverageConfirmationStore()
        self.userIDProvider = { Auth.auth().currentUser?.uid }
    }

    init(
        coverageConfirmationStore: any CoverageConfirmationPersisting,
        userIDProvider: @escaping () -> String?
    ) {
        self.apiClient = InventoryAPIClient()
        self.coverageConfirmationStore = coverageConfirmationStore
        self.userIDProvider = userIDProvider
    }

    init(
        coverageConfirmationStore: any CoverageConfirmationPersisting,
        userIDProvider: @escaping () -> String?,
        apiClient: any InventoryProcessingCalling
    ) {
        self.apiClient = apiClient
        self.coverageConfirmationStore = coverageConfirmationStore
        self.userIDProvider = userIDProvider
    }

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
    private var retainedProcessingRequest: InventoryProcessingRequest?
    /// S4 (S4-CD7): holds only the actor-issued lease; the transcript is materialized from the owner when the request is built.
    private var pendingNarration: NarrationLease?

    // MARK: - Computed

    var totalItemCount: Int {
        scannedRooms.reduce(0) { $0 + $1.items.count }
    }

    var allItems: [InventoryItem] {
        scannedRooms.flatMap { $0.items }
    }

    var coverageReport: InventoryCoverageReport {
        InventoryCoverage.report(
            expectedRooms: expectedCoverageRooms,
            scannedRoomNames: scannedRooms.map(\.name),
            confirmedRoomIDs: coverageConfirmedRoomIDs
        )
    }

    var userId: String? {
        userIDProvider()
    }

    var hasRetainedProcessingRequest: Bool {
        retainedProcessingRequest != nil
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

        let db = FirestoreRuntime.firestore()
        var loadedStatus: SubmissionStatus = .draft

        do {
            let metadataDoc = try await db.collection("users").document(userId)
                .collection("inventory").document("_metadata")
                .getDocument()

            if let data = metadataDoc.data() {
                if let statusRaw = data["submissionStatus"] as? String,
                   let status = SubmissionStatus(rawValue: statusRaw) {
                    loadedStatus = status
                }
                coverageConfirmedRoomIDs = InventoryCoverage.confirmedRoomIDs(
                    fromMetadata: data
                )
            }
        } catch {
            loadedStatus = .draft
        }

        do {
            let knowledgeData = try? await db.collection("userKnowledge")
                .document(userId).getDocument().data()
            let assessmentSnapshot = try await db.collection("users").document(userId)
                .collection("user_assessments").getDocuments()
            let inputs = InventoryCoverage.expectationInputs(
                userKnowledgeData: knowledgeData,
                legacyAssessmentDocuments: assessmentSnapshot.documents.map { $0.data() }
            )
            configureCoverage(
                bedroomsAnswer: inputs.bedroomsAnswer,
                dwellingType: inputs.dwellingType
            )
        } catch {
            configureCoverage(bedroomsAnswer: "", dwellingType: "")
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

    func configureCoverage(bedroomsAnswer: String, dwellingType: String) {
        expectedCoverageRooms = InventoryCoverage.expectedRooms(
            bedroomsAnswer: bedroomsAnswer,
            dwellingType: dwellingType
        )
    }

    /// Resolves an expected room as intentionally empty and verifies the
    /// backend-owned metadata round-trip before considering the action saved.
    func confirmNothingThere(_ room: ExpectedCoverageRoom) async {
        guard expectedCoverageRooms.contains(where: { $0.id == room.id }) else { return }
        let wasAlreadyConfirmed = coverageConfirmedRoomIDs.contains(room.id)
        coverageConfirmedRoomIDs.insert(room.id)

        // DEBUG acceptance fixtures have no signed-in user; local state still
        // exercises the exact action and rendering path.
        guard let userId else { return }

        do {
            let readBack = try await coverageConfirmationStore.insertConfirmedRoomID(
                room.id,
                userID: userId
            )
            // Union, never assign: another row may have completed while this
            // operation was suspended.
            coverageConfirmedRoomIDs.formUnion(readBack)
        } catch {
            // Roll back only this operation. Restoring an old snapshot could
            // discard another row that succeeded concurrently.
            if !wasAlreadyConfirmed { coverageConfirmedRoomIDs.remove(room.id) }
            self.error = "Couldn't save that coverage answer. Please try again."
        }
    }

    /// Hand off frames extracted from a scan. Fire-and-forget from the caller's
    /// perspective. The manager owns the processing Task internally so it
    /// survives the camera view being deallocated.
    func handleFramesExtracted(
        _ frames: [ExtractedFrame],
        roomName: String,
        narration: String? = nil
    ) {
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
        // `narration` is the camera view's lease ID (S4-CD7), resolved against the owner inside the pipeline.
        processingTask = Task { @MainActor [weak self] in
            await self?.runProcessingPipeline(
                frames: frames,
                userId: userId,
                roomName: roomName,
                narrationLeaseId: narration
            )
        }
    }

    /// The §8.9.3 admission every `InventoryAPIClient` call site applies (S4-CD6): the current signed UID is the request's,
    /// the deletion gate is `clear`, and the response is applied only while the Firestore runtime generation it was
    /// dispatched under is still current. Pure, so the fixtures can drive every projection.
    nonisolated static func admits(currentUID: String?, requestUID: String, gate: AccountDeletionGate) -> Bool {
        currentUID == requestUID && gate == .clear
    }

    /// The generation the dispatch ran under; nil before the runtime is installed (the S1 transitional path).
    private func currentRuntimeGeneration() -> FirestoreRuntimeGeneration? {
        FirestoreRuntime.shared.isInstalled ? FirestoreRuntime.provider.published().generation : nil
    }

    /// Internal pipeline. Owns the upload + Cloud Function call, then installs
    /// the Firestore listener and returns. State transitions out of .processing
    /// are driven by the listener (handleSessionUpdate), not by awaiting here.
    private func runProcessingPipeline(
        frames: [ExtractedFrame],
        userId: String,
        roomName: String,
        narrationLeaseId: String? = nil
    ) async {
        do {
            // S4-CD7: every media transfer runs under a lease; the camera's lease is reused, else one is acquired for the
            // scan. No lease (the gate is not clear for this UID) closes the registry: no next segment.
            var lease: NarrationLease?
            if let narrationLeaseId { lease = await artifactOwner.lease(withId: narrationLeaseId) }
            if lease == nil { lease = await artifactOwner.acquire(uid: userId, sessionId: roomName) }
            guard let lease else {
                isProcessing = false
                error = "Scanning is paused while your account is being cleared."
                state = .roomList
                return
            }
            pendingNarration = lease

            // Phase 1 — upload frames to Storage + create session doc, registered as an in-flight transfer whose
            // cancellation cancels the awaiting Task; the transfer settles when that Task exits by return or throw.
            let service = storageService
            let uploadTask = Task { try await service.uploadFrames(frames, userId: userId, roomName: roomName) }
            let handle = await artifactOwner.register(transfer: lease, cancel: { uploadTask.cancel() })
            let session: InventoryScanSession
            do {
                session = try await uploadTask.value
                await artifactOwner.settle(handle)
            } catch {
                await artifactOwner.settle(handle)
                throw error
            }

            // Bail out if the user moved on while we were uploading; a revoked lease drops the buffer.
            guard !Task.isCancelled, await artifactOwner.revalidate(lease) else {
                pendingNarration = nil
                return
            }

            state = .processing(roomName: roomName, progress: "Analyzing room...")

            // Phase 2 — kick off Cloud Function. The complete callable payload
            // is retained if entitlement is denied so a purchase can retry it
            // without uploading or scanning again.
            let narrationForRequest = await artifactOwner.materialize(for: lease)
            pendingNarration = nil
            let request = InventoryProcessingRequest(
                userId: userId,
                sessionId: session.id,
                roomName: roomName,
                frameCount: session.frameCount,
                narration: narrationForRequest
            )
            await processUploadedSession(request)

        } catch {
            // Callable failures are handled in processUploadedSession. This
            // catch is for the frame upload/session-creation phase.
            guard !Task.isCancelled else { return }
            pendingNarration = nil
            self.isProcessing = false
            self.error = error.localizedDescription
            self.state = .roomList
        }
    }

    func processUploadedSession(_ request: InventoryProcessingRequest) async {
        // §8.9.3 admission (S4-CD6): the current signed UID, a clear gate, and the dispatch generation
        let gate = await artifactOwner.currentGate().gate
        guard Self.admits(currentUID: userIDProvider(), requestUID: request.userId, gate: gate) else {
            isProcessing = false
            error = "Scanning is paused while your account is being cleared."
            retainedProcessingRequest = nil
            movePassRequired = false
            state = .roomList
            return
        }
        let dispatchGeneration = currentRuntimeGeneration()
        // a held response across a generation change, a gate change, or an account change is discarded, never applied
        func stillAdmitted() async -> Bool {
            if Task.isCancelled { return false }
            if let dispatchGeneration, !FirestoreRuntime.provider.isCurrent(dispatchGeneration) { return false }
            return Self.admits(currentUID: userIDProvider(), requestUID: request.userId, gate: await artifactOwner.currentGate().gate)
        }
        do {
            try await apiClient.processInventory(request)
            guard await stillAdmitted() else { return }

            retainedProcessingRequest = nil
            movePassRequired = false

            // State transitions out of .processing happen in
            // handleSessionUpdate after the callable accepts this payload.
            installSessionListener(
                userId: request.userId,
                sessionId: request.sessionId,
                roomName: request.roomName
            )
        } catch InventoryError.movePassRequired {
            guard await stillAdmitted() else { return }
            isProcessing = false
            error = nil
            retainedProcessingRequest = request
            movePassRequired = true
            state = .roomList
        } catch {
            guard await stillAdmitted() else { return }
            isProcessing = false
            self.error = error.localizedDescription
            retainedProcessingRequest = nil
            movePassRequired = false
            state = .roomList
        }
    }

    func retryRetainedProcessingRequest() async {
        guard let request = retainedProcessingRequest else {
            movePassRequired = false
            return
        }

        movePassRequired = false
        error = nil
        isProcessing = true
        state = .processing(roomName: request.roomName, progress: "Analyzing room...")
        await processUploadedSession(request)
    }

    func discardRetainedProcessingRequest() {
        retainedProcessingRequest = nil
        movePassRequired = false
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
        // S4 (S4-CD6): the listener is admitted under the UID, gate, and runtime generation it was installed for; a
        // callback already queued when any of them rotates is dropped before it touches state.
        let installedGeneration = currentRuntimeGeneration()

        sessionListener = storageService.observeSession(
            userId: userId,
            sessionId: sessionId
        ) { [weak self] session in
            // Hop to MainActor before touching any observable state.
            // self is captured weakly so a stale callback after manager
            // deallocation is a no-op.
            Task { @MainActor [weak self] in
                guard let self, await self.listenerAdmits(userId: userId, generation: installedGeneration) else { return }
                self.handleSessionUpdate(session, roomName: roomName)
            }
        }
    }

    /// The §8.9.3 admission for a queued listener callback: same UID, clear gate, same runtime generation.
    func listenerAdmits(userId: String, generation: FirestoreRuntimeGeneration?) async -> Bool {
        if let generation, !FirestoreRuntime.provider.isCurrent(generation) { return false }
        return Self.admits(currentUID: userIDProvider(), requestUID: userId, gate: await artifactOwner.currentGate().gate)
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
        retainedProcessingRequest = nil
        if let lease = pendingNarration { let owner = artifactOwner; Task { await owner.release(lease) } }
        pendingNarration = nil
        movePassRequired = false
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

        let db = FirestoreRuntime.firestore()
        let batch = db.batch()

        addRoomWrites(to: batch, db: db, userId: userId)

        let metaRef = db.collection("users").document(userId)
            .collection("inventory").document("_metadata")
        var metadata: [String: Any] = [
            "submissionStatus": SubmissionStatus.draft.rawValue,
            "updatedAt": Timestamp(date: Date())
        ]
        metadata.merge(
            InventoryCoverage.metadata(confirmedRoomIDs: coverageConfirmedRoomIDs),
            uniquingKeysWith: { _, new in new }
        )
        batch.setData(metadata, forDocument: metaRef, merge: true)

        try await batch.commit()

        self.submissionStatus = .draft
    }

    /// Persists edits made after final submission without unlocking inventory.
    func persistRooms() async throws {
        guard let userId, !userId.isEmpty else {
            throw InventoryError.notAuthenticated
        }
        guard scannedRooms.allSatisfy({ !$0.id.isEmpty }) else {
            throw InventoryError.invalidRequest("Inventory room is missing an identifier")
        }

        let db = FirestoreRuntime.firestore()
        let batch = db.batch()
        addRoomWrites(to: batch, db: db, userId: userId)

        let metaRef = db.collection("users").document(userId)
            .collection("inventory").document("_metadata")
        var metadata: [String: Any] = [
            "submissionStatus": SubmissionStatus.submitted.rawValue,
            "updatedAt": Timestamp(date: Date())
        ]
        metadata.merge(
            InventoryCoverage.metadata(confirmedRoomIDs: coverageConfirmedRoomIDs),
            uniquingKeysWith: { _, new in new }
        )
        batch.setData(metadata, forDocument: metaRef, merge: true)
        try await batch.commit()
        self.submissionStatus = .submitted

        guard let identity = await IdentityService.shared.loadOrMigrate(userId: userId),
              let moveDate = identity.moveDate else {
            throw PackingPlanPersistenceError.missingMoveDate
        }
        _ = try await TaskActionService().regeneratePackingPlanFromStoredInventory(
            userId: userId,
            moveDate: moveDate
        )
    }

    /// Final submit — persists every generated output before locking inventory.
    func submitFinal() async throws {
        guard let userId else {
            throw InventoryError.notAuthenticated
        }

        let db = FirestoreRuntime.firestore()
        let metaRef = db.collection("users").document(userId)
            .collection("inventory").document("_metadata")

        var processingMetadata: [String: Any] = [
            "submissionStatus": SubmissionStatus.processing.rawValue,
            "updatedAt": Timestamp(date: Date())
        ]
        processingMetadata.merge(
            InventoryCoverage.metadata(confirmedRoomIDs: coverageConfirmedRoomIDs),
            uniquingKeysWith: { _, new in new }
        )
        let batch = db.batch()
        addRoomWrites(to: batch, db: db, userId: userId)
        batch.setData(processingMetadata, forDocument: metaRef, merge: true)
        try await batch.commit()
        self.submissionStatus = .processing

        guard let identity = await IdentityService.shared.loadOrMigrate(userId: userId),
              let moveDate = identity.moveDate else {
            throw PackingPlanPersistenceError.missingMoveDate
        }

        try await TaskActionService().generatePackingPlan(
            userId: userId,
            rooms: scannedRooms,
            moveDate: moveDate
        )

        var submittedMetadata: [String: Any] = [
            "submissionStatus": SubmissionStatus.submitted.rawValue,
            "submittedAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ]
        submittedMetadata.merge(
            InventoryCoverage.metadata(confirmedRoomIDs: coverageConfirmedRoomIDs),
            uniquingKeysWith: { _, new in new }
        )
        try await metaRef.setData(submittedMetadata, merge: true)

        self.submissionStatus = .submitted
        let cubicFeet = allItems
            .filter(\.shouldMove)
            .reduce(0) { partial, item in
                partial + PricingConstants.cubicFeet(
                    forItemNamed: item.name,
                    scannerEstimate: item.cubicFeet,
                    quantity: item.quantity
                )
            }
        AnalyticsEvents.scanCompleted(
            itemCount: totalItemCount,
            cubicFeet: cubicFeet
        )
    }

    func reset() {
        teardownActiveProcessing()
        scannedRooms = []
        coverageConfirmedRoomIDs = []
        submissionStatus = .draft
        error = nil
        isProcessing = false
        retainedProcessingRequest = nil
        pendingNarration = nil
        movePassRequired = false
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

        let db = FirestoreRuntime.firestore()
        let inventoryRef = db.collection("users").document(userId).collection("inventory")

        let snapshot = try await inventoryRef.getDocuments()
        if !snapshot.documents.isEmpty {
            let batch = db.batch()
            for doc in snapshot.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
        }

        try await TaskActionService().clearPackingPlan(userId: userId)

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

private enum CoveragePersistenceError: Error {
    case readBackMismatch
}

// MARK: - ScannedRoom

struct ScannedRoom: Identifiable {
    let id: String
    let name: String
    var items: [InventoryItem]
    let scannedAt: Date
}
