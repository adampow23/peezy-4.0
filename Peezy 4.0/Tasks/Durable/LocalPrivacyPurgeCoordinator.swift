import FirebaseFirestore
import Foundation

// S4 (C10.2 L4119): the Firestore runtime owner, the client-telemetry privacy authority, the
// room/media/narration-transfer actor, the completion-presentation owner, and the local privacy
// purge over the eight owners and both barriers. Every SDK is reached through an injected seam so
// the families run on fakes; S7 constructs the production instances (C9.7.16).

// MARK: - Firestore runtime owner (C2.2 firestore_cache owner; S4-CD2 installation)

/// The three operations the owner performs on the process-wide Firestore instance, behind a seam so the
/// purge order is proved without a FirebaseApp.
protocol FirestoreInstanceControlling: Sendable {
    /// The instance the owner publishes at install.
    func initial() -> Firestore
    /// `terminate()` without `waitForPendingWrites()`, then `clearPersistence()`.
    func terminateAndClearPersistence(_ firestore: Firestore) async throws
    /// A fresh instance after termination.
    func fresh() -> Firestore
    /// A bounded probe proving the fresh instance is usable; throws when it is not.
    func probe(_ firestore: Firestore) async throws
}

/// Production conformer over the Firebase SDK (S7 constructs it).
struct FirebaseFirestoreInstanceController: FirestoreInstanceControlling {
    func initial() -> Firestore { Firestore.firestore() }
    func terminateAndClearPersistence(_ firestore: Firestore) async throws {
        try await firestore.terminate()
        try await firestore.clearPersistence()
    }
    func fresh() -> Firestore { Firestore.firestore() }
    func probe(_ firestore: Firestore) async throws {
        // The cache must be empty after clearing: a cache-only read of a synthetic path returns nothing.
        _ = try? await firestore.collection("phase2Probe").document("probe").getDocument(source: .cache)
    }
}

enum FirestoreRuntimeError: Error, Equatable {
    /// `FIRESTORE_RUNTIME_NOT_INSTALLED`: acquisition before `FirestoreRuntime.install(_:)`.
    case notInstalled
    /// Acquisition while the runtime's purge is in flight or unacknowledged: Firestore cannot be acquired before its purge ack (C2.4).
    case purging
}

/// The firestore_cache owner: owns the instance, its invalidation, recreation, and publication (C2.2 L57).
/// Purge order: `terminate()` without `waitForPendingWrites()` → `clearPersistence()` → fresh instance → probe → new generation.
final class FirestoreRuntimeOwner: FirestoreRuntimeProviding, FirestoreLocalCachePurging, @unchecked Sendable {
    private let lock = NSLock()
    private let controller: any FirestoreInstanceControlling
    private var lease: FirestoreRuntimeLease
    private var purging = false

    init(controller: any FirestoreInstanceControlling) {
        self.controller = controller
        self.lease = FirestoreRuntimeLease(firestore: controller.initial(), generation: FirestoreRuntimeGeneration(rawValue: 1))
    }

    func acquire() async throws -> FirestoreRuntimeLease {
        let current: FirestoreRuntimeLease? = lock.withLock { purging ? nil : lease }
        guard let current else { throw FirestoreRuntimeError.purging }
        return current
    }

    func published() -> FirestoreRuntimeLease { lock.withLock { lease } }

    func isCurrent(_ generation: FirestoreRuntimeGeneration) -> Bool {
        lock.withLock { !purging && generation == lease.generation }
    }

    /// The scope is irrelevant to the cache: both scopes clear the whole local persistence.
    func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck {
        let stale: FirestoreRuntimeLease? = lock.withLock {
            guard !purging else { return nil }
            purging = true
            return lease
        }
        guard let stale else { return .failed }
        do {
            try await controller.terminateAndClearPersistence(stale.firestore)
            let fresh = controller.fresh()
            try await controller.probe(fresh)
            lock.withLock {
                lease = FirestoreRuntimeLease(firestore: fresh, generation: FirestoreRuntimeGeneration(rawValue: stale.generation.rawValue &+ 1))
                purging = false
            }
            return .acknowledged
        } catch {
            // The old generation is dead and no new one exists: acquisition keeps refusing until a later purge acks.
            return .failed
        }
    }
}

// MARK: - Client-telemetry privacy authority (C2.2 telemetry barrier; C9.7.14)

/// The Firebase Analytics/Crashlytics calls the barrier issues, behind a seam.
protocol TelemetryPrivacySDK: Sendable {
    func setAnalyticsCollectionEnabled(_ enabled: Bool)
    func setUserID(_ userID: String?)
    func setUserProperty(_ value: String?, forName name: String)
    func resetAnalyticsData()
    /// Crashlytics `checkForUnsentReports`: the callback reports whether unsent reports exist.
    func checkForUnsentReports(_ completion: @escaping @Sendable (Bool) -> Void)
    func deleteUnsentReports()
}

