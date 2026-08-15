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
    private(set) var preparationPages: [MoversPreparationPage] = []
    private(set) var preparationIndex = 0
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
        preparationPages = Self.buildPreparationPages(callSheet: nil)
    }

    static func buildPreparationPages(callSheet: TaskCallSheet?) -> [MoversPreparationPage] {
        var pages = [
            MoversPreparationPage(
                kind: .education,
                title: "If something breaks",
                body: "By law, moving companies only have to pay 60 cents per pound for anything damaged beyond repair.",
                systemImage: "shield.lefthalf.filled",
                accessibilityPrefix: "movers.education.valuationRule",
                primary: .advance
            ),
            MoversPreparationPage(
                kind: .education,
                title: "What that means in real money",
                body: "Say your $1,000 TV weighs 50 pounds and gets destroyed. They legally owe you $30. Not $1,000 — $30.",
                systemImage: "shield.lefthalf.filled",
                accessibilityPrefix: "movers.education.valuationMath",
                primary: .advance
            ),
            MoversPreparationPage(
                kind: .education,
                title: "What to do about it",
                body: "If that doesn't worry you, skip it. If it does, ask every company what additional coverage costs and exactly what it covers — before you book.",
                systemImage: "shield.lefthalf.filled",
                accessibilityPrefix: "movers.education.valuationAction",
                primary: .advance
            ),
            MoversPreparationPage(
                kind: .education,
                title: "How quotes really work",
                body: "A quote is a guess: their hourly rate × how long they think it'll take. A lower total usually just means a smaller guess — the job costs whatever it actually takes. Compare the hourly rates and crew sizes, not the totals.",
                systemImage: "clock.badge.questionmark",
                accessibilityPrefix: "movers.education.estimates",
                primary: .advance
            ),
            MoversPreparationPage(
                kind: .intro,
                title: "Get three quotes",
                body: "Give every company the same facts, then get the rate and time estimate in writing.",
                systemImage: "phone.fill",
                accessibilityPrefix: "movers.equip",
                primary: .advance
            )
        ]

        if let callSheet {
            let sections: [(String, [String], String, String)] = [
                ("What to say", callSheet.say, "text.bubble.fill", "movers.equip.say"),
                ("What to ask", callSheet.ask, "questionmark.bubble.fill", "movers.equip.ask"),
                ("What to get", callSheet.get, "checkmark.seal.fill", "movers.equip.get")
            ]

            for (title, sourceItems, systemImage, accessibilityPrefix) in sections {
                let survivingItems = sourceItems.filter {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                guard !survivingItems.isEmpty else { continue }
                pages.append(
                    MoversPreparationPage(
                        kind: .callSheetSection(items: survivingItems),
                        title: title,
                        body: nil,
                        systemImage: systemImage,
                        accessibilityPrefix: accessibilityPrefix,
                        primary: .advance
                    )
                )
            }
        }

        let finalIndex = pages.count - 1
        return pages.enumerated().map { index, page in
            MoversPreparationPage(
                kind: page.kind,
                title: page.title,
                body: page.body,
                systemImage: page.systemImage,
                accessibilityPrefix: page.accessibilityPrefix,
                primary: index == finalIndex ? .getQuotes : .advance
            )
        }
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

    var currentCardIndex: Int {
        if role == .getQuotes && !isLegacyInline {
            switch stage {
            case .loading, .failure:
                return 0
            case .preparation:
                return preparationIndex
            case .confirmation:
                return preparationPages.count
            case .quotes:
                return 3
            case .matrix:
                return 4
            }
        }

        switch stage {
        case .loading, .preparation, .failure:
            return 0
        case .quotes:
            return 3
        case .matrix, .confirmation:
            return 4
        }
    }

    var cardsRemaining: Int {
        if role == .getQuotes && !isLegacyInline {
            switch stage {
            case .loading, .failure:
                return preparationPages.count + 1
            case .preparation:
                return (preparationPages.count + 1) - preparationIndex
            case .confirmation, .matrix:
                return 1
            case .quotes:
                return 2
            }
        }

        switch stage {
        case .loading, .preparation, .failure:
            return 5
        case .quotes:
            return 2
        case .matrix, .confirmation:
            return 1
        }
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
            rebuildPreparationPages()
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
            return .preparation
        case .compareQuotes:
            return persistedResumeStage ?? .quotes
        case .bookMovers:
            // BOOK_YOUR_MOVERS renders its own screen, never this model.
            return .failure
        }
    }

    // MARK: - Preparation (get-quotes role)

    func advancePreparation() {
        preparationIndex = min(preparationIndex + 1, preparationPages.count - 1)
    }

    func backPreparation() {
        preparationIndex = max(preparationIndex - 1, 0)
    }

    func goBack() {
        switch stage {
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

    private func rebuildPreparationPages() {
        preparationPages = Self.buildPreparationPages(callSheet: callSheet)
        preparationIndex = 0
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
        isLegacyInline: Bool = false,
        callSheet: TaskCallSheet? = nil,
        preparationIndex: Int = 0
    ) {
        self.userId = userId
        self.taskDocumentId = taskDocumentId
        self.quotes = quotes
        self.stage = stage
        self.isLegacyInline = isLegacyInline
        self.callSheet = callSheet
        rebuildPreparationPages()
        self.preparationIndex = min(max(preparationIndex, 0), preparationPages.count - 1)
    }
    #endif
}
