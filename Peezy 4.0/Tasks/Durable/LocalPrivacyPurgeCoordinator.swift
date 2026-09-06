import FirebaseFirestore
import Foundation
import SwiftUI

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
        AnalyticsEvents.suspend() // no event or property leaves this process after the barrier begins (C2.2)
        return await run()
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

    /// The outstanding lease with this ID (the camera view hands the session manager only the lease ID).
    func lease(withId leaseId: String) -> NarrationLease? { leases.first { $0.leaseId == leaseId } }

    /// The deletion gate and generation the §8.9.3 admission at the inventory call sites reads (S4-CD6).
    func currentGate() async -> (gate: AccountDeletionGate, generation: GateGeneration) { await gateSnapshot() }

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

// MARK: - Durable file replacement, unlink, and observation (C9.7.5) for the S4-owned files (S1 owns `DurableFileReplacement`)

/// The C9.7.5 replacement and unlink sequences over one target: unique temp → complete write → file fsync →
/// atomic rename → directory fsync; unlink → directory fsync. Failures are the C9.7.2 storage codes.
enum PrivacyDurableFile {
    struct Failure: Error, Equatable { let code: StorageIOErrorCode }

    /// A file as read: complete bytes plus the device/inode identity the CAS compares, and the full fstat tuple the
    /// C9.7.12 `fileIdentityDigest` hashes for an over-cap file.
    struct Observation: Equatable, Sendable {
        let bytes: Data
        let device: UInt64
        let inode: UInt64
        let size: UInt64
        let mtimeSeconds: Int64
        let mtimeNanoseconds: Int64
        let ctimeSeconds: Int64
        let ctimeNanoseconds: Int64

        var fileIdentityDigest: String {
            FileObservationV1.fileIdentityDigest(device: device, inode: inode, size: size, mtimeSeconds: mtimeSeconds, mtimeNanoseconds: mtimeNanoseconds, ctimeSeconds: ctimeSeconds, ctimeNanoseconds: ctimeNanoseconds)
        }
    }

    /// Atomic rename (target → sibling) followed by the directory fsync (the C9.7.3 malformed-target quarantine step).
    static func rename(_ source: URL, to destination: URL) throws {
        guard Foundation.rename(source.path, destination.path) == 0 else { throw Failure(code: .fileRenameFailed) }
        try syncDirectory(destination.deletingLastPathComponent())
    }

    static func replace(at target: URL, bytes: Data) throws {
        let directory = target.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString.lowercased()).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else {
            throw Failure(code: .fileOpenFailed)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let descriptor = open(temporary.path, O_WRONLY)
        guard descriptor >= 0 else { throw Failure(code: .fileOpenFailed) }
        var written = 0
        let result: Bool = bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return bytes.isEmpty }
            while written < bytes.count {
                let count = Foundation.write(descriptor, base + written, bytes.count - written)
                if count <= 0 { return false }
                written += count
            }
            return true
        }
        guard result else { close(descriptor); throw Failure(code: .fileWriteFailed) }
        guard fsync(descriptor) == 0 else { close(descriptor); throw Failure(code: .fileFsyncFailed) }
        close(descriptor)
        guard Foundation.rename(temporary.path, target.path) == 0 else { throw Failure(code: .fileRenameFailed) }
        try syncDirectory(directory)
    }

    static func unlink(at target: URL) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            guard Foundation.unlink(target.path) == 0 else { throw Failure(code: .fileUnlinkFailed) }
        }
        try syncDirectory(target.deletingLastPathComponent())
    }

    /// Reads the complete bytes through a no-follow descriptor bounded by `limit + 1`; nil when absent.
    static func observe(at target: URL, limit: Int) throws -> Observation? {
        let descriptor = open(target.path, O_RDONLY | O_NOFOLLOW)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw Failure(code: .fileOpenFailed)
        }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw Failure(code: .fileReadFailed) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        guard let bytes = try? handle.read(upToCount: limit + 1) else { throw Failure(code: .fileReadFailed) }
        return Observation(bytes: bytes ?? Data(), device: UInt64(status.st_dev), inode: UInt64(status.st_ino), size: UInt64(max(status.st_size, 0)),
                           mtimeSeconds: Int64(status.st_mtimespec.tv_sec), mtimeNanoseconds: Int64(status.st_mtimespec.tv_nsec),
                           ctimeSeconds: Int64(status.st_ctimespec.tv_sec), ctimeNanoseconds: Int64(status.st_ctimespec.tv_nsec))
    }

    static func syncDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw Failure(code: .directoryFsyncFailed) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw Failure(code: .directoryFsyncFailed) }
    }
}

