import CryptoKit
import FirebaseFirestore
import Foundation

// S1 (briefs/S1_BRIEF.md): store/state vocabulary, seams, and the startup
// barrier declared by PHASE2_REPLACEMENT_MANIFEST_v9 §7, §8 (967–1008),
// §8.9.3, and PHASE2_CONTRACT C2.4/C2.5. This file performs no file I/O.
// Production conformers live with their owners (S4–S7); every seam is Sendable.

// MARK: - Durable stores and readiness (§8 readiness vector, §7 BlockedSnapshot)

enum DurableStore: String, CaseIterable, Sendable, Codable {
    case route, handoff, reset, workflow
}

/// S4-CD1: the recovery surface's store vocabulary — the four durable stores plus
/// the dose store (`peezy.{uid}.dailyDose.v2`), which is never a `ReadinessVector`
/// member and blocks only the reset's dose cleanup.
enum RecoveryStore: String, CaseIterable, Sendable, Codable, Hashable {
    case route, handoff, reset, workflow, dose

    init(_ store: DurableStore) {
        switch store {
        case .route: self = .route
        case .handoff: self = .handoff
        case .reset: self = .reset
        case .workflow: self = .workflow
        }
    }

    /// The durable store this projects onto; nil for the dose store.
    var durable: DurableStore? {
        switch self {
        case .route: return .route
        case .handoff: return .handoff
        case .reset: return .reset
        case .workflow: return .workflow
        case .dose: return nil
        }
    }
}

enum StoreReadiness: Sendable, Equatable {
    case loading
    case ready
    case blocked(BlockedSnapshot)
}

/// Exact `{route,handoff,reset,workflow}`, each `loading|ready|blocked(BlockedSnapshot)`.
struct ReadinessVector: Sendable, Equatable {
    var route: StoreReadiness = .loading
    var handoff: StoreReadiness = .loading
    var reset: StoreReadiness = .loading
    var workflow: StoreReadiness = .loading

    subscript(store: DurableStore) -> StoreReadiness {
        get {
            switch store {
            case .route: return route
            case .handoff: return handoff
            case .reset: return reset
            case .workflow: return workflow
            }
        }
        set {
            switch store {
            case .route: route = newValue
            case .handoff: handoff = newValue
            case .reset: reset = newValue
            case .workflow: workflow = newValue
            }
        }
    }
}

enum StorageIOErrorCode: String, CaseIterable, Sendable, Codable {
    case fileOpenFailed = "FILE_OPEN_FAILED"
    case fileReadFailed = "FILE_READ_FAILED"
    case fileWriteFailed = "FILE_WRITE_FAILED"
    case fileFsyncFailed = "FILE_FSYNC_FAILED"
    case fileRenameFailed = "FILE_RENAME_FAILED"
    case directoryFsyncFailed = "DIRECTORY_FSYNC_FAILED"
    case fileUnlinkFailed = "FILE_UNLINK_FAILED"
    case fileProtectionFailed = "FILE_PROTECTION_FAILED"
}

enum KeychainUnavailableCode: String, CaseIterable, Sendable, Codable {
    case load = "KEYCHAIN_LOAD_FAILED"
    case update = "KEYCHAIN_UPDATE_FAILED"
    case add = "KEYCHAIN_ADD_FAILED"
}

/// Stored six-phase reset vocabulary (§5 phase table).
enum ResetRowPhase: String, CaseIterable, Sendable, Codable {
    case prepared
    case resetDispatched = "reset_dispatched"
    case resetReceiptDeleting = "reset_receipt/deleting"
    case resetReceiptAwaitingLocalReset = "reset_receipt/awaiting_local_reset"
    case finalizeDispatched = "finalize_dispatched"
    case finalReceipt = "final_receipt"
    case applying
}

/// Exact per-phase recovery action (§5).
enum ResetRecoveryAction: String, CaseIterable, Sendable, Codable {
    case retryReset = "retry_reset"
    case resumeServerDeletion = "resume_server_deletion"
    case runLocalCleanup = "run_local_cleanup"
    case retryFinalize = "retry_finalize"
    case applyFinal = "apply_final"
}

struct ResetEpochOccupant: Sendable, Equatable, Codable {
    let expectedTaskGenerationEpoch: Int
    let phase: ResetRowPhase
    let recoveryAction: ResetRecoveryAction
}

struct ForeignInstallationObservation: Sendable, Equatable {
    let targetPresent: Bool
    let targetEnumerable: Bool
    let targetPendingRecordCount: Int?
    let quarantinePresent: Bool
    let quarantineEnumerable: Bool
    let quarantinePendingRecordCount: Int?
}

struct ForeignDecisionGroup: Sendable, Equatable {
    let decisionDigest: String
    let actionLabel: String
}

/// §7 total startup-blocked union. `availableActions` is the exact ordered list
/// each member exposes.
enum BlockedSnapshot: Sendable, Equatable {
    case quarantined(store: DurableStore, recoveryStateDigest: String, quarantineEnumerable: Bool, pendingRecordCount: Int?)
    case collision(store: DurableStore, recoveryStateDigest: String, quarantineEnumerable: Bool, pendingRecordCount: Int?)
    case recoveredPendingCleanup(store: DurableStore, recoveryStateDigest: String)
    case quarantineConflict(store: DurableStore, recoveryStateDigest: String, quarantineEnumerable: Bool, pendingRecordCount: Int?)
    case receiptMismatch(store: DurableStore, recoveryStateDigest: String, mismatchIdentityDigest: String)
    case resetEpochConflict(recoveryStateDigest: String, actionableExpectedTaskGenerationEpoch: Int, occupants: [ResetEpochOccupant])
    case foreignInstallation(recoveryStateDigest: String, observation: ForeignInstallationObservation)
    case foreignResolutionRequired(recoveryStateDigest: String, resolutionDigest: String, observation: ForeignInstallationObservation, decisionGroups: [ForeignDecisionGroup])
    case storageIOUnavailable(store: DurableStore, errorCode: StorageIOErrorCode)
    case installationAuthorityUnavailable(errorCode: KeychainUnavailableCode)
    case installationAuthorityInvalid
    /// S4-CD1: the `peezy.{uid}.dailyDose.v2` bytes fail the C9.5.16 grammar; every byte and
    /// every legacy key is untouched; the sole action copies the bytes aside before removal.
    case doseMalformed(recoveryStateDigest: String, bytesSHA256: String, byteLength: Int)

