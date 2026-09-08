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

// MARK: - C2.3 wire binding

/// Every wire the reducer consumes is bound to the durable capability before any transition: it names the intent's
/// operation, every instant it carries is a representable canonical UTC millisecond (regex and Gregorian round trip),
/// and the authority members and deadline the intent already persisted are byte-matched (immutable once stored).
enum AccountDeletionWireBinding {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Canonical shape and a strict round trip: `2026-99-99T99:99:99.999Z` matches the shape and is refused here.
    static func isRepresentableInstant(_ value: String) -> Bool {
        guard CanonicalInstant.isCanonical(value), let date = formatter.date(from: value) else { return false }
        return CanonicalInstant.string(from: date) == value
    }

    static func operationId(of wire: AccountDeletionRemoteResultV1) -> String {
        switch wire {
        case let .absent(operationId): return operationId
        case let .dataFinal(w): return w.operationId
        case let .authGuarding(w): return w.operationId
        case let .accountDeleted(w): return w.operationId
        }
    }

    static func instants(of wire: AccountDeletionRemoteResultV1) -> [String] {
        switch wire {
        case .absent: return []
        case let .dataFinal(w): return [w.startedAt, w.dataDeletedAt]
        case let .authGuarding(w): return [w.startedAt, w.dataDeletedAt, w.authAbsenceObservedAt, w.authGuardAfter]
        case let .accountDeleted(w): return [w.startedAt, w.dataDeletedAt, w.authAbsenceObservedAt, w.authGuardAfter, w.authGuardCompletedAt, w.accountDeletedAt]
        }
    }

    static func names(_ wire: AccountDeletionRemoteResultV1, operationId: String) -> Bool { self.operationId(of: wire) == operationId }

    static func instantsRepresentable(_ wire: AccountDeletionRemoteResultV1) -> Bool { instants(of: wire).allSatisfy(isRepresentableInstant) }

    static func binds(_ wire: AccountDeletionRemoteResultV1, to intent: AccountDeletionIntentV1) -> Bool {
        guard names(wire, operationId: intent.operationId), instantsRepresentable(wire) else { return false }
        let authority: (kind: AccountDeletionAuthorityKind, startedAt: String, dataDeletedAt: String)
        var authGuardAfter: String?
        switch wire {
        case .absent: return true
        case let .dataFinal(w): authority = (w.authorityKind, w.startedAt, w.dataDeletedAt)
        case let .authGuarding(w): authority = (w.authorityKind, w.startedAt, w.dataDeletedAt); authGuardAfter = w.authGuardAfter
        case let .accountDeleted(w): authority = (w.authorityKind, w.startedAt, w.dataDeletedAt); authGuardAfter = w.authGuardAfter
        }
        if let stored = intent.authorityKind {
            guard stored == authority.kind, intent.startedAt == authority.startedAt, intent.dataDeletedAt == authority.dataDeletedAt else { return false }
        }
        if let deadline = intent.authGuardAfter, let authGuardAfter {
            guard deadline == authGuardAfter else { return false } // deadline continuity
        }
        return true
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

    var isCompletion: Bool { if case .completion = self { return true }; return false }

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
        /// Signs out only a Firebase user whose UID matches (terminal consumption, Apple revocation); true when no
        /// matching user remains afterwards. S7 wires the production closure; no other sign-out reaches the coordinator.
        let signOutMatchingUser: @Sendable (String) async -> Bool
    }

    /// The Apple credential-state rule (C2.5): revoked/notFound for still-matching authority signs out and resumes only an
    /// already-named deletion; authorized is a no-op; every other state is the fixed `APPLE_CREDENTIAL_STATE_UNRESOLVED`.
    enum AppleCredentialStateDisposition: Sendable, Equatable {
        case resumed(AccountDeletionDispatchResult)
        case signedOut
        case noOp
        case unresolved(String)
    }
    static let appleCredentialStateUnresolved = "APPLE_CREDENTIAL_STATE_UNRESOLVED"

