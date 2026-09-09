//  HandoffSession.swift
//  Peezy 4.0
//
//  S5 I1 — the durable value types of the handoff store (C9.7.17 file, C9.7.18 records).
//  Values only: no file I/O, no server call, no Keychain access. `HandoffSessionStore`
//  owns all three of those.
//
//  Two rules from C9.7.18 shape everything here and are easy to lose in a later edit:
//
//  1. Transitions are indexed by **event × source phase**, never by phase alone. A
//     phase-only table forbids the edge C9.7.8 L3730 requires — every current-auth
//     RECEIPT or APPLYING row loaded from disk is a `receipt_mismatch`, and on `absent`
//     it returns to DISPATCHED, which a forward-only chain has no way to express.
//  2. The table below covers this store's **own operation edges only**. Every
//     recovery-time removal, drop, replacement and reconstruction is the named C9.7.4
//     recovery action, C9.7.11 choice or C9.7.9 replacement that produces it, on that
//     rule's authority — C9.7.4 L3569: live rows are "never removed/changed except
//     named reconciliation replacement". Do not add those edges here.

import CryptoKit
import Foundation

// MARK: - Vocabulary (C9.7.18)

/// The five HANDOFF-family actions. `cancelHandoff` is the HANDOFF_CANCEL family and
/// never appears on an ordinary record.
enum HandoffAction: String, Sendable, Equatable, CaseIterable {
    case beginHandoff
    case acknowledgeHandoffOpened
    case recordHandoffReturned
    case continueHandoff
    case resolveHandoff
}

/// C9.7.9 L3752 pairs each reason with an exact stored/requester namespace invariant;
/// `HandoffNamespacePair.isReasonPaired` is the only place that invariant is decided.
enum HandoffCancelReason: String, Sendable, Equatable, CaseIterable {
    case authEpochChanged = "AUTH_EPOCH_CHANGED"
    case takeover = "TAKEOVER"
}

enum HandoffSessionPhase: String, Sendable, Equatable, CaseIterable {
    case prepared = "PREPARED"
    case dispatched = "DISPATCHED"
    case receipt = "RECEIPT"
    case applying = "APPLYING"
    case serverSnapshot = "SERVER_SNAPSHOT"
}

enum ReconciliationCancelPhase: String, Sendable, Equatable, CaseIterable {
    case preflight = "PREFLIGHT"
    case prepared = "PREPARED"
    case dispatched = "DISPATCHED"
    case receipt = "RECEIPT"
    case applying = "APPLYING"
}

/// `{installationId, authEpochUUID}` — C9.7.18's requester and stored namespaces.
/// Neither carries a UID or a credential revision (C9.7.9 L3751).
struct HandoffNamespace: Sendable, Equatable, Hashable {
    let installationId: String
    let authEpochUUID: String

    func map() -> [String: Any] { ["installationId": installationId, "authEpochUUID": authEpochUUID] }

    static func from(_ raw: Any?) -> HandoffNamespace? {
        guard let map = raw as? [String: Any], Set(map.keys) == ["installationId", "authEpochUUID"],
              let installationId = map["installationId"] as? String, !installationId.isEmpty,
              let authEpochUUID = map["authEpochUUID"] as? String, !authEpochUUID.isEmpty else { return nil }
        return HandoffNamespace(installationId: installationId, authEpochUUID: authEpochUUID)
    }
}

enum HandoffNamespacePair {
    /// C9.7.9 L3752. Any other pairing is structural corruption, so this is a total
    /// predicate over the two reasons rather than a validation convenience.
    static func isReasonPaired(reason: HandoffCancelReason, stored: HandoffNamespace, requester: HandoffNamespace) -> Bool {
        switch reason {
        case .authEpochChanged:
            return stored.installationId == requester.installationId && stored.authEpochUUID != requester.authEpochUUID
        case .takeover:
            return stored.installationId != requester.installationId
        }
    }
}

// MARK: - Recovery keys (C9.7.6 L3613, L3614)

