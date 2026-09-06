import Foundation
import Security

// S4 (briefs/S4_BRIEF.md): the client account-deletion coordinator (C2.1–C2.7). The one actor of
// `PeezyAccountDeletion-v1.json`; drives the phase machine over S1's transport and the eight purge owners
// through `LocalPrivacyPurgeCoordinator`; projects the gate through the `AccountDeletionGateControlling` seam.
// Unmounted: S7 declares `Phase2ProductionRuntime.accountDeletionCoordinator` (C9.7.16).

// MARK: - Intent vocabulary (C2.1, C2.2)

enum AccountDeletionPhase: String, CaseIterable, Sendable {
    case prepared
    case dataConfirmed = "data_confirmed"
    case purging
    case localDetaching = "local_detaching"
    case authFinalizeDispatched = "auth_finalize_dispatched"
    case guarding
    case completed
    case localCleared = "local_cleared"
}

enum AccountDeletionPurpose: String, CaseIterable, Sendable {
    case confirmedBegin = "confirmed_begin"
    case startupDiscover = "startup_discover"
}

/// D1 detach reasons for the nonstaged `local_detaching` variant.
enum AccountDeletionDetachReason: String, CaseIterable, Sendable {
    case authDeleted = "auth_deleted"
    case remoteUnverified = "remote_unverified"
    case capabilityInvalid = "capability_invalid"
}

enum AccountDeletionStagedRoot: String, CaseIterable, Sendable {
    case dataDeleted = "DATA_DELETED"
    case authGuarding = "AUTH_GUARDING"
}

/// The exact C2.1 payload. Every missing, surplus, unknown, wrong-phase, or cross-branch member rejects (`isValid`).
struct AccountDeletionIntentV1: Sendable, Equatable {
    static let operationIdPattern = #"^adel1_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#
    static let proofNoncePattern = #"^[A-Za-z0-9_-]{43}$"#
    static let memberKeys: Set<String> = [
        "schemaVersion", "uid", "authEpochUUID", "credentialRevision", "operationId", "proofNonce", "appleRevocation", "googleRevocation",
        "googleProviderUid", "phase", "purpose", "authorityKind", "detachReason", "stagedRoot", "startedAt", "dataDeletedAt", "authGuardAfter",
        "acks", "createdAt", "updatedAt"
    ]

    let uid: String
    let authEpochUUID: String
    let credentialRevision: Int
    let operationId: String
    let proofNonce: String
    let dispositions: AccountDeletionProviderDispositions
    var phase: AccountDeletionPhase
    var purpose: AccountDeletionPurpose?
    var authorityKind: AccountDeletionAuthorityKind?
    var detachReason: AccountDeletionDetachReason?
    var stagedRoot: AccountDeletionStagedRoot?
    var startedAt: String?
    var dataDeletedAt: String?
    var authGuardAfter: String?
    var acks: [PurgeOwner]
    let createdAt: String
    var updatedAt: String

    var canonical: [String: Any] {
        var map: [String: Any] = [
            "schemaVersion": 1, "uid": uid, "authEpochUUID": authEpochUUID, "credentialRevision": credentialRevision,
            "operationId": operationId, "proofNonce": proofNonce, "appleRevocation": dispositions.appleRevocation.rawValue,
            "googleRevocation": dispositions.googleRevocation.rawValue, "phase": phase.rawValue, "acks": acks.map(\.rawValue),
            "createdAt": createdAt, "updatedAt": updatedAt
        ]
        if let value = dispositions.googleProviderUid { map["googleProviderUid"] = value }
        if let value = purpose { map["purpose"] = value.rawValue }
        if let value = authorityKind { map["authorityKind"] = value.rawValue }
        if let value = detachReason { map["detachReason"] = value.rawValue }
        if let value = stagedRoot { map["stagedRoot"] = value.rawValue }
        if let value = startedAt { map["startedAt"] = value }
        if let value = dataDeletedAt { map["dataDeletedAt"] = value }
        if let value = authGuardAfter { map["authGuardAfter"] = value }
        return map
    }

    /// The server capability `{operationId, proofSHA256}` (C2.1).
    var proofSHA256: String { AccountDeletionCapability.proofSHA256(uid: uid, operationId: operationId, proofNonce: proofNonce) }

    var providerContext: PurgeProviderContextV1 {
        PurgeProviderContextV1(deletionOperationId: operationId, deletionProofSHA256: proofSHA256, googleRevocation: dispositions.googleRevocation, googleProviderUid: dispositions.googleProviderUid)
    }