// MARK: - Completion presentation owner (C2.5)

/// The exact C2.5 surface copy, titles, buttons, and frozen provider URLs.
enum AccountDeletionCompletionCopy {
    static let title = "Account deleted"
    static let body = "Your Peezy account was deleted."
    static let button = "Done"
    static let appleManual = "Your Peezy account was deleted. To stop using Sign in with Apple for Peezy, open Settings, tap your name, tap Sign in with Apple, select Peezy, then tap Delete."
    static let appleInstructions = "Apple instructions"
    static let appleURL = URL(string: "https://support.apple.com/102571")!
    static let googleManual = "Your Peezy account was deleted. To stop using Sign in with Google for Peezy, open your Google Account's linked apps, select Peezy, and choose Stop using Sign in with Google."
    static let googleInstructions = "Google instructions"
    static let googleURL = URL(string: "https://support.google.com/accounts/answer/13533235?hl=en")!
    static let localCleared = "This account was deleted from another device. This device has been cleared."
    static let remoteUnconfirmedTitle = "Deletion not verified"
    static let remoteUnconfirmed = "Local data for this account was removed, but remote account deletion could not be verified. Sign in again to retry if the account still exists."
    static let queued = "Deletion is queued while Peezy finishes clearing protected copies. You can close the app and try again later."
    static let guardingTemplate = "Deletion is in progress. Protected copies clear by {date}."
    static let telemetryRelaunch = "Close and reopen Peezy to finish clearing local diagnostics."
}

extension CompletionResultV1 {
    /// The C2.5 presentation map that is also the completion file's `result`.
    var presentation: [String: Any] {
        switch self {
        case let .completed(apple, google):
            return ["schemaVersion": 1, "kind": "ACCOUNT_DELETION_COMPLETED", "appleRevocation": apple.rawValue, "googleRevocation": google.rawValue]
        case .localCleared:
            return ["schemaVersion": 1, "kind": "ACCOUNT_DELETION_LOCAL_CLEARED"]
        case .remoteUnconfirmed:
            return ["schemaVersion": 1, "kind": "ACCOUNT_DELETION_REMOTE_UNCONFIRMED"]
        }
    }

    static func decode(_ map: [String: Any]) -> CompletionResultV1? {
        guard TaskGenerationEpochStamp.safeInteger(map["schemaVersion"]) == 1, let kind = map["kind"] as? String else { return nil }
        switch kind {
        case "ACCOUNT_DELETION_COMPLETED":
            guard Set(map.keys) == ["schemaVersion", "kind", "appleRevocation", "googleRevocation"],
                  let apple = (map["appleRevocation"] as? String).flatMap(AppleRevocationDisposition.init(rawValue:)),
                  let google = (map["googleRevocation"] as? String).flatMap(GoogleCompletedRevocation.init(rawValue:)) else { return nil }
            return .completed(appleRevocation: apple, googleRevocation: google)
        case "ACCOUNT_DELETION_LOCAL_CLEARED":
            return Set(map.keys) == ["schemaVersion", "kind"] ? .localCleared : nil
        case "ACCOUNT_DELETION_REMOTE_UNCONFIRMED":
            return Set(map.keys) == ["schemaVersion", "kind"] ? .remoteUnconfirmed : nil
        default:
            return nil
        }
    }
}

enum CompletionObservation: Sendable, Equatable {
    case absent
    case present(CompletionSnapshotV1)
    case malformed
    case ioFailed(StorageIOErrorCode)
}

enum CompletionDeriveOutcome: Sendable, Equatable {
    case written(CompletionSnapshotV1)
    /// Exact replay: the pending file already carries this result; bytes preserved.
    case replayed(CompletionSnapshotV1)
    /// A different pending snapshot blocks; the source phase is retained.
    case blocked
    case failed(StorageIOErrorCode)
}