/// `(uid,installationId,authEpochUUID,taskInstanceId,sessionId)`. Carries no `action`,
/// which is why a C9.7.11 L3793 reconstruction keeps the same key (C9.7.6 L3628).
struct HandoffOrdinaryKey: Sendable, Equatable, Hashable {
    let uid: String
    let installationId: String
    let authEpochUUID: String
    let taskInstanceId: String
    let sessionId: String

    /// The key's own member order, which is the order the C9.7.18 sort compares in.
    var sortMembers: [String] { [uid, installationId, authEpochUUID, taskInstanceId, sessionId] }
}

/// `(uid,taskInstanceId,sessionId,reasonCode,requesterNamespace.installationId,
/// requesterNamespace.authEpochUUID,storedNamespace.installationId,storedNamespace.authEpochUUID)`.
///
/// The two stored members are in the key by S5-CD10. C9.7.9 L3749 replaces **per
/// candidate**, so two lawful ordinary rows differing only in `authEpochUUID` — or only
/// in `installationId` under `TAKEOVER` — replace into two PREFLIGHTs identical on every
/// other member. Without them the key collides and C9.7.6's uniqueness rule calls two
/// required rows unresolved.
struct HandoffCancelKey: Sendable, Equatable, Hashable {
    let uid: String
    let taskInstanceId: String
    let sessionId: String
    let reasonCode: HandoffCancelReason
    let requesterNamespace: HandoffNamespace
    let storedNamespace: HandoffNamespace

    var sortMembers: [String] {
        [uid, taskInstanceId, sessionId, reasonCode.rawValue,
         requesterNamespace.installationId, requesterNamespace.authEpochUUID,
         storedNamespace.installationId, storedNamespace.authEpochUUID]
    }
}

/// C9.7.7's cancellation lineage identity. A lineage is a **group**, not a pair: the
/// ordinary recovery key adds `installationId` and `authEpochUUID` that this identity
/// does not, so one lineage may lawfully hold several ordinary rows in different
/// namespaces. Replacement stays per candidate (C9.7.9 L3749, C9.7.7 L3673).
struct HandoffLineageIdentity: Sendable, Equatable, Hashable {
    let uid: String
    let taskDocumentId: String
    let taskInstanceId: String
    let sessionId: String
}

// MARK: - Ordinary record (C9.7.18)

/// `common = {uid,installationId,authEpochUUID,taskDocumentId,taskInstanceId,sessionId,
/// action,phase,createdAt,updatedAt}` plus the members each phase adds.
///
/// `SERVER_SNAPSHOT` is the one phase that carries **no** `action`: it is reconstructed
/// server authority, not an operation. Its own recovery key *is* the identity key of the
/// row it replaced (C9.7.6 L3628 counts the reconstruction as `recovered`). Where the
/// resumed action comes from is a registered open decision: see `HandoffOrdinaryEvent.resume`.
struct HandoffSessionRecordV1: Sendable, Equatable {
    let uid: String
    let installationId: String
    let authEpochUUID: String
    let taskDocumentId: String
    let taskInstanceId: String
    let sessionId: String
    /// Absent exactly on `SERVER_SNAPSHOT`; immutable wherever present.
    let action: HandoffAction?
    var phase: HandoffSessionPhase
    let createdAt: String
    var updatedAt: String

    let operationId: String?
    /// `UTF-8(TaskCanonicalV1(<the validated callable request>))`, stored and hashed but
    /// never traversed as a hidden object (C9.6.6 L3200).
    let requestCanonicalJSON: String?
    let requestSHA256: String?
    /// `UTF-8(TaskCanonicalV1(<the exact stored server response map>))` — the C9.7.8
    /// `receiptSHA256` hashes exactly these bytes, so the digest has one preimage.
    var receipt: String?
    var applicationId: String?
    /// The canonical server authority C9.7.11 copied, retained byte-for-byte and opaque.
    let serverSnapshot: String?

    var recoveryKey: HandoffOrdinaryKey {
        HandoffOrdinaryKey(uid: uid, installationId: installationId, authEpochUUID: authEpochUUID,
                           taskInstanceId: taskInstanceId, sessionId: sessionId)
    }