    var store: RecoveryStore {
        switch self {
        case let .quarantined(store, _, _, _), let .collision(store, _, _, _),
             let .recoveredPendingCleanup(store, _), let .quarantineConflict(store, _, _, _),
             let .receiptMismatch(store, _, _), let .storageIOUnavailable(store, _):
            return RecoveryStore(store)
        case .resetEpochConflict:
            return .reset
        case .foreignInstallation, .foreignResolutionRequired,
             .installationAuthorityUnavailable, .installationAuthorityInvalid:
            return .handoff
        case .doseMalformed:
            return .dose
        }
    }

    var state: String {
        switch self {
        case .quarantined: return "quarantined"
        case .collision: return "collision"
        case .recoveredPendingCleanup: return "recovered_pending_cleanup"
        case .quarantineConflict: return "quarantine_conflict"
        case .receiptMismatch: return "receipt_mismatch"
        case .resetEpochConflict: return "reset_epoch_conflict"
        case .foreignInstallation: return "foreign_installation"
        case .foreignResolutionRequired: return "foreign_resolution_required"
        case .storageIOUnavailable: return "storage_io_unavailable"
        case .installationAuthorityUnavailable: return "installation_authority_unavailable"
        case .installationAuthorityInvalid: return "installation_authority_invalid"
        case .doseMalformed: return "malformed"
        }
    }

    var availableActions: [String] {
        switch self {
        case let .quarantined(_, _, enumerable, _), let .collision(_, _, enumerable, _):
            return enumerable ? ["recover", "discard_quarantine"] : ["discard_quarantine"]
        case .recoveredPendingCleanup:
            return ["retry_cleanup"]
        case let .quarantineConflict(_, _, enumerable, _):
            return enumerable ? ["merge", "discard_quarantine"] : ["discard_quarantine"]
        case .receiptMismatch, .foreignInstallation:
            return ["reconcile"]
        case .resetEpochConflict:
            return ["recover_epoch"]
        case .foreignResolutionRequired:
            return ["resolve"]
        case .storageIOUnavailable, .installationAuthorityUnavailable:
            return ["retry"]
        case .installationAuthorityInvalid:
            return ["repair_installation_identity"]
        case .doseMalformed:
            return ["quarantine_dose_bytes"]
        }
    }

    var recoveryStateDigest: String? {
        switch self {
        case let .quarantined(_, digest, _, _), let .collision(_, digest, _, _),
             let .recoveredPendingCleanup(_, digest), let .quarantineConflict(_, digest, _, _),
             let .receiptMismatch(_, digest, _), let .resetEpochConflict(digest, _, _),
             let .foreignInstallation(digest, _), let .foreignResolutionRequired(digest, _, _, _),
             let .doseMalformed(digest, _, _):
            return digest
        case .storageIOUnavailable, .installationAuthorityUnavailable, .installationAuthorityInvalid:
            return nil
        }
    }
}

/// Closed result of every S4 recovery method (§7).
enum RecoveryResult: Sendable, Equatable {
    case ready
    case blocked(BlockedSnapshot)
    /// `{schemaVersion:1,reason:"RECOVERY_BUSY",store}`
    case busy(store: RecoveryStore)
    /// `{schemaVersion:1,reason:"RECOVERY_ACTION_UNAVAILABLE",store}`
    case unavailable(store: RecoveryStore)
}

// MARK: - S4 recovery observation, attempt keys, actions, and the store-owner protocol (C9.7.12, C9.7.14; S4-CD1, S4-CD5, S4-CD7)

/// `FileObservationV1` — one durable file as observed by its owner (C9.7.12).
enum FileObservationV1: Sendable, Equatable {
    case absent
    case valid(byteLength: Int, bytesSHA256: String, generationId: String, envelopeSHA256: String)
    case malformed(byteLength: Int, bytesSHA256: String)
    case overCap(byteLength: Int, fileIdentityDigest: String)

    var canonical: [String: Any] {
        switch self {
        case .absent:
            return ["present": false]
        case let .valid(byteLength, bytesSHA256, generationId, envelopeSHA256):
            return ["present": true, "classification": "valid", "byteLength": byteLength, "bytesSHA256": bytesSHA256, "generationId": generationId, "envelopeSHA256": envelopeSHA256]
        case let .malformed(byteLength, bytesSHA256):
            return ["present": true, "classification": "malformed", "byteLength": byteLength, "bytesSHA256": bytesSHA256]
        case let .overCap(byteLength, fileIdentityDigest):
            return ["present": true, "classification": "over_cap", "byteLength": byteLength, "fileIdentityDigest": fileIdentityDigest]
        }
    }

    /// `fileIdentityDigest` over the fstat tuple (base-10 strings) of an opened no-follow descriptor.
    static func fileIdentityDigest(device: UInt64, inode: UInt64, size: UInt64, mtimeSeconds: Int64, mtimeNanoseconds: Int64, ctimeSeconds: Int64, ctimeNanoseconds: Int64) -> String {
        TaskCanonicalV1.sha256Hex([
            "deviceDecimal": String(device), "inodeDecimal": String(inode), "sizeDecimal": String(size),
            "mtimeSecondsDecimal": String(mtimeSeconds), "mtimeNanosecondsDecimal": String(mtimeNanoseconds),
            "ctimeSecondsDecimal": String(ctimeSeconds), "ctimeNanosecondsDecimal": String(ctimeNanoseconds),
        ])
    }
}

/// Handoff-only observations that enter the observed state after authority success (C9.7.12).
enum FirebaseObservationV1: Sendable, Equatable {
    case signedOut
    case signedIn(uid: String)

    var canonical: [String: Any] {
        switch self {
        case .signedOut: return ["state": "signed_out"]
        case let .signedIn(uid): return ["state": "signed_in", "uid": uid]
        }
    }
}