/// The completion-presentation owner (C2.5): sole reader/writer of `PeezyAccountDeletionCompletion-v1.json`.
/// `acknowledge` is the sole consuming action and runs the injected terminal consumption before unlinking;
/// `open` is offered only for the matching manual-required provider and its frozen URL and never consumes.
actor AccountDeletionCompletionPresentation: AccountDeletionCompletionPresenting {
    static let fileName = "PeezyAccountDeletionCompletion-v1.json"
    typealias Consume = @Sendable (CompletionSnapshotV1) async -> Bool
    typealias Opener = @Sendable (URL) async -> Bool

    private let directory: URL
    private let clock: any LocalDurableClock
    private let consume: Consume
    private let opener: Opener

    init(directory: URL, clock: any LocalDurableClock, consume: @escaping Consume, opener: @escaping Opener) {
        self.directory = directory
        self.clock = clock
        self.consume = consume
        self.opener = opener
    }

    private var target: URL { directory.appendingPathComponent(Self.fileName) }

    private func decode(_ bytes: Data) -> CompletionSnapshotV1? {
        guard let decoded = DurableEnvelopeCodec.decode(bytes, fileKind: .accountDeletionCompletionV1),
              Set(decoded.payload.keys) == ["schemaVersion", "result", "createdAt"],
              TaskGenerationEpochStamp.safeInteger(decoded.payload["schemaVersion"]) == 1,
              let resultMap = decoded.payload["result"] as? [String: Any], let result = CompletionResultV1.decode(resultMap),
              let createdAt = decoded.payload["createdAt"] as? String, CanonicalInstant.isCanonical(createdAt) else { return nil }
        return CompletionSnapshotV1(generationId: decoded.generationId, sha256: decoded.sha256, result: result, createdAt: createdAt)
    }

    func observe() -> CompletionObservation {
        do {
            guard let observation = try PrivacyDurableFile.observe(at: target, limit: DurableFileKind.accountDeletionCompletionV1.storeCap) else { return .absent }
            guard let snapshot = decode(observation.bytes) else { return .malformed }
            return .present(snapshot)
        } catch let failure as PrivacyDurableFile.Failure {
            return .ioFailed(failure.code)
        } catch {
            return .ioFailed(.fileReadFailed)
        }
    }

    /// Entry to a terminal derives the file before publication: exact replay preserves bytes; a different pending snapshot blocks.
    func derive(_ result: CompletionResultV1) -> CompletionDeriveOutcome {
        switch observe() {
        case let .present(existing):
            return existing.result == result ? .replayed(existing) : .blocked
        case .malformed:
            return .blocked
        case let .ioFailed(code):
            return .failed(code)
        case .absent:
            let instant = clock.now()
            let generation = UUID().uuidString.lowercased()
            let payload: [String: Any] = ["schemaVersion": 1, "result": result.presentation, "createdAt": instant]
            guard let bytes = DurableEnvelopeCodec.encode(fileKind: .accountDeletionCompletionV1, generationId: generation, payload: payload) else { return .failed(.fileWriteFailed) }
            do { try PrivacyDurableFile.replace(at: target, bytes: bytes) } catch let failure as PrivacyDurableFile.Failure { return .failed(failure.code) } catch { return .failed(.fileWriteFailed) }
            guard let written = decode(bytes) else { return .failed(.fileWriteFailed) }
            return .written(written)
        }
    }

    func current() async -> CompletionSnapshotV1? {
        if case let .present(snapshot) = observe() { return snapshot }
        return nil
    }

    /// Rereads complete bytes/device/inode and requires the expected generation and hash before consuming.
    private func matching(generationId: String, sha256: String) -> (snapshot: CompletionSnapshotV1, observation: PrivacyDurableFile.Observation)? {
        guard let observation = try? PrivacyDurableFile.observe(at: target, limit: DurableFileKind.accountDeletionCompletionV1.storeCap),
              let snapshot = decode(observation.bytes), snapshot.generationId == generationId, snapshot.sha256 == sha256 else { return nil }
        return (snapshot, observation)
    }

    func acknowledge(expectedGenerationId: String, expectedSHA256: String) async -> CompletionAcknowledgeResult {
        guard let match = matching(generationId: expectedGenerationId, sha256: expectedSHA256) else { return .stale }
        guard await consume(match.snapshot) else { return .failed }
        // The consumption may take time: the file must still be the same bytes/identity before the unlink.
        guard let again = matching(generationId: expectedGenerationId, sha256: expectedSHA256), again.observation == match.observation else { return .stale }
        do { try PrivacyDurableFile.unlink(at: target) } catch { return .failed }
        return .acknowledged
    }

    func open(expectedGenerationId: String, expectedSHA256: String, provider: CompletionProvider) async -> CompletionOpenResult {
        guard let match = matching(generationId: expectedGenerationId, sha256: expectedSHA256) else { return .stale }
        guard case let .completed(apple, google) = match.snapshot.result else { return .notOffered }
        let url: URL
        switch provider {
        case .apple:
            guard apple == .manualRequired else { return .notOffered }
            url = AccountDeletionCompletionCopy.appleURL
        case .google:
            guard google == .manualRequired else { return .notOffered }
            url = AccountDeletionCompletionCopy.googleURL
        }
        return await opener(url) ? .opened : .failed
    }
}