    var lineage: HandoffLineageIdentity {
        HandoffLineageIdentity(uid: uid, taskDocumentId: taskDocumentId,
                               taskInstanceId: taskInstanceId, sessionId: sessionId)
    }

    /// C9.7.8 L3698's ordinary identity map. `action` is a member; `taskDocumentId` is
    /// not — this store carries that one for presentation and route consumption and never
    /// contributes it to an identity digest.
    func identityMap() -> [String: Any]? {
        guard let action else { return nil }
        return ["kind": "handoff", "action": action.rawValue, "uid": uid,
                "installationId": installationId, "authEpochUUID": authEpochUUID,
                "taskInstanceId": taskInstanceId, "sessionId": sessionId]
    }
}

// MARK: - Reconciliation-cancel record (C9.7.18)

struct ReconciliationCancelV1: Sendable, Equatable {
    let uid: String
    let taskDocumentId: String
    let taskInstanceId: String
    let sessionId: String
    let reasonCode: HandoffCancelReason
    let storedNamespace: HandoffNamespace
    let requesterNamespace: HandoffNamespace
    var phase: ReconciliationCancelPhase
    let createdAt: String
    var updatedAt: String

    let operationId: String?
    let requestCanonicalJSON: String?
    let requestSHA256: String?
    var receipt: String?
    var applicationId: String?

    var recoveryKey: HandoffCancelKey {
        HandoffCancelKey(uid: uid, taskInstanceId: taskInstanceId, sessionId: sessionId,
                         reasonCode: reasonCode, requesterNamespace: requesterNamespace,
                         storedNamespace: storedNamespace)
    }

    var lineage: HandoffLineageIdentity {
        HandoffLineageIdentity(uid: uid, taskDocumentId: taskDocumentId,
                               taskInstanceId: taskInstanceId, sessionId: sessionId)
    }

    /// C9.7.8 L3699's cancel identity map: flat requester members, no `taskDocumentId`,
    /// and no stored namespace.
    func identityMap() -> [String: Any] {
        ["kind": "handoff_cancel", "uid": uid, "taskInstanceId": taskInstanceId, "sessionId": sessionId,
         "reasonCode": reasonCode.rawValue,
         "requesterInstallationId": requesterNamespace.installationId,
         "requesterAuthEpochUUID": requesterNamespace.authEpochUUID]
    }
}

// MARK: - Application identity (C9.7.18)

enum HandoffApplicationIdentity {
    /// `"hap1_" + first40(SHA-256(TaskCanonicalV1({uid,identity_digest,receipt_sha256})))`.
    static func ordinary(uid: String, identityDigest: String, receiptSHA256: String) -> String {
        "hap1_" + String(TaskCanonicalV1.sha256Hex([
            "uid": uid, "identity_digest": identityDigest, "receipt_sha256": receiptSHA256
        ]).prefix(40))
    }
}

// MARK: - Transitions (C9.7.18, event × source phase)

/// The store's own operation events. Recovery-time removals, drops, replacements and
/// reconstructions are **not** here: each is the named C9.7.4 / C9.7.9 / C9.7.11 rule
/// that produces it.
enum HandoffOrdinaryEvent: Sendable, Equatable {
    case prepare
    case dispatch
    /// The same-process response to the call this row issued: the only edge that stores a
    /// receipt outside recovery (C9.7.8 L3692's frozen first-response behavior, with
    /// L3731 forbidding any first-response notification, accounting or callback).
    case firstResponse
    /// C9.7.4 L3571. Sources are the two receipt-bearing phases only — C9.7.3 L3540
    /// classifies only a receipt-bearing row, so DISPATCHED can never be one.
    case reconcileCommitted(landsInApplying: Bool)
    case reconcileAbsent
    case reconstruct
    /// C9.7.11 L3793's exact-epoch resume. **Not modelled as an edge**: the resumed
    /// action is a registered open decision. The only presentation-time read C9.7.11
    /// offers is L3796's `actionLabel`, a trimmed/bounded *safe-label* string whose
    /// duplicates L3811 disambiguates with ordinals — so it is not injective onto the
    /// five actions and cannot name one. Modelling the edge anyway would either leave a
    /// SERVER_SNAPSHOT and a PREPARED row under one recovery key (permanently unresolved)
    /// or perform a removal no named C9.7.3/C9.7.4/C9.7.6/C9.7.7/C9.7.9/C9.7.11 rule
    /// authorizes. The case exists so the table is honest about the gap.
    case resume
    /// S6's under Decision 11. S5 writes rows into RECEIPT and recovers rows found in
    /// either receipt-bearing phase; it never applies one.
    case apply
    case applied
    case purge
}