    /// The C2.2 per-phase requires/forbids table plus the member grammar.
    var isValid: Bool {
        guard !uid.isEmpty, authEpochUUID.range(of: DurableEnvelopeCodec.uuidPattern, options: .regularExpression) != nil, credentialRevision >= 0,
              operationId.range(of: Self.operationIdPattern, options: .regularExpression) != nil,
              proofNonce.range(of: Self.proofNoncePattern, options: .regularExpression) != nil,
              CanonicalInstant.isCanonical(createdAt), CanonicalInstant.isCanonical(updatedAt),
              Array(PurgeOwner.order.prefix(acks.count)) == acks else { return false }
        if dispositions.googleRevocation == .sdkDisconnectRequired && dispositions.googleProviderUid == nil { return false }
        if let providerUid = dispositions.googleProviderUid, providerUid.isEmpty { return false }
        for time in [startedAt, dataDeletedAt, authGuardAfter].compactMap({ $0 }) where !CanonicalInstant.isCanonical(time) { return false }
        let hasAuthority = authorityKind != nil && startedAt != nil && dataDeletedAt != nil
        let noAuthority = authorityKind == nil && startedAt == nil && dataDeletedAt == nil
        let allAcks = acks == PurgeOwner.order
        switch phase {
        case .prepared:
            return purpose != nil && noAuthority && detachReason == nil && stagedRoot == nil && authGuardAfter == nil && acks.isEmpty
        case .dataConfirmed:
            return purpose == nil && hasAuthority && detachReason == nil && stagedRoot == nil && authGuardAfter == nil && acks.isEmpty
        case .purging:
            return purpose == nil && hasAuthority && detachReason == nil && stagedRoot == nil && authGuardAfter == nil
        case .localDetaching:
            guard purpose == nil else { return false }
            switch (stagedRoot, detachReason) {
            case let (.some(root), .none):
                return hasAuthority && (authGuardAfter != nil) == (root == .authGuarding)
            case (.none, .some):
                return noAuthority && authGuardAfter == nil
            default:
                return false
            }
        case .authFinalizeDispatched:
            return purpose == nil && hasAuthority && detachReason == nil && stagedRoot == nil && authGuardAfter == nil && allAcks
        case .guarding:
            return purpose == nil && hasAuthority && detachReason == nil && stagedRoot == nil && authGuardAfter != nil && allAcks
        case .completed, .localCleared:
            return purpose == nil && noAuthority && detachReason == nil && stagedRoot == nil && authGuardAfter == nil && allAcks
        }
    }

    static func decode(_ map: [String: Any]) -> AccountDeletionIntentV1? {
        guard Set(map.keys).isSubset(of: memberKeys), TaskGenerationEpochStamp.safeInteger(map["schemaVersion"]) == 1,
              let uid = map["uid"] as? String, let authEpochUUID = map["authEpochUUID"] as? String,
              let credentialRevision = TaskGenerationEpochStamp.safeInteger(map["credentialRevision"]),
              let operationId = map["operationId"] as? String, let proofNonce = map["proofNonce"] as? String,
              let apple = (map["appleRevocation"] as? String).flatMap(AppleRevocationDisposition.init(rawValue:)),
              let google = (map["googleRevocation"] as? String).flatMap(GoogleRevocationDisposition.init(rawValue:)),
              let phase = (map["phase"] as? String).flatMap(AccountDeletionPhase.init(rawValue:)),
              let rawAcks = map["acks"] as? [Any], let createdAt = map["createdAt"] as? String, let updatedAt = map["updatedAt"] as? String else { return nil }
        var acks: [PurgeOwner] = []
        for raw in rawAcks { guard let owner = (raw as? String).flatMap(PurgeOwner.init(rawValue:)) else { return nil }; acks.append(owner) }
        func optionalString(_ key: String) -> (present: Bool, value: String?) {
            guard map[key] != nil else { return (false, nil) }
            return (true, map[key] as? String)
        }
        func typed<T: RawRepresentable>(_ key: String, _ type: T.Type) -> T?? where T.RawValue == String {
            let read = optionalString(key)
            guard read.present else { return .some(nil) }
            guard let value = read.value, let typed = T(rawValue: value) else { return nil }
            return .some(typed)
        }
        func time(_ key: String) -> String?? {
            let read = optionalString(key)
            guard read.present else { return .some(nil) }
            guard let value = read.value else { return nil }
            return .some(value)
        }
        guard let googleProviderUid = time("googleProviderUid"), let purpose = typed("purpose", AccountDeletionPurpose.self),
              let authorityKind = typed("authorityKind", AccountDeletionAuthorityKind.self), let detachReason = typed("detachReason", AccountDeletionDetachReason.self),
              let stagedRoot = typed("stagedRoot", AccountDeletionStagedRoot.self), let startedAt = time("startedAt"), let dataDeletedAt = time("dataDeletedAt"),
              let authGuardAfter = time("authGuardAfter") else { return nil }
        let intent = AccountDeletionIntentV1(
            uid: uid, authEpochUUID: authEpochUUID, credentialRevision: credentialRevision, operationId: operationId, proofNonce: proofNonce,
            dispositions: AccountDeletionProviderDispositions(appleRevocation: apple, googleRevocation: google, googleProviderUid: googleProviderUid),
            phase: phase, purpose: purpose, authorityKind: authorityKind, detachReason: detachReason, stagedRoot: stagedRoot,
            startedAt: startedAt, dataDeletedAt: dataDeletedAt, authGuardAfter: authGuardAfter, acks: acks, createdAt: createdAt, updatedAt: updatedAt)
        guard intent.isValid, TaskCanonicalV1.data(intent.canonical) == TaskCanonicalV1.data(map) else { return nil }
        return intent
    }
}

// MARK: - Capability (C2.1)

enum AccountDeletionCapability {
    static func newOperationId() -> String { "adel1_" + UUID().uuidString.lowercased() }

    /// 32 random bytes, unpadded base64url; nil when the system RNG fails (nothing is written then).
    static func newProofNonce() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// `sha256(TaskCanonicalV1({uid,operation_id,proof_nonce}))`.
    static func proofSHA256(uid: String, operationId: String, proofNonce: String) -> String {
        TaskCanonicalV1.sha256Hex(data: TaskCanonicalV1.data(["uid": uid, "operation_id": operationId, "proof_nonce": proofNonce]) ?? Data())
    }
}

