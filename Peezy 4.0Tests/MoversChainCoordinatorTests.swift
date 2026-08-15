import Foundation
import Testing
@testable import Peezy_4_0

// MARK: - Fakes

private struct ChainError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
private final class FakeSpawner: MoversChainSpawning {
    var tokens: [String] = []
    var sources: [String] = []
    var successors: [String] = []
    var failsNext = false

    nonisolated init() {}

    func spawnSuccessor(token: String, sourceTaskDocumentId: String, successorTaskId: String) async throws {
        tokens.append(token)
        sources.append(sourceTaskDocumentId)
        successors.append(successorTaskId)
        if failsNext {
            failsNext = false
            throw ChainError(message: "spawn unavailable")
        }
    }
}

@MainActor
private final class FakePersister: MoversChainPersisting {
    var operations: [String] = []
    var failsNotes = false
    var failsComplete = false
    var failsQuotes = false
    var failsStage = false
    /// When set, completeTask suspends until the gate is released — used to
    /// observe the in-flight state deterministically.
    var completeGate: CheckedContinuation<Void, Never>?
    var holdsComplete = false

    nonisolated init() {}

    func persistNotes(taskDocumentId: String, notes: String) async throws {
        operations.append("notes")
        if failsNotes { throw ChainError(message: "notes write failed") }
    }

    func completeTask(taskDocumentId: String) async throws {
        operations.append("complete")
        if holdsComplete {
            await withCheckedContinuation { continuation in
                completeGate = continuation
            }
        }
        if failsComplete { throw ChainError(message: "completion write failed") }
    }

    func persistQuotes(taskDocumentId: String, quotes: [TaskQuote]) async throws {
        operations.append("quotes")
        if failsQuotes { throw ChainError(message: "quotes write failed") }
    }

    func persistStage(taskDocumentId: String, stage: TaskStage) async throws {
        operations.append("stage:\(stage.rawValue)")
        if failsStage { throw ChainError(message: "stage write failed") }
    }
}

// MARK: - Coordinator tests

@MainActor
struct MoversChainCoordinatorTests {

    private func makeCoordinator() -> (MoversChainCoordinator, FakeSpawner, FakePersister) {
        let spawner = FakeSpawner()
        let persister = FakePersister()
        return (MoversChainCoordinator(spawner: spawner, persister: persister), spawner, persister)
    }

