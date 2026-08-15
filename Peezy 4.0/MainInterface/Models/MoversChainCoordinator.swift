//
//  MoversChainCoordinator.swift
//  Peezy 4.0
//
//  Movers three-task spawn chain (plan v7). Flow-local orchestration of the
//  notes→spawn→complete→confirmation sequence with stable per-edge idempotency
//  tokens. The coordinator never owns the Home callback: its terminal output is
//  confirmation state, and only Done's completeTaskFlowAlreadyPersisted() path
//  touches local Home accounting.
//

import FirebaseFirestore
import Foundation
import Observation

// MARK: - Role

/// Explicit role per router case. Spawned task documents carry random IDs, so
/// the role can never be derived from the task document id — the router derives
/// it from the flowId it matched on and passes it alongside `taskDocumentId`.
enum MoversFlowRole: Equatable {
    case getQuotes
    case compareQuotes
    case bookMovers

    var catalogTaskId: String {
        switch self {
        case .getQuotes: "BOOK_MOVERS"
        case .compareQuotes: "COMPARE_MOVING_QUOTES"
        case .bookMovers: "BOOK_YOUR_MOVERS"
        }
    }
}

// MARK: - Legacy classification (pure)

/// Legacy-inline predicate. Stage alone is not enough: historic stage/quote
/// writes swallowed errors, and the old flow wrote `.complete` before Home's
/// detached status write — so `.complete` on an active doc is legacy-terminal
/// residue, and nonempty quotes are legacy regardless of stage.
enum MoversLegacyClassifier {
    static func isLegacyInline(stageRaw: String?, quotesCount: Int) -> Bool {
        if quotesCount > 0 { return true }
        guard let raw = stageRaw, let stage = TaskStage(rawValue: raw) else { return false }
        return stage == .compare || stage == .verify || stage == .complete
    }
}

// MARK: - Title migration (pure payload)

/// The catalog retitle never reaches existing users on its own — generation
/// denormalizes title/desc onto each user task doc and the UI reads that copy.
/// This builds the exact `title` + `desc` payload for an existing BOOK_MOVERS
/// doc, or nil when the stored title already matches.
enum MoversTitleMigration {
    static let chainTitle = "Get Moving Quotes"
    static let chainDesc = "Learn how mover pricing really works, then start collecting binding estimates from three USDOT-licensed movers with the same facts in every hand."
    static let legacyTitle = "Compare your moving quotes"
    static let legacyDesc = "Finish comparing the quotes you already collected, then book the company you choose."

    static func payload(isLegacyInline: Bool, currentTitle: String?) -> [String: Any]? {
        let expectedTitle = isLegacyInline ? legacyTitle : chainTitle
        guard currentTitle != expectedTitle else { return nil }
        return [
            "title": expectedTitle,
            "desc": isLegacyInline ? legacyDesc : chainDesc
        ]
    }
}

// MARK: - Predecessor chips (pure)

/// BOOK_YOUR_MOVERS prefill: quotes live on the predecessor doc (reached via
/// spawnedFrom.id), never on the spawned doc. Dedup preserves entry order.
enum MoversPredecessorChips {
    static func companyChips(fromQuotesData quotesData: [[String: Any]]) -> [String] {
        var seen = Set<String>()
        var chips: [String] = []
        for entry in quotesData {
            guard let company = entry["company"] as? String else { continue }
            let trimmed = company.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            chips.append(trimmed)
        }
        return chips
    }
}

// MARK: - Booking details (pure payload)

/// Durable BOOK_YOUR_MOVERS "Yes" schema: one atomic update carrying the exact
/// status-contract string "Completed" (lowercase decodes as .upcoming and the
/// booked task stays visually active), completedAt, and the bookingDetails map
/// with required booked + savedAt and optional captured fields.
struct MoversBookingDetails: Equatable {
    var company: String?
    var moveDate: Date?
    var arrivalWindow: String?
    var crewSize: Int?
    var crewHourlyRate: Double?