/// `RecoveryObservedStateV1` (C9.7.12): the exact map whose canonical SHA-256 is the
/// `recoveryStateDigest` every digest-bearing action CASes. The dose alternative (S4-CD1)
/// carries the malformed v2 bytes' digest and length in place of file observations.
enum RecoveryObservedStateV1: Sendable, Equatable {
    case files(store: DurableStore, baseState: String, target: FileObservationV1, quarantine: FileObservationV1, availableActions: [String],
               keychainInstallationId: String? = nil, firebase: FirebaseObservationV1? = nil, auth: SignedAuthTuple? = nil, mismatchIdentityDigest: String? = nil)
    case dose(bytesSHA256: String, byteLength: Int, quarantineCount: Int)

    var store: RecoveryStore {
        switch self {
        case let .files(store, _, _, _, _, _, _, _, _): return RecoveryStore(store)
        case .dose: return .dose
        }
    }

    var availableActions: [String] {
        switch self {
        case let .files(_, _, _, _, actions, _, _, _, _): return actions
        case .dose: return ["quarantine_dose_bytes"]
        }
    }

    var canonical: [String: Any] {
        switch self {
        case let .files(store, baseState, target, quarantine, actions, keychain, firebase, auth, mismatch):
            var map: [String: Any] = ["schemaVersion": 1, "store": store.rawValue, "baseState": baseState, "target": target.canonical, "quarantine": quarantine.canonical, "availableActions": actions]
            if let keychain { map["keychain"] = ["state": "valid", "installationId": keychain] }
            if let firebase { map["firebase"] = firebase.canonical }
            if let auth { map["auth"] = ["state": "signed_in", "uid": auth.uid, "authEpochUUID": auth.authEpochUUID, "credentialRevision": auth.credentialRevision] }
            if let mismatch { map["mismatchIdentityDigest"] = mismatch }
            return map
        case let .dose(bytesSHA256, byteLength, quarantineCount):
            return ["schemaVersion": 1, "store": "dose", "baseState": "malformed", "bytesSHA256": bytesSHA256, "byteLength": byteLength, "quarantineCount": quarantineCount, "availableActions": ["quarantine_dose_bytes"]]
        }
    }

    /// `recoveryStateDigest = lowercase SHA-256(TaskCanonicalV1(RecoveryObservedStateV1))`.
    var recoveryStateDigest: String { TaskCanonicalV1.sha256Hex(canonical) }
}

/// The typed unavailable branch: a store whose observation is refused by I/O or Keychain (C9.7.2).
struct UnavailableToken: Sendable, Equatable, Hashable {
    let store: RecoveryStore
    let state: String
    let errorCode: String
}

/// `RecoveryAttemptKey` (C9.7.12): the private key of the single shared `(RecoveryAttemptKey,Task)` slot per store owner.
enum RecoveryAttemptKey: Sendable, Equatable, Hashable {
    case recover(recoveryStateDigest: String)
    case merge(recoveryStateDigest: String)
    case discard(recoveryStateDigest: String)
    case cleanup(recoveryStateDigest: String)
    case receiptReconcile(recoveryStateDigest: String, mismatchIdentityDigest: String)
    case foreignReconcile(recoveryStateDigest: String)
    case resolveForeign(recoveryStateDigest: String, resolutionDigest: String, choicesSHA256: String)
    case recoverEpoch(recoveryStateDigest: String, expectedTaskGenerationEpoch: Int, expectedPhase: ResetRowPhase, action: ResetRecoveryAction)
    case unavailable(store: RecoveryStore, state: String, errorCode: String, action: String)
    case doseQuarantine(recoveryStateDigest: String)

    var kind: String {
        switch self {
        case .recover: return "recover"
        case .merge: return "merge"
        case .discard: return "discard"
        case .cleanup: return "cleanup"
        case .receiptReconcile: return "receipt_reconcile"
        case .foreignReconcile: return "foreign_reconcile"
        case .resolveForeign: return "resolve_foreign"
        case .recoverEpoch: return "recover_epoch"
        case .unavailable: return "unavailable"
        case .doseQuarantine: return "dose_quarantine"
        }
    }

    var canonical: [String: Any] {
        switch self {
        case let .recover(d), let .merge(d), let .discard(d), let .cleanup(d), let .foreignReconcile(d), let .doseQuarantine(d):
            return ["kind": kind, "recoveryStateDigest": d]
        case let .receiptReconcile(d, mismatch):
            return ["kind": kind, "recoveryStateDigest": d, "mismatchIdentityDigest": mismatch]
        case let .resolveForeign(d, resolution, choices):
            return ["kind": kind, "recoveryStateDigest": d, "resolutionDigest": resolution, "choicesSHA256": choices]
        case let .recoverEpoch(d, epoch, phase, action):
            return ["kind": kind, "recoveryStateDigest": d, "expectedTaskGenerationEpoch": epoch, "expectedPhase": phase.rawValue, "action": action.rawValue]
        case let .unavailable(store, state, errorCode, action):
            return ["kind": kind, "store": store.rawValue, "state": state, "errorCode": errorCode, "action": action]
        }
    }
}

/// `RecoveryAction` (S4-CD5): the public actions of C9.7.4, mapping 1:1 onto the attempt-key kinds.
enum RecoveryAction: Sendable, Equatable {
    case recover
    case discardQuarantine
    case retryCleanup
    case merge
    case reconcile(mismatchIdentityDigest: String)
    case foreignReconcile
    case resolve(resolutionDigest: String, choices: [String])
    case retry(errorCode: String)
    case repairInstallationIdentity
    case quarantineDoseBytes

    /// The C9.7.2 `availableActions` literal.
    var name: String {
        switch self {
        case .recover: return "recover"
        case .discardQuarantine: return "discard_quarantine"
        case .retryCleanup: return "retry_cleanup"
        case .merge: return "merge"
        case .reconcile, .foreignReconcile: return "reconcile"
        case .resolve: return "resolve"
        case .retry: return "retry"
        case .repairInstallationIdentity: return "repair_installation_identity"
        case .quarantineDoseBytes: return "quarantine_dose_bytes"
        }
    }