// MARK: - Preference barrier (C2.2; C6.6 eleven-key registry)

/// The eleven C6.6 UID-scoped key templates (`{uid}` interpolated) and the conditional global first name.
enum PreferenceBarrier {
    static let uidScopedTemplates: [String] = [
        "phase1.pendingRetakeOperation.{uid}",
        "peezy.{uid}.dailyDose.completedCount",
        "peezy.{uid}.dailyDose.lastDate",
        "peezy.{uid}.dailyDose.firstLaunchDate",
        "peezy.{uid}.dailyDose.v2",
        "peezy.{uid}.hasSeenFirstTimeWelcome",
        "peezy.{uid}.lastGreetingDate",
        "peezy.{uid}.totalCompletedCount",
        "inventory.scanCoaching.seen.{uid}",
        "inventory.narrationOffer.seen.{uid}",
        "peezy.{uid}.dailyDose.v2.quarantine",
    ]
    static let globalFirstNameKey = "peezy.user.firstName"

    static func keys(for uid: String) -> [String] { uidScopedTemplates.map { $0.replacingOccurrences(of: "{uid}", with: uid) } }

    /// Every stored key that matches a template for any UID (all-scope).
    static func uidScopedKeys(in defaults: UserDefaults) -> [String] {
        let patterns = uidScopedTemplates.map { "^" + NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: "\\{uid\\}", with: "[^.]+") + "$" }
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        return defaults.dictionaryRepresentation().keys.filter { key in
            let range = NSRange(key.startIndex..., in: key)
            return regexes.contains { $0.firstMatch(in: key, range: range) != nil }
        }.sorted()
    }

    /// Remove the keys, `synchronize()` success, reread absence (C2.2 L58). UID deletion removes the global first
    /// name only while Firebase still names that UID or no different current UID is established.
    static func run(scope: LocalPurgeScope, defaults: UserDefaults, currentFirebaseUID: String?) -> LocalPurgeAck {
        var removed: [String]
        switch scope {
        case let .uid(uid):
            removed = keys(for: uid)
            if currentFirebaseUID == nil || currentFirebaseUID == uid { removed.append(globalFirstNameKey) }
        case .all:
            removed = uidScopedKeys(in: defaults) + [globalFirstNameKey]
        }
        for key in removed { defaults.removeObject(forKey: key) }
        guard defaults.synchronize() else { return .failed }
        return removed.allSatisfy { defaults.object(forKey: $0) == nil } ? .acknowledged : .failed
    }
}

// MARK: - Local privacy purge journal (C3)

/// `{deletionOperationId,deletionProofSHA256,googleRevocation,googleProviderUid?}`; required iff UID scope and must match the intent.
struct PurgeProviderContextV1: Sendable, Equatable {
    let deletionOperationId: String
    let deletionProofSHA256: String
    let googleRevocation: GoogleRevocationDisposition
    let googleProviderUid: String?

    var canonical: [String: Any] {
        var map: [String: Any] = ["deletionOperationId": deletionOperationId, "deletionProofSHA256": deletionProofSHA256, "googleRevocation": googleRevocation.rawValue]
        if let googleProviderUid { map["googleProviderUid"] = googleProviderUid }
        return map
    }