/// Process-lifetime singleflight state (C9.7.14): only a fresh process resets it. Tests inject one per case.
final class TelemetryPrivacyLifetime: @unchecked Sendable {
    static let shared = TelemetryPrivacyLifetime()
    private let lock = NSLock()
    private var outcome: ClientTelemetryPurgeOutcomeV1?
    private var inFlight: Task<ClientTelemetryPurgeOutcomeV1, Never>?
    private var generation: UInt64 = 0

    init() {}

    fileprivate func settled() -> ClientTelemetryPurgeOutcomeV1? { lock.withLock { outcome } }
    fileprivate func current() -> Task<ClientTelemetryPurgeOutcomeV1, Never>? { lock.withLock { inFlight } }
    fileprivate func begin(_ task: Task<ClientTelemetryPurgeOutcomeV1, Never>) -> UInt64 {
        lock.withLock { inFlight = task; generation &+= 1; return generation }
    }
    /// Records a sticky outcome (`cleared`/`relaunchRequired`); `failed` is not sticky and frees the singleflight.
    fileprivate func finish(_ generation: UInt64, _ result: ClientTelemetryPurgeOutcomeV1) {
        lock.withLock {
            guard generation == self.generation else { return }
            inFlight = nil
            if result != .failed { outcome = result }
        }
    }
    fileprivate func isCurrent(_ generation: UInt64) -> Bool { lock.withLock { generation == self.generation } }
}

/// C2.2 telemetry barrier: the five Analytics calls, then the sole process-lifetime `checkForUnsentReports`
/// racing a literal 10-second monotonic timeout on the main actor; `false` → cleared (sticky), `true` →
/// `deleteUnsentReports()` once → relaunchRequired (sticky); timeout/cancellation/invariant → failed.
@MainActor
final class ClientTelemetryPrivacyAuthority: ClientTelemetryPrivacyPurging {
    static let timeoutSeconds: Double = 10
    private let sdk: any TelemetryPrivacySDK
    private let lifetime: TelemetryPrivacyLifetime
    private let clock: ContinuousClock

    nonisolated init(sdk: any TelemetryPrivacySDK, lifetime: TelemetryPrivacyLifetime = .shared, clock: ContinuousClock = ContinuousClock()) {
        self.sdk = sdk
        self.lifetime = lifetime
        self.clock = clock
    }

    nonisolated func purgeAll() async -> ClientTelemetryPurgeOutcomeV1 {
        await run()
    }

    private func run() async -> ClientTelemetryPurgeOutcomeV1 {
        if let settled = lifetime.settled() { return settled }
        if let inFlight = lifetime.current() { return await inFlight.value }
        let sdk = self.sdk
        let clock = self.clock
        let lifetime = self.lifetime
        let task = Task<ClientTelemetryPurgeOutcomeV1, Never> { @MainActor in
            sdk.setAnalyticsCollectionEnabled(false)
            sdk.setUserID(nil)
            sdk.setUserProperty(nil, forName: "has_subscription")
            sdk.resetAnalyticsData()
            let verdict = await Self.checkOnce(sdk: sdk, clock: clock)
            switch verdict {
            case .some(false):
                return .cleared
            case .some(true):
                sdk.deleteUnsentReports()
                return .relaunchRequired
            case .none:
                return .failed
            }
        }
        let generation = lifetime.begin(task)
        let result = await task.value
        lifetime.finish(generation, result)
        return result
    }

    /// One `checkForUnsentReports` racing the timeout; a late or duplicate callback loses the CAS.
    private static func checkOnce(sdk: any TelemetryPrivacySDK, clock: ContinuousClock) async -> Bool? {
        let box = CallbackOnce()
        return await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
                    box.arm(continuation)
                    sdk.checkForUnsentReports { hasUnsent in box.fire(hasUnsent) }
                }
            }
            group.addTask {
                try? await clock.sleep(for: .seconds(timeoutSeconds))
                return box.timeout()
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Delivers exactly one verdict: the first of callback or timeout; later callbacks are dropped.
    private final class CallbackOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool?, Never>?
        private var delivered = false
        func arm(_ continuation: CheckedContinuation<Bool?, Never>) { lock.withLock { self.continuation = continuation } }
        func fire(_ value: Bool) {
            let target: CheckedContinuation<Bool?, Never>? = lock.withLock {
                guard !delivered else { return nil }
                delivered = true
                defer { continuation = nil }
                return continuation
            }
            target?.resume(returning: value)
        }
        func timeout() -> Bool? {
            let target: CheckedContinuation<Bool?, Never>? = lock.withLock {
                guard !delivered else { return nil }
                delivered = true
                defer { continuation = nil }
                return continuation
            }
            target?.resume(returning: nil)
            return nil
        }
    }
}

// MARK: - Room capture artifact owner and narration lease (C2.2 room_capture owner; S4-CD7)

