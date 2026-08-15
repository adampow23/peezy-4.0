//
//  MoversFlowViewModel.swift
//  Peezy 4.0
//
//  Movers chain view model (plan v7). One role-driven model backs the
//  get-quotes and compare-quotes flows; BOOK_YOUR_MOVERS has its own screen.
//  Legacy-inline BOOK_MOVERS docs (mid-flight before the chain shipped) resume
//  the old quotes/matrix experience in place and spawn only BOOK_YOUR_MOVERS.
//

import FirebaseFirestore
import Foundation
import Observation

@MainActor
@Observable
final class MoversFlowViewModel {
    private(set) var stage: MoversFlowStage = .loading
    private(set) var quotes: [TaskQuote] = []
    private(set) var callSheet: TaskCallSheet?
    private(set) var inventoryRooms: [ScannedRoom] = []
    private(set) var hasInventory = false
    private(set) var hasSubmittedInventory = false
    private(set) var peezyManHours: Double?
    private(set) var errorMessage: String?
    /// Transient write-failure surface: the flow stays put with retry
    /// affordances instead of silently advancing (plan A6).
    private(set) var actionError: String?
    private(set) var isLegacyInline = false
    private(set) var expertState: ExpertReviewSendState = .notSent
    var notes = ""

    let role: MoversFlowRole
    let chain: MoversChainCoordinator
    let supportService = SupportChatService()

    private var userId = ""
    private var taskDocumentId = ""
    private var persistedResumeStage: MoversFlowStage?
    private let actionService = TaskActionService()
    private var persister: MoversChainPersisting

    init(
        role: MoversFlowRole,
        spawner: MoversChainSpawning = LiveMoversChainSpawner(),
        persister: MoversChainPersisting? = nil
    ) {
        self.role = role
        let resolvedPersister = persister ?? LiveMoversChainPersister(userId: "")
        self.persister = resolvedPersister
        self.chain = MoversChainCoordinator(spawner: spawner, persister: resolvedPersister)
    }

    var canSummarize: Bool {
        !quotes.isEmpty && quotes.allSatisfy { $0.moverQuote != nil }
    }

    var scenarios: [ManHourNormalizer.Scenario] {
        let moverQuotes = quotes.compactMap(\.moverQuote)
        var bases = moverQuotes.map { quote in
            ManHourNormalizer.Basis(
                name: quote.company,
                manHours: Double(quote.crew) * quote.hours,
                isPeezy: false
            )
        }
        if let peezyManHours {
            bases.append(
                ManHourNormalizer.Basis(
                    name: "Peezy",
                    manHours: peezyManHours,
                    isPeezy: true
                )
            )
        }
        return ManHourNormalizer.scenarios(bases: bases, quotes: moverQuotes)
    }

    var supportTaskContext: SupportTaskContext {
        SupportTaskContext(
            userTaskId: taskDocumentId,
            catalogTaskId: isLegacyInline ? "BOOK_MOVERS" : role.catalogTaskId,
            title: "Compare your moving quotes"
        )
    }