    static func decode(_ map: [String: Any]) -> PurgeProviderContextV1? {
        let keys = Set(map.keys)
        guard keys == ["deletionOperationId", "deletionProofSHA256", "googleRevocation"] || keys == ["deletionOperationId", "deletionProofSHA256", "googleRevocation", "googleProviderUid"],
              let operation = map["deletionOperationId"] as? String, operation.range(of: #"^adel1_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: .regularExpression) != nil,
              let proof = map["deletionProofSHA256"] as? String, proof.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              let google = (map["googleRevocation"] as? String).flatMap(GoogleRevocationDisposition.init(rawValue:)) else { return nil }
        let providerUid = map["googleProviderUid"] as? String
        if keys.contains("googleProviderUid") && (providerUid ?? "").isEmpty { return nil }
        if google == .sdkDisconnectRequired && providerUid == nil { return nil }
        return PurgeProviderContextV1(deletionOperationId: operation, deletionProofSHA256: proof, googleRevocation: google, googleProviderUid: providerUid)
    }
}

/// `{deletionOperationId,deletionProofSHA256}`; only for the terminal all-scope handoff.
struct TerminalDeletionLinkV1: Sendable, Equatable {
    let deletionOperationId: String
    let deletionProofSHA256: String
    var canonical: [String: Any] { ["deletionOperationId": deletionOperationId, "deletionProofSHA256": deletionProofSHA256] }
    static func decode(_ map: [String: Any]) -> TerminalDeletionLinkV1? {
        guard Set(map.keys) == ["deletionOperationId", "deletionProofSHA256"], let operation = map["deletionOperationId"] as? String, let proof = map["deletionProofSHA256"] as? String,
              operation.range(of: #"^adel1_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: .regularExpression) != nil,
              proof.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else { return nil }
        return TerminalDeletionLinkV1(deletionOperationId: operation, deletionProofSHA256: proof)
    }
}

/// The eight purge owners in the exact C2.2 order; `acks` is a displayed-order prefix of this list.
enum PurgeOwner: String, CaseIterable, Sendable {
    case route, handoff, reset, workflow, roomCapture = "room_capture", firestoreCache = "firestore_cache", notifications, google
    static let order: [PurgeOwner] = allCases
}

/// `PeezyLocalPrivacyPurge-v1.json` payload (C3): `{schemaVersion:1,scope,providerContext?,terminalDeletionLink?,acks,createdAt,updatedAt}`.
struct LocalPrivacyPurgeJournalV1: Sendable, Equatable {
    let scope: LocalPurgeScope
    let providerContext: PurgeProviderContextV1?
    let terminalDeletionLink: TerminalDeletionLinkV1?
    let acks: [PurgeOwner]
    let createdAt: String
    let updatedAt: String

    /// `providerContext` required iff UID scope; `terminalDeletionLink` only for all-scope; acks an exact prefix.
    var isValid: Bool {
        switch scope {
        case .uid: if providerContext == nil || terminalDeletionLink != nil { return false }
        case .all: if providerContext != nil { return false }
        }
        return Array(PurgeOwner.order.prefix(acks.count)) == acks && CanonicalInstant.isCanonical(createdAt) && CanonicalInstant.isCanonical(updatedAt)
    }

    var canonical: [String: Any] {
        var map: [String: Any] = ["schemaVersion": 1, "acks": acks.map(\.rawValue), "createdAt": createdAt, "updatedAt": updatedAt]
        switch scope {
        case .all: map["scope"] = ["kind": "all"]
        case let .uid(uid): map["scope"] = ["kind": "uid", "uid": uid]
        }
        if let providerContext { map["providerContext"] = providerContext.canonical }
        if let terminalDeletionLink { map["terminalDeletionLink"] = terminalDeletionLink.canonical }
        return map
    }