enum ReconciliationCancelEvent: Sendable, Equatable {
    case preflight
    case prepare
    case dispatch
    case firstResponse
    case reconcileCommitted(landsInApplying: Bool)
    case reconcileAbsent
    /// C9.7.9 L3750's conclusive-no-commit retirement, lawful only in the same envelope
    /// write that creates the replacement, and never from a receipt-bearing phase because
    /// C9.7.6 L3638 never drops those bytes and L3640 always reruns them.
    case retire
    case apply
    case applied
    case purge
}

/// What an edge does to the row. `.removed` covers both removal-with-replacement and
/// plain removal; the caller's rule decides which, since only it knows the replacement.
enum HandoffTransitionOutcome<Phase: Equatable>: Equatable {
    case created(Phase)
    case moved(to: Phase)
    case removed
}

enum HandoffTransitions {
    /// `nil` means the pair is not an edge, which C9.7.18 makes structural corruption
    /// unless a named C9.7.3/C9.7.4/C9.7.6/C9.7.7/C9.7.9/C9.7.11 rule produces it.
    /// `.resume` is deliberately `nil` from every phase: see `HandoffOrdinaryEvent.resume`.
    static func ordinary(_ event: HandoffOrdinaryEvent,
                         from phase: HandoffSessionPhase?) -> HandoffTransitionOutcome<HandoffSessionPhase>? {
        switch (event, phase) {
        case (.prepare, nil): return .created(.prepared)
        case (.dispatch, .prepared): return .moved(to: .dispatched)
        case (.firstResponse, .dispatched): return .moved(to: .receipt)
        case (.reconcileCommitted(let landsInApplying), .receipt),
             (.reconcileCommitted(let landsInApplying), .applying):
            return .moved(to: landsInApplying ? .applying : .receipt)
        case (.reconcileAbsent, .receipt), (.reconcileAbsent, .applying): return .moved(to: .dispatched)
        case (.reconstruct, nil): return .created(.serverSnapshot)
        case (.apply, .receipt): return .moved(to: .applying)
        case (.applied, .applying): return .removed
        case (.purge, .some): return .removed
        default: return nil
        }
    }

    static func cancel(_ event: ReconciliationCancelEvent,
                       from phase: ReconciliationCancelPhase?) -> HandoffTransitionOutcome<ReconciliationCancelPhase>? {
        switch (event, phase) {
        case (.preflight, nil): return .created(.preflight)
        case (.prepare, .preflight): return .moved(to: .prepared)
        case (.dispatch, .prepared): return .moved(to: .dispatched)
        case (.firstResponse, .dispatched): return .moved(to: .receipt)
        case (.reconcileCommitted(let landsInApplying), .receipt),
             (.reconcileCommitted(let landsInApplying), .applying):
            return .moved(to: landsInApplying ? .applying : .receipt)
        case (.reconcileAbsent, .receipt), (.reconcileAbsent, .applying): return .moved(to: .dispatched)
        case (.retire, .preflight), (.retire, .prepared): return .removed
        case (.apply, .receipt): return .moved(to: .applying)
        case (.applied, .applying): return .removed
        case (.purge, .some): return .removed
        default: return nil
        }
    }

    /// The two edges Decision 11 moved to S6. S5 must not take them, and a test asserts it.
    static let sixthSliceOrdinaryEvents: [HandoffOrdinaryEvent] = [.apply, .applied]
    static let sixthSliceCancelEvents: [ReconciliationCancelEvent] = [.apply, .applied]
}