    func completionPayload() -> [String: Any] {
        var details: [String: Any] = [
            "booked": true,
            "savedAt": FieldValue.serverTimestamp()
        ]
        if let company, !company.isEmpty { details["company"] = company }
        if let moveDate { details["moveDate"] = Timestamp(date: moveDate) }
        if let arrivalWindow, !arrivalWindow.isEmpty { details["arrivalWindow"] = arrivalWindow }
        if let crewSize { details["crewSize"] = crewSize }
        if let crewHourlyRate { details["crewHourlyRate"] = crewHourlyRate }
        return [
            "status": "Completed",
            "completedAt": FieldValue.serverTimestamp(),
            "bookingDetails": details
        ]
    }
}

// MARK: - Expert review composition (pure)

/// Deterministic admin-inbox message body. Rates are reported crew-total
/// (stored per-man rate × crew); man-hours are crew × hours.
enum ExpertReviewMessageComposer {
    static func message(quotes: [TaskQuote], peezyManHours: Double?) -> String {
        var lines = ["Expert review request — my moving quotes:"]
        for quote in quotes {
            if let mover = quote.moverQuote {
                let crewRate = mover.perManRate * Double(mover.crew)
                let manHours = Double(mover.crew) * mover.hours
                lines.append(
                    "• \(mover.company): \(mover.crew) crew, "
                    + "\(trimmedNumber(mover.hours)) hrs, "
                    + "$\(trimmedNumber(crewRate))/hr crew rate, "
                    + "$\(trimmedNumber(mover.travelFee)) travel — "
                    + "\(trimmedNumber(manHours)) man-hours"
                )
            } else {
                lines.append("• \(quote.company): details incomplete")
            }
        }
        if let peezyManHours {
            lines.append("Peezy's estimate: \(trimmedNumber(peezyManHours)) man-hours")
        }
        return lines.joined(separator: "\n")
    }

    private static func trimmedNumber(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}

// MARK: - Expert review send state (pure)

/// Durable per-task already-sent state, reconstructed from the mandatory
/// `expertReview` task-doc marker — the persisted message alone can never
/// prove adminQueued (SupportMessage has no queue field and rules bar clients
/// from updating user messages).
enum ExpertReviewSendState: Equatable {
    case notSent
    case sending
    case sent(adminQueued: Bool)

    var buttonDisabled: Bool { self != .notSent }

    var showsDeliveryPendingNotice: Bool {
        if case .sent(adminQueued: false) = self { return true }
        return false
    }

    static func fromMarker(_ marker: [String: Any]?) -> ExpertReviewSendState {
        guard let marker, marker["messageId"] as? String != nil else { return .notSent }
        return .sent(adminQueued: marker["adminQueued"] as? Bool ?? false)
    }
}

// MARK: - Coordinator protocols

protocol MoversChainSpawning {
    func spawnSuccessor(token: String, sourceTaskDocumentId: String, successorTaskId: String) async throws
}

protocol MoversChainPersisting {
    func persistNotes(taskDocumentId: String, notes: String) async throws
    func completeTask(taskDocumentId: String) async throws
    func persistQuotes(taskDocumentId: String, quotes: [TaskQuote]) async throws
    func persistStage(taskDocumentId: String, stage: TaskStage) async throws
}

// MARK: - Coordinator

/// Flow-local, protocol-injected orchestration of one chain edge:
/// notes (optional) → spawn successor (stable token, idempotent replay) →
/// throwing completion write → confirmation state. Zero callbacks fire at
/// persistence; the owning view routes confirmation Done to
/// onStatusAction(.completedAlreadyPersisted).
@MainActor
@Observable
final class MoversChainCoordinator {

    enum EdgeState: Equatable {
        case idle
        case inFlight
        case failed(String)
        case confirmation
    }