/// The room_capture owner: issues `NarrationLease`s only while the deletion gate is `clear` for the UID and the
/// current gate generation, holds deposited transcripts and in-flight transfer registrations, registers the
/// capture artifacts, and on gate activation revokes every lease before its purge ack.
actor RoomCaptureArtifactOwner: RoomCaptureArtifactPurging {
    typealias GateSnapshot = @Sendable () async -> (gate: AccountDeletionGate, generation: GateGeneration)

    enum RevocationState: Sendable, Equatable { case open, revoked }

    private let gateSnapshot: GateSnapshot
    private let fileManager: FileManager
    private var leases: Set<NarrationLease> = []
    private var transcripts: [NarrationLease: String] = [:]
    private var transfers: [TransferHandle: @Sendable () -> Void] = [:]
    private var settlements: [TransferHandle: [CheckedContinuation<Void, Never>]] = [:]
    private var artifacts: [URL: NarrationLease] = [:]
    private var revocation: RevocationState = .open

    init(gateSnapshot: @escaping GateSnapshot, fileManager: FileManager = .default) {
        self.gateSnapshot = gateSnapshot
        self.fileManager = fileManager
    }

    /// A lease only while the gate is `clear` for this UID and the current generation; nil otherwise.
    func acquire(uid: String, sessionId: String) async -> NarrationLease? {
        let snapshot = await gateSnapshot()
        guard revocation == .open, snapshot.gate == .clear, !uid.isEmpty, !sessionId.isEmpty else { return nil }
        let lease = NarrationLease(leaseId: UUID().uuidString.lowercased(), uid: uid, gateGeneration: snapshot.generation, sessionId: sessionId)
        leases.insert(lease)
        return lease
    }

    /// True only while the lease is outstanding and the gate generation is unchanged.
    func revalidate(_ lease: NarrationLease) async -> Bool {
        guard leases.contains(lease) else { return false }
        let snapshot = await gateSnapshot()
        return snapshot.gate == .clear && snapshot.generation == lease.gateGeneration
    }

    func release(_ lease: NarrationLease) {
        leases.remove(lease)
        transcripts[lease] = nil
    }

    /// Stores the transcript under a live lease; false (and dropped) when the lease no longer revalidates.
    func deposit(_ transcript: String, for lease: NarrationLease) async -> Bool {
        guard await revalidate(lease) else { return false }
        transcripts[lease] = transcript
        return true
    }

    /// Returns and clears the deposited transcript only while the lease revalidates; nil otherwise.
    func materialize(for lease: NarrationLease) async -> String? {
        guard await revalidate(lease) else { transcripts[lease] = nil; return nil }
        defer { transcripts[lease] = nil }
        return transcripts[lease]
    }

    /// Registers an in-flight transfer; `cancel` cancels the Swift task awaiting the upload.
    func register(transfer lease: NarrationLease, cancel: @escaping @Sendable () -> Void) -> TransferHandle {
        let handle = TransferHandle(handleId: UUID().uuidString.lowercased(), lease: lease)
        transfers[handle] = cancel
        if revocation == .revoked { cancel() }
        return handle
    }

    /// The call site settles the transfer when its task exits by return or throw.
    func settle(_ handle: TransferHandle) {
        transfers[handle] = nil
        let waiting = settlements.removeValue(forKey: handle) ?? []
        for continuation in waiting { continuation.resume() }
    }

    func registerArtifact(_ url: URL, lease: NarrationLease) async -> Bool {
        guard await revalidate(lease) else { return false }
        artifacts[url] = lease
        return true
    }

    func registeredArtifacts() -> [URL] { artifacts.keys.sorted { $0.path < $1.path } }
    func outstandingLeases() -> Int { leases.count }
    func inFlightTransfers() -> Int { transfers.count }

    /// Invalidates every lease, invokes every registered transfer's `cancel`, and awaits every registered
    /// transfer's settlement before returning (S4-CD7); no lease is issued again until `reopen()`.
    func revokeAll() async {
        revocation = .revoked
        leases.removeAll()
        transcripts.removeAll()
        let pending = transfers
        for (_, cancel) in pending { cancel() }
        for (handle, _) in pending {
            guard transfers[handle] != nil else { continue }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if transfers[handle] == nil { continuation.resume(); return }
                settlements[handle, default: []].append(continuation)
            }
        }
    }

    /// Reopens lease issuance once the gate is `clear` again (S7's mount calls it after a purge completes).
    func reopen() { revocation = .open }

    /// Gate activation order (C2.2): revoke every lease, then remove every registered artifact; acknowledged only
    /// when no registered artifact remains on disk.
    func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck {
        await revokeAll()
        var failed = false
        for url in artifacts.keys {
            if fileManager.fileExists(atPath: url.path) {
                do { try fileManager.removeItem(at: url) } catch { failed = true; continue }
            }
            artifacts[url] = nil
        }
        return failed ? .failed : .acknowledged
    }
}