// MARK: - Per-phase member sets (C9.7.18)

/// The four operation/request/receipt/application members, named once so the required and
/// forbidden sets below cannot drift apart from each other or from `map()`.
enum HandoffRecordMember: String, CaseIterable {
    case operationId, requestCanonicalJSON, requestSHA256, receipt, applicationId, serverSnapshot
}

extension HandoffSessionPhase {
    /// Members this phase requires. Everything in `HandoffRecordMember` not listed here is
    /// forbidden, which is what makes the two sets one statement rather than two.
    var requiredMembers: Set<HandoffRecordMember> {
        switch self {
        case .prepared, .dispatched: return [.operationId, .requestCanonicalJSON, .requestSHA256]
        case .receipt: return [.operationId, .requestCanonicalJSON, .requestSHA256, .receipt]
        case .applying: return [.operationId, .requestCanonicalJSON, .requestSHA256, .receipt, .applicationId]
        case .serverSnapshot: return [.serverSnapshot]
        }
    }

    var forbiddenMembers: Set<HandoffRecordMember> {
        Set(HandoffRecordMember.allCases).subtracting(requiredMembers)
    }

    /// SERVER_SNAPSHOT alone carries no `action` (C9.7.18, S5-CD10).
    var carriesAction: Bool { self != .serverSnapshot }
}

extension ReconciliationCancelPhase {
    var requiredMembers: Set<HandoffRecordMember> {
        switch self {
        case .preflight: return []
        case .prepared, .dispatched: return [.operationId, .requestCanonicalJSON, .requestSHA256]
        case .receipt: return [.operationId, .requestCanonicalJSON, .requestSHA256, .receipt]
        case .applying: return [.operationId, .requestCanonicalJSON, .requestSHA256, .receipt, .applicationId]
        }
    }

    /// A cancel record has no `serverSnapshot` in any phase (C9.7.7 L3674).
    var forbiddenMembers: Set<HandoffRecordMember> {
        Set(HandoffRecordMember.allCases).subtracting(requiredMembers)
    }
}

// MARK: - Ordinary codec

extension HandoffSessionRecordV1 {
    private static let commonKeys: Set<String> = [
        "uid", "installationId", "authEpochUUID", "taskDocumentId", "taskInstanceId",
        "sessionId", "phase", "createdAt", "updatedAt"
    ]

    private func present() -> Set<HandoffRecordMember> {
        var members: Set<HandoffRecordMember> = []
        if operationId != nil { members.insert(.operationId) }
        if requestCanonicalJSON != nil { members.insert(.requestCanonicalJSON) }
        if requestSHA256 != nil { members.insert(.requestSHA256) }
        if receipt != nil { members.insert(.receipt) }
        if applicationId != nil { members.insert(.applicationId) }
        if serverSnapshot != nil { members.insert(.serverSnapshot) }
        return members
    }

    /// The row's member set is exactly its phase's, and `action` is present exactly when
    /// the phase carries one. Anything else is structural corruption, not a repairable row.
    var isWellFormed: Bool {
        present() == phase.requiredMembers
            && (action != nil) == phase.carriesAction
            && CanonicalInstant.isCanonical(createdAt) && CanonicalInstant.isCanonical(updatedAt)
            && !uid.isEmpty && !installationId.isEmpty && !authEpochUUID.isEmpty
            && !taskDocumentId.isEmpty && !taskInstanceId.isEmpty && !sessionId.isEmpty
            && (requestSHA256.map(HandoffDigest.isSHA256Hex) ?? true)
            && (applicationId.map { $0.hasPrefix("hap1_") && $0.count == 45 } ?? true)
    }

