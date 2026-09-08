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
        #expect(routed.map(\.route) == [.row, .outcome(sessionId: nil)] && routed.map(\.taskDocumentId) == ["d", "a"])
        // the C9.3.12 precedence over the raw contract and the document's strictly decoded routing authority
        typealias R = TaskRoutingAuthorityV1
        let waiting: [String: Any] = ["disposition": "WAITING_ON_EXTERNAL"], tracked: [String: Any] = ["disposition": "USER_ACTION_TRACKED"], deferred: [String: Any] = ["disposition": "DEFERRED"]
        #expect(UrgentRecoveryProjection.route(rawContract: waiting, routing: R(pendingConfirmationCoherent: true, returnedHandoffSessionId: "s1")) == .row, "1: a coherent pending confirmation opens only the plan update, never the waiting outcome")
        #expect(UrgentRecoveryProjection.route(rawContract: deferred, routing: R(returnedHandoffSessionId: "s1")) == .row, "2: DEFERRED")
        #expect(UrgentRecoveryProjection.route(rawContract: tracked, routing: R(waitingFallbackValid: true, returnedHandoffSessionId: "s1")) == .row, "3: a valid waiting fallback state")
        #expect(UrgentRecoveryProjection.route(rawContract: tracked, routing: R(returnedHandoffSessionId: "s1")) == .outcome(sessionId: "s1"), "4: USER_ACTION with a returned handoff")
        #expect(UrgentRecoveryProjection.route(rawContract: waiting, routing: R(returnedHandoffSessionId: "s2")) == .outcome(sessionId: "s2"), "4: WAITING with a returned handoff")
        #expect(UrgentRecoveryProjection.route(rawContract: waiting, routing: R()) == .outcome(sessionId: nil), "5: WAITING without a returned handoff")
        #expect(UrgentRecoveryProjection.route(rawContract: tracked, routing: R()) == .row && UrgentRecoveryProjection.route(rawContract: nil, routing: nil) == .row, "6")
        // the strict document decoder: every member proves its row completely or proves nothing
        // the complete precedence-1 authority as `taskPlan.js` writes it for an external supersede
        // byte-shaped like `taskPlan.js`: `cleanReplacement`'s six members with `cleanDescriptor`'s two, and
        // `documentFingerprint`'s unprefixed 64-hex SHA-256
        let descriptor: [String: Any] = ["nextTrigger": ["kind": "date", "at": "2026-10-01T00:00:00.000Z", "payload": ["basis": "derived", "protected_outcome": "Lease signed"]], "resumeDestination": "task_detail"]
        let replacement: [String: Any] = ["taskId": "UPDATE_BANK_ADDRESS", "subject": ["kind": "service", "id": "inst_9"], "institutionId": "inst_9", "institution": "Bank",
                                          "amendmentAction": descriptor, "verification": descriptor]
        let cycle: [String: Any] = ["action": "supersede", "reason": "institution_changed", "revision": 3, "priorStatus": "InProgress", "replacementTaskId": "amend_1",
                                    "replacement": replacement,
                                    "amendmentBaselineFingerprint": String(repeating: "a", count: 64),
                                    "priorDispositionContract": ["disposition": "WAITING_ON_EXTERNAL", "external_submission": true]]
        let coherent: [String: Any] = ["task_instance_id": "ti_a", "planChangeState": "pending_confirmation", "pendingAmendmentTaskId": "amend_1", "planChangeRevision": 3, "planChangeHistory": [["action": "confirm_amendment", "revision": 2], cycle],
                                       "taskInteractionState": ["waiting_fallback_state": ["fallback_evidence_id": "fe_1"]], "activeHandoff": ["state": "returned", "session_id": "s9", "task_instance_id": "ti_a"]]
        #expect(R(document: coherent) == R(pendingConfirmationCoherent: true, waitingFallbackValid: true, returnedHandoffSessionId: "s9"))
        func without(_ key: String) -> [String: Any] { var row = cycle; row[key] = nil; var document = coherent; document["planChangeHistory"] = [row]; return document }
        var noLink = coherent; noLink["pendingAmendmentTaskId"] = nil
        var staleCycle = coherent; staleCycle["planChangeRevision"] = 4
        var otherReplacement = coherent; otherReplacement["planChangeHistory"] = [cycle.merging(["replacementTaskId": "amend_9"]) { _, b in b }]
        func withReplacement(_ change: [String: Any]) -> [String: Any] {
            var document = coherent; document["planChangeHistory"] = [cycle.merging(["replacement": replacement.merging(change) { _, b in b }]) { _, b in b }]; return document
        }
        var garbageReplacement = coherent; garbageReplacement["planChangeHistory"] = [cycle.merging(["replacement": ["garbage": 1]]) { _, b in b }]
        var noVerification = coherent; noVerification["planChangeHistory"] = [cycle.merging(["replacement": ["institution": "Bank", "amendmentAction": descriptor]]) { _, b in b }]
        var emptySnapshot = coherent; emptySnapshot["planChangeHistory"] = [cycle.merging(["priorDispositionContract": [:]]) { _, b in b }]
        var unshapedSnapshot = coherent; unshapedSnapshot["planChangeHistory"] = [cycle.merging(["priorDispositionContract": ["visible_status_copy": "Waiting"]]) { _, b in b }]
        var shortFingerprint = coherent; shortFingerprint["planChangeHistory"] = [cycle.merging(["amendmentBaselineFingerprint": "tf1_" + String(repeating: "a", count: 40)]) { _, b in b }]
        var upperFingerprint = coherent; upperFingerprint["planChangeHistory"] = [cycle.merging(["amendmentBaselineFingerprint": String(repeating: "A", count: 64)]) { _, b in b }]
        var notPending = coherent; notPending["planChangeState"] = "confirmed"
        var noCycleRow = coherent; noCycleRow["planChangeHistory"] = [["action": "undo_confirmation", "revision": 3, "replacementTaskId": "amend_1"]]
        for (name, document) in [("no replacement link on the task", noLink), ("cycle not at the current revision", staleCycle), ("cycle naming another replacement", otherReplacement),
                                 ("an arbitrary nonempty replacement map", garbageReplacement), ("no verification descriptor", noVerification), ("an empty retained snapshot", emptySnapshot),
                                 ("a snapshot with no disposition", unshapedSnapshot), ("a prefixed 44-char fingerprint", shortFingerprint), ("an uppercase fingerprint", upperFingerprint),
                                 ("no source binding", without("amendmentBaselineFingerprint")), ("no retained snapshot member", without("priorDispositionContract")),
                                 ("no replacement descriptor", without("replacement")), ("not pending", notPending), ("no supersede row at all", noCycleRow),
                                 // malformed-present nested authority: every member the server sanitizes, corrupted one at a time
                                 ("an empty verification descriptor", withReplacement(["verification": [:]])),
                                 ("a verification with no resumeDestination", withReplacement(["verification": ["nextTrigger": ["kind": "date"]]])),
                                 ("a blank resumeDestination", withReplacement(["verification": ["nextTrigger": ["kind": "date"], "resumeDestination": "   "]])),
                                 ("a surplus descriptor member", withReplacement(["verification": ["nextTrigger": ["kind": "date"], "resumeDestination": "task_detail", "extra": 1]])),
                                 ("a trigger with no kind", withReplacement(["verification": ["nextTrigger": ["at": "2026-10-01T00:00:00.000Z"], "resumeDestination": "task_detail"]])),
                                 ("a trigger of an unknown kind", withReplacement(["verification": ["nextTrigger": ["kind": "DATE"], "resumeDestination": "task_detail"]])),
                                 ("an empty amendmentAction", withReplacement(["amendmentAction": [:]])),
                                 ("a surplus replacement member", withReplacement(["extra": 1])),
                                 ("a blank institution", withReplacement(["institution": ""])),
                                 ("a blank institutionId", withReplacement(["institutionId": ""])),
                                 ("a blank catalog taskId", withReplacement(["taskId": ""])),
                                 ("a subject with no id", withReplacement(["subject": ["kind": "service"]])),
                                 ("a subject with a blank id", withReplacement(["subject": ["kind": "service", "id": ""]])),
                                 ("an over-long subject id", withReplacement(["subject": ["kind": "service", "id": String(repeating: "x", count: 257)]])),
                                 // every non-temporal identity constraint `validateSpawnRequest` enforces
                                 ("a subject kind outside the approved set", withReplacement(["subject": ["kind": "financial_institution", "id": "inst_9"]])),
                                 ("an untrimmed subject id", withReplacement(["subject": ["kind": "service", "id": " inst_9 "]])),
                                 ("an untrimmed institution", withReplacement(["institution": " Bank "])),
                                 ("an over-long institution", withReplacement(["institution": String(repeating: "b", count: 513)])),
                                 ("an over-long institutionId", withReplacement(["institutionId": String(repeating: "i", count: 257)])),
                                 ("a taskId containing a path separator", withReplacement(["taskId": "catalog/row"])),
                                 ("a taskId of two dots", withReplacement(["taskId": ".."])),
                                 ("a reserved taskId", withReplacement(["taskId": "__name__"])),
                                 ("an over-long taskId", withReplacement(["taskId": String(repeating: "t", count: 257)]))] {
            #expect(!R(document: document).pendingConfirmationCoherent, Comment(rawValue: name))
        }
        #expect(UrgentRecoveryProjection.route(rawContract: waiting, routing: R(document: noLink)) == .outcome(sessionId: "s9"), "an incoherent pending confirmation falls through to the returned WAIT outcome")
        #expect(UrgentRecoveryProjection.route(rawContract: waiting, routing: R(document: garbageReplacement)) == .outcome(sessionId: "s9"), "an arbitrary replacement map never proves precedence 1")
        #expect(UrgentRecoveryProjection.route(rawContract: waiting, routing: R(document: withReplacement(["verification": [:]]))) == .outcome(sessionId: "s9"), "one corrupted nested descriptor falls through to the returned WAIT outcome")
        #expect(UrgentRecoveryProjection.route(rawContract: waiting, routing: R(document: withReplacement(["subject": ["kind": "financial_institution", "id": "inst_9"]]))) == .outcome(sessionId: "s9"), "a subject kind the server would reject never proves precedence 1")
        #expect(TaskRoutingAuthorityV1.approvedSubjectKinds == ["person", "pet", "vehicle", "property", "service", "child"], "the closed set `validateSpawnRequest` accepts")
        // the decoder is never stricter than the writer: `cleanDescriptor` bounds `resumeDestination` only by the request size
        let longDestination: [String: Any] = ["nextTrigger": ["kind": "date"], "resumeDestination": String(repeating: "x", count: 1_025)]
        #expect(R(document: withReplacement(["verification": longDestination])).pendingConfirmationCoherent, "a long but server-storable resumeDestination still proves precedence 1")
        #expect(UrgentRecoveryProjection.route(rawContract: waiting, routing: R(document: withReplacement(["verification": longDestination]))) == .row)
        // trimming parity with the writer's own `String.prototype.trim`, which is neither Foundation's `.whitespaces` nor
        // `.whitespacesAndNewlines`: JavaScript keeps U+0085 and trims U+FEFF, and Foundation does the opposite of both
        #expect(TaskRoutingAuthorityV1.ecmaScriptTrimmed("route\u{0085}") == "route\u{0085}", "U+0085 is not ECMAScript whitespace")
        #expect(TaskRoutingAuthorityV1.ecmaScriptTrimmed("route\u{FEFF}") == "route", "U+FEFF is")
        for (name, scalar) in [("tab", "\u{0009}"), ("line feed", "\u{000A}"), ("vertical tab", "\u{000B}"), ("form feed", "\u{000C}"), ("carriage return", "\u{000D}"), ("space", "\u{0020}"), ("no-break space", "\u{00A0}"), ("ogham space", "\u{1680}"), ("en quad", "\u{2000}"), ("hair space", "\u{200A}"), ("line separator", "\u{2028}"), ("paragraph separator", "\u{2029}"), ("narrow no-break space", "\u{202F}"), ("medium mathematical space", "\u{205F}"), ("ideographic space", "\u{3000}"), ("zero-width no-break space", "\u{FEFF}")] {
            #expect(TaskRoutingAuthorityV1.ecmaScriptTrimmed(scalar + "route" + scalar) == "route", Comment(rawValue: name))
        }
        let keptDestination: [String: Any] = ["nextTrigger": ["kind": "date"], "resumeDestination": "route\u{0085}"]
        #expect(R(document: withReplacement(["verification": keptDestination])).pendingConfirmationCoherent, "a value the writer can store is never rejected: JavaScript does not trim U+0085")
        let bomDestination: [String: Any] = ["nextTrigger": ["kind": "date"], "resumeDestination": "route\u{FEFF}"]
        #expect(!R(document: withReplacement(["verification": bomDestination])).pendingConfirmationCoherent, "a value the writer could never store is never accepted: JavaScript trims U+FEFF")
        #expect(!R(document: withReplacement(["institution": "Bank\u{FEFF}"])).pendingConfirmationCoherent)
        #expect(R(document: withReplacement(["institution": "Bank\u{0085}"])).pendingConfirmationCoherent)
        #expect(TaskRoutingAuthorityV1.isValidDocumentId("UPDATE_BANK_ADDRESS") && !TaskRoutingAuthorityV1.isValidDocumentId("a/b") && !TaskRoutingAuthorityV1.isValidDocumentId(".") && !TaskRoutingAuthorityV1.isValidDocumentId("..") && !TaskRoutingAuthorityV1.isValidDocumentId("__x__") && !TaskRoutingAuthorityV1.isValidDocumentId(String(repeating: "t", count: 257)))
        var malformedFallback = coherent; malformedFallback["planChangeState"] = nil; malformedFallback["taskInteractionState"] = ["waiting_fallback_state": 7]
        #expect(!R(document: malformedFallback).waitingFallbackValid)
        #expect(UrgentRecoveryProjection.route(rawContract: tracked, routing: R(document: malformedFallback)) == .outcome(sessionId: "s9"), "a malformed fallback state proves nothing; the returned handoff routes the outcome")
        var staleHandoff = coherent; staleHandoff["activeHandoff"] = ["state": "returned", "session_id": "s9", "task_instance_id": "ti_previous"]
        var openedHandoff = coherent; openedHandoff["activeHandoff"] = ["state": "opened", "session_id": "s9"]
        var sessionless = coherent; sessionless["activeHandoff"] = ["state": "returned"]
        var camelSession = coherent; camelSession["activeHandoff"] = ["state": "returned", "sessionId": "s9"]
        for (name, document) in [("another instance's handoff", staleHandoff), ("not returned", openedHandoff), ("no session", sessionless), ("wrong member name", camelSession)] {
            #expect(R(document: document).returnedHandoffSessionId == nil, Comment(rawValue: name))
        }
        // the production registry is empty: every classified line is excluded and the rest keep deadline order
        let production = UrgentRecoveryProjection.lines(cards: cards, instanceIds: instances(cards), rawContracts: [:], evidence: mixed, registry: .production)
        #expect(production.map(\.taskDocumentId) == ["d", "a"] && UrgentRecoveryRegistry.production.ranks.isEmpty)
        // zero / one / many rendering
        #expect(UrgentRecoveryProjection.header(for: []) == nil)
        #expect(UrgentRecoveryProjection.header(for: Array(production.prefix(1))) == "Needs attention now", "one line: the same group header")
        #expect(UrgentRecoveryProjection.header(for: production) == "Needs attention now")
        // line content: the policy threshold label/protected outcome and the current owner/action
        let labelled = UrgentRecoveryEvidence(taskDocumentId: "a", taskInstanceId: "ti_a", wakeId: "w_a", urgency: "urgent_recovery", thresholdId: "th1", thresholdAt: "2026-09-09T00:00:00.000Z", thresholdLabel: "Deposit due", protectedOutcome: "Lease signed", consequenceClass: nil, deadlineEvidenceId: "de_a", policyValid: true, basisResolves: true, liveState: .attentionNow(wakeId: "w_a"))
        let content = UrgentRecoveryProjection.lines(cards: cards, instanceIds: instances(cards), rawContracts: ["a": ["disposition": "WAITING_ON_EXTERNAL", "owner": "leasing office", "next_action": "Call before Friday"]], evidence: [labelled], registry: .production)
        #expect(content.map(\.thresholdText) == ["Deposit due \u{00B7} Lease signed"] && content.map(\.ownerActionText) == ["leasing office \u{00B7} Call before Friday"], "the contract's current owner and next_action, never a fabricated route label")
        #expect(UrgentRecoveryProjection.lines(cards: cards, instanceIds: instances(cards), rawContracts: ["a": ["disposition": "WAITING_ON_EXTERNAL", "owner": "peezy"]], evidence: [labelled], registry: .production).map(\.ownerActionText) == ["peezy \u{00B7} Record outcome"], "no next_action: the route's surface")
        #expect(UrgentRecoveryProjection.lines(cards: cards, instanceIds: instances(cards), rawContracts: [:], evidence: [labelled], registry: .production).map(\.ownerActionText) == ["Open task"], "no contract: no owner, the row action")
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
        #expect(store.urgentRecoveryLines == UrgentRecoveryProjection.lines(cards: store.tasks, instanceIds: store.instanceIds, rawContracts: store.rawContracts, routing: store.routing, evidence: evidence, registry: .production), "Home and Tasks consume the same projection")
        #expect(store.urgentRecoveryLines.map(\.route) == [.outcome(sessionId: nil)], "the route comes from the raw stored contract")
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
        #expect(store.rawContracts.isEmpty && store.instanceIds.isEmpty && store.routing.isEmpty)
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
    }
}