    @Test func tokenIsStableAndExact() {
        #expect(
            MoversChainCoordinator.spawnToken(
                fromCatalogTaskId: "BOOK_MOVERS",
                toCatalogTaskId: "COMPARE_MOVING_QUOTES",
                taskDocumentId: "BOOK_MOVERS"
            ) == "BOOK_MOVERS->COMPARE_MOVING_QUOTES:BOOK_MOVERS"
        )
        // Spawned docs carry random ids — the token uses the doc id verbatim.
        #expect(
            MoversChainCoordinator.spawnToken(
                fromCatalogTaskId: "COMPARE_MOVING_QUOTES",
                toCatalogTaskId: "BOOK_YOUR_MOVERS",
                taskDocumentId: "aZ9x3Random"
            ) == "COMPARE_MOVING_QUOTES->BOOK_YOUR_MOVERS:aZ9x3Random"
        )
    }

    @Test func edgeRunsNotesSpawnCompleteInOrderThenConfirmation() async {
        let (coordinator, spawner, persister) = makeCoordinator()
        let reached = await coordinator.runEdge(
            taskDocumentId: "doc1",
            fromCatalogTaskId: "COMPARE_MOVING_QUOTES",
            toCatalogTaskId: "BOOK_YOUR_MOVERS",
            notes: "my notes"
        )
        #expect(reached)
        #expect(persister.operations == ["notes", "complete"])
        #expect(spawner.successors == ["BOOK_YOUR_MOVERS"])
        #expect(spawner.sources == ["doc1"])
        #expect(coordinator.edgeState == .confirmation)
        #expect(coordinator.isExitLocked)
    }

    @Test func notesFailurePreventsSpawnAndUnlocksExit() async {
        let (coordinator, spawner, persister) = makeCoordinator()
        persister.failsNotes = true
        let reached = await coordinator.runEdge(
            taskDocumentId: "doc1",
            fromCatalogTaskId: "COMPARE_MOVING_QUOTES",
            toCatalogTaskId: "BOOK_YOUR_MOVERS",
            notes: "my notes"
        )
        #expect(!reached)
        #expect(spawner.tokens.isEmpty)
        #expect(!persister.operations.contains("complete"))
        #expect(coordinator.edgeState == .failed("notes write failed"))
        #expect(!coordinator.isExitLocked)
    }

    @Test func spawnFailurePreventsCompletionWrite() async {
        let (coordinator, spawner, persister) = makeCoordinator()
        spawner.failsNext = true
        let reached = await coordinator.runEdge(
            taskDocumentId: "doc1",
            fromCatalogTaskId: "BOOK_MOVERS",
            toCatalogTaskId: "COMPARE_MOVING_QUOTES"
        )
        #expect(!reached)
        #expect(!persister.operations.contains("complete"))
        #expect(coordinator.edgeState == .failed("spawn unavailable"))
        #expect(!coordinator.isExitLocked)
    }

    @Test func completionFailureFailsEdgeWithoutConfirmation() async {
        let (coordinator, _, persister) = makeCoordinator()
        persister.failsComplete = true
        let reached = await coordinator.runEdge(
            taskDocumentId: "doc1",
            fromCatalogTaskId: "BOOK_MOVERS",
            toCatalogTaskId: "COMPARE_MOVING_QUOTES"
        )
        #expect(!reached)
        #expect(coordinator.edgeState == .failed("completion write failed"))
        #expect(!coordinator.isExitLocked)
    }

    @Test func retryAfterFailureReusesTheSameToken() async {
        let (coordinator, spawner, _) = makeCoordinator()
        spawner.failsNext = true
        _ = await coordinator.runEdge(
            taskDocumentId: "doc1",
            fromCatalogTaskId: "BOOK_MOVERS",
            toCatalogTaskId: "COMPARE_MOVING_QUOTES"
        )
        let reached = await coordinator.runEdge(
            taskDocumentId: "doc1",
            fromCatalogTaskId: "BOOK_MOVERS",
            toCatalogTaskId: "COMPARE_MOVING_QUOTES"
        )
        #expect(reached)
        #expect(spawner.tokens.count == 2)
        #expect(spawner.tokens[0] == spawner.tokens[1])
        #expect(spawner.tokens[0] == "BOOK_MOVERS->COMPARE_MOVING_QUOTES:doc1")
    }

    @Test func reentryInFlightAndAfterConfirmationIsSuppressed() async {
        let (coordinator, spawner, persister) = makeCoordinator()
        persister.holdsComplete = true

        let firstEdge = Task {
            await coordinator.runEdge(
                taskDocumentId: "doc1",
                fromCatalogTaskId: "BOOK_MOVERS",
                toCatalogTaskId: "COMPARE_MOVING_QUOTES"
            )
        }
        // Wait until the first edge reaches the held completion write.
        while persister.completeGate == nil {
            await Task.yield()
        }
        #expect(coordinator.edgeState == .inFlight)
        #expect(coordinator.isExitLocked)

        // Double-tap while in flight: suppressed, no second spawn.
        let secondResult = await coordinator.runEdge(
            taskDocumentId: "doc1",
            fromCatalogTaskId: "BOOK_MOVERS",
            toCatalogTaskId: "COMPARE_MOVING_QUOTES"
        )
        #expect(!secondResult)
        #expect(spawner.tokens.count == 1)

        persister.completeGate?.resume()
        persister.completeGate = nil
        #expect(await firstEdge.value)
        #expect(coordinator.edgeState == .confirmation)

        // Re-entry after confirmation (dismiss-reopen on the same instance):
        // suppressed — no respawn, no extra writes.
        let thirdResult = await coordinator.runEdge(
            taskDocumentId: "doc1",
            fromCatalogTaskId: "BOOK_MOVERS",
            toCatalogTaskId: "COMPARE_MOVING_QUOTES"
        )
        #expect(!thirdResult)
        #expect(spawner.tokens.count == 1)
    }

    @Test func emptyDocumentIdFailsWithoutSideEffects() async {
        let (coordinator, spawner, persister) = makeCoordinator()
        let reached = await coordinator.runEdge(
            taskDocumentId: "",
            fromCatalogTaskId: "BOOK_MOVERS",
            toCatalogTaskId: "COMPARE_MOVING_QUOTES"
        )
        #expect(!reached)
        #expect(spawner.tokens.isEmpty)
        #expect(persister.operations.isEmpty)
        #expect(!coordinator.isExitLocked)
    }
}

// MARK: - Handshake + persistence transitions through the view model

@MainActor
struct MoversChainHandshakeTests {