    func prepare(userId: String, taskDocumentId: String) async {
        self.userId = userId
        self.taskDocumentId = taskDocumentId
        errorMessage = nil
        actionError = nil
        stage = .loading

        guard !userId.isEmpty, !taskDocumentId.isEmpty else {
            fail("Sign in again to continue collecting mover quotes.")
            return
        }

        do {
            try await loadTaskWorkspace(userId: userId, taskDocumentId: taskDocumentId)
            await loadCallSheet()
            await loadInventoryAndEstimate(userId: userId)
            stage = initialStage()
            if stage == .matrix && !canSummarize {
                stage = .quotes
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func initialStage() -> MoversFlowStage {
        switch role {
        case .getQuotes:
            if isLegacyInline {
                // Legacy resumes in place: verified quotes go to the matrix,
                // everything else (incl. .complete residue) to the quote list.
                return persistedResumeStage ?? (canSummarize ? .matrix : .quotes)
            }
            return .protectionEducation
        case .compareQuotes:
            return persistedResumeStage ?? .quotes
        case .bookMovers:
            // BOOK_YOUR_MOVERS renders its own screen, never this model.
            return .failure
        }
    }

    // MARK: - Education / equip (get-quotes role)

    func advanceEducation() {
        switch stage {
        case .protectionEducation:
            stage = .estimateEducation
        case .estimateEducation:
            stage = .equip
        default:
            break
        }
    }

    func goBack() {
        switch stage {
        case .estimateEducation:
            stage = .protectionEducation
        case .equip:
            stage = .estimateEducation
        case .matrix:
            stage = .quotes
        default:
            break
        }
    }

    // MARK: - Chain edges (plan A1/A2/A5)

    /// "I'm getting quotes": spawn COMPARE_MOVING_QUOTES, then the throwing
    /// completion write. Persistence yields ONLY confirmation state — zero
    /// callbacks fire here; Done routes .completedAlreadyPersisted.
    func completeGetQuotes() async {
        actionError = nil
        let reached = await chain.runEdge(
            taskDocumentId: taskDocumentId,
            fromCatalogTaskId: "BOOK_MOVERS",
            toCatalogTaskId: "COMPARE_MOVING_QUOTES"
        )
        if reached {
            stage = .confirmation
        } else if case .failed(let message) = chain.edgeState {
            actionError = message
        }
    }

    /// Compare Done: notes persist (throwing) BEFORE the spawn — a notes
    /// failure blocks spawning. Then BOOK_YOUR_MOVERS spawns and this task
    /// completes durably.
    func completeCompareChain() async {
        actionError = nil
        notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let predecessor = isLegacyInline ? "BOOK_MOVERS" : "COMPARE_MOVING_QUOTES"
        let reached = await chain.runEdge(
            taskDocumentId: taskDocumentId,
            fromCatalogTaskId: predecessor,
            toCatalogTaskId: "BOOK_YOUR_MOVERS",
            notes: notes
        )
        if reached {
            stage = .confirmation
        } else if case .failed(let message) = chain.edgeState {
            actionError = message
        }
    }

    // MARK: - Quote collection

    func stageForQuoteCollection() async {
        actionError = nil
        do {
            try await persister.persistStage(taskDocumentId: taskDocumentId, stage: .compare)
            stage = .quotes
            persistedResumeStage = .quotes
        } catch {
            actionError = error.localizedDescription
        }
    }

    func summarizeQuotes() async {
        guard canSummarize else { return }
        actionError = nil
        do {
            try await persister.persistStage(taskDocumentId: taskDocumentId, stage: .verify)
            stage = .matrix
            persistedResumeStage = .matrix
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Throwing quote persistence (plan A6): the write succeeds before the
    /// local list mutates, so a failure never advances or silently drops.
    func saveQuote(_ quote: TaskQuote, editing index: Int?) async {
        actionError = nil
        var updated = quotes
        if let index, updated.indices.contains(index) {
            updated[index] = quote
        } else {
            updated.append(quote)
        }
        do {
            try await persister.persistQuotes(taskDocumentId: taskDocumentId, quotes: updated)
            quotes = updated
        } catch {
            actionError = "Couldn't save that quote — check your connection and try again."
        }
    }

    func deleteQuote(at index: Int) async {
        guard quotes.indices.contains(index) else { return }
        actionError = nil
        var updated = quotes
        updated.remove(at: index)
        do {
            try await persister.persistQuotes(taskDocumentId: taskDocumentId, quotes: updated)
            quotes = updated
            if stage == .matrix && !canSummarize {
                stage = .quotes
                persistedResumeStage = .quotes
                try? await persister.persistStage(taskDocumentId: taskDocumentId, stage: .compare)
            }
        } catch {
            actionError = "Couldn't remove that quote — check your connection and try again."
        }
    }

    // MARK: - Expert review (plan GOAL B)

    /// Sends the deterministic quote summary through the existing support
    /// pipeline. The task-doc `expertReview` marker commits atomically with the
    /// message and makes suppression durable across dismiss/reopen. The
    /// non-idempotent callable is never retried.
    @discardableResult
    func sendExpertReview() async -> Bool {
        guard expertState == .notSent else { return false }
        actionError = nil
        expertState = .sending

        let body = ExpertReviewMessageComposer.message(
            quotes: quotes,
            peezyManHours: peezyManHours
        )
        let result = await supportService.sendMessage(
            body,
            taskContext: supportTaskContext,
            atomicTaskMarker: SupportChatService.TaskMarker(
                userId: userId,
                taskDocumentId: taskDocumentId
            )
        )

        if result.persisted {
            expertState = .sent(adminQueued: result.adminQueued)
            return true
        }
        expertState = .notSent
        actionError = "Couldn't send your quotes to support — check your connection and try again."
        return false
    }

    func retry() async {
        await prepare(userId: userId, taskDocumentId: taskDocumentId)
    }

    // MARK: - Loading

    private func loadTaskWorkspace(userId: String, taskDocumentId: String) async throws {
        let snapshot = try await Firestore.firestore()
            .collection("users").document(userId)
            .collection("tasks").document(taskDocumentId)
            .getDocument()
        let data = snapshot.data() ?? [:]
        notes = data["notes"] as? String ?? ""
        quotes = (data["quotes"] as? [[String: Any]] ?? []).compactMap(TaskQuote.init(data:))
        expertState = ExpertReviewSendState.fromMarker(data["expertReview"] as? [String: Any])

        if role == .getQuotes {
            isLegacyInline = MoversLegacyClassifier.isLegacyInline(
                stageRaw: data["stage"] as? String,
                quotesCount: (data["quotes"] as? [[String: Any]])?.count ?? 0
            )
        }

        switch (data["stage"] as? String).flatMap(TaskStage.init(rawValue:)) {
        case .compare:
            persistedResumeStage = .quotes
        case .verify:
            persistedResumeStage = .matrix
        default:
            persistedResumeStage = nil
        }

        // The chain persister needs the caller identity; rebuild the live one
        // now that it is known. Injected test persisters are kept as-is.
        if persister is LiveMoversChainPersister {
            persister = LiveMoversChainPersister(userId: userId)
            chain.replacePersister(persister)
        }
    }

    private func loadCallSheet() async {
        let catalogData = await TaskContentStore.shared.catalogData(for: "BOOK_MOVERS")
        let contentData = catalogData["content"] as? [String: Any] ?? [:]
        callSheet = TaskContent(data: contentData).callSheet
    }

    private func loadInventoryAndEstimate(userId: String) async {
        let manager = InventorySessionManager()
        await manager.loadExistingInventory()
        inventoryRooms = manager.scannedRooms
        let inventoryItems = manager.allItems
        hasInventory = inventoryItems.contains(where: \.shouldMove)
        hasSubmittedInventory = hasInventory && manager.submissionStatus == .submitted
        guard hasInventory else {
            peezyManHours = nil
            return
        }

        let assessment = await loadAssessment(userId: userId)
        let packedStatus = (assessment["packedStatus"] as? String)
            .flatMap(PackedStatus.init(rawValue:)) ?? .unknown
        let scope = MoveScopeFactory.makeScope(
            inventoryItems: inventoryItems,
            assessment: assessment,
            packedStatus: packedStatus
        )
        peezyManHours = PricingEngine.estimatedManHours(for: scope)
    }

    private func loadAssessment(userId: String) async -> [String: Any] {
        guard let snapshot = try? await Firestore.firestore()
            .collection("users").document(userId)
            .collection("user_assessments").limit(to: 1)
            .getDocuments()
        else { return [:] }
        return snapshot.documents.first?.data() ?? [:]
    }

    private func fail(_ message: String) {
        errorMessage = message
        stage = .failure
    }

    #if DEBUG
    /// Test seam: sets the workspace state that `prepare` would otherwise load
    /// from Firestore, so the pure persistence/chain transitions are testable
    /// with injected fakes. Never called by production code.
    func _testConfigure(
        userId: String,
        taskDocumentId: String,
        quotes: [TaskQuote],
        stage: MoversFlowStage,
        isLegacyInline: Bool = false
    ) {
        self.userId = userId
        self.taskDocumentId = taskDocumentId
        self.quotes = quotes
        self.stage = stage
        self.isLegacyInline = isLegacyInline
    }
    #endif
}
