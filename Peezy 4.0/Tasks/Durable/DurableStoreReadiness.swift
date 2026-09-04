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

    var store: DurableStore {
        switch self {
        case let .quarantined(store, _, _, _), let .collision(store, _, _, _),
             let .recoveredPendingCleanup(store, _), let .quarantineConflict(store, _, _, _),
             let .receiptMismatch(store, _, _), let .storageIOUnavailable(store, _):
            return store
        case .resetEpochConflict:
            return .reset
        case .foreignInstallation, .foreignResolutionRequired,
             .installationAuthorityUnavailable, .installationAuthorityInvalid:
            return .handoff
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
        }
    }

    var recoveryStateDigest: String? {
        switch self {
        case let .quarantined(_, digest, _, _), let .collision(_, digest, _, _),
             let .recoveredPendingCleanup(_, digest), let .quarantineConflict(_, digest, _, _),
             let .receiptMismatch(_, digest, _), let .resetEpochConflict(digest, _, _),
             let .foreignInstallation(digest, _), let .foreignResolutionRequired(digest, _, _, _):
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
    case busy(store: DurableStore)
    /// `{schemaVersion:1,reason:"RECOVERY_ACTION_UNAVAILABLE",store}`
    case unavailable(store: DurableStore)
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

/// Transitional S1 conformer: one fixed generation over the default instance.
/// S4 replaces it with `FirestoreRuntimeOwner`; every consumer already routes
/// through `FirestoreRuntime`, so that swap touches no consumer.
struct TransitionalFirestoreRuntime: FirestoreRuntimeProviding {
    private static let generation = FirestoreRuntimeGeneration(rawValue: 1)

    func acquire() async throws -> FirestoreRuntimeLease { published() }

    func published() -> FirestoreRuntimeLease {
        FirestoreRuntimeLease(firestore: Firestore.firestore(), generation: Self.generation)
    }

    func isCurrent(_ generation: FirestoreRuntimeGeneration) -> Bool { generation == Self.generation }
}

enum FirestoreRuntime {
    static let provider: any FirestoreRuntimeProviding = TransitionalFirestoreRuntime()

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