    static func decode(_ map: [String: Any]) -> LocalPrivacyPurgeJournalV1? {
        let keys = Set(map.keys)
        let allowed: Set<String> = ["schemaVersion", "scope", "providerContext", "terminalDeletionLink", "acks", "createdAt", "updatedAt"]
        guard keys.isSubset(of: allowed), keys.isSuperset(of: ["schemaVersion", "scope", "acks", "createdAt", "updatedAt"]),
              TaskGenerationEpochStamp.safeInteger(map["schemaVersion"]) == 1,
              let scopeMap = map["scope"] as? [String: Any], let kind = scopeMap["kind"] as? String,
              let ackNames = map["acks"] as? [String], let createdAt = map["createdAt"] as? String, let updatedAt = map["updatedAt"] as? String else { return nil }
        let scope: LocalPurgeScope
        switch kind {
        case "all": guard Set(scopeMap.keys) == ["kind"] else { return nil }; scope = .all
        case "uid": guard Set(scopeMap.keys) == ["kind", "uid"], let uid = scopeMap["uid"] as? String, !uid.isEmpty else { return nil }; scope = .uid(uid)
        default: return nil
        }
        let acks = ackNames.compactMap(PurgeOwner.init(rawValue:))
        guard acks.count == ackNames.count else { return nil }
        var providerContext: PurgeProviderContextV1?
        if keys.contains("providerContext") { guard let raw = map["providerContext"] as? [String: Any], let decoded = PurgeProviderContextV1.decode(raw) else { return nil }; providerContext = decoded }
        var link: TerminalDeletionLinkV1?
        if keys.contains("terminalDeletionLink") { guard let raw = map["terminalDeletionLink"] as? [String: Any], let decoded = TerminalDeletionLinkV1.decode(raw) else { return nil }; link = decoded }
        let journal = LocalPrivacyPurgeJournalV1(scope: scope, providerContext: providerContext, terminalDeletionLink: link, acks: acks, createdAt: createdAt, updatedAt: updatedAt)
        return journal.isValid ? journal : nil
    }
}

enum JournalObservation: Sendable, Equatable {
    case absent
    case present(LocalPrivacyPurgeJournalV1)
    case malformed
    case ioFailed(StorageIOErrorCode)
}

/// The eight purge seams the coordinator drives, in the C2.2 order; each is injected (S5/S7 conformers, S4's own two).
struct LocalPurgeOwners: Sendable {
    let route: any RouteAccountDeletionPurging
    let handoff: any HandoffAccountDeletionPurging
    let reset: any ResetAccountDeletionPurging
    let workflow: any WorkflowAccountDeletionPurging
    let roomCapture: any RoomCaptureArtifactPurging
    let firestoreCache: any FirestoreLocalCachePurging
    let notifications: any NotificationIdentityPurging
    let google: any GoogleIdentityControlling