    /// The private key this action derives under the given expectation (C9.7.12 public-action table); nil when
    /// the expectation kind does not match the action (a digest-bearing action needs a digest, unavailable actions the token).
    func attemptKey(expecting expectation: RecoveryExpectation) -> RecoveryAttemptKey? {
        switch (self, expectation) {
        case let (.recover, .digest(d)): return .recover(recoveryStateDigest: d)
        case let (.merge, .digest(d)): return .merge(recoveryStateDigest: d)
        case let (.discardQuarantine, .digest(d)): return .discard(recoveryStateDigest: d)
        case let (.retryCleanup, .digest(d)): return .cleanup(recoveryStateDigest: d)
        case let (.reconcile(mismatch), .digest(d)): return .receiptReconcile(recoveryStateDigest: d, mismatchIdentityDigest: mismatch)
        case let (.foreignReconcile, .digest(d)): return .foreignReconcile(recoveryStateDigest: d)
        case let (.resolve(resolution, choices), .digest(d)):
            return .resolveForeign(recoveryStateDigest: d, resolutionDigest: resolution, choicesSHA256: TaskCanonicalV1.sha256Hex(["choices": choices]))
        case let (.quarantineDoseBytes, .digest(d)): return .doseQuarantine(recoveryStateDigest: d)
        case let (.retry(errorCode), .unavailable(token)) where token.errorCode == errorCode:
            return .unavailable(store: token.store, state: token.state, errorCode: token.errorCode, action: "retry")
        case let (.repairInstallationIdentity, .unavailable(token)):
            return .unavailable(store: token.store, state: token.state, errorCode: token.errorCode, action: "repair")
        default:
            return nil
        }
    }
}

/// `RecoveryObservation` (S4-CD5): what an owner's `observe()` returns — a digest-bearing observed state or the typed unavailable branch.
enum RecoveryObservation: Sendable, Equatable {
    case observed(RecoveryObservedStateV1)
    case unavailable(UnavailableToken)
}

/// `RecoveryExpectation` (S4-CD5): the token a caller CASes — the displayed digest, or the unavailable token for Retry/Repair.
enum RecoveryExpectation: Sendable, Equatable {
    case digest(String)
    case unavailable(UnavailableToken)
}

/// `DurableStoreRecovering` (S4-CD5): the one protocol every durable-store owner conforms to. The coordinator
/// drives every store only through it and never opens, replaces, or unlinks an owner's file; the single
/// `(RecoveryAttemptKey,Task)` slot of C9.7.12 lives in the owner.
protocol DurableStoreRecovering: Sendable {
    func observe() async -> RecoveryObservation
    func classify(_ observation: RecoveryObservation) -> RecoveryClassification
    func perform(_ action: RecoveryAction, expecting expectation: RecoveryExpectation) async -> RecoveryResult
}

/// The pure classification result: `ready | blocked(BlockedSnapshot)` (never `loading`).
enum RecoveryClassification: Sendable, Equatable {
    case ready
    case blocked(BlockedSnapshot)
}

/// `NarrationLease` (S4-CD7): issued by `RoomCaptureArtifactOwner` only while the deletion gate is `clear` for the
/// UID and the current gate generation; the only value `pendingNarration`, `pendingNarrationTranscript`, and
/// `NarrationService.start(lease:)` hold.
struct NarrationLease: Sendable, Equatable, Hashable {
    let leaseId: String
    let uid: String
    let gateGeneration: GateGeneration
    let sessionId: String
}

/// The registration of one in-flight media transfer under a lease (S4-CD7): `{handleId (lowercase UUID), lease}`; settled by its call site.
struct TransferHandle: Sendable, Equatable, Hashable {
    let handleId: String
    let lease: NarrationLease
}

// MARK: - Signed auth and identity seams (§8)

struct SignedAuthTuple: Sendable, Hashable, Codable {
    let uid: String
    let authEpochUUID: String
    let credentialRevision: Int
}

struct AuthIdentity: Sendable, Hashable, Codable {
    let uid: String
    let authEpochUUID: String
}

enum SignedAuthAuthority: Sendable, Equatable {
    case signedOut
    case signedIn(SignedAuthTuple)
}

enum AuthRefreshOutcome: Sendable, Equatable {
    case committed(SignedAuthTuple)
    case notCommitted
}

enum AccountDeletionAuthObservation: String, Sendable {
    case definitivelyDeleted
    case notProven
}

/// Asynchronous and nonthrowing at its boundary.
protocol AuthAuthorityProviding: Sendable {
    func currentSignedAuth() async -> SignedAuthAuthority
    func forceRefresh(expected: SignedAuthTuple) async -> AuthRefreshOutcome
    func confirmAccountDeleted(expected: AuthIdentity) async -> AccountDeletionAuthObservation
}

/// Synchronous snapshot used only to compare deletion-gate UID for local
/// navigation; never server, file, or auth authority.
protocol CurrentFirebaseUIDProviding: Sendable {
    func currentFirebaseUID() -> String?
}

// MARK: - Route ingress seams (§8)

enum RouteIngressSource: String, CaseIterable, Sendable {
    case notificationTap = "notification_tap"
    case url
}

enum RouteIngressResult: String, CaseIterable, Sendable {
    case persisted
    case duplicate
    case rejectedBlocked = "rejected_blocked"
    case rejectedFull = "rejected_full"
    case invalid
}

enum RouteIngressDiagnosticReason: String, CaseIterable, Sendable {
    case intentIdTypeInvalid = "INTENT_ID_TYPE_INVALID"
    case intentIdInvalid = "INTENT_ID_INVALID"
    case taskURLInvalid = "TASK_URL_INVALID"
    case receivedAtEpochInvalid = "RECEIVED_AT_EPOCH_INVALID"
    case routeInboxBlocked = "ROUTE_INBOX_BLOCKED"
    case routeInboxFull = "ROUTE_INBOX_FULL"
    case routeInboxReceivedEvicted = "ROUTE_INBOX_RECEIVED_EVICTED"
}

protocol RouteIngressReceiving: Sendable {
    func receive(intentId: String, source: RouteIngressSource) async -> RouteIngressResult
}

/// Synchronous, nonthrowing, best-effort; never dispatch authority.
protocol RouteIngressDiagnosticReporting: Sendable {
    func record(_ reason: RouteIngressDiagnosticReason)
}

// MARK: - Provider context and completion presentation (§8, C2.5)

enum AppleRevocationDisposition: String, CaseIterable, Sendable, Codable {
    case notRequired = "not_required"
    case manualRequired = "manual_required"
}

enum GoogleRevocationDisposition: String, CaseIterable, Sendable, Codable {
    case notRequired = "not_required"
    case sdkDisconnectRequired = "sdk_disconnect_required"
    case manualRequired = "manual_required"
}