    private func makeModel(
        role: MoversFlowRole,
        quotes: [TaskQuote] = [],
        stage: MoversFlowStage,
        isLegacyInline: Bool = false
    ) -> (MoversFlowViewModel, FakeSpawner, FakePersister) {
        let spawner = FakeSpawner()
        let persister = FakePersister()
        let model = MoversFlowViewModel(role: role, spawner: spawner, persister: persister)
        model._testConfigure(
            userId: "user1",
            taskDocumentId: "docABC",
            quotes: quotes,
            stage: stage,
            isLegacyInline: isLegacyInline
        )
        return (model, spawner, persister)
    }

    private var completeQuote: TaskQuote {
        TaskQuote(company: "Acme", notes: "", crew: 3, hours: 5, perManRate: 50, travelFee: 100)
    }

    @Test func getQuotesEdgeYieldsConfirmationOnly() async {
        let (model, spawner, persister) = makeModel(role: .getQuotes, stage: .equip)
        await model.completeGetQuotes()
        // Durable persistence yields ONLY confirmation state — the local Home
        // callback fires later, from confirmation Done, never here.
        #expect(model.stage == .confirmation)
        #expect(spawner.successors == ["COMPARE_MOVING_QUOTES"])
        #expect(persister.operations == ["complete"])
        #expect(model.chain.isExitLocked)
    }

    @Test func compareEdgePersistsNotesBeforeSpawnAndCompletes() async {
        let (model, spawner, persister) = makeModel(
            role: .compareQuotes,
            quotes: [completeQuote],
            stage: .matrix
        )
        model.notes = "  final notes  "
        await model.completeCompareChain()
        #expect(persister.operations == ["notes", "complete"])
        #expect(spawner.successors == ["BOOK_YOUR_MOVERS"])
        #expect(spawner.tokens == ["COMPARE_MOVING_QUOTES->BOOK_YOUR_MOVERS:docABC"])
        #expect(model.stage == .confirmation)
        #expect(model.notes == "final notes")
    }

    @Test func legacyInlineEdgeSpawnsOnlyBookYourMoversFromBookMovers() async {
        let (model, spawner, _) = makeModel(
            role: .getQuotes,
            quotes: [completeQuote],
            stage: .matrix,
            isLegacyInline: true
        )
        await model.completeCompareChain()
        #expect(spawner.successors == ["BOOK_YOUR_MOVERS"])
        #expect(spawner.tokens == ["BOOK_MOVERS->BOOK_YOUR_MOVERS:docABC"])
        #expect(model.stage == .confirmation)
    }

    @Test func notesFailureBlocksSpawnAndStaysOnMatrix() async {
        let (model, spawner, persister) = makeModel(
            role: .compareQuotes,
            quotes: [completeQuote],
            stage: .matrix
        )
        persister.failsNotes = true
        await model.completeCompareChain()
        #expect(spawner.tokens.isEmpty)
        #expect(model.stage == .matrix)
        #expect(model.actionError != nil)
        #expect(!model.chain.isExitLocked)
    }

    @Test func failedQuoteSaveKeepsRetryableStateAndNeverAdvances() async {
        let (model, _, persister) = makeModel(role: .compareQuotes, stage: .quotes)
        persister.failsQuotes = true
        await model.saveQuote(completeQuote, editing: nil)
        #expect(model.quotes.isEmpty)
        #expect(model.actionError != nil)
        #expect(model.stage == .quotes)

        // Retry after the transient failure clears succeeds and commits.
        persister.failsQuotes = false
        await model.saveQuote(completeQuote, editing: nil)
        #expect(model.quotes.count == 1)
        #expect(model.actionError == nil)
    }

    @Test func failedQuoteDeleteKeepsTheQuote() async {
        let (model, _, persister) = makeModel(
            role: .compareQuotes,
            quotes: [completeQuote],
            stage: .quotes
        )
        persister.failsQuotes = true
        await model.deleteQuote(at: 0)
        #expect(model.quotes.count == 1)
        #expect(model.actionError != nil)
    }

    @Test func failedStageWriteNeverAdvancesToMatrix() async {
        let (model, _, persister) = makeModel(
            role: .compareQuotes,
            quotes: [completeQuote],
            stage: .quotes
        )
        persister.failsStage = true
        await model.summarizeQuotes()
        #expect(model.stage == .quotes)
        #expect(model.actionError != nil)

        persister.failsStage = false
        await model.summarizeQuotes()
        #expect(model.stage == .matrix)
    }
}