    private let dependencies: Dependencies
    private let store: AccountDeletionIntentStore
    private var inflight: Task<AccountDeletionDispatchResult, Never>?
    private var inflightUID: String?
    private var inflightToken: UUID?
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
        case let .present(intent, _) where intent.uid != uid && intent.phase != .guarding:
            return .busy
        case let .present(intent, identity) where intent.uid != uid:
            return await runSingleflight(uid: uid) { await self.optionB(from: intent, identity, to: uid) }
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
        // the slot is reserved before the first suspension; the body never re-enters a public entry point
        return await runSingleflight(uid: "") { await self.discoverBody() }
    }

    private func discoverBody() async -> AccountDeletionDispatchResult {
        switch store.observe() {
        case .present:
            return await resume()
        case .absent:
            if let settled = await residualAuthority() { return settled }
            guard case let .signedIn(tuple) = await dependencies.auth.currentSignedAuth() else { return await clearGate() }
            inflightUID = tuple.uid
            return await discover(tuple: tuple)
        case .malformed:
            return await blockGate(.fileIO)
        case let .ioFailed(code):
            trace.append("intent:io:\(code.rawValue)")
            return await blockGate(.fileIO)
        }
    }

    /// With no intent, the durable authority that may still exist (the same typed discovery startup and Retry perform):
    /// a surviving linked all-scope journal finishes its consumption (the intent was already unlinked); a stray completion
    /// file (crash between the journal unlink and the file unlink) is re-presented for its acknowledge; malformed or
    /// unreadable completion bytes block `FILE_IO` with the bytes retained (C2.5: never absence). nil when none exists.
    private func residualAuthority() async -> AccountDeletionDispatchResult? {
        if let settled = await journalResidue() { return settled }
        switch await dependencies.completion.observeCompletion() {
        case let .present(snapshot):
            trace.append("completion:stray")
            presentation = .completion(snapshot)
            await dependencies.gate.setGate(.blocked)
            await dependencies.gate.setPendingTerminalPresentation(Self.terminalKind(of: snapshot.result))
            return .settled(.completion(snapshot))
        case .malformed:
            trace.append("completion:malformed")
            return await blockGate(.fileIO)
        case let .ioFailed(code):
            trace.append("completion:io:\(code.rawValue)")
            return await blockGate(.fileIO)
        case .absent:
            return nil
        }
    }

    /// The journal half of the residue, classified exhaustively before anything can clear (C3): a linked all-scope journal
    /// finishes its consumption; a crash-surviving ordinary all-scope journal resumes until every owner and both barriers
    /// ack; a UID journal whose intent is gone is unmatched authority; malformed and unreadable journals block with the
    /// bytes retained. nil only for observed absence. The consumption uses this alone: the completion file it is consuming
    /// is the presenter's, and re-presenting it there would refuse the acknowledge that is running.
    private func journalResidue() async -> AccountDeletionDispatchResult? {
        switch await dependencies.purge.observeJournal() {
        case let .present(journal) where journal.scope == .all && journal.terminalDeletionLink != nil:
            return await finishConsumption(link: journal.terminalDeletionLink!, intentIdentity: nil)
        case let .present(journal) where journal.scope == .all:
            trace.append("journal:resume_all")
            let result = await dependencies.purge.purge(scope: .all)
            trace.append("journal:resume_all:\(result)")
            guard result == .cleared else {
                if case let .blocked(reason) = result { return await blockGate(reason) }
                return await blockGate(.localPrivacyPurgeFailed)
            }
        case .present:
            trace.append("journal:unmatched_uid")
            return await blockGate(.localPrivacyPurgeFailed)
        case .malformed:
            trace.append("journal:malformed")
            return await blockGate(.localPrivacyPurgeFailed)
        case let .ioFailed(code):
            trace.append("journal:io:\(code.rawValue)")
            return await blockGate(.fileIO)
        case .absent:
            break
        }
        return nil
    }

    /// Every SIGNED_OUT transition and direct A→B switch (C2.4): `loading`, the intent-linked reducer first, then the
    /// crash-durable all-scope purge, then startup discovery; `clear` or the next UID is published only after both finish.
    /// Every waiter re-arbitrates after each await, so two callers parked on one predecessor run one after the other.
    func authTransition() async -> AccountDeletionDispatchResult {
        await awaitPredecessors()
        return await runSingleflight(uid: "") { await self.authTransitionBody() }
    }

    /// Re-arbitrates after every await: a caller parked on a predecessor waits for it, retires the completed task from the
    /// slot itself (the installing caller's deferred clear becomes a no-op), and looks again, so two waiters on one
    /// predecessor run one after the other and never install over each other.
    private func awaitPredecessors() async {
        while let predecessor = inflight {
            _ = await predecessor.value
            if inflight == predecessor { inflight = nil; inflightUID = nil; inflightToken = nil }
        }
    }

    private func authTransitionBody() async -> AccountDeletionDispatchResult {
        await dependencies.gate.setGate(.loading)
        trace.append("auth_transition")
        var intentResult: AccountDeletionDispatchResult?
        if case .present = store.observe() {
            intentResult = await resume()
        }
        let purged = await dependencies.purge.purge(scope: .all)
        trace.append("all_scope:\(purged)")
        if case let .blocked(reason) = purged { return await blockGate(reason) }
        if let intentResult, case .present = store.observe() { return intentResult }
        return await discoverBody()
    }

    /// C2.5 Apple credential state for `uid`'s still-matching authority.
    func appleCredentialState(_ state: AppleCredentialStateOutcomeV1, uid: String) async -> AppleCredentialStateDisposition {
        switch state {
        case .authorized:
            return .noOp
        case .revoked, .notFound:
            guard case let .signedIn(tuple) = await dependencies.auth.currentSignedAuth(), tuple.uid == uid else { return .noOp }
            trace.append("apple:\(state.rawValue):sign_out")
            _ = await dependencies.signOutMatchingUser(uid)
            guard case let .present(intent, _) = store.observe(), intent.uid == uid else { return .signedOut }
            return .resumed(await retry())
        case .transferred, .unresolved:
            trace.append(Self.appleCredentialStateUnresolved)
            return .unresolved(Self.appleCredentialStateUnresolved)
        }
    }

    /// The presenter's `consume`: the terminal consumption order of C2.2. True only when the intent and journal are gone.
    func consumeTerminal(_ snapshot: CompletionSnapshotV1) async -> Bool {
        await awaitPredecessors()
        _ = snapshot
        return await runSingleflight(uid: "") { await self.consumeBody() } == .clear
    }

    /// `.clear` only when the intent and journal are gone; every other rest state answers the presenter `false`.
    private func consumeBody() async -> AccountDeletionDispatchResult {
        switch store.observe() {
        case let .present(intent, identity):
            guard Self.isTerminal(intent) else { trace.append("consume:not_terminal"); return .settled(.blocked(.localPrivacyPurgeFailed)) }
            inflightUID = intent.uid
            trace.append("consume:sign_out")
            guard await dependencies.signOutMatchingUser(intent.uid) else { return await blockGate(.localPrivacyPurgeFailed) }
            // no Firebase Auth user item of any app configuration outlives the account (the installation item is untouched)
            trace.append("consume:keychain_scrub:\(FirebaseAuthKeychainScrub.removeUserItems())")
            let link = TerminalDeletionLinkV1(deletionOperationId: intent.operationId, deletionProofSHA256: intent.proofSHA256)
            return await finishConsumption(link: link, intentIdentity: identity)
        case .absent:
            // the same exhaustive journal classification; the completion file is the presenter's and is not re-presented here
            if let settled = await journalResidue() { return settled }
            // the consumption already completed; only the completion file remained
            return await clearGate()
        case .malformed, .ioFailed:
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
            // no intent: a linked all-scope journal or a completion file is durable authority (the startup discovery's typed
            // journal/completion step, without the server discovery); only their absence clears
            return await runSingleflight(uid: "") {
                if let settled = await self.residualAuthority() { return settled }
                return await self.clearGate()
            }
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
        // the slot is never overwritten: a task installed by another caller between this caller's last await and now is joined
        if let existing = inflight { return await existing.value }
        let token = UUID()
        let task = Task { await body() }
        inflight = task
        inflightUID = uid
        inflightToken = token
        defer { if inflightToken == token { inflight = nil; inflightUID = nil; inflightToken = nil } }
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
        // the discovery wire must name the capability it was sent and carry only representable instants (C2.3)
        if let outcome, !AccountDeletionWireBinding.names(outcome, operationId: operationId) || !AccountDeletionWireBinding.instantsRepresentable(outcome) {
            trace.append("wire:unbound")
            return await blockGate(.remoteMalformed)
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
        let observed = store.observe()
        guard case let .present(intent, identity) = observed else {
            // never re-enter a public entry point from inside the singleflight body
            switch observed {
            case .absent: return await clearGate()
            default: return await blockGate(.fileIO)
            }
        }
        if Self.isTerminal(intent), case let .present(journal) = await dependencies.purge.observeJournal(), journal.scope == .all, let link = journal.terminalDeletionLink {
            return await finishConsumption(link: link, intentIdentity: identity)
        }
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
        guard intent.phase == .prepared else {
            presentation = .blocked(.remoteMalformed)
            return .rest(.settled(.blocked(.remoteMalformed)))
        }
        if observation == .definitivelyDeleted {
            return await transition(intent, identity) { next in
                next.phase = .localDetaching; next.detachReason = .capabilityInvalid; next.purpose = nil
                next.authorityKind = nil; next.startedAt = nil; next.dataDeletedAt = nil; next.stagedRoot = nil; next.authGuardAfter = nil
            }
        }
        // The honest branch: no Auth user to re-enroll with and no proof of deletion — local data is removed, remote deletion unverified.
        if case .signedOut = await dependencies.auth.currentSignedAuth() {
            return await transition(intent, identity) { next in
                next.phase = .localDetaching; next.detachReason = .remoteUnverified; next.purpose = nil
                next.authorityKind = nil; next.startedAt = nil; next.dataDeletedAt = nil; next.stagedRoot = nil; next.authGuardAfter = nil
            }
        }
        presentation = .blocked(.remoteMalformed)
        return .rest(.settled(.blocked(.remoteMalformed)))
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
        if let rest = unbound(outcome, intent) { return rest }
        guard let authority = Self.authority(of: outcome) else {
            presentation = .blocked(.remoteMalformed)
            return .rest(.settled(.blocked(.remoteMalformed)))
        }
        return await transition(intent, identity, wire: outcome) { next in
            next.phase = .dataConfirmed; next.purpose = nil
            next.authorityKind = authority.kind; next.startedAt = authority.startedAt; next.dataDeletedAt = authority.dataDeletedAt
        }
    }

    /// C2.3 binding before every transition: a wire that names another operation, carries a nonrepresentable instant, or
    /// disagrees with the authority or deadline the intent already holds is `REMOTE_MALFORMED` with every byte retained.
    private func unbound(_ wire: AccountDeletionRemoteResultV1, _ intent: AccountDeletionIntentV1) -> Step? {
        guard !AccountDeletionWireBinding.binds(wire, to: intent) else { return nil }
        trace.append("wire:unbound")
        presentation = .blocked(.remoteMalformed)
        return .rest(.settled(.blocked(.remoteMalformed)))
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
        if let rest = unbound(root, purged) { return rest }
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
            // Entering `guarding` from the staged root never calls finalize (C2.2); the reducer rests here, and a later
            // launch or Retry in `guarding` dispatches finalize once.
            _ = wire
            let step = await transition(detached, detachedIdentity) { $0.phase = .guarding; $0.stagedRoot = nil }
            guard case let .next(entered, _, _) = step else { return step }
            let guarding: AccountDeletionPresentationV1 = .guarding(authGuardAfter: entered.authGuardAfter ?? "")
            presentation = guarding
            return .rest(.settled(guarding))
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
        if let rest = unbound(outcome, intent) { return rest }
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
        if let rest = unbound(outcome, intent) { return rest }
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

    // MARK: terminal consumption (C2.2) and the Option-B guarding handoff (C2.4)

    private static func isTerminal(_ intent: AccountDeletionIntentV1) -> Bool {
        intent.phase == .completed || intent.phase == .localCleared || (intent.phase == .localDetaching && intent.detachReason == .remoteUnverified)
    }

    private static func terminalKind(of result: CompletionResultV1) -> TerminalPresentationKind {
        switch result {
        case .completed: return .completed
        case .localCleared: return .localCleared
        case .remoteUnconfirmed: return .remoteUnconfirmed
        }
    }

    /// After the matching sign-out: the linked all-scope journal (created before the intent is unlinked) drives the eight
    /// owners and both barriers again, then the intent is unlinked, then the journal, then `clear` is published. A journal
    /// whose link does not byte-match the surviving intent is `LOCAL_PRIVACY_PURGE_FAILED`.
    private func finishConsumption(link: TerminalDeletionLinkV1, intentIdentity: AccountDeletionIntentIdentity?) async -> AccountDeletionDispatchResult {
        if case let .present(intent, _) = store.observe() {
            guard intent.operationId == link.deletionOperationId, intent.proofSHA256 == link.deletionProofSHA256 else {
                trace.append("consume:link_mismatch")
                return await blockGate(.localPrivacyPurgeFailed)
            }
        }
        let result = await dependencies.purge.purge(LocalPrivacyPurgeCoordinator.Request(scope: .all, providerContext: nil, terminalDeletionLink: link))
        trace.append("consume:purge:\(result)")
        guard result == .cleared else {
            if case let .blocked(reason) = result { return await blockGate(reason) }
            return await blockGate(.localPrivacyPurgeFailed)
        }
        if case let .present(_, identity) = store.observe() {
            guard case .success = store.unlink(expecting: intentIdentity ?? identity) else { trace.append("consume:unlink_stale"); return await blockGate(.fileIO) }
            trace.append("consume:intent_unlinked")
        }
        guard await dependencies.purge.unlinkJournal() else { return await blockGate(.fileIO) }
        trace.append("consume:journal_unlinked")
        return await clearGate()
    }

    /// Option B: the guarding intent's server AUTH_GUARDING authority and every local postcondition are byte-matched, the
    /// new UID's capability is prepared without an intervening await after the CAS unlink; any drift refuses with retained bytes.
    private func optionB(from guarding: AccountDeletionIntentV1, _ identity: AccountDeletionIntentIdentity, to newUID: String) async -> AccountDeletionDispatchResult {
        guard case let .signedIn(tuple) = await dependencies.auth.currentSignedAuth(), tuple.uid == newUID else { trace.append("optionB:auth_drift"); return .busy }
        guard case let .success(.authGuarding(wire)) = await dispatch(.resume(uid: guarding.uid, operationId: guarding.operationId, proofNonce: guarding.proofNonce)),
              AccountDeletionWireBinding.binds(.authGuarding(wire), to: guarding), wire.authorityKind == guarding.authorityKind, wire.startedAt == guarding.startedAt, wire.dataDeletedAt == guarding.dataDeletedAt,
              wire.authGuardAfter == guarding.authGuardAfter else { trace.append("optionB:authority_mismatch"); return .busy }
        switch await dependencies.purge.observeJournal() {
        case .absent: break
        case let .present(journal) where journal.scope == .uid(guarding.uid) && journal.acks == PurgeOwner.order: break
        default: trace.append("optionB:journal_incomplete"); return .busy
        }
        let dispositions = await dependencies.providerContext.dispositions(expectedUID: newUID)
        guard let proofNonce = AccountDeletionCapability.newProofNonce() else { return .busy }
        let now = dependencies.clock.now()
        guard CanonicalInstant.isCanonical(now) else { trace.append("clock:nonrepresentable"); return .busy }
        guard case let .signedIn(current) = await dependencies.auth.currentSignedAuth(), current == tuple else { trace.append("optionB:auth_drift"); return .busy }
        // no await between the unlink and the new intent's persistence
        guard case .success = store.unlink(expecting: identity) else { trace.append("optionB:cas_drift"); return .busy }
        trace.append("optionB:unlinked")
        let intent = AccountDeletionIntentV1(
            uid: newUID, authEpochUUID: tuple.authEpochUUID, credentialRevision: tuple.credentialRevision,
            operationId: AccountDeletionCapability.newOperationId(), proofNonce: proofNonce, dispositions: dispositions,
            phase: .prepared, purpose: .confirmedBegin, authorityKind: nil, detachReason: nil, stagedRoot: nil,
            startedAt: nil, dataDeletedAt: nil, authGuardAfter: nil, acks: [], createdAt: now, updatedAt: now)
        guard case let .success(newIdentity) = store.write(intent, expecting: nil) else { return await blockGate(.fileIO) }
        trace.append("phase:prepared:confirmed_begin")
        _ = await dependencies.purge.unlinkJournal()
        await project(intent)
        return await reduce(intent, newIdentity)
    }

    // MARK: terminal publication

    private func publishTerminal(_ intent: AccountDeletionIntentV1) async -> AccountDeletionDispatchResult {
        let result: CompletionResultV1
        switch (intent.phase, intent.detachReason) {
        case (.completed, _):
            let google: GoogleCompletedRevocation
            switch intent.dispositions.googleRevocation {
            case .notRequired: google = .notRequired
            case .sdkDisconnectRequired: google = .revoked
            case .manualRequired: google = .manualRequired
            }
            result = .completed(appleRevocation: intent.dispositions.appleRevocation, googleRevocation: google)
        case (.localCleared, _):
            result = .localCleared
        default:
            result = .remoteUnconfirmed
        }
        let kind = Self.terminalKind(of: result)
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

extension CompletionResultV1 {
    /// The manual-required providers whose instruction paragraphs and links the surface shows, Apple then Google (C2.5).
    var manualProviders: [CompletionProvider] {
        guard case let .completed(apple, google) = self else { return [] }
        var providers: [CompletionProvider] = []
        if apple == .manualRequired { providers.append(.apple) }
        if google == .manualRequired { providers.append(.google) }
        return providers
    }
}

// MARK: - Durable-file observation shared by the store owners (C9.7.12 `FileObservationV1`; C9.7.5 enumerability)

/// A file read through one no-follow descriptor bounded by `cap + 1`: absent, over-cap (identity digest only), or the
/// complete bytes classified by the caller's strict decoder.
enum DurableFileObserver {
    struct Read: Sendable {
        let observation: FileObservationV1
        /// Complete bytes for a within-cap file; nil when absent or over-cap.
        let bytes: Data?
        /// The identity the unlink precondition compares (over-cap files by descriptor identity).
        let identity: PrivacyDurableFile.Observation?
    }

    static func read(at url: URL, cap: Int, isValid: (Data) -> (generationId: String, envelopeSHA256: String)?) throws -> Read {
        guard let observed = try PrivacyDurableFile.observe(at: url, limit: cap) else { return Read(observation: .absent, bytes: nil, identity: nil) }
        if observed.bytes.count > cap {
            return Read(observation: .overCap(byteLength: Int(observed.size), fileIdentityDigest: observed.fileIdentityDigest), bytes: nil, identity: observed)
        }
        let sha = TaskCanonicalV1.sha256Hex(data: observed.bytes)
        if let valid = isValid(observed.bytes) {
            return Read(observation: .valid(byteLength: observed.bytes.count, bytesSHA256: sha, generationId: valid.generationId, envelopeSHA256: valid.envelopeSHA256), bytes: observed.bytes, identity: observed)
        }
        return Read(observation: .malformed(byteLength: observed.bytes.count, bytesSHA256: sha), bytes: observed.bytes, identity: observed)
    }

    /// The unlink precondition (C9.7.12): within-cap bytes reread and hashed; over-cap by a new no-follow descriptor's identity.
    /// Whole-state CAS for a file that may be absent in the displayed observation: an absent observation matches only a
    /// still-absent file; every other observation matches as `matches` does.
    static func stillMatches(_ observation: FileObservationV1, at url: URL, cap: Int) -> Bool {
        if case .absent = observation {
            // only a successful observation that finds nothing matches displayed absence; a thrown error (unreadable file) is drift
            do { return try PrivacyDurableFile.observe(at: url, limit: cap) == nil } catch { return false }
        }
        return matches(observation, at: url, cap: cap)
    }

    static func matches(_ observation: FileObservationV1, at url: URL, cap: Int) -> Bool {
        guard let current = try? PrivacyDurableFile.observe(at: url, limit: cap) else { return false }
        switch observation {
        case .absent:
            return false
        case let .valid(_, sha, _, _), let .malformed(_, sha):
            return current.bytes.count <= cap && TaskCanonicalV1.sha256Hex(data: current.bytes) == sha
        case let .overCap(_, identity):
            return current.bytes.count > cap && current.fileIdentityDigest == identity
        }
    }
}

/// Enumerability (C9.7.5): bounded bytes parse as exactly one JSON object under a duplicate-member-rejecting parser.
enum JSONObjectScanner {
    /// The parsed top-level object, or nil for non-JSON bytes, a non-object root, or a duplicate member on any path.
    static func object(_ data: Data) -> [String: Any]? {
        guard hasNoDuplicateKeys(data), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    /// A structural scan that tracks the member names of every object on every path.
    static func hasNoDuplicateKeys(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var index = 0
        var stack: [Set<String>?] = []   // nil = array frame
        var expectingKey = false
        func skipWhitespace() { while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 } }
        func readString() -> String? {
            guard index < bytes.count, bytes[index] == 0x22 else { return nil }
            index += 1
            var raw: [UInt8] = []
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x5C { // backslash: keep the escape verbatim (names compare on their escaped form)
                    raw.append(byte)
                    index += 1
                    if index < bytes.count { raw.append(bytes[index]); index += 1 }
                    continue
                }
                if byte == 0x22 { index += 1; return String(decoding: raw, as: UTF8.self) }
                raw.append(byte)
                index += 1
            }
            return nil
        }
        skipWhitespace()
        guard index < bytes.count, bytes[index] == 0x7B else { return false }
        while index < bytes.count {
            skipWhitespace()
            guard index < bytes.count else { break }
            let byte = bytes[index]
            switch byte {
            case 0x7B: stack.append(Set<String>()); expectingKey = true; index += 1
            case 0x5B: stack.append(nil); expectingKey = false; index += 1
            case 0x7D, 0x5D: guard !stack.isEmpty else { return false }; stack.removeLast(); expectingKey = false; index += 1
            case 0x2C: expectingKey = stack.last.map { $0 != nil } ?? false; index += 1
            case 0x3A: index += 1
            case 0x22:
                guard let text = readString() else { return false }
                if expectingKey, let frame = stack.last, var names = frame {
                    if names.contains(text) { return false }
                    names.insert(text)
                    stack[stack.count - 1] = names
                    expectingKey = false
                }
            default: index += 1
            }
        }
        return stack.isEmpty
    }
}

// MARK: - The store-recovery driver (S4-CD5): every store only through `DurableStoreRecovering`

/// The four durable-store owners in the frozen order route, handoff, reset, workflow (S5/S7 conformers, S4's reset).
struct DurableStoreOwners: Sendable {
    let route: any DurableStoreRecovering
    let handoff: any DurableStoreRecovering
    let reset: any DurableStoreRecovering
    let workflow: any DurableStoreRecovering

    func owner(of store: DurableStore) -> any DurableStoreRecovering {
        switch store {
        case .route: return route
        case .handoff: return handoff
        case .reset: return reset
        case .workflow: return workflow
        }
    }
}

/// Classifies every store through the protocol (never opening, replacing, or unlinking an owner's file), publishes the
/// readiness vector, and routes each action to its owner; the dose store is classified for the current signed UID
/// through `DailyDoseLocalStore` and blocks only the reset's dose cleanup (C9.7.13).
actor DurableStoreRecoveryDriver {
    typealias Publish = @Sendable (DurableStore, StoreReadiness) async -> Void

    private let owners: DurableStoreOwners
    private let dose: DailyDoseLocalStore
    private let currentUID: any CurrentFirebaseUIDProviding
    private let publish: Publish
    private(set) var classifications: [RecoveryStore: RecoveryClassification] = [:]
    private(set) var trace: [String] = []
    /// Bumped at every `perform` entry: a classification observed before the action never overwrites the one after it.
    private var generations: [RecoveryStore: Int] = [:]

    init(owners: DurableStoreOwners, dose: DailyDoseLocalStore, currentUID: any CurrentFirebaseUIDProviding, publish: @escaping Publish) {
        self.owners = owners
        self.dose = dose
        self.currentUID = currentUID
        self.publish = publish
    }

    /// Frozen order route, handoff, reset, workflow, then the dose store; each result is published as it settles.
    func classifyAll() async -> [RecoveryStore: RecoveryClassification] {
        for store in DurableStore.allCases { _ = await classify(store) }
        _ = await classifyDose()
        return classifications
    }

    func classify(_ store: DurableStore) async -> RecoveryClassification {
        let owner = owners.owner(of: store)
        let generation = generations[RecoveryStore(store), default: 0]
        let observation = await owner.observe()
        let classification = owner.classify(observation)
        guard generations[RecoveryStore(store), default: 0] == generation else { return classification } // stale: an action ran meanwhile
        classifications[RecoveryStore(store)] = classification
        trace.append("classify:\(store.rawValue):\(Self.label(classification))")
        switch classification {
        case .ready: await publish(store, .ready)
        case let .blocked(snapshot): await publish(store, .blocked(snapshot))
        }
        return classification
    }

    func classifyDose() async -> RecoveryClassification {
        let generation = generations[.dose, default: 0]
        let classification: RecoveryClassification
        if let uid = currentUID.currentFirebaseUID(), let observed = await dose.observeMalformed(uid: uid), case let .dose(sha, length, _) = observed {
            classification = .blocked(.doseMalformed(recoveryStateDigest: observed.recoveryStateDigest, bytesSHA256: sha, byteLength: length))
        } else {
            classification = .ready
        }
        guard generations[.dose, default: 0] == generation else { return classification }
        classifications[.dose] = classification
        trace.append("classify:dose:\(Self.label(classification))")
        return classification
    }

    /// Routes the action to the owning store (the dose store to `DailyDoseLocalStore`), then reclassifies that store.
    func perform(store: RecoveryStore, action: RecoveryAction, expecting expectation: RecoveryExpectation) async -> RecoveryResult {
        trace.append("perform:\(store.rawValue):\(action.name)")
        generations[store, default: 0] += 1
        if store == .dose {
            guard action == .quarantineDoseBytes, case let .digest(digest) = expectation, let uid = currentUID.currentFirebaseUID() else { return .unavailable(store: .dose) }
            let result = await dose.performQuarantine(uid: uid, expecting: digest)
            _ = await classifyDose()
            return result
        }
        guard let durable = store.durable else { return .unavailable(store: store) }
        let result = await owners.owner(of: durable).perform(action, expecting: expectation)
        _ = await classify(durable)
        return result
    }

    private static func label(_ classification: RecoveryClassification) -> String {
        switch classification {
        case .ready: return "ready"
        case let .blocked(snapshot): return snapshot.state
        }
    }
}

// MARK: - Foreign resolution choice collection (C9.7.11; purely local until the single `resolve` call)

enum ForeignResolutionChoices {
    /// Display labels in displayed order; duplicate labels get a deterministic 1-based ordinal appended for display only
    /// (the group's label bytes and digests are unchanged).
    static func displayLabels(_ groups: [ForeignDecisionGroup]) -> [String] {
        var counts: [String: Int] = [:]
        for group in groups { counts[group.actionLabel, default: 0] += 1 }
        var ordinals: [String: Int] = [:]
        return groups.map { group in
            guard counts[group.actionLabel, default: 0] > 1 else { return group.actionLabel }
            ordinals[group.actionLabel, default: 0] += 1
            return "\(group.actionLabel) (\(ordinals[group.actionLabel] ?? 1))"
        }
    }

    /// The exact full ordered `choices` array for `resolve`: one `continue|restart` per displayed group in displayed order;
    /// nil when any group lacks a choice or a selection names an unknown group or value.
    static func choices(groups: [ForeignDecisionGroup], selections: [String: String]) -> [[String: String]]? {
        let known = Set(groups.map(\.decisionDigest))
        guard Set(selections.keys).isSubset(of: known) else { return nil }
        var choices: [[String: String]] = []
        for group in groups {
            guard let choice = selections[group.decisionDigest], choice == "continue" || choice == "restart" else { return nil }
            choices.append(["decisionDigest": group.decisionDigest, "choice": choice])
        }
        return choices
    }

    /// Each choice as its canonical element string (`{"choice":...,"decisionDigest":...}`), the form `RecoveryAction.resolve` carries.
    static func elements(_ choices: [[String: String]]) -> [String] {
        choices.map { String(decoding: TaskCanonicalV1.data($0) ?? Data(), as: UTF8.self) }
    }

    /// `choicesSHA256 = SHA-256(TaskCanonicalV1(choices))`: the canonical JSON array of the canonical elements.
    static func choicesSHA256(elements: [String]) -> String {
        TaskCanonicalV1.sha256Hex(data: Data(("[" + elements.joined(separator: ",") + "]").utf8))
    }

    /// `resolutionDigest = SHA-256(TaskCanonicalV1({recovery_state_digest, decision_groups}))`.
    static func resolutionDigest(recoveryStateDigest: String, groups: [ForeignDecisionGroup]) -> String {
        TaskCanonicalV1.sha256Hex(["recovery_state_digest": recoveryStateDigest, "decision_groups": groups.map { ["decisionDigest": $0.decisionDigest, "actionLabel": $0.actionLabel] }])
    }
}
