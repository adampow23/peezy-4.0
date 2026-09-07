import FirebaseFirestore
import FirebaseFunctions
import Observation
import SwiftUI

// S4 (briefs/S4_BRIEF.md; P1-Q): the store's namespace, readiness, and revision are qualified by the UID and a fresh
// listener token minted by every `start`; every callback and mutation is guarded by that namespace. Firestore is reached
// only through the seams below (production: the installed `FirestoreRuntime`; no direct Firestore acquisition here, C10.2 L4141).

// MARK: - Namespace and seams

/// The identity every listener callback and mutation is checked against: the UID plus the token of the listener that
/// is currently installed. A late callback from an earlier listener carries a stale token and is dropped.
struct TasksStoreNamespace: Equatable, Sendable {
    let uid: String
    let listenerToken: UUID
}

protocol TasksListenerHandle: Sendable {
    func remove()
}

/// One snapshot: the decoded cards plus every stored `dispositionContract` map unmodified, keyed by task document ID
/// (C9.5.24: the surface decodes the stored map, never the card mapper's projection).
struct TasksSnapshot: Sendable {
    let cards: [PeezyCard]
    let rawContracts: [String: [String: Any]]
    /// Every stored `task_instance_id` string, keyed by task document ID (C9.3.14 instance matching).
    let instanceIds: [String: String]

    init(cards: [PeezyCard], rawContracts: [String: [String: Any]] = [:], instanceIds: [String: String] = [:]) {
        self.cards = cards
        self.rawContracts = rawContracts
        self.instanceIds = instanceIds
    }
}

/// One live snapshot listener over `users/{uid}/tasks`; the callback delivers the snapshot or an error.
protocol TasksSnapshotSource: Sendable {
    func listen(uid: String, onChange: @escaping @Sendable (Result<TasksSnapshot, Error>) -> Void) -> any TasksListenerHandle
}

/// The write seam: one document update under the namespace's UID.
protocol TasksWriter: Sendable {
    func update(uid: String, taskId: String, fields: [String: Any]) async throws
}

/// Production listener over the installed Firestore runtime (acquired only when a listener starts, so constructing
/// the store never touches Firestore).
struct FirestoreTasksSource: TasksSnapshotSource {
    private struct Handle: TasksListenerHandle, @unchecked Sendable {
        let registration: ListenerRegistration
        func remove() { registration.remove() }
    }

    func listen(uid: String, onChange: @escaping @Sendable (Result<TasksSnapshot, Error>) -> Void) -> any TasksListenerHandle {
        let registration = FirestoreRuntime.firestore().collection("users").document(uid).collection("tasks")
            .addSnapshotListener(includeMetadataChanges: false) { snapshot, error in
                if let error { onChange(.failure(error)); return }
                guard let snapshot else { return }
                var rawContracts: [String: [String: Any]] = [:]
                var instanceIds: [String: String] = [:]
                for document in snapshot.documents {
                    if let raw = document.data()["dispositionContract"] as? [String: Any] { rawContracts[document.documentID] = raw }
                    if let instance = document.data()["task_instance_id"] as? String { instanceIds[document.documentID] = instance }
                }
                onChange(.success(TasksSnapshot(cards: snapshot.documents.compactMap { PeezyCardFirestoreMapper.card(from: $0) }, rawContracts: rawContracts, instanceIds: instanceIds)))
            }
        return Handle(registration: registration)
    }
}

struct FirestoreTasksWriter: TasksWriter {
    func update(uid: String, taskId: String, fields: [String: Any]) async throws {
        try await FirestoreRuntime.firestore().collection("users").document(uid).collection("tasks").document(taskId).updateData(fields)
    }
}

// MARK: - C9.3.14 urgent-recovery projection (over injected evidence; the production registry is `{}`)

/// The client's view of one urgent-recovery wake: the retained evidence the projection keys on. Produced by the
/// listener's owner from `wakeEvidence`/`taskInteractionState`; injected as fixtures until S6 writes wake evidence.
struct UrgentRecoveryEvidence: Equatable, Sendable {
    enum LiveState: Equatable, Sendable {
        /// A/W with `ATTENTION_NOW` pointing at this wake.
        case attentionNow(wakeId: String)
        /// Upcoming with the exact threshold/DEFER wake history.
        case upcomingThreshold
        case other
    }

