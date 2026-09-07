import FirebaseFirestore
import Foundation
import Testing
@testable import Peezy_4_0

/// S4 (S4-CD3, C9.5.24): `TaskDispositionSurfaceState` maps every stored-contract shape to exactly one member; the
/// gate and the blocked stores map every row to read-only; the tri-state/shared-surface matrix.
struct TaskDispositionSurfaceTests {
    let at = Date(timeIntervalSince1970: 1_800_000_000)

    var v2: [String: Any] {
        ["schema_version": 2, "terminal_kind": "superseded", "superseded_by": "inst_2", "superseded_at": Timestamp(date: at), "visible_status_copy": "Replaced", "visible_status_detail": ["kind": "DATE", "at": Timestamp(date: at)]]
    }
    var v1: [String: Any] {
        ["schema_version": 1, "terminal_kind": "superseded", "superseded_by": "task_doc_9", "visible_status_copy": "Replaced by an updated task"]
    }

    func state(_ raw: [String: Any]?, status: TaskStatus = .upcoming, gate: AccountDeletionGateProjection = .clear, readiness: ReadinessVector = ReadinessVector()) -> TaskDispositionSurfaceState {
        TaskDispositionSurface.state(rawContract: raw, status: status, gateProjection: gate, readiness: readiness)
    }

    @Test func everyStoredContractShapeMapsToExactlyOneMember() {
        // no contract: the row's status decides
        #expect(state(nil) == .actionable(contractPresent: false))
        #expect(state(nil, status: .completed) == .readOnly(reason: .completed, contractPresent: false))
        #expect(state(nil, status: .dismissed) == .readOnly(reason: .dismissed, contractPresent: false))
        // nonterminal policy-absent and policy-bearing contracts are actionable
        #expect(state(["disposition": "USER_ACTION_TRACKED", "owner": "user"]) == .actionable(contractPresent: true))
        #expect(state(["disposition": "WAITING_ON_EXTERNAL", "owner": "peezy", "profile_version": 3]) == .actionable(contractPresent: true))
        // terminal contracts are read-only with their reason
        #expect(state(["disposition": "COMPLETED"]) == .readOnly(reason: .completed, contractPresent: true))
        #expect(state(["disposition": "NOT_APPLICABLE", "terminal_kind": "not_applicable"]) == .readOnly(reason: .dismissed, contractPresent: true))
        #expect(state(["disposition": "USER_ACTION_TRACKED", "terminal_kind": "retired"]) == .readOnly(reason: .dismissed, contractPresent: true))
        // superseded: a valid v2 and a valid legacy v1 record, source naming which
        guard case let .superseded(fresh) = state(v2) else { Issue.record("v2"); return }
        #expect(fresh == SupersededPresentation(source: .v2, supersededBy: "inst_2", supersededAt: at, copy: "Replaced", detailAt: at))
        guard case let .superseded(legacy) = state(v1) else { Issue.record("v1"); return }
        #expect(legacy == SupersededPresentation(source: .legacyV1, supersededBy: "task_doc_9", supersededAt: nil, copy: "Replaced by an updated task", detailAt: nil))
        // a malformed superseded record is read-only malformed_present with no contract, never actionable
        var hybrid = v2; hybrid["schema_version"] = 1
        #expect(state(hybrid) == .readOnly(reason: .malformedPresent, contractPresent: false))
        var mismatch = v2; mismatch["visible_status_detail"] = ["kind": "DATE", "at": Timestamp(date: at.addingTimeInterval(1))]
        #expect(state(mismatch) == .readOnly(reason: .malformedPresent, contractPresent: false))
        var surplus = v1; surplus["superseded_at"] = Timestamp(date: at)
        #expect(state(surplus) == .readOnly(reason: .malformedPresent, contractPresent: false))
        #expect(state(["terminal_kind": "superseded", "superseded_by": "x", "visible_status_copy": "Replaced by an updated task"]) == .readOnly(reason: .malformedPresent, contractPresent: false), "schema-less")
        #expect(state(["schema_version": 3, "terminal_kind": "superseded"]) == .readOnly(reason: .malformedPresent, contractPresent: false))
    }

    @Test func nonclearGateAndBlockedStoresMapEveryRowToReadOnly() {
        for projection in AccountDeletionGateProjection.allCases where projection != .clear {
            #expect(state(nil, gate: projection) == .readOnly(reason: .gateNonclear, contractPresent: false), Comment(rawValue: projection.rawValue))
            #expect(state(v2, gate: projection) == .readOnly(reason: .gateNonclear, contractPresent: true), Comment(rawValue: "\(projection.rawValue) over a superseded record"))
            #expect(state(["disposition": "COMPLETED"], status: .completed, gate: projection) == .readOnly(reason: .gateNonclear, contractPresent: true))
        }
        var readiness = ReadinessVector()
        readiness.route = .blocked(.quarantined(store: .route, recoveryStateDigest: "d", quarantineEnumerable: false, pendingRecordCount: nil))
        #expect(state(nil, readiness: readiness) == .readOnly(reason: .storeBlocked, contractPresent: false))
        #expect(state(v1, readiness: readiness) == .readOnly(reason: .storeBlocked, contractPresent: true))
        var handoff = ReadinessVector()
        handoff.handoff = .blocked(.installationAuthorityInvalid)
        #expect(state(nil, readiness: handoff) == .readOnly(reason: .storeBlocked, contractPresent: false))
        var loading = ReadinessVector()
        loading.reset = .blocked(.recoveredPendingCleanup(store: .reset, recoveryStateDigest: "d"))
        #expect(state(nil, readiness: loading) == .actionable(contractPresent: false), "the reset and workflow stores are not a task row's required set; loading stores never block")
        #expect(TaskDispositionSurface.requiredStores == [.route, .handoff])
        // the gate outranks a blocked store; the union carries no UID, identity, or digest
        #expect(state(nil, gate: .guardingOtherUID, readiness: readiness) == .readOnly(reason: .gateNonclear, contractPresent: false))
        #expect(TaskDispositionReadOnlyReason.allCases.map(\.rawValue) == ["completed", "dismissed", "malformed_present", "gate_nonclear", "store_blocked"])
    }