    func map() -> [String: Any] {
        var map: [String: Any] = [
            "uid": uid, "installationId": installationId, "authEpochUUID": authEpochUUID,
            "taskDocumentId": taskDocumentId, "taskInstanceId": taskInstanceId, "sessionId": sessionId,
            "phase": phase.rawValue, "createdAt": createdAt, "updatedAt": updatedAt
        ]
        if let action { map["action"] = action.rawValue }
        if let operationId { map["operationId"] = operationId }
        if let requestCanonicalJSON { map["requestCanonicalJSON"] = requestCanonicalJSON }
        if let requestSHA256 { map["requestSHA256"] = requestSHA256 }
        if let receipt { map["receipt"] = receipt }
        if let applicationId { map["applicationId"] = applicationId }
        if let serverSnapshot { map["serverSnapshot"] = serverSnapshot }
        return map
    }

    static func from(_ map: [String: Any]) -> HandoffSessionRecordV1? {
        var keys = Set(map.keys)
        guard commonKeys.isSubset(of: keys) else { return nil }
        keys.subtract(commonKeys)
        let optionalKeys = Set(HandoffRecordMember.allCases.map(\.rawValue)).union(["action"])
        guard keys.isSubset(of: optionalKeys),
              let uid = map["uid"] as? String,
              let installationId = map["installationId"] as? String,
              let authEpochUUID = map["authEpochUUID"] as? String,
              let taskDocumentId = map["taskDocumentId"] as? String,
              let taskInstanceId = map["taskInstanceId"] as? String,
              let sessionId = map["sessionId"] as? String,
              let phaseRaw = map["phase"] as? String, let phase = HandoffSessionPhase(rawValue: phaseRaw),
              let createdAt = map["createdAt"] as? String,
              let updatedAt = map["updatedAt"] as? String else { return nil }
        var action: HandoffAction?
        if let raw = map["action"] {
            guard let value = raw as? String, let parsed = HandoffAction(rawValue: value) else { return nil }
            action = parsed
        }
        func string(_ member: HandoffRecordMember) -> String?? {
            guard let raw = map[member.rawValue] else { return .some(nil) }
            guard let value = raw as? String, !value.isEmpty else { return nil }
            return .some(value)
        }
        guard let operationId = string(.operationId), let requestCanonicalJSON = string(.requestCanonicalJSON),
              let requestSHA256 = string(.requestSHA256), let receipt = string(.receipt),
              let applicationId = string(.applicationId), let serverSnapshot = string(.serverSnapshot)
        else { return nil }
        let record = HandoffSessionRecordV1(
            uid: uid, installationId: installationId, authEpochUUID: authEpochUUID,
            taskDocumentId: taskDocumentId, taskInstanceId: taskInstanceId, sessionId: sessionId,
            action: action, phase: phase, createdAt: createdAt, updatedAt: updatedAt,
            operationId: operationId, requestCanonicalJSON: requestCanonicalJSON,
            requestSHA256: requestSHA256, receipt: receipt, applicationId: applicationId,
            serverSnapshot: serverSnapshot)
        return record.isWellFormed ? record : nil
    }
}

// MARK: - Cancel codec

extension ReconciliationCancelV1 {
    private static let commonKeys: Set<String> = [
        "uid", "taskDocumentId", "taskInstanceId", "sessionId", "reasonCode",
        "storedNamespace", "requesterNamespace", "phase", "createdAt", "updatedAt"
    ]

    private func present() -> Set<HandoffRecordMember> {
        var members: Set<HandoffRecordMember> = []
        if operationId != nil { members.insert(.operationId) }
        if requestCanonicalJSON != nil { members.insert(.requestCanonicalJSON) }
        if requestSHA256 != nil { members.insert(.requestSHA256) }
        if receipt != nil { members.insert(.receipt) }
        if applicationId != nil { members.insert(.applicationId) }
        return members
    }

    var isWellFormed: Bool {
        present() == phase.requiredMembers
            && HandoffNamespacePair.isReasonPaired(reason: reasonCode, stored: storedNamespace, requester: requesterNamespace)
            && CanonicalInstant.isCanonical(createdAt) && CanonicalInstant.isCanonical(updatedAt)
            && !uid.isEmpty && !taskDocumentId.isEmpty && !taskInstanceId.isEmpty && !sessionId.isEmpty
            && (requestSHA256.map(HandoffDigest.isSHA256Hex) ?? true)
            && (applicationId.map { $0.hasPrefix("hap1_") && $0.count == 45 } ?? true)
    }