    let taskDocumentId: String
    let taskInstanceId: String
    let wakeId: String
    let urgency: String
    let thresholdId: String
    let thresholdAt: String
    let consequenceClass: String?
    let deadlineEvidenceId: String
    /// The mapped policy is valid and `urgency_basis` resolves byte-for-byte to the retained evidence.
    let policyValid: Bool
    let basisResolves: Bool
    let liveState: LiveState
}

/// Consequence classes → ranks. Every production line uses deadline order until one reviewed Phase 3 source+policy
/// change activates classes; no catalog percentage or label invents a rank.
struct UrgentRecoveryRegistry: Equatable, Sendable {
    let ranks: [String: Int]
    nonisolated static let production = UrgentRecoveryRegistry(ranks: [:])
}

/// One line of the "Needs attention now" group: the policy threshold label and the line's route.
struct UrgentRecoveryLine: Equatable, Identifiable, Sendable {
    enum Route: Equatable, Sendable {
        case row
        case outcome
    }

    let taskDocumentId: String
    let title: String
    let thresholdId: String
    let thresholdAt: String
    let consequenceRank: Int?
    let route: Route

    var id: String { taskDocumentId }
}

enum UrgentRecoveryProjection {
    static let groupTitle = "Needs attention now"

    /// Eligible lines in the C9.3.14 comparison order: classified `(0,rank,threshold_at,threshold_id,task_document_id)`
    /// before unclassified `(1,threshold_at,threshold_id,task_document_id)`; string ties in unsigned UTF-8 order.
    /// The instance rule: the evidence names the exact stored `task_instance_id` of the task document (a document that
    /// stores no instance never matches). The route follows the raw stored contract, never the card mapper's projection.
    static func lines(cards: [PeezyCard], instanceIds: [String: String], rawContracts: [String: [String: Any]], evidence: [UrgentRecoveryEvidence], registry: UrgentRecoveryRegistry) -> [UrgentRecoveryLine] {
        let candidates: [(line: UrgentRecoveryLine, key: [String])] = evidence.compactMap { item in
            guard item.policyValid, item.basisResolves, item.urgency == "urgent_recovery", CanonicalInstant.isCanonical(item.thresholdAt), !item.thresholdId.isEmpty,
                  let card = cards.first(where: { $0.id == item.taskDocumentId }), instanceIds[card.id] == item.taskInstanceId else { return nil }
            switch item.liveState {
            case let .attentionNow(wakeId): guard wakeId == item.wakeId else { return nil }
            case .upcomingThreshold: break
            case .other: return nil
            }
            var rank: Int?
            if let consequenceClass = item.consequenceClass {
                guard let mapped = registry.ranks[consequenceClass] else { return nil } // an unregistered class is excluded, never downgraded
                rank = mapped
            }
            let route: UrgentRecoveryLine.Route = rawContracts[card.id]?["disposition"] as? String == "WAITING_ON_EXTERNAL" ? .outcome : .row
            let line = UrgentRecoveryLine(taskDocumentId: card.id, title: card.title, thresholdId: item.thresholdId, thresholdAt: item.thresholdAt, consequenceRank: rank, route: route)
            let key = rank.map { ["0", String(format: "%020d", $0), item.thresholdAt, item.thresholdId, card.id] } ?? ["1", item.thresholdAt, item.thresholdId, card.id]
            return (line, key)
        }
        return candidates.sorted { lhs, rhs in
            for (l, r) in zip(lhs.key, rhs.key) where l != r { return Array(l.utf8).lexicographicallyPrecedes(Array(r.utf8)) }
            return lhs.key.count < rhs.key.count
        }.map(\.line)
    }

    /// Zero lines: group hidden (nil). One: the task's own header. Many: one "Needs attention now" group.
    static func header(for lines: [UrgentRecoveryLine]) -> String? {
        switch lines.count {
        case 0: return nil
        case 1: return lines[0].title
        default: return groupTitle
        }
    }
}