    init(route: any RouteAccountDeletionPurging, handoff: any HandoffAccountDeletionPurging, reset: any ResetAccountDeletionPurging, workflow: any WorkflowAccountDeletionPurging, roomCapture: any RoomCaptureArtifactPurging, firestoreCache: any FirestoreLocalCachePurging, notifications: any NotificationIdentityPurging, google: any GoogleIdentityControlling) {
        self.route = route; self.handoff = handoff; self.reset = reset; self.workflow = workflow
        self.roomCapture = roomCapture; self.firestoreCache = firestoreCache; self.notifications = notifications; self.google = google
    }
}

/// The local privacy purge (C2.2 L55–58; C3 journal): the eight owners in order with each ack journaled, then the
/// preference and telemetry barriers. An intent-linked UID purge has absolute priority; an all-scope or other request
/// waits and reclassifies after all eight owners and both barriers.
actor LocalPrivacyPurgeCoordinator: LocalPrivacyPurgeCoordinating {
    static let journalFileName = "PeezyLocalPrivacyPurge-v1.json"

    struct Request: Sendable, Equatable {
        let scope: LocalPurgeScope
        let providerContext: PurgeProviderContextV1?
        let terminalDeletionLink: TerminalDeletionLinkV1?
        /// A UID purge linked to the durable intent: absolute priority (C2.2 singleflight).
        var isIntentLinked: Bool { if case .uid = scope { return providerContext != nil }; return false }
    }

    private let directory: URL
    private let clock: any LocalDurableClock
    private let owners: LocalPurgeOwners
    private let defaults: UserDefaults
    private let currentUID: any CurrentFirebaseUIDProviding
    private let telemetry: any ClientTelemetryPrivacyPurging
    private var running = false
    private var waiters: [(intentLinked: Bool, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var log: [String] = []

    init(directory: URL, clock: any LocalDurableClock, owners: LocalPurgeOwners, defaults: UserDefaults, currentUID: any CurrentFirebaseUIDProviding, telemetry: any ClientTelemetryPrivacyPurging) {
        self.directory = directory
        self.clock = clock
        self.owners = owners
        self.defaults = defaults
        self.currentUID = currentUID
        self.telemetry = telemetry
    }

    private var journalURL: URL { directory.appendingPathComponent(Self.journalFileName) }

    // MARK: journal

    func observeJournal() -> JournalObservation {
        do {
            guard let observation = try PrivacyDurableFile.observe(at: journalURL, limit: DurableFileKind.localPrivacyPurgeV1.storeCap) else { return .absent }
            guard let decoded = DurableEnvelopeCodec.decode(observation.bytes, fileKind: .localPrivacyPurgeV1), let journal = LocalPrivacyPurgeJournalV1.decode(decoded.payload) else { return .malformed }
            return .present(journal)
        } catch let failure as PrivacyDurableFile.Failure { return .ioFailed(failure.code) } catch { return .ioFailed(.fileReadFailed) }
    }

    private func writeJournal(_ journal: LocalPrivacyPurgeJournalV1) -> Bool {
        guard journal.isValid, let bytes = DurableEnvelopeCodec.encode(fileKind: .localPrivacyPurgeV1, generationId: UUID().uuidString.lowercased(), payload: journal.canonical) else { return false }
        return (try? PrivacyDurableFile.replace(at: journalURL, bytes: bytes)) != nil
    }

    /// Unlinks the journal (the caller decides when a UID journal's lifecycle ends; all-scope purges unlink their own).
    func unlinkJournal() -> Bool { (try? PrivacyDurableFile.unlink(at: journalURL)) != nil }

    // MARK: singleflight

    private func acquireSlot(intentLinked: Bool) async {
        guard running else { running = true; return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append((intentLinked, continuation))
        }
    }

    private func releaseSlot() {
        if let index = waiters.firstIndex(where: { $0.intentLinked }) ?? (waiters.isEmpty ? nil : 0) {
            let next = waiters.remove(at: index)
            next.continuation.resume() // stays `running`
        } else {
            running = false
        }
    }

    // MARK: purge

    func purge(scope: LocalPurgeScope) async -> LocalPrivacyPurgeResult {
        await purge(Request(scope: scope, providerContext: nil, terminalDeletionLink: nil))
    }

    /// Every owner ack is journaled, then offered to `onAck` (the deletion coordinator mirrors it into the intent, C2.2);
    /// a `false` return stops the purge as `FILE_IO` with the journal retained. All-scope acks are never offered.
    typealias AckMirror = @Sendable (PurgeOwner) async -> Bool

    func purge(_ request: Request, onAck: AckMirror? = nil) async -> LocalPrivacyPurgeResult {
        if case .uid = request.scope, request.providerContext == nil { return .blocked(.localPrivacyPurgeFailed) }
        if case .uid = request.scope, request.terminalDeletionLink != nil { return .blocked(.localPrivacyPurgeFailed) }
        await acquireSlot(intentLinked: request.isIntentLinked)
        defer { releaseSlot() }
        return await runPurge(request, onAck: onAck)
    }

    private func runPurge(_ request: Request, onAck: AckMirror? = nil) async -> LocalPrivacyPurgeResult {
        // resume a matching journal; a different journal is finished first (its scope), then this request starts fresh
        var journal: LocalPrivacyPurgeJournalV1
        switch observeJournal() {
        case let .ioFailed(code):
            log.append("journal:\(code.rawValue)")
            return .blocked(.fileIO)
        case .malformed:
            return .blocked(.localPrivacyPurgeFailed)
        case let .present(existing) where existing.scope == request.scope && existing.providerContext == request.providerContext && existing.terminalDeletionLink == request.terminalDeletionLink:
            journal = existing
        case let .present(existing):
            let finished = await runPurge(Request(scope: existing.scope, providerContext: existing.providerContext, terminalDeletionLink: existing.terminalDeletionLink))
            guard finished == .cleared, unlinkJournal() else { return finished == .cleared ? .blocked(.fileIO) : finished }
            fallthrough
        case .absent:
            let now = clock.now()
            journal = LocalPrivacyPurgeJournalV1(scope: request.scope, providerContext: request.providerContext, terminalDeletionLink: request.terminalDeletionLink, acks: [], createdAt: now, updatedAt: now)
            guard writeJournal(journal) else { return .blocked(.fileIO) }
        }
        for owner in PurgeOwner.order.dropFirst(journal.acks.count) {
            let ack = await run(owner, scope: request.scope, providerContext: request.providerContext)
            log.append("\(owner.rawValue):\(ack.rawValue)")
            guard ack == .acknowledged else { return .blocked(.localPrivacyPurgeFailed) }
            let now = clock.now()
            journal = LocalPrivacyPurgeJournalV1(scope: journal.scope, providerContext: journal.providerContext, terminalDeletionLink: journal.terminalDeletionLink, acks: journal.acks + [owner], createdAt: journal.createdAt, updatedAt: now)
            guard writeJournal(journal) else { return .blocked(.fileIO) }
            if let onAck, case .uid = request.scope, await onAck(owner) == false { return .blocked(.fileIO) }
        }
        // a resumed journal already past some owners re-offers them so the intent's prefix catches up
        if let onAck, case .uid = request.scope {
            for owner in journal.acks where await onAck(owner) == false { return .blocked(.fileIO) }
        }
        let preferences = PreferenceBarrier.run(scope: request.scope, defaults: defaults, currentFirebaseUID: currentUID.currentFirebaseUID())
        log.append("preferences:\(preferences.rawValue)")
        guard preferences == .acknowledged else { return .blocked(.localPrivacyPurgeFailed) }
        let telemetry = await telemetry.purgeAll()
        log.append("telemetry:\(telemetry.rawValue)")
        guard telemetry == .cleared else { return .blocked(.localPrivacyPurgeFailed) }
        if case .all = request.scope, request.terminalDeletionLink == nil { _ = unlinkJournal() }
        return .cleared
    }

    private func run(_ owner: PurgeOwner, scope: LocalPurgeScope, providerContext: PurgeProviderContextV1?) async -> LocalPurgeAck {
        switch owner {
        case .route: return await owners.route.purgeForAccountDeletion(scope: scope)
        case .handoff: return await owners.handoff.purgeForAccountDeletion(scope: scope)
        case .reset: return await owners.reset.purgeForAccountDeletion(scope: scope)
        case .workflow: return await owners.workflow.purgeForAccountDeletion(scope: scope)
        case .roomCapture: return await owners.roomCapture.purgeForAccountDeletion(scope: scope)
        case .firestoreCache: return await owners.firestoreCache.purgeForAccountDeletion(scope: scope)
        case .notifications: return await owners.notifications.purgeForAccountDeletion(scope: scope)
        case .google:
            switch scope {
            case .all:
                return await owners.google.signOutAll() == .signedOut ? .acknowledged : .failed
            case .uid:
                guard let context = providerContext else { return .failed }
                switch context.googleRevocation {
                case .sdkDisconnectRequired:
                    guard let providerUid = context.googleProviderUid else { return .failed }
                    return await owners.google.disconnect(expectedProviderUID: providerUid) == .disconnected ? .acknowledged : .failed
                case .manualRequired, .notRequired:
                    return .acknowledged // no SDK mutation
                }
            }
        }
    }
}

// MARK: - The room-capture owner in the SwiftUI environment (S7 injects the one production owner; nil until then)

private struct RoomCaptureArtifactOwnerKey: EnvironmentKey {
    static let defaultValue: RoomCaptureArtifactOwner? = nil
}

extension EnvironmentValues {
    /// The sole `RoomCaptureArtifactOwner`; the camera view acquires narration leases from it. Nil (unmounted) means
    /// no lease can be issued, so no narration is captured.
    var roomCaptureArtifactOwner: RoomCaptureArtifactOwner? {
        get { self[RoomCaptureArtifactOwnerKey.self] }
        set { self[RoomCaptureArtifactOwnerKey.self] = newValue }
    }
}