    func map() -> [String: Any] {
        var map: [String: Any] = [
            "uid": uid, "taskDocumentId": taskDocumentId, "taskInstanceId": taskInstanceId,
            "sessionId": sessionId, "reasonCode": reasonCode.rawValue,
            "storedNamespace": storedNamespace.map(), "requesterNamespace": requesterNamespace.map(),
            "phase": phase.rawValue, "createdAt": createdAt, "updatedAt": updatedAt
        ]
        if let operationId { map["operationId"] = operationId }
        if let requestCanonicalJSON { map["requestCanonicalJSON"] = requestCanonicalJSON }
        if let requestSHA256 { map["requestSHA256"] = requestSHA256 }
        if let receipt { map["receipt"] = receipt }
        if let applicationId { map["applicationId"] = applicationId }
        return map
    }

    static func from(_ map: [String: Any]) -> ReconciliationCancelV1? {
        var keys = Set(map.keys)
        guard commonKeys.isSubset(of: keys) else { return nil }
        keys.subtract(commonKeys)
        // `serverSnapshot` is not in the optional set: a cancel row never carries one.
        let optionalKeys: Set<String> = ["operationId", "requestCanonicalJSON", "requestSHA256", "receipt", "applicationId"]
        guard keys.isSubset(of: optionalKeys),
              let uid = map["uid"] as? String,
              let taskDocumentId = map["taskDocumentId"] as? String,
              let taskInstanceId = map["taskInstanceId"] as? String,
              let sessionId = map["sessionId"] as? String,
              let reasonRaw = map["reasonCode"] as? String, let reasonCode = HandoffCancelReason(rawValue: reasonRaw),
              let storedNamespace = HandoffNamespace.from(map["storedNamespace"]),
              let requesterNamespace = HandoffNamespace.from(map["requesterNamespace"]),
              let phaseRaw = map["phase"] as? String, let phase = ReconciliationCancelPhase(rawValue: phaseRaw),
              let createdAt = map["createdAt"] as? String,
              let updatedAt = map["updatedAt"] as? String else { return nil }
        func string(_ key: String) -> String?? {
            guard let raw = map[key] else { return .some(nil) }
            guard let value = raw as? String, !value.isEmpty else { return nil }
            return .some(value)
        }
        guard let operationId = string("operationId"), let requestCanonicalJSON = string("requestCanonicalJSON"),
              let requestSHA256 = string("requestSHA256"), let receipt = string("receipt"),
              let applicationId = string("applicationId") else { return nil }
        let record = ReconciliationCancelV1(
            uid: uid, taskDocumentId: taskDocumentId, taskInstanceId: taskInstanceId, sessionId: sessionId,
            reasonCode: reasonCode, storedNamespace: storedNamespace, requesterNamespace: requesterNamespace,
            phase: phase, createdAt: createdAt, updatedAt: updatedAt,
            operationId: operationId, requestCanonicalJSON: requestCanonicalJSON,
            requestSHA256: requestSHA256, receipt: receipt, applicationId: applicationId)
        return record.isWellFormed ? record : nil
    }
}