// MARK: - The store

@Observable
@MainActor
final class TasksStore {
    static let shared = TasksStore(source: FirestoreTasksSource(), writer: FirestoreTasksWriter())

    private(set) var tasks: [PeezyCard] = []
    /// The stored `dispositionContract` maps of the current snapshot, unmodified (C9.5.24 raw-input seam).
    private(set) var rawContracts: [String: [String: Any]] = [:]
    /// The stored `task_instance_id` of every task document in the current snapshot.
    private(set) var instanceIds: [String: String] = [:]
    private(set) var loadState: LoadState = .idle
    private(set) var pendingResetTaskIds: Set<String> = []
    /// The namespace of the installed listener; nil while stopped.
    private(set) var namespace: TasksStoreNamespace?
    /// Increments on every applied snapshot of the current namespace; resets to zero on `start`.
    private(set) var revision: Int = 0
    /// The listener stamps each callback; an out-of-order older snapshot is dropped, so `tasks` never regresses.
    private var lastAppliedSequence = 0

    /// A monotonically increasing stamp handed out on the listener's thread.
    private final class SnapshotSequence: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int { lock.withLock { value += 1; return value } }
    }
    /// C9.3.14 evidence for the current namespace (injected by the listener's owner; empty in production until S6).
    private(set) var urgentRecoveryEvidence: [UrgentRecoveryEvidence] = []
    private(set) var urgentRecoveryRegistry: UrgentRecoveryRegistry = .production

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let source: any TasksSnapshotSource
    private let writer: any TasksWriter
    private var listener: (any TasksListenerHandle)?

    init(source: any TasksSnapshotSource, writer: any TasksWriter) {
        self.source = source
        self.writer = writer
    }

    /// The one shared urgent-recovery projection Home and Tasks consume byte-identically.
    var urgentRecoveryLines: [UrgentRecoveryLine] {
        UrgentRecoveryProjection.lines(cards: tasks, instanceIds: instanceIds, rawContracts: rawContracts, evidence: urgentRecoveryEvidence, registry: urgentRecoveryRegistry)
    }

    // MARK: - Lifecycle

    /// Reuse: the same UID with a live listener keeps it. Otherwise a fresh token is minted and the listener installed
    /// under it; every callback checks the token before touching the store.
    func start(userId: String) {
        if namespace?.uid == userId, listener != nil { return }
        stop()
        let fresh = TasksStoreNamespace(uid: userId, listenerToken: UUID())
        namespace = fresh
        revision = 0
        lastAppliedSequence = 0
        loadState = .loading
        let sequence = SnapshotSequence()
        listener = source.listen(uid: userId) { [weak self] result in
            let stamp = sequence.next()
            Task { @MainActor [weak self] in
                self?.apply(result, for: fresh, sequence: stamp)
            }
        }
    }

    /// Internal for the reordering fixture: a same-token snapshot older than the last applied one never regresses the store.
    func apply(_ result: Result<TasksSnapshot, Error>, for token: TasksStoreNamespace, sequence: Int) {
        guard namespace == token else { return } // a late callback of a retired listener changes nothing
        guard sequence > lastAppliedSequence else { return } // an older snapshot never regresses the store
        lastAppliedSequence = sequence
        switch result {
        case let .failure(error):
            loadState = .failed(error.localizedDescription)
        case let .success(snapshot):
            tasks = snapshot.cards
            rawContracts = snapshot.rawContracts
            instanceIds = snapshot.instanceIds
            revision += 1
            loadState = .loaded
        }
    }

    /// The shared surface state of one row (S4-CD3): the stored map, the row's status, the gate, and readiness.
    func surfaceState(for card: PeezyCard, gateProjection: AccountDeletionGateProjection, readiness: ReadinessVector) -> TaskDispositionSurfaceState {
        TaskDispositionSurface.state(rawContract: rawContracts[card.id], status: card.status, gateProjection: gateProjection, readiness: readiness)
    }

    func stop() {
        listener?.remove()
        listener = nil
        namespace = nil
        revision = 0
        tasks = []
        rawContracts = [:]
        instanceIds = [:]
        urgentRecoveryEvidence = []
        loadState = .idle
    }

    /// Evidence and registry arrive under the namespace they were produced for; a different namespace is ignored.
    func setUrgentRecovery(evidence: [UrgentRecoveryEvidence], registry: UrgentRecoveryRegistry = .production, for namespace: TasksStoreNamespace) {
        guard self.namespace == namespace else { return }
        urgentRecoveryEvidence = evidence
        urgentRecoveryRegistry = registry
    }

    // MARK: - Dispatch

    func dispatch(_ action: TaskAction, onNavigate: @MainActor @escaping (PeezyCard) -> Void) async {
        switch action {
        case .open(let card):
            PeezyHaptics.light()
            onNavigate(card)

        case .markComplete(let card):
            await performWrite(
                taskId: card.id,
                optimistic: { $0.status = .completed; $0.completedAt = Date() },
                revertStatus: card.status,
                revertCompletedAt: card.completedAt,
                firestoreUpdate: [
                    "status": "Completed",
                    "completedAt": FieldValue.serverTimestamp()
                ],
                onSuccess: {
                    ConfettiBus.shared.fire()
                    PeezyHaptics.success()
                },
                onFailure: {
                    ToastManager.shared.show("Couldn't mark complete", style: .error)
                }
            )

        case .undo(let card):
            await performWrite(
                taskId: card.id,
                optimistic: { $0.status = .upcoming; $0.completedAt = nil },
                revertStatus: card.status,
                revertCompletedAt: card.completedAt,
                firestoreUpdate: [
                    "status": "Upcoming",
                    "completedAt": FieldValue.delete()
                ],
                onSuccess: {
                    PeezyHaptics.light()
                    ToastManager.shared.show("\(card.title) moved back to active")
                },
                onFailure: {
                    ToastManager.shared.show("Couldn't undo — please try again", style: .error)
                }
            )

        case .resetInventory(let card):
            await performInventoryReset(card)
        }
    }

    /// Every mutation is bound to the namespace at entry: the write goes to that UID, and the optimistic state is
    /// reverted only while the same namespace is still installed (a namespace change drops the late result).
    private func performWrite(
        taskId: String,
        optimistic: (inout PeezyCard) -> Void,
        revertStatus: TaskStatus,
        revertCompletedAt: Date?,
        firestoreUpdate: [String: Any],
        onSuccess: () -> Void,
        onFailure: () -> Void
    ) async {
        guard let bound = namespace, let idx = tasks.firstIndex(where: { $0.id == taskId }) else {
            onFailure()
            return
        }

        optimistic(&tasks[idx])

        do {
            try await writer.update(uid: bound.uid, taskId: taskId, fields: firestoreUpdate)
            guard namespace == bound else { return }
            onSuccess()
        } catch {
            guard namespace == bound else { return }
            if let i = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[i].status = revertStatus
                tasks[i].completedAt = revertCompletedAt
            }
            onFailure()
        }
    }

    private func performInventoryReset(_ card: PeezyCard) async {
        guard card.isScanInventory, let bound = namespace else { return }
        pendingResetTaskIds.insert(card.id)
        defer { pendingResetTaskIds.remove(card.id) }

        let priorStatus = card.status
        let priorCompletedAt = card.completedAt

        if let i = tasks.firstIndex(where: { $0.id == card.id }) {
            tasks[i].status = .upcoming
            tasks[i].completedAt = nil
        }

        do {
            let manager = InventorySessionManager()
            try await manager.resetInventory()
            guard namespace == bound else { return }
            ToastManager.shared.show("Inventory reset — ready to scan again", style: .success)
            PeezyHaptics.success()
            // No refetch. Listener reconciles.
        } catch {
            guard namespace == bound else { return }
            if let i = tasks.firstIndex(where: { $0.id == card.id }) {
                tasks[i].status = priorStatus
                tasks[i].completedAt = priorCompletedAt
            }
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNotConnectedToInternet {
                ToastManager.shared.show("Inventory reset needs a connection", style: .error)
            } else {
                ToastManager.shared.show("Couldn't reset inventory — please try again", style: .error)
            }
        }
    }
}