    private(set) var edgeState: EdgeState = .idle

    /// Exit-lock contract consumed by the flow container: locked while an edge
    /// is in flight AND through confirmation (Done is the only way out);
    /// unlocked again on failure so the user is never trapped.
    var isExitLocked: Bool {
        edgeState == .inFlight || edgeState == .confirmation
    }

    private let spawner: MoversChainSpawning
    private var persister: MoversChainPersisting

    init(spawner: MoversChainSpawning, persister: MoversChainPersisting) {
        self.spawner = spawner
        self.persister = persister
    }

    /// The live persister needs the signed-in userId, which the owning model
    /// only learns at prepare time. Idle-only swap: never mid-edge.
    func replacePersister(_ persister: MoversChainPersisting) {
        guard edgeState == .idle else { return }
        self.persister = persister
    }

    /// Stable per-edge idempotency token — identical across retries so the
    /// callable's replay path returns the stored result instead of duplicating.
    static func spawnToken(
        fromCatalogTaskId predecessor: String,
        toCatalogTaskId successor: String,
        taskDocumentId: String
    ) -> String {
        "\(predecessor)->\(successor):\(taskDocumentId)"
    }

    /// Runs one edge. Returns true when the chain reached confirmation.
    /// Re-entry while in flight or in confirmation is suppressed (double-tap
    /// and dismiss-reopen protection for the same instance).
    @discardableResult
    func runEdge(
        taskDocumentId: String,
        fromCatalogTaskId predecessor: String,
        toCatalogTaskId successor: String,
        notes: String? = nil
    ) async -> Bool {
        guard edgeState != .inFlight, edgeState != .confirmation else { return false }
        guard !taskDocumentId.isEmpty else {
            edgeState = .failed("This task is missing its identity. Close and reopen it.")
            return false
        }

        edgeState = .inFlight
        do {
            if let notes {
                try await persister.persistNotes(taskDocumentId: taskDocumentId, notes: notes)
            }
            try await spawner.spawnSuccessor(
                token: Self.spawnToken(
                    fromCatalogTaskId: predecessor,
                    toCatalogTaskId: successor,
                    taskDocumentId: taskDocumentId
                ),
                sourceTaskDocumentId: taskDocumentId,
                successorTaskId: successor
            )
            try await persister.completeTask(taskDocumentId: taskDocumentId)
            edgeState = .confirmation
            return true
        } catch {
            edgeState = .failed(error.localizedDescription)
            return false
        }
    }
}

// MARK: - Live adapters

struct LiveMoversChainSpawner: MoversChainSpawning {
    func spawnSuccessor(
        token: String,
        sourceTaskDocumentId: String,
        successorTaskId: String
    ) async throws {
        _ = try await SpawnService().spawn(
            token: token,
            source: SpawnService.Source(kind: "onComplete", id: sourceTaskDocumentId),
            spawns: [SpawnService.Spawn(taskId: successorTaskId)]
        )
    }
}

struct LiveMoversChainPersister: MoversChainPersisting {
    let userId: String
    private let actionService = TaskActionService()

    func persistNotes(taskDocumentId: String, notes: String) async throws {
        try await actionService.updateNotesThrowing(
            userId: userId,
            taskId: taskDocumentId,
            notes: notes
        )
    }

    func completeTask(taskDocumentId: String) async throws {
        try await actionService.completeTaskThrowing(
            userId: userId,
            taskDocumentId: taskDocumentId
        )
    }

    func persistQuotes(taskDocumentId: String, quotes: [TaskQuote]) async throws {
        try await actionService.updateQuotesThrowing(
            userId: userId,
            taskId: taskDocumentId,
            quotes: quotes
        )
    }

    func persistStage(taskDocumentId: String, stage: TaskStage) async throws {
        try await actionService.setStageThrowing(
            userId: userId,
            taskId: taskDocumentId,
            stage: stage
        )
    }
}