    @Test func triStateMatrixDrivesTheRowButtonsAndStatusLine() {
        let card = PeezyCard(id: "t", type: .task, title: "Task", subtitle: "", taskId: "c")
        let actionable = TaskRow(task: card, section: .todo, isExpanded: true, onExpandToggle: {}, onAction: { _ in }, surfaceState: .actionable(contractPresent: false))
        guard case .single = actionable.buttonLayout else { Issue.record("actionable rows keep their buttons"); return }
        let readOnly = TaskRow(task: card, section: .todo, isExpanded: true, onExpandToggle: {}, onAction: { _ in }, surfaceState: .readOnly(reason: .gateNonclear, contractPresent: false))
        guard case .none = readOnly.buttonLayout else { Issue.record("read-only rows show no buttons"); return }
        let superseded = TaskRow(task: card, section: .peezyOnIt, isExpanded: true, onExpandToggle: {}, onAction: { _ in }, surfaceState: .superseded(SupersededPresentation(source: .legacyV1, supersededBy: "x", supersededAt: nil, copy: "Replaced by an updated task", detailAt: nil)))
        guard case .none = superseded.buttonLayout else { Issue.record("superseded rows show no buttons"); return }
        let untouched = TaskRow(task: card, section: .todo, isExpanded: true, onExpandToggle: {}, onAction: { _ in })
        guard case .single = untouched.buttonLayout else { Issue.record("a row without a surface state keeps the committed layout"); return }
        #expect(TaskDispositionSurface.statusLine(for: .actionable(contractPresent: false)) == nil && TaskDispositionSurface.statusLine(for: .actionable(contractPresent: true)) == nil)
        #expect(TaskDispositionSurface.statusLine(for: .readOnly(reason: .completed, contractPresent: true)) == nil)
        #expect(TaskDispositionSurface.statusLine(for: .readOnly(reason: .gateNonclear, contractPresent: false)) == "Actions are paused while your account is being cleared.")
        #expect(TaskDispositionSurface.statusLine(for: .readOnly(reason: .storeBlocked, contractPresent: false)) == "Actions are paused until local recovery finishes.")
        #expect(TaskDispositionSurface.statusLine(for: .readOnly(reason: .malformedPresent, contractPresent: false)) == "This task's status could not be read.")
        #expect(TaskDispositionSurface.statusLine(for: .superseded(SupersededPresentation(source: .legacyV1, supersededBy: "x", supersededAt: nil, copy: "Replaced by an updated task", detailAt: nil))) == "Replaced by an updated task")
    }

    /// S4 close-out (Sol round 1, finding 16): the Home queue consumes the union and never inspects the stored map itself; only
    /// `actionable(contractPresent: false)` enters the dose path, a completed/dismissed contractless row leaves the surface, and
    /// every other member is the passive row carrying the union's status line.
    @Test func homeQueueConsumesTheSharedSurfaceStateAndNeverInspectsTheMap() throws {
        let now = Date()
        let plain = PeezyCard(id: "p", type: .task, title: "Plain", subtitle: "", taskId: "c")
        let done = PeezyCard(id: "d", type: .task, title: "Done", subtitle: "", status: .completed)
        let contracted = PeezyCard(id: "c", type: .task, title: "A contract", subtitle: "", dispositionContract: .init(visibleStatusCopy: "Waiting"))
        let superseded = PeezyCard(id: "s", type: .task, title: "B superseded", subtitle: "")
        let gated = PeezyCard(id: "g", type: .task, title: "C gated", subtitle: "")
        let projection = PeezyHomeViewModel.projectHomeTasks([plain, done, contracted, superseded, gated], now: now) { card in
            switch card.id {
            case "p": return .actionable(contractPresent: false)
            case "d": return .readOnly(reason: .completed, contractPresent: false)
            case "c": return .actionable(contractPresent: true)
            case "s": return .superseded(SupersededPresentation(source: .legacyV1, supersededBy: "x", supersededAt: nil, copy: "Replaced by an updated task", detailAt: nil))
            default: return .readOnly(reason: .gateNonclear, contractPresent: false)
            }
        }
        #expect(projection.actionableLegacy.map(\.id) == ["p"], "only a contractless actionable row reaches the dose path")
        #expect(projection.userInProgressLegacy.isEmpty)
        #expect(projection.readOnlyContractStatus.map(\.id) == ["c", "s", "g"], "every nonactionable union member is the passive row, whatever the mapped card says")
        #expect(projection.readOnlyStatusLines == ["s": "Replaced by an updated task", "g": "Actions are paused while your account is being cleared."])
        // the pinned two-argument projection derives the same union from presence alone
        let pinned = PeezyHomeViewModel.projectHomeTasks([plain, contracted, done], now: now)
        #expect(pinned.actionableLegacy.map(\.id) == ["p"] && pinned.readOnlyContractStatus.map(\.id) == ["c"] && pinned.readOnlyStatusLines.isEmpty)
        // the load hands the raw stored map to the surface and never branches on the map itself (source pin)
        let source = try String(contentsOf: repositoryRoot().appendingPathComponent("Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift"), encoding: .utf8)
        #expect(source.contains("TaskDispositionSurface.state(rawContract: rawContracts[card.id]"))
        #expect(!source.contains("if card.dispositionContract != nil {"), "Home no longer classifies by the map's presence itself")
    }
}
