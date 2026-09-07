import Foundation
import Testing
@testable import Peezy_4_0

/// S4 (P1-Q): the store's namespace, readiness, and revision are qualified by UID plus a fresh listener token, every
/// callback and mutation is guarded by it, and the C9.3.14 urgent-recovery projection is one shared pure function.
@MainActor
struct TasksStoreNamespaceTests {

    final class ScriptedTasksSource: TasksSnapshotSource, @unchecked Sendable {
        final class Handle: TasksListenerHandle, @unchecked Sendable {
            let uid: String
            let onChange: @Sendable (Result<TasksSnapshot, Error>) -> Void
            private(set) var removed = false
            init(uid: String, onChange: @escaping @Sendable (Result<TasksSnapshot, Error>) -> Void) { self.uid = uid; self.onChange = onChange }
            func remove() { removed = true }
        }
        private let lock = NSLock()
        private var handles: [Handle] = []
        var listeners: [Handle] { lock.withLock { handles } }
        func listen(uid: String, onChange: @escaping @Sendable (Result<TasksSnapshot, Error>) -> Void) -> any TasksListenerHandle {
            let handle = Handle(uid: uid, onChange: onChange)
            lock.withLock { handles.append(handle) }
            return handle
        }
    }

    final class RecordingTasksWriter: TasksWriter, @unchecked Sendable {
        struct Failure: Error {}
        private let lock = NSLock()
        private var recorded: [String] = []
        private var failing = false
        private var held: CheckedContinuation<Void, Never>?
        private var holding = false
        var updates: [String] { lock.withLock { recorded } }
        func setFailing(_ value: Bool) { lock.withLock { failing = value } }
        func setHold() { lock.withLock { holding = true } }
        var isHolding: Bool { lock.withLock { held != nil } }
        func release() { let continuation: CheckedContinuation<Void, Never>? = lock.withLock { defer { held = nil; holding = false }; return held }; continuation?.resume() }
        func update(uid: String, taskId: String, fields: [String: Any]) async throws {
            let shouldHold: Bool = lock.withLock { recorded.append("\(uid)/\(taskId):\(fields["status"] ?? "")"); return holding }
            if shouldHold { await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in lock.withLock { held = c } } }
            if lock.withLock({ failing }) { throw Failure() }
        }
    }

    func card(_ id: String, title: String = "Task") -> PeezyCard {
        PeezyCard(id: id, type: .task, title: title, subtitle: "", taskId: "CATALOG_\(id)")
    }

    /// Delivers a snapshot through the listener installed for `uid` and lets the main-actor hop settle.
    func deliver(_ source: ScriptedTasksSource, index: Int, _ result: Result<[PeezyCard], Error>, rawContracts: [String: [String: Any]] = [:], instanceIds: [String: String] = [:]) async {
        source.listeners[index].onChange(result.map { TasksSnapshot(cards: $0, rawContracts: rawContracts, instanceIds: instanceIds) })
        for _ in 0..<5 { await Task.yield() }
    }

    /// The stored instance of every card (`ti_<id>`), the shape the evidence fixtures name.
    func instances(_ cards: [PeezyCard]) -> [String: String] { Dictionary(uniqueKeysWithValues: cards.map { ($0.id, "ti_\($0.id)") }) }

    @Test func namespaceIsQualifiedByUIDAndAFreshListenerTokenAndLateCallbacksAreDropped() async throws {
        let source = ScriptedTasksSource()
        let store = TasksStore(source: source, writer: RecordingTasksWriter())
        #expect(store.namespace == nil && store.loadState == .idle && store.revision == 0)
        store.start(userId: "A")
        let first = try #require(store.namespace)
        #expect(first.uid == "A" && store.loadState == .loading && source.listeners.count == 1 && source.listeners[0].uid == "A")
        await deliver(source, index: 0, .success([card("t1")]))
        #expect(store.tasks.map(\.id) == ["t1"] && store.revision == 1 && store.loadState == .loaded)
        await deliver(source, index: 0, .success([card("t1"), card("t2")]))
        #expect(store.revision == 2 && store.tasks.count == 2)
        // reuse: the same UID with a live listener keeps the token and installs nothing
        store.start(userId: "A")
        #expect(store.namespace == first && source.listeners.count == 1)
        // A→B: the retired listener is removed; its late callback carries a stale token and changes nothing
        store.start(userId: "B")
        let second = try #require(store.namespace)
        #expect(second.uid == "B" && second.listenerToken != first.listenerToken && source.listeners[0].removed && store.tasks.isEmpty && store.revision == 0 && store.loadState == .loading)
        await deliver(source, index: 0, .success([card("late-A")]))
        #expect(store.tasks.isEmpty && store.revision == 0 && store.loadState == .loading, "a late A snapshot never reaches B's namespace")
        await deliver(source, index: 0, .failure(RecordingTasksWriter.Failure()))
        #expect(store.loadState == .loading, "a late A error never reaches B's readiness")
        await deliver(source, index: 1, .success([card("b1")]))
        #expect(store.tasks.map(\.id) == ["b1"] && store.revision == 1)
        // stop then start the same UID: a fresh token, readiness and revision from zero
        store.stop()
        #expect(store.namespace == nil && store.tasks.isEmpty && store.loadState == .idle && source.listeners[1].removed)
        await deliver(source, index: 1, .success([card("late-B")]))
        #expect(store.tasks.isEmpty && store.loadState == .idle)
        store.start(userId: "A")
        let third = try #require(store.namespace)
        #expect(third.uid == "A" && third.listenerToken != first.listenerToken && store.revision == 0 && source.listeners.count == 3)
        // late same-UID callback: the first A listener's snapshot carries the retired token and is dropped even though the UID matches
        await deliver(source, index: 0, .success([card("stale-A")]))
        #expect(store.tasks.isEmpty && store.revision == 0 && store.loadState == .loading, "a retired listener of the same UID never reaches the fresh namespace")
        await deliver(source, index: 2, .failure(RecordingTasksWriter.Failure()))
        guard case .failed = store.loadState else { Issue.record("failed readiness"); return }
    }

    @Test func mutationsAreBoundToTheNamespaceAtEntry() async throws {
        let source = ScriptedTasksSource()
        let writer = RecordingTasksWriter()
        let store = TasksStore(source: source, writer: writer)
        // stopped: no write, the failure path only
        await store.dispatch(.markComplete(card("t1"))) { _ in }
        #expect(writer.updates.isEmpty)
        store.start(userId: "A")
        await deliver(source, index: 0, .success([card("t1"), card("t2")]))
        // the write goes to the namespace's UID; success keeps the optimistic state
        await store.dispatch(.markComplete(card("t1"))) { _ in }
        #expect(writer.updates == ["A/t1:Completed"] && store.tasks.first { $0.id == "t1" }?.status == .completed)
        // a failure reverts while the same namespace is installed
        writer.setFailing(true)
        await store.dispatch(.markComplete(card("t2"))) { _ in }
        #expect(store.tasks.first { $0.id == "t2" }?.status == .upcoming)
        writer.setFailing(false)
        // a namespace change during the write drops the late result: B's tasks are never touched by A's revert
        writer.setHold()
        writer.setFailing(true)
        let inflight = Task { await store.dispatch(.undo(card("t1"))) { _ in } }
        while !writer.isHolding { await Task.yield() }
        store.start(userId: "B")
        await deliver(source, index: 1, .success([card("t1", title: "B's t1")]))
        let before = store.tasks
        writer.release()
        await inflight.value
        #expect(store.tasks == before, "the late failure of A's write reverts nothing in B's namespace")
        #expect(writer.updates.last == "A/t1:Upcoming")
    }

    @Test func urgentRecoveryProjectionOrdersClassifiedBeforeUnclassifiedAndExcludesStaleEvidence() {
        let cards = ["a", "b", "c", "d", "e", "f", "g", "h"].map { card($0, title: "Task \($0)") }
        func evidence(_ task: String, at: String = "2026-09-10T00:00:00.000Z", threshold: String = "th1", cls: String? = nil, valid: Bool = true, resolves: Bool = true, live: UrgentRecoveryEvidence.LiveState? = nil, urgency: String = "urgent_recovery") -> UrgentRecoveryEvidence {
            UrgentRecoveryEvidence(taskDocumentId: task, taskInstanceId: "ti_\(task)", wakeId: "w_\(task)", urgency: urgency, thresholdId: threshold, thresholdAt: at, consequenceClass: cls, deadlineEvidenceId: "de_\(task)", policyValid: valid, basisResolves: resolves, liveState: live ?? .attentionNow(wakeId: "w_\(task)"))
        }
        let registry = UrgentRecoveryRegistry(ranks: ["high": 1, "low": 2])
        let mixed = [
            evidence("a", at: "2026-09-09T00:00:00.000Z"),                                   // unclassified, earliest deadline
            evidence("b", at: "2026-09-12T00:00:00.000Z", cls: "low"),                       // classified rank 2
            evidence("c", at: "2026-09-13T00:00:00.000Z", cls: "high"),                      // classified rank 1 → first
            evidence("d", at: "2026-09-09T00:00:00.000Z", threshold: "th0"),                 // unclassified, same instant as a: threshold_id "th0" < "th1"
            evidence("e", cls: "unknown"),                                                   // unregistered class → excluded, never downgraded
            evidence("f", valid: false),                                                     // invalid policy → excluded
            evidence("g", live: .other),                                                     // no attended live state → excluded
            evidence("h", live: .attentionNow(wakeId: "stale")),                             // ATTENTION_NOW pointing at another wake → excluded
            evidence("a", at: "2026-09-09T00:00:00Z"),                                       // noncanonical → excluded
            evidence("zz"),                                                                  // no matching task instance → excluded
            evidence("b", urgency: "normal")                                                 // not urgent → excluded
        ]
        let lines = UrgentRecoveryProjection.lines(cards: cards, instanceIds: instances(cards), rawContracts: [:], evidence: mixed, registry: registry)
        #expect(lines.map(\.taskDocumentId) == ["c", "b", "d", "a"])
        #expect(lines.map(\.consequenceRank) == [1, 2, nil, nil] && lines.allSatisfy { $0.route == .row })
        // equal ranks, instants, and threshold IDs tie by task_document_id in unsigned UTF-8 order
        let ties = [evidence("b", cls: "high"), evidence("a", cls: "high"), evidence("c", cls: "high")]
        #expect(UrgentRecoveryProjection.lines(cards: cards, instanceIds: instances(cards), rawContracts: [:], evidence: ties, registry: registry).map(\.taskDocumentId) == ["a", "b", "c"])
        // the instance rule: evidence for a prior instance sharing the document ID, or a document storing no instance, is excluded
        var staleInstance = instances(cards); staleInstance["c"] = "ti_c_previous"; staleInstance["b"] = nil
        #expect(UrgentRecoveryProjection.lines(cards: cards, instanceIds: staleInstance, rawContracts: [:], evidence: mixed, registry: registry).map(\.taskDocumentId) == ["d", "a"])
        // the route follows the raw stored contract, never the mapped card: WAITING_ON_EXTERNAL routes to the outcome capture
        let routed = UrgentRecoveryProjection.lines(cards: cards, instanceIds: instances(cards), rawContracts: ["a": ["disposition": "WAITING_ON_EXTERNAL", "owner": "peezy"], "d": ["disposition": "USER_ACTION_TRACKED"]], evidence: mixed, registry: .production)
        #expect(routed.map { "\($0.taskDocumentId):\($0.route)" } == ["d:row", "a:outcome"])
        // the production registry is empty: every classified line is excluded and the rest keep deadline order
        let production = UrgentRecoveryProjection.lines(cards: cards, instanceIds: instances(cards), rawContracts: [:], evidence: mixed, registry: .production)
        #expect(production.map(\.taskDocumentId) == ["d", "a"] && UrgentRecoveryRegistry.production.ranks.isEmpty)
        // zero / one / many rendering
        #expect(UrgentRecoveryProjection.header(for: []) == nil)
        #expect(UrgentRecoveryProjection.header(for: Array(production.prefix(1))) == "Task d")
        #expect(UrgentRecoveryProjection.header(for: production) == "Needs attention now")
        // the Upcoming-with-threshold live state is eligible; a mutation of one line leaves its siblings
        let upcoming = [evidence("a", live: .upcomingThreshold), evidence("b", at: "2026-09-11T00:00:00.000Z", live: .upcomingThreshold)]
        let both = UrgentRecoveryProjection.lines(cards: cards, instanceIds: instances(cards), rawContracts: [:], evidence: upcoming, registry: .production)
        #expect(both.map(\.taskDocumentId) == ["a", "b"], "deadline order")
        let afterOne = UrgentRecoveryProjection.lines(cards: cards, instanceIds: instances(cards), rawContracts: [:], evidence: [upcoming[1]], registry: .production)
        #expect(afterOne == [both[1]], "acknowledging one line leaves its sibling's line byte-identical")
    }

    @Test func storeSharesOneProjectionAndIgnoresEvidenceForARetiredNamespace() async throws {
        let source = ScriptedTasksSource()
        let store = TasksStore(source: source, writer: RecordingTasksWriter())
        store.start(userId: "A")
        let namespace = try #require(store.namespace)
        await deliver(source, index: 0, .success([card("a"), card("b")]), rawContracts: ["b": ["disposition": "WAITING_ON_EXTERNAL"]], instanceIds: ["a": "ti_a", "b": "ti"])
        let evidence = [UrgentRecoveryEvidence(taskDocumentId: "b", taskInstanceId: "ti", wakeId: "w", urgency: "urgent_recovery", thresholdId: "th", thresholdAt: "2026-09-10T00:00:00.000Z", consequenceClass: nil, deadlineEvidenceId: "de", policyValid: true, basisResolves: true, liveState: .attentionNow(wakeId: "w"))]
        store.setUrgentRecovery(evidence: evidence, for: TasksStoreNamespace(uid: "A", listenerToken: UUID()))
        #expect(store.urgentRecoveryLines.isEmpty, "evidence for another token is ignored")
        store.setUrgentRecovery(evidence: evidence, for: namespace)
        #expect(store.urgentRecoveryLines == UrgentRecoveryProjection.lines(cards: store.tasks, instanceIds: store.instanceIds, rawContracts: store.rawContracts, evidence: evidence, registry: .production), "Home and Tasks consume the same projection")
        #expect(store.urgentRecoveryLines.map(\.route) == [.outcome], "the route comes from the raw stored contract")
        #expect(store.urgentRecoveryLines.map(\.taskDocumentId) == ["b"])
        store.start(userId: "B")
        #expect(store.urgentRecoveryLines.isEmpty && store.urgentRecoveryEvidence.isEmpty)
        // the stored contract map is retained unmodified and handed to the surface; a namespace change drops it
        await deliver(source, index: 1, .success([card("s")]), rawContracts: ["s": ["schema_version": 2, "terminal_kind": "superseded", "superseded_by": "inst_2", "superseded_at": Date(timeIntervalSince1970: 1_800_000_000), "visible_status_copy": "Replaced", "visible_status_detail": ["kind": "DATE", "at": Date(timeIntervalSince1970: 1_800_000_000)]]])
        #expect(store.rawContracts["s"]?["schema_version"] as? Int == 2)
        guard case .superseded(let presentation) = store.surfaceState(for: card("s"), gateProjection: .clear, readiness: ReadinessVector()) else { Issue.record("superseded"); return }
        #expect(presentation.source == .v2 && presentation.supersededBy == "inst_2")
        #expect(store.surfaceState(for: card("s"), gateProjection: .activeSameUID, readiness: ReadinessVector()) == .readOnly(reason: .gateNonclear, contractPresent: true))
        store.stop()
        #expect(store.rawContracts.isEmpty && store.instanceIds.isEmpty)
    }

    /// S4 close-out (Sol round 1, findings 17/18): a same-token snapshot older than the last applied one never regresses the
    /// store, and both consumers render the one shared group view.
    @Test func aSameTokenSnapshotOlderThanTheLastAppliedNeverRegressesTheStoreAndBothConsumersRenderTheGroup() async throws {
        let source = ScriptedTasksSource()
        let store = TasksStore(source: source, writer: RecordingTasksWriter())
        store.start(userId: "A")
        let namespace = try #require(store.namespace)
        // S2's main-actor hop ran before S1's: S1 arrives with the older stamp and changes nothing
        store.apply(.success(TasksSnapshot(cards: [card("s2")])), for: namespace, sequence: 2)
        #expect(store.tasks.map(\.id) == ["s2"] && store.revision == 1 && store.loadState == .loaded)
        store.apply(.success(TasksSnapshot(cards: [card("s1")])), for: namespace, sequence: 1)
        #expect(store.tasks.map(\.id) == ["s2"] && store.revision == 1, "an older same-token snapshot never regresses cards or revision")
        store.apply(.failure(RecordingTasksWriter.Failure()), for: namespace, sequence: 1)
        #expect(store.loadState == .loaded, "an older same-token error never regresses readiness")
        store.apply(.success(TasksSnapshot(cards: [card("s3")])), for: namespace, sequence: 3)
        #expect(store.tasks.map(\.id) == ["s3"] && store.revision == 2)
        // both consumers render the one shared "Needs attention now" group over `TasksStore.urgentRecoveryLines` (source pin)
        for relative in ["Peezy 4.0/Tasks/Views/TasksList.swift", "Peezy 4.0/MainInterface/Views/PeezyHomeView.swift"] {
            let text = try String(contentsOf: repositoryRoot().appendingPathComponent(relative), encoding: .utf8)
            #expect(text.contains("UrgentRecoveryGroupView(lines:"), Comment(rawValue: relative))
        }
        let home = try String(contentsOf: repositoryRoot().appendingPathComponent("Peezy 4.0/MainInterface/Views/PeezyHomeView.swift"), encoding: .utf8)
        let tab = try String(contentsOf: repositoryRoot().appendingPathComponent("Peezy 4.0/Tasks/Views/TasksTabView.swift"), encoding: .utf8)
        #expect(home.contains("TasksStore.shared.urgentRecoveryLines") && tab.contains("urgentRecoveryLines: store.urgentRecoveryLines"), "one projection, consumed byte-identically")
        #expect(UrgentRecoveryGroupView.actionLabel(for: .row) == "Open task" && UrgentRecoveryGroupView.actionLabel(for: .outcome) == "Record outcome")
    }
}