/// Exact immutable dispositions computed before the first intent write.
struct AccountDeletionProviderDispositions: Sendable, Equatable, Codable {
    let appleRevocation: AppleRevocationDisposition
    let googleRevocation: GoogleRevocationDisposition
    let googleProviderUid: String?
}

protocol AccountDeletionProviderContextProviding: Sendable {
    func dispositions(expectedUID: String) async -> AccountDeletionProviderDispositions
}

enum GoogleCompletedRevocation: String, CaseIterable, Sendable, Codable {
    case notRequired = "not_required"
    case revoked
    case manualRequired = "manual_required"
}

/// Exactly one of completed, local-cleared, or remote-unconfirmed (C2.5).
enum CompletionResultV1: Sendable, Equatable {
    case completed(appleRevocation: AppleRevocationDisposition, googleRevocation: GoogleCompletedRevocation)
    case localCleared
    case remoteUnconfirmed
}

struct CompletionSnapshotV1: Sendable, Equatable {
    let generationId: String
    let sha256: String
    let result: CompletionResultV1
    let createdAt: String
}

enum CompletionAcknowledgeResult: String, Sendable { case acknowledged, stale, failed }
enum CompletionOpenResult: String, Sendable { case opened, stale, notOffered, failed }
enum CompletionProvider: String, Sendable { case apple, google }

protocol AccountDeletionCompletionPresenting: Sendable {
    func current() async -> CompletionSnapshotV1?
    func acknowledge(expectedGenerationId: String, expectedSHA256: String) async -> CompletionAcknowledgeResult
    func open(expectedGenerationId: String, expectedSHA256: String, provider: CompletionProvider) async -> CompletionOpenResult
}

// MARK: - Apple, Google, telemetry seams (§8)

enum AppleCredentialStateOutcomeV1: String, CaseIterable, Sendable {
    case authorized, revoked, notFound, transferred, unresolved
}

protocol AppleCredentialStateChecking: Sendable {
    func credentialState(forProviderUID providerUID: String) async -> AppleCredentialStateOutcomeV1
}

enum GoogleCredentialOutcomeV1: String, CaseIterable, Sendable {
    case disconnected, signedOut, identityMismatch, failed
}

enum GoogleURLHandleOutcomeV1: String, Sendable { case handled, notHandled }

enum GoogleFirebaseSignInFailureV1: String, CaseIterable, Sendable {
    case missingClientID, missingPresenter, sdkFailure, missingToken, firebaseFailure, staleGeneration
}

enum GoogleFirebaseSignInOutcomeV1: Sendable, Equatable {
    case signedIn(uid: String)
    case cancelled
    case failed(GoogleFirebaseSignInFailureV1)
}

/// Every result is a closed Sendable value; no SDK object, token, or credential escapes.
protocol GoogleIdentityControlling: Sendable {
    func currentProviderUID() async -> String?
    func handle(_ url: URL) async -> GoogleURLHandleOutcomeV1
    func signIn() async -> GoogleFirebaseSignInOutcomeV1
    func disconnect(expectedProviderUID: String) async -> GoogleCredentialOutcomeV1
    func signOutAll() async -> GoogleCredentialOutcomeV1
}

enum ClientTelemetryPurgeOutcomeV1: String, CaseIterable, Sendable {
    case cleared, relaunchRequired, failed
}

/// Nonthrowing; exposes no SDK error or value.
protocol ClientTelemetryPrivacyPurging: Sendable {
    func purgeAll() async -> ClientTelemetryPurgeOutcomeV1
}

// MARK: - Installation identity seam (§7 B3)

enum KeychainStage: String, Sendable { case load, update, add }
enum KeychainRepairErrorStage: String, Sendable { case load, add }

enum InstallationIdentityLoadResult: Sendable, Equatable {
    case absent, present(String), invalid, error
}

enum InstallationIdentityAddResult: Sendable, Equatable {
    case inserted(String), existing(String), invalid, error
}

enum InstallationIdentityRekeyResult: Sendable, Equatable {
    case rekeyed(String), existingConcurrent(String), error(stage: KeychainStage)
}

enum InstallationIdentityRepairResult: Sendable, Equatable {
    case existing(String), repaired(String), added(String), addExisting(String), stillInvalid
    case error(stage: KeychainRepairErrorStage)
}

/// Only B3's exact load, add-if-absent, empty-container-rekey, and invalid-repair
/// operations; no result carries raw Keychain bytes or OSStatus.
protocol InstallationIdentityProviding: Sendable {
    func load() async -> InstallationIdentityLoadResult
    func addIfAbsent(_ candidate: String) async -> InstallationIdentityAddResult
    func rekeyEmptyContainer(_ candidate: String) async -> InstallationIdentityRekeyResult
    func repairInvalid(_ candidate: String) async -> InstallationIdentityRepairResult
}

// MARK: - Reset epoch seams (§5)

struct ResetEpochAuthority: Sendable, Equatable {
    let uid: String
    let taskGenerationEpoch: Int
}

/// Reads the user-root authority through the authenticated Firestore seam;
/// never synthesizes epoch zero from read failure (throws instead).
protocol ResetEpochAuthorityProviding: Sendable {
    func current(uid: String, expectedAuth: SignedAuthTuple) async throws -> ResetEpochAuthority
}

protocol ResetEpochConflictRecovering: Sendable {
    func recoverEpoch(
        recoveryStateDigest: String,
        expectedTaskGenerationEpoch: Int,
        expectedPhase: ResetRowPhase,
        action: ResetRecoveryAction
    ) async -> RecoveryResult
}

// MARK: - Account-deletion transport seam (C2.3, §8.9.2)

/// The typed DTO/transport conformance lives in `TaskPlanService.swift`
/// (`TaskPlanService.AccountDeletionTransport`); S2 owns the callable's server
/// implementation, which mirrors those exact maps.
protocol AccountDeletionRemoteProviding: Sendable {
    func perform(_ request: AccountDeletionRequestV1) async throws -> AccountDeletionRemoteResultV1
}

// MARK: - Local purge seams (§8.9.3, C3 journal scope)

/// Journal scope: `{kind:"all"}` or `{kind:"uid",uid}`.
enum LocalPurgeScope: Sendable, Equatable {
    case all
    case uid(String)
}