enum HandoffDigest {
    static func isSHA256Hex(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

// MARK: - Payload (C9.7.17)

/// `{installation:{installationId},auth:<signedAuth>,sessions:{records:[…]},
/// reconciliationCancels:[…]}` — the exact four-member set, every member required.
struct HandoffPayloadV1: Sendable, Equatable {
    let installationId: String
    let auth: HandoffSignedAuth
    var records: [HandoffSessionRecordV1]
    var reconciliationCancels: [ReconciliationCancelV1]

    /// C9.7.5 L3593's canonical empty payload: the current Keychain installation, the
    /// resulting signed auth, and both collections empty.
    static func canonicalEmpty(installationId: String, auth: HandoffSignedAuth) -> HandoffPayloadV1 {
        HandoffPayloadV1(installationId: installationId, auth: auth, records: [], reconciliationCancels: [])
    }

    var isEmpty: Bool { records.isEmpty && reconciliationCancels.isEmpty }

    /// C9.7.6 L3624: the counted universe is session elements plus cancel elements; the
    /// `installation` and `auth` singletons are excluded.
    var pendingRecordCount: Int { records.count + reconciliationCancels.count }

    func map() -> [String: Any] {
        ["installation": ["installationId": installationId],
         "auth": auth.map(),
         "sessions": ["records": records.map { $0.map() }],
         "reconciliationCancels": reconciliationCancels.map { $0.map() }]
    }

    static func from(_ map: [String: Any]) -> HandoffPayloadV1? {
        guard Set(map.keys) == ["installation", "auth", "sessions", "reconciliationCancels"],
              let installation = map["installation"] as? [String: Any],
              Set(installation.keys) == ["installationId"],
              let installationId = installation["installationId"] as? String, !installationId.isEmpty,
              let auth = HandoffSignedAuth.from(map["auth"]),
              let sessions = map["sessions"] as? [String: Any], Set(sessions.keys) == ["records"],
              let rawRecords = sessions["records"] as? [[String: Any]],
              let rawCancels = map["reconciliationCancels"] as? [[String: Any]] else { return nil }
        var records: [HandoffSessionRecordV1] = []
        for raw in rawRecords {
            guard let record = HandoffSessionRecordV1.from(raw) else { return nil }
            records.append(record)
        }
        var cancels: [ReconciliationCancelV1] = []
        for raw in rawCancels {
            guard let cancel = ReconciliationCancelV1.from(raw) else { return nil }
            cancels.append(cancel)
        }
        return HandoffPayloadV1(installationId: installationId, auth: auth,
                                records: records, reconciliationCancels: cancels)
    }
}

/// The payload's `auth` singleton (C9.7.9 L3742). SIGNED_OUT carries no `uid` and no
/// `credentialRevision`; the row's revision is always this singleton's, never a record
/// member, which is what C9.7.8 L3687's provenance binds.
enum HandoffSignedAuth: Sendable, Equatable {
    case signedOut(installationId: String, epochUUID: String)
    case signedIn(uid: String, installationId: String, epochUUID: String, credentialRevision: Int)

    var epochUUID: String {
        switch self {
        case .signedOut(_, let epochUUID), .signedIn(_, _, let epochUUID, _): return epochUUID
        }
    }

    var credentialRevision: Int? {
        switch self {
        case .signedOut: return nil
        case .signedIn(_, _, _, let revision): return revision
        }
    }

    func map() -> [String: Any] {
        switch self {
        case .signedOut(let installationId, let epochUUID):
            return ["state": "SIGNED_OUT", "installationId": installationId, "epochUUID": epochUUID]
        case .signedIn(let uid, let installationId, let epochUUID, let revision):
            return ["state": "SIGNED_IN", "uid": uid, "installationId": installationId,
                    "epochUUID": epochUUID, "credentialRevision": revision]
        }
    }

    static func from(_ raw: Any?) -> HandoffSignedAuth? {
        guard let map = raw as? [String: Any], let state = map["state"] as? String,
              let installationId = map["installationId"] as? String, !installationId.isEmpty,
              let epochUUID = map["epochUUID"] as? String, !epochUUID.isEmpty else { return nil }
        switch state {
        case "SIGNED_OUT":
            guard Set(map.keys) == ["state", "installationId", "epochUUID"] else { return nil }
            return .signedOut(installationId: installationId, epochUUID: epochUUID)
        case "SIGNED_IN":
            guard Set(map.keys) == ["state", "uid", "installationId", "epochUUID", "credentialRevision"],
                  let uid = map["uid"] as? String, !uid.isEmpty,
                  let revision = TaskGenerationEpochStamp.safeInteger(map["credentialRevision"]),
                  revision >= 0 else { return nil }
            return .signedIn(uid: uid, installationId: installationId, epochUUID: epochUUID, credentialRevision: revision)
        default:
            return nil
        }
    }
}