// MARK: - Intent file store with generation/hash/inode CAS (C2.1, C2.2)

/// The identity a compare-and-swap requires: the envelope generation and hash plus the device/inode of the bytes read.
struct AccountDeletionIntentIdentity: Sendable, Equatable {
    let generationId: String
    let sha256: String
    let device: UInt64
    let inode: UInt64
}

enum AccountDeletionIntentObservation: Sendable, Equatable {
    case absent
    case present(AccountDeletionIntentV1, AccountDeletionIntentIdentity)
    /// Undecodable, over-cap, or invalid bytes: retained, never read as absence.
    case malformed
    case ioFailed(StorageIOErrorCode)
}

enum AccountDeletionIntentWriteFailure: Error, Sendable, Equatable {
    /// The file no longer carries the expected identity; bytes retained.
    case stale
    /// Nonrepresentable payload or over-cap envelope; nothing written.
    case encodeFailed
    case io(StorageIOErrorCode)
}

/// Sole reader/writer of `PeezyAccountDeletion-v1.json` (used only by the coordinator actor).
struct AccountDeletionIntentStore: Sendable {
    static let fileName = "PeezyAccountDeletion-v1.json"
    let url: URL

    init(directory: URL) { url = directory.appendingPathComponent(Self.fileName) }

    func observe() -> AccountDeletionIntentObservation {
        do {
            guard let observation = try PrivacyDurableFile.observe(at: url, limit: DurableFileKind.accountDeletionIntentV1.storeCap) else { return .absent }
            guard let decoded = DurableEnvelopeCodec.decode(observation.bytes, fileKind: .accountDeletionIntentV1),
                  let intent = AccountDeletionIntentV1.decode(decoded.payload) else { return .malformed }
            return .present(intent, AccountDeletionIntentIdentity(generationId: decoded.generationId, sha256: decoded.sha256, device: observation.device, inode: observation.inode))
        } catch let failure as PrivacyDurableFile.Failure { return .ioFailed(failure.code) } catch { return .ioFailed(.fileReadFailed) }
    }

    /// Creates (`expecting: nil`, the target must be absent) or replaces (the target must carry `expecting`) under CAS.
    func write(_ intent: AccountDeletionIntentV1, expecting: AccountDeletionIntentIdentity?) -> Result<AccountDeletionIntentIdentity, AccountDeletionIntentWriteFailure> {
        guard intent.isValid else { return .failure(.encodeFailed) }
        switch (observe(), expecting) {
        case (.absent, .none): break
        case let (.present(_, identity), .some(expected)) where identity == expected: break
        case let (.ioFailed(code), _): return .failure(.io(code))
        default: return .failure(.stale)
        }
        let generationId = UUID().uuidString.lowercased()
        guard let bytes = DurableEnvelopeCodec.encode(fileKind: .accountDeletionIntentV1, generationId: generationId, payload: intent.canonical) else { return .failure(.encodeFailed) }
        do { try PrivacyDurableFile.replace(at: url, bytes: bytes) } catch let failure as PrivacyDurableFile.Failure { return .failure(.io(failure.code)) } catch { return .failure(.io(.fileWriteFailed)) }
        guard case let .present(_, identity) = observe(), identity.generationId == generationId else { return .failure(.io(.fileReadFailed)) }
        return .success(identity)
    }

    func unlink(expecting: AccountDeletionIntentIdentity) -> Result<Void, AccountDeletionIntentWriteFailure> {
        guard case let .present(_, identity) = observe(), identity == expecting else { return .failure(.stale) }
        do { try PrivacyDurableFile.unlink(at: url) } catch let failure as PrivacyDurableFile.Failure { return .failure(.io(failure.code)) } catch { return .failure(.io(.fileUnlinkFailed)) }
        return .success(())
    }
}

// MARK: - Presentations (C2.5)

/// The frozen `{date}` formatter: Gregorian, current locale and zone, medium date style, no time.
enum AccountDeletionDateFormatter {
    static func string(from canonicalInstant: String) -> String? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        parser.timeZone = TimeZone(identifier: "UTC")
        guard CanonicalInstant.isCanonical(canonicalInstant), let date = parser.date(from: canonicalInstant) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = TimeZone.autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

enum AccountDeletionPresentationV1: Sendable, Equatable {
    case queued
    case blocked(LocalPrivacyPurgeBlockedReason)
    case guarding(authGuardAfter: String)
    /// The completed, local-cleared, or remote-unconfirmed file snapshot published by the completion presenter.
    case completion(CompletionSnapshotV1)