enum LocalPurgeAck: String, Sendable { case acknowledged, failed }

protocol RouteAccountDeletionPurging: Sendable {
    func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck
}
protocol HandoffAccountDeletionPurging: Sendable {
    func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck
}
protocol ResetAccountDeletionPurging: Sendable {
    func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck
}
protocol WorkflowAccountDeletionPurging: Sendable {
    func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck
}
protocol FirestoreLocalCachePurging: Sendable {
    func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck
}
protocol NotificationIdentityPurging: Sendable {
    func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck
}
protocol RoomCaptureArtifactPurging: Sendable {
    func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck
}

enum LocalPrivacyPurgeBlockedReason: String, CaseIterable, Sendable {
    case fileIO = "FILE_IO"
    case remoteUnavailable = "REMOTE_UNAVAILABLE"
    case remoteMalformed = "REMOTE_MALFORMED"
    case localPrivacyPurgeFailed = "LOCAL_PRIVACY_PURGE_FAILED"
}

enum LocalPrivacyPurgeResult: Sendable, Equatable {
    case cleared
    case blocked(LocalPrivacyPurgeBlockedReason)
}

protocol LocalPrivacyPurgeCoordinating: Sendable {
    func purge(scope: LocalPurgeScope) async -> LocalPrivacyPurgeResult
}

// MARK: - Startup barrier and account-deletion gate (§8, §8.9.3, C2.4)

enum AccountDeletionGate: Sendable, Equatable {
    case loading
    case clear
    case active(uid: String)
    case guarding(uid: String, authGuardAfter: String)
    case blocked
}

/// Closed consumer projection; every enumeration uses all applicable members.
enum AccountDeletionGateProjection: String, CaseIterable, Sendable {
    case clear
    case loading
    case blocked
    case activeSameUID = "active-same-UID"
    case activeOtherUID = "active-other-UID"
    case activeWithNilCurrentUID = "active-with-nil-current-UID"
    case guardingSameUID = "guarding-same-UID"
    case guardingOtherUID = "guarding-other-UID"
    case localCleared = "local_cleared"
}

/// Terminal presentation awaiting consumption; `clear` is published only after
/// the completed or local_cleared action is consumed (D2).
enum TerminalPresentationKind: Sendable, Equatable {
    case completed, localCleared, remoteUnconfirmed
}

struct GateGeneration: Hashable, Sendable {
    let rawValue: UInt64
}

/// Operations with exact §8 required sets.
enum GatedOperation: Sendable, Hashable, CaseIterable {
    case handoffOperation
    case routeClaim, routeRefresh, routeReturnedSessionPresentation
    case resetReserve, resetBind, resetDispatch, resetApplication
    case workflowPrepare, workflowDispatch, workflowApplication
    /// Direct task callable touching no durable aggregate.
    case directTaskCallable

    var requiredSet: Set<DurableStore> {
        switch self {
        case .handoffOperation: return [.handoff]
        case .routeClaim, .routeRefresh, .routeReturnedSessionPresentation: return [.route, .handoff]
        case .resetReserve, .resetBind, .resetDispatch, .resetApplication: return [.reset, .handoff]
        case .workflowPrepare, .workflowDispatch, .workflowApplication: return [.workflow, .handoff]
        case .directTaskCallable: return []
        }
    }
}

enum Admission: Sendable, Equatable {
    /// Admitted under this gate generation; discard a late result after it changes.
    case admitted(GateGeneration)
    case deferred(storesLoading: [DurableStore])
    case blocked(store: DurableStore, BlockedSnapshot)
    case refused(AccountDeletionGateProjection)
}

/// Sendable deletion-gate-controlling seam the coordinator receives.
protocol AccountDeletionGateControlling: Sendable {
    func setGate(_ gate: AccountDeletionGate) async
    func setPendingTerminalPresentation(_ kind: TerminalPresentationKind?) async
}

/// One process-wide barrier (constructed and published by S7). Readiness a
/// store publishes while the gate is still `loading` is held until deletion,
/// journal, and presentation classification set the gate.
actor StartupBarrier: AccountDeletionGateControlling {
    private let currentUID: any CurrentFirebaseUIDProviding
    private var gateValue: AccountDeletionGate = .loading
    private var generation = GateGeneration(rawValue: 0)
    private var published = ReadinessVector()
    private var pendingTerminal: TerminalPresentationKind?

    init(currentUID: any CurrentFirebaseUIDProviding) {
        self.currentUID = currentUID
    }

    func gate() -> AccountDeletionGate { gateValue }

    func gateGeneration() -> GateGeneration { generation }

    func setGate(_ gate: AccountDeletionGate) {
        guard gate != gateValue else { return }
        gateValue = gate
        if gate == .clear { pendingTerminal = nil }
        advanceGeneration()
    }

    func setPendingTerminalPresentation(_ kind: TerminalPresentationKind?) {
        guard kind != pendingTerminal else { return }
        pendingTerminal = kind
        advanceGeneration()
    }

    func publish(_ store: DurableStore, _ state: StoreReadiness) {
        published[store] = state
    }

    func readiness() -> ReadinessVector {
        gateValue == .loading ? ReadinessVector() : published
    }

    func projection() -> AccountDeletionGateProjection {
        if pendingTerminal == .localCleared, gateValue != .clear { return .localCleared }
        switch gateValue {
        case .loading: return .loading
        case .clear: return .clear
        case .blocked: return .blocked
        case let .active(uid):
            guard let current = currentUID.currentFirebaseUID() else { return .activeWithNilCurrentUID }
            return current == uid ? .activeSameUID : .activeOtherUID
        case let .guarding(uid, _):
            return currentUID.currentFirebaseUID() == uid ? .guardingSameUID : .guardingOtherUID
        }
    }

    /// Admits only under both the operation's required set and the gate; an
    /// empty required set never bypasses a nonclear gate, and a clear gate adds
    /// no store dependency to an empty-required-set callable.
    func admission(of operation: GatedOperation, uid: String?) -> Admission {
        if pendingTerminal == .localCleared, gateValue != .clear { return .refused(.localCleared) }
        switch gateValue {
        case .loading: return .refused(.loading)
        case .blocked: return .refused(.blocked)
        case .active: return .refused(projection())
        case let .guarding(deletedUID, _):
            if uid == deletedUID { return .refused(.guardingSameUID) }
        case .clear:
            break
        }
        let required = DurableStore.allCases.filter { operation.requiredSet.contains($0) }
        for store in required {
            if case let .blocked(snapshot) = published[store] { return .blocked(store: store, snapshot) }
        }
        let loading = required.filter { published[$0] == .loading }
        if !loading.isEmpty { return .deferred(storesLoading: loading) }
        return .admitted(generation)
    }

    private func advanceGeneration() {
        generation = GateGeneration(rawValue: generation.rawValue &+ 1)
    }
}