    var map: [String: Any] {
        switch self {
        case .queued:
            return ["schemaVersion": 1, "state": "account_deletion_queued", "copy": AccountDeletionCompletionCopy.queued, "availableActions": ["retry"]]
        case let .blocked(reason):
            return ["schemaVersion": 1, "state": "account_deletion_recovery_unavailable", "reason": reason.rawValue, "availableActions": ["retry"]]
        case let .guarding(authGuardAfter):
            let date = AccountDeletionDateFormatter.string(from: authGuardAfter) ?? authGuardAfter
            return ["schemaVersion": 1, "kind": "ACCOUNT_DELETION_GUARDING", "authGuardAfter": authGuardAfter,
                    "copy": AccountDeletionCompletionCopy.guardingTemplate.replacingOccurrences(of: "{date}", with: date)]
        case let .completion(snapshot):
            return snapshot.result.presentation
        }
    }
}

/// Exact local `{schemaVersion:1,reason:"ACCOUNT_DELETION_BUSY"}` (C2.4).
struct AccountDeletionBusy: Error, Equatable, Sendable {
    static let map: [String: Any] = ["schemaVersion": 1, "reason": "ACCOUNT_DELETION_BUSY"]
}

enum AccountDeletionDispatchResult: Sendable, Equatable {
    /// No intent remains and the gate is `clear`.
    case clear
    /// The reducer rests here (queued, blocked, guarding, or a terminal awaiting consumption).
    case settled(AccountDeletionPresentationV1)
    /// A different UID's `startDeletion` while an intent is live in a nonguarding phase.
    case busy
}

// MARK: - The coordinator (C2.1–C2.6)

/// The client account-deletion coordinator: one actor, one intent file, one in-flight reducer.
actor DurableStoreRecoveryCoordinator {
    struct Dependencies: Sendable {
        let directory: URL
        let clock: any LocalDurableClock
        let auth: any AuthAuthorityProviding
        let remote: any AccountDeletionRemoteProviding
        let providerContext: any AccountDeletionProviderContextProviding
        let purge: LocalPrivacyPurgeCoordinator
        let completion: AccountDeletionCompletionPresentation
        let gate: any AccountDeletionGateControlling
    }

    private let dependencies: Dependencies
    private let store: AccountDeletionIntentStore
    private var inflight: Task<AccountDeletionDispatchResult, Never>?
    private var inflightUID: String?
    private var presentation: AccountDeletionPresentationV1?
    /// Phase transitions, dispatches, and outcomes in order (tests read it; never user-facing).
    private(set) var trace: [String] = []

    init(_ dependencies: Dependencies) {
        self.dependencies = dependencies
        store = AccountDeletionIntentStore(directory: dependencies.directory)
    }

    // MARK: entry points

    /// The Settings entry (`purpose:"confirmed_begin"`): a different UID is `busy` in every phase but `guarding`; the
    /// same UID joins the singleton and never replaces its capability.
    func startDeletion(uid: String) async -> AccountDeletionDispatchResult {
        if let inflight {
            guard inflightUID == uid else { return .busy }
            return await inflight.value
        }
        switch store.observe() {
        case let .present(intent, _) where intent.uid != uid:
            // Nonguarding phases: the exact local BUSY. The guarding Option-B handoff lands with the terminal-consumption increment.
            return .busy
        case .present:
            return await runSingleflight(uid: uid) { await self.resume() }
        case .absent:
            return await runSingleflight(uid: uid) { await self.begin(uid: uid) }
        case .malformed:
            return await blockGate(.fileIO)
        case let .ioFailed(code):
            trace.append("intent:io:\(code.rawValue)")
            return await blockGate(.fileIO)
        }
    }

    /// Launch: resumes a valid intent, else discovers a server root for the signed-in UID (zero write on absence).
    func discoverAtStartup() async -> AccountDeletionDispatchResult {
        if let inflight { return await inflight.value }
        switch store.observe() {
        case let .present(intent, _):
            return await runSingleflight(uid: intent.uid) { await self.resume() }
        case .absent:
            guard case let .signedIn(tuple) = await dependencies.auth.currentSignedAuth() else { return await clearGate() }
            return await runSingleflight(uid: tuple.uid) { await self.discover(tuple: tuple) }
        case .malformed:
            return await blockGate(.fileIO)
        case let .ioFailed(code):
            trace.append("intent:io:\(code.rawValue)")
            return await blockGate(.fileIO)
        }
    }

    /// The exact Retry reducer over the durable intent (the only operation the deleted UID keeps while guarding).
    func retry() async -> AccountDeletionDispatchResult {
        if let inflight { return await inflight.value }
        switch store.observe() {
        case let .present(intent, _):
            return await runSingleflight(uid: intent.uid) { await self.resume() }
        case .absent:
            return await clearGate()
        case .malformed:
            return await blockGate(.fileIO)
        case let .ioFailed(code):
            trace.append("intent:io:\(code.rawValue)")
            return await blockGate(.fileIO)
        }
    }

    func currentPresentation() -> AccountDeletionPresentationV1? { presentation }

    func currentIntent() -> AccountDeletionIntentV1? {
        if case let .present(intent, _) = store.observe() { return intent }
        return nil
    }

    // MARK: singleflight

    private func runSingleflight(uid: String, _ body: @escaping @Sendable () async -> AccountDeletionDispatchResult) async -> AccountDeletionDispatchResult {
        let task = Task { await body() }
        inflight = task
        inflightUID = uid
        defer { inflight = nil; inflightUID = nil }
        return await task.value
    }

    // MARK: gate

    private func clearGate() async -> AccountDeletionDispatchResult {
        presentation = nil
        await dependencies.gate.setPendingTerminalPresentation(nil)
        await dependencies.gate.setGate(.clear)
        return .clear
    }

    private func blockGate(_ reason: LocalPrivacyPurgeBlockedReason) async -> AccountDeletionDispatchResult {
        presentation = .blocked(reason)
        await dependencies.gate.setGate(.blocked)
        return .settled(.blocked(reason))
    }

    private func project(_ intent: AccountDeletionIntentV1) async {
        switch intent.phase {
        case .guarding:
            await dependencies.gate.setGate(.guarding(uid: intent.uid, authGuardAfter: intent.authGuardAfter ?? ""))
        default:
            await dependencies.gate.setGate(.active(uid: intent.uid))
        }
    }

    // MARK: begin / discover / resume

    private func begin(uid: String) async -> AccountDeletionDispatchResult {
        guard case let .signedIn(tuple) = await dependencies.auth.currentSignedAuth(), tuple.uid == uid else {
            trace.append("begin:auth_required")
            return await blockGate(.remoteUnavailable)
        }
        let dispositions = await dependencies.providerContext.dispositions(expectedUID: uid)
        guard let proofNonce = AccountDeletionCapability.newProofNonce() else { return await blockGate(.fileIO) }
        let now = dependencies.clock.now()
        guard CanonicalInstant.isCanonical(now) else { trace.append("clock:nonrepresentable"); return await blockGate(.fileIO) }
        let intent = AccountDeletionIntentV1(
            uid: uid, authEpochUUID: tuple.authEpochUUID, credentialRevision: tuple.credentialRevision,
            operationId: AccountDeletionCapability.newOperationId(), proofNonce: proofNonce, dispositions: dispositions,
            phase: .prepared, purpose: .confirmedBegin, authorityKind: nil, detachReason: nil, stagedRoot: nil,
            startedAt: nil, dataDeletedAt: nil, authGuardAfter: nil, acks: [], createdAt: now, updatedAt: now)
        guard case let .success(identity) = store.write(intent, expecting: nil) else { return await blockGate(.fileIO) }
        trace.append("phase:prepared:confirmed_begin")
        await project(intent)
        return await reduce(intent, identity)
    }

    private func discover(tuple: SignedAuthTuple) async -> AccountDeletionDispatchResult {
        // Dispositions are computed before the first intent write; discovery itself writes nothing on absence.
        let dispositions = await dependencies.providerContext.dispositions(expectedUID: tuple.uid)
        guard let proofNonce = AccountDeletionCapability.newProofNonce() else { return await blockGate(.fileIO) }
        let operationId = AccountDeletionCapability.newOperationId()
        trace.append("dispatch:discover")
        var outcome: AccountDeletionRemoteResultV1?
        do {
            outcome = try await dependencies.remote.perform(.discover(uid: tuple.uid, operationId: operationId, proofNonce: proofNonce))
        } catch let error as AccountDeletionRemoteError {
            trace.append("discover:\(error)")
            switch error {
            case .retryRequired: break // DELETING-guarding: the capability is kept in a prepared intent projecting queued (C2.3)
            case .transport, .authRequired: return await blockGate(.remoteUnavailable)
            case .capabilityInvalid, .requestInvalid, .protocolAmbiguity: return await blockGate(.remoteMalformed)
            }
        } catch {
            return await blockGate(.remoteUnavailable)
        }
        if case .absent = outcome { trace.append("discover:absent"); return await clearGate() }
        let now = dependencies.clock.now()
        guard CanonicalInstant.isCanonical(now) else { trace.append("clock:nonrepresentable"); return await blockGate(.fileIO) }
        let intent = AccountDeletionIntentV1(
            uid: tuple.uid, authEpochUUID: tuple.authEpochUUID, credentialRevision: tuple.credentialRevision,
            operationId: operationId, proofNonce: proofNonce, dispositions: dispositions,
            phase: .prepared, purpose: .startupDiscover, authorityKind: nil, detachReason: nil, stagedRoot: nil,
            startedAt: nil, dataDeletedAt: nil, authGuardAfter: nil, acks: [], createdAt: now, updatedAt: now)
        guard case let .success(identity) = store.write(intent, expecting: nil) else { return await blockGate(.fileIO) }
        trace.append("phase:prepared:startup_discover")
        await project(intent)
        guard let outcome else { presentation = .queued; return .settled(.queued) }
        return await reduce(intent, identity, wire: outcome)
    }

    private func resume() async -> AccountDeletionDispatchResult {
        guard case let .present(intent, identity) = store.observe() else { return await retry() }
        await project(intent)
        return await reduce(intent, identity)
    }

    // MARK: the reducer

    private enum Step {
        case next(AccountDeletionIntentV1, AccountDeletionIntentIdentity, AccountDeletionRemoteResultV1?)
        case rest(AccountDeletionDispatchResult)
    }

    private func reduce(_ start: AccountDeletionIntentV1, _ startIdentity: AccountDeletionIntentIdentity, wire: AccountDeletionRemoteResultV1? = nil) async -> AccountDeletionDispatchResult {
        var intent = start
        var identity = startIdentity
        var pendingWire = wire
        while true {
            let step: Step
            switch intent.phase {
            case .prepared:
                step = await stepPrepared(intent, identity, wire: pendingWire)
            case .dataConfirmed:
                step = await transition(intent, identity, wire: pendingWire) { $0.phase = .purging }
            case .purging:
                step = await stepPurging(intent, identity, wire: pendingWire)
            case .localDetaching:
                step = await stepLocalDetaching(intent, identity, wire: pendingWire)
            case .authFinalizeDispatched:
                step = await stepFinalize(intent, identity, wire: pendingWire)
            case .guarding:
                step = await stepGuarding(intent, identity, wire: pendingWire)
            case .completed, .localCleared:
                return await publishTerminal(intent)
            }
            switch step {
            case let .next(nextIntent, nextIdentity, nextWire):
                intent = nextIntent; identity = nextIdentity; pendingWire = nextWire
            case let .rest(result):
                return result
            }
        }
    }

    private func transition(_ intent: AccountDeletionIntentV1, _ identity: AccountDeletionIntentIdentity, wire: AccountDeletionRemoteResultV1? = nil, _ mutate: (inout AccountDeletionIntentV1) -> Void) async -> Step {
        var next = intent
        mutate(&next)
        let now = dependencies.clock.now()
        guard CanonicalInstant.isCanonical(now) else { trace.append("clock:nonrepresentable"); return .rest(await blockGate(.fileIO)) }
        // Forward advances, equal repeats, backward never regresses the stored instant.
        next.updatedAt = max(now, intent.updatedAt)
        switch store.write(next, expecting: identity) {
        case let .success(nextIdentity):
            trace.append("phase:\(next.phase.rawValue)" + (next.stagedRoot.map { ":\($0.rawValue)" } ?? "") + (next.detachReason.map { ":\($0.rawValue)" } ?? ""))
            await project(next)
            return .next(next, nextIdentity, wire)
        case .failure(.stale):
            trace.append("write:stale")
            return .rest(await blockGate(.fileIO))
        case .failure(.encodeFailed):
            trace.append("write:encode_failed")
            return .rest(await blockGate(.fileIO))
        case let .failure(.io(code)):
            trace.append("write:io:\(code.rawValue)")
            return .rest(await blockGate(.fileIO))
        }
    }

    private func dispatch(_ request: AccountDeletionRequestV1) async -> Result<AccountDeletionRemoteResultV1, AccountDeletionRemoteError> {
        trace.append("dispatch:\(request.action)")
        do { return .success(try await dependencies.remote.perform(request)) }
        catch let error as AccountDeletionRemoteError { trace.append("error:\(error)"); return .failure(error) }
        catch { trace.append("error:unknown"); return .failure(.transport) }
    }

    /// C2.3 error handling shared by every dispatch: retry-required keeps the phase (queued), transport and auth are
    /// `REMOTE_UNAVAILABLE`, ambiguity is `REMOTE_MALFORMED`, capability-invalid is the C2.6 check; bytes are retained.
    private func rest(after error: AccountDeletionRemoteError, _ intent: AccountDeletionIntentV1, _ identity: AccountDeletionIntentIdentity) async -> Step {
        switch error {
        case .retryRequired:
            let kept: AccountDeletionPresentationV1 = intent.phase == .guarding ? .guarding(authGuardAfter: intent.authGuardAfter ?? "") : .queued
            presentation = kept
            return .rest(.settled(kept))
        case .transport, .authRequired:
            presentation = .blocked(.remoteUnavailable)
            return .rest(.settled(.blocked(.remoteUnavailable)))
        case .requestInvalid, .protocolAmbiguity:
            presentation = .blocked(.remoteMalformed)
            return .rest(.settled(.blocked(.remoteMalformed)))
        case .capabilityInvalid:
            return await capabilityInvalidExit(intent, identity)
        }
    }

    /// C2.6: only `definitivelyDeleted` with no member branch takes the exit; an Auth user still present blocks with retained bytes.
    private func capabilityInvalidExit(_ intent: AccountDeletionIntentV1, _ identity: AccountDeletionIntentIdentity) async -> Step {
        let observation = await dependencies.auth.confirmAccountDeleted(expected: AuthIdentity(uid: intent.uid, authEpochUUID: intent.authEpochUUID))
        trace.append("confirmAccountDeleted:\(observation.rawValue)")
        guard observation == .definitivelyDeleted, intent.phase == .prepared else {
            presentation = .blocked(.remoteMalformed)
            return .rest(.settled(.blocked(.remoteMalformed)))
        }
        return await transition(intent, identity) { next in
            next.phase = .localDetaching; next.detachReason = .capabilityInvalid; next.purpose = nil
            next.authorityKind = nil; next.startedAt = nil; next.dataDeletedAt = nil; next.stagedRoot = nil; next.authGuardAfter = nil
        }
    }

    private func request(for intent: AccountDeletionIntentV1, preferred: (String, String, String) -> AccountDeletionRequestV1) async -> AccountDeletionRequestV1 {
        if case let .signedIn(tuple) = await dependencies.auth.currentSignedAuth(), tuple.uid == intent.uid {
            return preferred(intent.uid, intent.operationId, intent.proofNonce)
        }
        return .resume(uid: intent.uid, operationId: intent.operationId, proofNonce: intent.proofNonce)
    }

    private func stepPrepared(_ intent: AccountDeletionIntentV1, _ identity: AccountDeletionIntentIdentity, wire: AccountDeletionRemoteResultV1?) async -> Step {
        let outcome: AccountDeletionRemoteResultV1
        if let wire {
            outcome = wire
        } else {
            let request: AccountDeletionRequestV1
            switch intent.purpose {
            case .confirmedBegin, .none: request = await self.request(for: intent) { .begin(uid: $0, operationId: $1, proofNonce: $2) }
            case .startupDiscover: request = await self.request(for: intent) { .discover(uid: $0, operationId: $1, proofNonce: $2) }
            }
            switch await dispatch(request) {
            case let .success(value): outcome = value
            case let .failure(error): return await rest(after: error, intent, identity)
            }
            if case .absent = outcome {
                if request.action == "begin" {
                    presentation = .blocked(.remoteMalformed)
                    return .rest(.settled(.blocked(.remoteMalformed)))
                }
                presentation = .queued
                return .rest(.settled(.queued))
            }
        }
        guard let authority = Self.authority(of: outcome) else {
            presentation = .blocked(.remoteMalformed)
            return .rest(.settled(.blocked(.remoteMalformed)))
        }
        return await transition(intent, identity, wire: outcome) { next in
            next.phase = .dataConfirmed; next.purpose = nil
            next.authorityKind = authority.kind; next.startedAt = authority.startedAt; next.dataDeletedAt = authority.dataDeletedAt
        }
    }

    private static func authority(of wire: AccountDeletionRemoteResultV1) -> (kind: AccountDeletionAuthorityKind, startedAt: String, dataDeletedAt: String)? {
        switch wire {
        case .absent: return nil
        case let .dataFinal(w): return (w.authorityKind, w.startedAt, w.dataDeletedAt)
        case let .authGuarding(w): return (w.authorityKind, w.startedAt, w.dataDeletedAt)
        case let .accountDeleted(w): return (w.authorityKind, w.startedAt, w.dataDeletedAt)
        }
    }

    /// The intent-linked UID purge with every owner ack mirrored into the intent before the next owner runs.
    private enum PurgeStep {
        case cleared(AccountDeletionIntentV1, AccountDeletionIntentIdentity)
        case blocked(LocalPrivacyPurgeBlockedReason)
    }

    private func runPurge(_ intent: AccountDeletionIntentV1, _ identity: AccountDeletionIntentIdentity) async -> PurgeStep {
        let cursor = PurgeCursor(intent: intent, identity: identity)
        let request = LocalPrivacyPurgeCoordinator.Request(scope: .uid(intent.uid), providerContext: intent.providerContext, terminalDeletionLink: nil)
        let result = await dependencies.purge.purge(request) { owner in await self.mirror(owner, cursor) }
        trace.append("purge:\(result)")
        switch result {
        case .cleared: let (next, nextIdentity) = await cursor.current; return .cleared(next, nextIdentity)
        case let .blocked(reason): return .blocked(reason)
        }
    }

    private actor PurgeCursor {
        var intent: AccountDeletionIntentV1
        var identity: AccountDeletionIntentIdentity
        init(intent: AccountDeletionIntentV1, identity: AccountDeletionIntentIdentity) { self.intent = intent; self.identity = identity }
        var current: (AccountDeletionIntentV1, AccountDeletionIntentIdentity) { (intent, identity) }
        func set(_ intent: AccountDeletionIntentV1, _ identity: AccountDeletionIntentIdentity) { self.intent = intent; self.identity = identity }
    }

    private func mirror(_ owner: PurgeOwner, _ cursor: PurgeCursor) async -> Bool {
        let (intent, identity) = await cursor.current
        guard !intent.acks.contains(owner) else { return true }
        var next = intent
        next.acks.append(owner)
        let now = dependencies.clock.now()
        guard CanonicalInstant.isCanonical(now) else { return false }
        next.updatedAt = max(now, intent.updatedAt)
        guard case let .success(nextIdentity) = store.write(next, expecting: identity) else { trace.append("ack:\(owner.rawValue):write_failed"); return false }
        trace.append("ack:\(owner.rawValue)")
        await cursor.set(next, nextIdentity)
        return true
    }

    private func stepPurging(_ intent: AccountDeletionIntentV1, _ identity: AccountDeletionIntentIdentity, wire: AccountDeletionRemoteResultV1?) async -> Step {
        let purged: AccountDeletionIntentV1
        let purgedIdentity: AccountDeletionIntentIdentity
        switch await runPurge(intent, identity) {
        case let .cleared(next, nextIdentity): purged = next; purgedIdentity = nextIdentity
        case let .blocked(reason): presentation = .blocked(reason); return .rest(.settled(.blocked(reason)))
        }
        // The root that stages the detach: the wire in hand, else a fresh resume (relaunch inside purging).
        let root: AccountDeletionRemoteResultV1
        if let wire {
            root = wire
        } else {
            switch await dispatch(.resume(uid: purged.uid, operationId: purged.operationId, proofNonce: purged.proofNonce)) {
            case let .success(value): root = value
            case let .failure(error): return await rest(after: error, purged, purgedIdentity)
            }
        }
        switch root {
        case .dataFinal:
            return await transition(purged, purgedIdentity, wire: root) { $0.phase = .localDetaching; $0.stagedRoot = .dataDeleted }
        case let .authGuarding(w):
            return await transition(purged, purgedIdentity, wire: root) { $0.phase = .localDetaching; $0.stagedRoot = .authGuarding; $0.authGuardAfter = w.authGuardAfter }
        case .accountDeleted:
            return await transition(purged, purgedIdentity, wire: root) { next in
                next.phase = .localDetaching; next.detachReason = .authDeleted
                next.authorityKind = nil; next.startedAt = nil; next.dataDeletedAt = nil
            }
        case .absent:
            presentation = .blocked(.remoteMalformed)
            return .rest(.settled(.blocked(.remoteMalformed)))
        }
    }

    /// Every `local_detaching` variant completes the eight-owner work and both barriers (the journal skips acknowledged
    /// owners; the barriers are proved fresh) before its next transition.
    private func stepLocalDetaching(_ intent: AccountDeletionIntentV1, _ identity: AccountDeletionIntentIdentity, wire: AccountDeletionRemoteResultV1?) async -> Step {
        let detached: AccountDeletionIntentV1
        let detachedIdentity: AccountDeletionIntentIdentity
        switch await runPurge(intent, identity) {
        case let .cleared(next, nextIdentity): detached = next; detachedIdentity = nextIdentity
        case let .blocked(reason): presentation = .blocked(reason); return .rest(.settled(.blocked(reason)))
        }
        guard detached.acks == PurgeOwner.order else {
            presentation = .blocked(.localPrivacyPurgeFailed)
            return .rest(.settled(.blocked(.localPrivacyPurgeFailed)))
        }
        switch (detached.stagedRoot, detached.detachReason) {
        case (.dataDeleted, _):
            return await transition(detached, detachedIdentity) { $0.phase = .authFinalizeDispatched; $0.stagedRoot = nil }
        case (.authGuarding, _):
            // The guarding wire in hand means no finalize call (C2.2); a relaunch here dispatches finalize once.
            return await transition(detached, detachedIdentity, wire: wire) { $0.phase = .guarding; $0.stagedRoot = nil }
        case (_, .authDeleted):
            return await transition(detached, detachedIdentity) { $0.phase = .completed; $0.detachReason = nil }
        case (_, .capabilityInvalid):
            return await transition(detached, detachedIdentity) { $0.phase = .localCleared; $0.detachReason = nil }
        case (_, .remoteUnverified):
            // Terminal without `completed`/`local_cleared`: the remote-unconfirmed presentation (its linked handoff is the terminal-consumption increment's).
            return .rest(await publishTerminal(detached))
        case (.none, .none):
            presentation = .blocked(.fileIO)
            return .rest(.settled(.blocked(.fileIO)))
        }
    }

    private func stepFinalize(_ intent: AccountDeletionIntentV1, _ identity: AccountDeletionIntentIdentity, wire: AccountDeletionRemoteResultV1?) async -> Step {
        _ = wire
        let outcome: AccountDeletionRemoteResultV1
        switch await dispatch(.finalize(uid: intent.uid, operationId: intent.operationId, proofNonce: intent.proofNonce)) {
        case let .success(value): outcome = value
        case let .failure(error): return await rest(after: error, intent, identity)
        }
        switch outcome {
        case let .authGuarding(w):
            // The guarding wire just received rests the reducer in `guarding`; a later Retry dispatches finalize again.
            return await transition(intent, identity, wire: outcome) { $0.phase = .guarding; $0.authGuardAfter = w.authGuardAfter }
        case .accountDeleted:
            return await transition(intent, identity) { next in
                next.phase = .localDetaching; next.detachReason = .authDeleted
                next.authorityKind = nil; next.startedAt = nil; next.dataDeletedAt = nil
            }
        case .dataFinal, .absent:
            presentation = .blocked(.remoteMalformed)
            return .rest(.settled(.blocked(.remoteMalformed)))
        }
    }

    private func stepGuarding(_ intent: AccountDeletionIntentV1, _ identity: AccountDeletionIntentIdentity, wire: AccountDeletionRemoteResultV1?) async -> Step {
        let outcome: AccountDeletionRemoteResultV1
        switch wire {
        case .some(.authGuarding), .some(.accountDeleted):
            outcome = wire!
        default:
            switch await dispatch(.finalize(uid: intent.uid, operationId: intent.operationId, proofNonce: intent.proofNonce)) {
            case let .success(value): outcome = value
            case let .failure(error): return await rest(after: error, intent, identity)
            }
        }
        switch outcome {
        case .authGuarding:
            let guarding: AccountDeletionPresentationV1 = .guarding(authGuardAfter: intent.authGuardAfter ?? "")
            presentation = guarding
            return .rest(.settled(guarding))
        case .accountDeleted:
            return await transition(intent, identity) { next in
                next.phase = .localDetaching; next.detachReason = .authDeleted
                next.authorityKind = nil; next.startedAt = nil; next.dataDeletedAt = nil; next.authGuardAfter = nil
            }
        case .dataFinal, .absent:
            presentation = .blocked(.remoteMalformed)
            return .rest(.settled(.blocked(.remoteMalformed)))
        }
    }

    // MARK: terminal publication (consumption is the next increment's)

    private func publishTerminal(_ intent: AccountDeletionIntentV1) async -> AccountDeletionDispatchResult {
        let result: CompletionResultV1
        let kind: TerminalPresentationKind
        switch (intent.phase, intent.detachReason) {
        case (.completed, _):
            let google: GoogleCompletedRevocation
            switch intent.dispositions.googleRevocation {
            case .notRequired: google = .notRequired
            case .sdkDisconnectRequired: google = .revoked
            case .manualRequired: google = .manualRequired
            }
            result = .completed(appleRevocation: intent.dispositions.appleRevocation, googleRevocation: google); kind = .completed
        case (.localCleared, _):
            result = .localCleared; kind = .localCleared
        default:
            result = .remoteUnconfirmed; kind = .remoteUnconfirmed
        }
        switch await dependencies.completion.derive(result) {
        case let .written(snapshot), let .replayed(snapshot):
            trace.append("completion:\(intent.phase.rawValue)")
            presentation = .completion(snapshot)
            await dependencies.gate.setGate(.active(uid: intent.uid))
            await dependencies.gate.setPendingTerminalPresentation(kind)
            return .settled(.completion(snapshot))
        case .blocked:
            trace.append("completion:blocked")
            return await blockGate(.fileIO)
        case let .failed(code):
            trace.append("completion:io:\(code.rawValue)")
            return await blockGate(.fileIO)
        }
    }
}