// MARK: - Firestore runtime seam (§11:1529, §12.2:1866)

/// Published generation of the process-wide Firestore instance. A lease whose
/// generation is no longer current must have its results discarded.
struct FirestoreRuntimeGeneration: Hashable, Sendable {
    let rawValue: UInt64
}

/// The published Firestore instance together with its generation.
struct FirestoreRuntimeLease: @unchecked Sendable {
    let firestore: Firestore
    let generation: FirestoreRuntimeGeneration
}

/// The single chokepoint through which every consumer obtains Firestore.
/// S4's `FirestoreRuntimeOwner` is the production conformer that owns the
/// instance, invalidation, recreation, and publication.
protocol FirestoreRuntimeProviding: Sendable {
    /// Admitted acquisition: waits for publication and throws only when
    /// acquisition is refused.
    func acquire() async throws -> FirestoreRuntimeLease
    /// Synchronous snapshot of the last published lease for consumers that
    /// cannot await (default parameters, listener registration).
    func published() -> FirestoreRuntimeLease
    func isCurrent(_ generation: FirestoreRuntimeGeneration) -> Bool
}

/// The outcome of `FirestoreRuntime.install(_:)` (S4-CD2): registry states `empty | installed(owner)`.
enum InstallOutcome: String, Sendable, Equatable {
    case installed
    case alreadyInstalled
}

/// Pre-install refusal (S4-CD2): `acquire()` throws the fixed `notInstalled`; the nonthrowing accessors trap with
/// the fixed message, because S7 installs before `AppRootView` is created and tests install before any acquisition.
private struct NotInstalledFirestoreRuntime: FirestoreRuntimeProviding {
    static let message = "FIRESTORE_RUNTIME_NOT_INSTALLED"
    func acquire() async throws -> FirestoreRuntimeLease { throw FirestoreRuntimeError.notInstalled }
    func published() -> FirestoreRuntimeLease { preconditionFailure(Self.message) }
    func isCurrent(_ generation: FirestoreRuntimeGeneration) -> Bool { false }
}

enum FirestoreRuntime {
    /// One process registry; `install` succeeds exactly once (S4-CD2). Tests use one `Registry` per case.
    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var owner: FirestoreRuntimeOwner?

        init() {}

        /// `installed` on an empty registry (the only state change); `alreadyInstalled` with zero state change otherwise.
        func install(_ owner: FirestoreRuntimeOwner) -> InstallOutcome {
            lock.withLock {
                guard self.owner == nil else { return .alreadyInstalled }
                self.owner = owner
                return .installed
            }
        }

        var isInstalled: Bool { lock.withLock { owner != nil } }

        /// The installed owner, or the pre-install refusal.
        var provider: any FirestoreRuntimeProviding {
            lock.withLock { () -> any FirestoreRuntimeProviding in
                if let owner { return owner }
                return NotInstalledFirestoreRuntime()
            }
        }
    }

    static let shared = Registry()

    /// Sole production caller: `Phase2ProductionRuntime.firestoreRuntimeOwner` (S7).
    @discardableResult
    static func install(_ owner: FirestoreRuntimeOwner) -> InstallOutcome { shared.install(owner) }

    /// Registry-backed: every consumer keeps its `FirestoreRuntime.provider.*` call unchanged.
    static var provider: any FirestoreRuntimeProviding { shared.provider }

    /// Mechanical substitution target for synchronous acquisition sites.
    static func firestore() -> Firestore { provider.published().firestore }
}

// MARK: - Task-generation epoch stamps (§5:540-546)

enum TaskGenerationEpochError: Error, Equatable {
    case resetActive
    case malformedRootEpoch
    case malformedStamp
    case stampMismatch(stored: Int, root: Int)
    case unstampedAtLaterEpoch(root: Int)
}

/// Effective root epoch: absent → 0, present safe integer → that value,
/// malformed → no write. Every fresh stamped value equals it.
enum TaskGenerationEpochStamp {
    static let fieldName = "task_generation_epoch"
    static let rootFieldName = "taskGenerationEpoch"
    static let maxSafeInteger = 9_007_199_254_740_991

    /// Exact nonnegative safe integer; booleans, fractions, and out-of-range values are nil.
    static func safeInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded(.towardZero) == double,
              double >= 0, double <= Double(maxSafeInteger) else { return nil }
        return Int(double)
    }

    static func effectiveRootEpoch(_ root: [String: Any]?, requireResetAbsent: Bool) throws -> Int {
        let data = root ?? [:]
        if requireResetAbsent, data["taskReset"] != nil { throw TaskGenerationEpochError.resetActive }
        guard let raw = data[rootFieldName] else { return 0 }
        guard let epoch = safeInteger(raw) else { throw TaskGenerationEpochError.malformedRootEpoch }
        return epoch
    }
}

private final class TransactionResultBox<Value>: @unchecked Sendable {
    var value: Value?
}

extension Firestore {
    /// Runs `body` inside a Firestore transaction and rethrows its typed error.
    func runTypedTransaction<T: Sendable>(_ body: @escaping @Sendable (Transaction) throws -> T) async throws -> T {
        let box = TransactionResultBox<T>()
        _ = try await runTransaction { transaction, errorPointer -> Any? in
            do {
                box.value = try body(transaction)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        guard let value = box.value else { throw TaskGenerationEpochError.malformedRootEpoch }
        return value
    }
}

// MARK: - Local durable clock (§5:500)

/// One injected clock; `now()` is a canonical UTC RFC 3339 millisecond instant.
protocol LocalDurableClock: Sendable {
    func now() -> String
}

struct SystemDurableClock: LocalDurableClock {
    func now() -> String { CanonicalInstant.string(from: Date()) }
}

enum CanonicalInstant {
    static let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$"#
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func string(from date: Date) -> String {
        let millisecond = (date.timeIntervalSince1970 * 1000).rounded(.down) / 1000
        return formatter.string(from: Date(timeIntervalSince1970: millisecond))
    }

    static func isCanonical(_ value: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - TaskCanonicalV1: sorted-key compact JSON and its SHA-256

enum TaskCanonicalV1 {
    static func data(_ object: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    static func sha256Hex(_ object: [String: Any]) -> String {
        sha256Hex(data: data(object) ?? Data())
    }

    static func sha256Hex(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - DurableFileEnvelopeV1 codec (§7); file I/O lives with each owner

enum DurableFileKind: String, Sendable, CaseIterable {
    case taskRouteInboxV1 = "TASK_ROUTE_INBOX_V1"
    case handoffAuthorityV1 = "HANDOFF_AUTHORITY_V1"
    case taskPlanResetV2 = "TASK_PLAN_RESET_V2"
    case workflowRequestsV2 = "WORKFLOW_REQUESTS_V2"
    /// C2.1 intent (cap 16,384), C2.5 completion (cap 4,096), C3 purge journal (cap 4,096): the same envelope
    /// grammar, no quarantine sibling and no recovery receipt.
    case accountDeletionIntentV1 = "ACCOUNT_DELETION_INTENT_V1"
    case accountDeletionCompletionV1 = "ACCOUNT_DELETION_COMPLETION_V1"
    case localPrivacyPurgeV1 = "LOCAL_PRIVACY_PURGE_V1"

    /// C9.7.1 normal `storeCap` (complete canonical outer-envelope bytes); the handoff
    /// expanded regime (68,157,440) is the owner's, applied only when its predicates hold.
    var storeCap: Int {
        switch self {
        case .taskRouteInboxV1: return 131_072
        case .handoffAuthorityV1: return 524_288
        case .taskPlanResetV2: return 131_072
        case .workflowRequestsV2: return 16_777_216
        case .accountDeletionIntentV1: return 16_384
        case .accountDeletionCompletionV1, .localPrivacyPurgeV1: return 4_096
        }
    }

    /// The four recoverable stores reserve the C9.7.1 receipt bytes on every normal write; the account-deletion
    /// files carry no receipt and use their complete-byte cap.
    var reservesRecoveryReceipt: Bool {
        switch self {
        case .taskRouteInboxV1, .handoffAuthorityV1, .taskPlanResetV2, .workflowRequestsV2: return true
        case .accountDeletionIntentV1, .accountDeletionCompletionV1, .localPrivacyPurgeV1: return false
        }
    }

    /// The expanded handoff cap `128 * 524,288 + 2 * 524,288`.
    static let expandedHandoffStoreCap = 68_157_440
}

struct DecodedDurableEnvelope: Sendable {
    let generationId: String
    let sha256: String
    let payload: [String: Any]
    let recoveryReceipt: [String: Any]?
}

enum DurableEnvelopeCodec {
    static let uuidPattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#
    /// C9.7.1 byte rule reserve: the byte length of the largest `recoveryReceipt` member a
    /// later recovery may add, so every normal write leaves room for it.
    static let recoveryReceiptReserve = 190

    /// Canonical envelope bytes with `sha256` over the complete canonical envelope
    /// minus itself; nil when the payload is not canonical, the complete bytes exceed
    /// `storeCap`, or the receipt-less base plus the 190-byte reserve exceeds `storeCap`
    /// (C9.7.1: `baseEnvelopeBytesWithoutRecoveryReceipt + 190 <= storeCap`).
    static func encode(fileKind: DurableFileKind, generationId: String, payload: [String: Any], recoveryReceipt: [String: Any]? = nil, storeCap: Int? = nil) -> Data? {
        let cap = storeCap ?? fileKind.storeCap
        var base: [String: Any] = ["schemaVersion": 1, "fileKind": fileKind.rawValue, "generationId": generationId, "payload": payload]
        guard let unsignedBase = TaskCanonicalV1.data(base) else { return nil }
        base["sha256"] = TaskCanonicalV1.sha256Hex(data: unsignedBase)
        guard let baseBytes = TaskCanonicalV1.data(base), baseBytes.count + (fileKind.reservesRecoveryReceipt ? recoveryReceiptReserve : 0) <= cap else { return nil }
        guard let recoveryReceipt else { return baseBytes }
        var envelope: [String: Any] = ["schemaVersion": 1, "fileKind": fileKind.rawValue, "generationId": generationId, "payload": payload, "recoveryReceipt": recoveryReceipt]
        guard let unsigned = TaskCanonicalV1.data(envelope) else { return nil }
        envelope["sha256"] = TaskCanonicalV1.sha256Hex(data: unsigned)
        guard let bytes = TaskCanonicalV1.data(envelope), bytes.count <= cap else { return nil }
        return bytes
    }

    /// Strict decode: exact member set, exact kind, canonical bytes, matching hash, cap.
    static func decode(_ bytes: Data, fileKind: DurableFileKind, storeCap: Int? = nil) -> DecodedDurableEnvelope? {
        guard bytes.count <= (storeCap ?? fileKind.storeCap),
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return nil }
        let keys = Set(object.keys)
        guard keys == ["schemaVersion", "fileKind", "generationId", "payload", "sha256"]
                || keys == ["schemaVersion", "fileKind", "generationId", "payload", "recoveryReceipt", "sha256"],
              TaskGenerationEpochStamp.safeInteger(object["schemaVersion"]) == 1,
              object["fileKind"] as? String == fileKind.rawValue,
              let generationId = object["generationId"] as? String,
              generationId.range(of: uuidPattern, options: .regularExpression) != nil,
              let payload = object["payload"] as? [String: Any],
              let sha256 = object["sha256"] as? String else { return nil }
        var unsigned = object
        unsigned.removeValue(forKey: "sha256")
        guard let unsignedBytes = TaskCanonicalV1.data(unsigned),
              TaskCanonicalV1.sha256Hex(data: unsignedBytes) == sha256,
              TaskCanonicalV1.data(object) == bytes else { return nil }
        return DecodedDurableEnvelope(generationId: generationId, sha256: sha256, payload: payload, recoveryReceipt: object["recoveryReceipt"] as? [String: Any])
    }
}
