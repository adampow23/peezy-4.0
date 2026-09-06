import Foundation
import CoreFoundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// Thin client for the single server-owned Phase-1 lifecycle surface.
struct TaskPlanService {
    typealias Callable = (_ name: String, _ payload: [String: Any]) async throws -> [String: Any]

    struct Subject {
        let kind: String
        let id: String
    }

    struct Trigger {
        let kind: String
        var at: Date? = nil
        var eventName: String? = nil
        var canonicalKey: String? = nil
        var afterSourceVersion: Int? = nil
        var payload: [String: Any]? = nil

        func dictionary() -> [String: Any] {
            var result: [String: Any] = ["kind": kind]
            if let at { result["at"] = ISO8601DateFormatter().string(from: at) }
            if let eventName { result["event_name"] = eventName }
            if let canonicalKey { result["canonical_key"] = canonicalKey }
            if let afterSourceVersion { result["after_source_version"] = afterSourceVersion }
            if let payload { result["payload"] = payload }
            return result
        }
    }

    struct ActionDescriptor {
        let nextTrigger: Trigger
        let resumeDestination: String

        func dictionary() -> [String: Any] {
            ["nextTrigger": nextTrigger.dictionary(), "resumeDestination": resumeDestination]
        }
    }

    struct Replacement {
        let taskId: String
        let subject: Subject
        let institutionId: String
        let institution: String
        let amendmentAction: ActionDescriptor
        let verification: ActionDescriptor

        func dictionary() -> [String: Any] {
            [
                "taskId": taskId,
                "subject": ["kind": subject.kind, "id": subject.id],
                "institutionId": institutionId,
                "institution": institution,
                "amendmentAction": amendmentAction.dictionary(),
                "verification": verification.dictionary()
            ]
        }
    }

    enum LifecycleState: String {
        case retired
        case pendingAmendment = "pending_amendment"
        case pendingConfirmation = "pending_confirmation"
        case confirmed
        case reopened
    }

    struct Response {
        let taskId: String
        let status: String
        let replacementTaskId: String?
        let lifecycleState: LifecycleState
        let revision: Int
        let replayed: Bool
    }

    struct ResetResponse {
        let deletedCount: Int
        let replayed: Bool
    }

    enum Error: Swift.Error, Equatable { case invalidResponse }

    private static let allowedTaskStatuses: Set<String> = [
        TaskStatus.upcoming.rawValue,
        TaskStatus.inProgress.rawValue,
        TaskStatus.pending.rawValue,
        TaskStatus.matchingInProgress.rawValue,
        TaskStatus.userInProgress.rawValue,
        TaskStatus.completed.rawValue,
        TaskStatus.snoozed.rawValue,
        TaskStatus.skipped.rawValue,
        TaskStatus.dismissed.rawValue,
        TaskStatus.converted.rawValue
    ]

    private let callable: Callable

    init(callable: @escaping Callable = TaskPlanService.productionCallable) {
        self.callable = callable
    }

    func supersedeTask(
        taskId: String,
        reason: String,
        operationId: String,
        replacement: Replacement? = nil
    ) async throws -> Response {
        var payload = base(action: "supersede", taskId: taskId, reason: reason, operationId: operationId)
        if let replacement { payload["replacement"] = replacement.dictionary() }
        return try decodeResponse(try await invoke(payload))
    }

    func confirmAmendment(taskId: String, reason: String, operationId: String) async throws -> Response {
        try decodeResponse(try await invoke(base(action: "confirmAmendment", taskId: taskId, reason: reason, operationId: operationId)))
    }

    func undoConfirmation(taskId: String, reason: String, operationId: String) async throws -> Response {
        try decodeResponse(try await invoke(base(action: "undoConfirmation", taskId: taskId, reason: reason, operationId: operationId)))
    }

    func reopenTask(taskId: String, reason: String, operationId: String) async throws -> Response {
        try decodeResponse(try await invoke(base(action: "reopen", taskId: taskId, reason: reason, operationId: operationId)))
    }

    func resetAllTasks(reason: String = "retake_assessment", operationId: String) async throws -> ResetResponse {
        try decodeReset(try await invoke([
            "action": "resetAllTasks", "reason": reason, "operationId": operationId
        ]))
    }

    func finalizeTaskReset(reason: String = "retake_assessment", operationId: String) async throws -> ResetResponse {
        try decodeReset(try await invoke([
            "action": "finalizeTaskReset", "reason": reason, "operationId": operationId
        ]))
    }

    private func base(action: String, taskId: String, reason: String, operationId: String) -> [String: Any] {
        ["action": action, "taskId": taskId, "reason": reason, "operationId": operationId]
    }

    private func invoke(_ payload: [String: Any]) async throws -> [String: Any] {
        try await callable("changeTaskPlan", payload)
    }

    private func decodeResponse(_ data: [String: Any]) throws -> Response {
        guard let taskId = data["taskId"] as? String,
              !taskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let status = data["status"] as? String,
              Self.allowedTaskStatuses.contains(status),
              data.keys.contains("replacementTaskId"),
              let stateRaw = data["lifecycleState"] as? String,
              let state = LifecycleState(rawValue: stateRaw),
              let revision = strictInteger(data["revision"], minimum: 1),
              let replayed = data["replayed"] as? Bool else { throw Error.invalidResponse }
        let replacement: String?
        if data["replacementTaskId"] is NSNull {
            replacement = nil
        } else if let value = data["replacementTaskId"] as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            replacement = value
        } else {
            throw Error.invalidResponse
        }
        return Response(
            taskId: taskId, status: status, replacementTaskId: replacement,
            lifecycleState: state, revision: revision, replayed: replayed
        )
    }

    private func decodeReset(_ data: [String: Any]) throws -> ResetResponse {
        guard data["reset"] as? Bool == true,
              let count = strictInteger(data["deletedCount"], minimum: 0),
              let replayed = data["replayed"] as? Bool else { throw Error.invalidResponse }
        return ResetResponse(deletedCount: count, replayed: replayed)
    }

    /// Firebase callable JSON numbers bridge through NSNumber. Reject booleans,
    /// fractional values, and values outside the exact nonnegative Int schema.
    private func strictInteger(_ value: Any?, minimum: Int) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite,
              double.rounded(.towardZero) == double,
              double >= Double(minimum),
              double < Double(Int.max) else { return nil }
        return Int(double)
    }

    private static func productionCallable(_ name: String, _ payload: [String: Any]) async throws -> [String: Any] {
        let result = try await Functions.functions().httpsCallable(name).call(payload)
        guard let data = result.data as? [String: Any] else { throw Error.invalidResponse }
        return data
    }
}

// MARK: - Account-deletion DTO/transport (S1; C2.3, manifest v9:1435, v7:1307)

/// Closed request union; every case carries the durable-intent UID.
enum AccountDeletionRequestV1: Sendable, Equatable {
    case discover(uid: String, operationId: String, proofNonce: String)
    case begin(uid: String, operationId: String, proofNonce: String)
    case resume(uid: String, operationId: String, proofNonce: String)
    case finalize(uid: String, operationId: String, proofNonce: String)

    var action: String {
        switch self {
        case .discover: return "discover"
        case .begin: return "begin"
        case .resume: return "resume"
        case .finalize: return "finalize"
        }
    }

    private var members: (uid: String, operationId: String, proofNonce: String) {
        switch self {
        case let .discover(uid, operationId, proofNonce),
             let .begin(uid, operationId, proofNonce),
             let .resume(uid, operationId, proofNonce),
             let .finalize(uid, operationId, proofNonce):
            return (uid, operationId, proofNonce)
        }
    }

    /// Exact `{schemaVersion:1,action,uid,operationId,proofNonce}`.
    func payload() -> [String: Any] {
        let m = members
        return ["schemaVersion": 1, "action": action, "uid": m.uid, "operationId": m.operationId, "proofNonce": m.proofNonce]
    }
}

enum AccountDeletionAuthorityKind: String, Sendable, Equatable {
    case member
    case authenticatedOverflow
}

/// `{schemaVersion:1,kind:"account_deletion_data_final",operationId,authorityKind,startedAt,dataDeletedAt,replayed}`
struct AccountDeletionDataFinalWireV1: Sendable, Equatable {
    let operationId: String
    let authorityKind: AccountDeletionAuthorityKind
    let startedAt: String
    let dataDeletedAt: String
    let replayed: Bool
}

/// `{schemaVersion:1,kind:"account_deletion_auth_guarding",operationId,authorityKind,startedAt,dataDeletedAt,authAbsenceObservedAt,authGuardAfter,replayed}`
struct AccountDeletionAuthGuardingWireV1: Sendable, Equatable {
    let operationId: String
    let authorityKind: AccountDeletionAuthorityKind
    let startedAt: String
    let dataDeletedAt: String
    let authAbsenceObservedAt: String
    let authGuardAfter: String
    let replayed: Bool
}

/// `{schemaVersion:1,kind:"account_deletion_account_deleted",operationId,authorityKind,startedAt,dataDeletedAt,authAbsenceObservedAt,authGuardAfter,authGuardCompletedAt,accountDeletedAt,replayed}`
struct AccountDeletionAccountDeletedWireV1: Sendable, Equatable {
    let operationId: String
    let authorityKind: AccountDeletionAuthorityKind
    let startedAt: String
    let dataDeletedAt: String
    let authAbsenceObservedAt: String
    let authGuardAfter: String
    let authGuardCompletedAt: String
    let accountDeletedAt: String
    let replayed: Bool
}

enum AccountDeletionRemoteResultV1: Sendable, Equatable {
    /// `{schemaVersion:1,kind:"account_deletion_discovery",state:"absent",operationId}`
    case absent(operationId: String)
    case dataFinal(AccountDeletionDataFinalWireV1)
    case authGuarding(AccountDeletionAuthGuardingWireV1)
    case accountDeleted(AccountDeletionAccountDeletedWireV1)
}

/// Thrown union (C2.3). `transport` covers transport and unknown-code failures,
/// the only retryable class; any unknown detail or member is `protocolAmbiguity`
/// and retains durable bytes.
enum AccountDeletionRemoteError: Error, Equatable {
    case requestInvalid(field: String)
    case authRequired
    case capabilityInvalid
    case retryRequired
    case transport
    case protocolAmbiguity
}

extension TaskPlanService {
    /// Typed transport over the `deleteAccount` callable.
    struct AccountDeletionTransport: AccountDeletionRemoteProviding, @unchecked Sendable {
        static let callableName = "deleteAccount"
        private static let timePattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$"#

        private let callable: Callable

        init(callable: @escaping Callable = TaskPlanService.productionCallable) {
            self.callable = callable
        }

        func perform(_ request: AccountDeletionRequestV1) async throws -> AccountDeletionRemoteResultV1 {
            let data: [String: Any]
            do {
                data = try await callable(Self.callableName, request.payload())
            } catch {
                throw Self.mapError(error)
            }
            return try Self.decode(data)
        }

        /// Exact-member decode of the four wires; anything else is protocol ambiguity.
        static func decode(_ data: [String: Any]) throws -> AccountDeletionRemoteResultV1 {
            guard TaskGenerationEpochStamp.safeInteger(data["schemaVersion"]) == 1,
                  let kind = data["kind"] as? String else { throw AccountDeletionRemoteError.protocolAmbiguity }
            switch kind {
            case "account_deletion_discovery":
                try exactKeys(data, ["schemaVersion", "kind", "state", "operationId"])
                guard data["state"] as? String == "absent" else { throw AccountDeletionRemoteError.protocolAmbiguity }
                return .absent(operationId: try string(data, "operationId"))
            case "account_deletion_data_final":
                try exactKeys(data, ["schemaVersion", "kind", "operationId", "authorityKind", "startedAt", "dataDeletedAt", "replayed"])
                return .dataFinal(AccountDeletionDataFinalWireV1(
                    operationId: try string(data, "operationId"), authorityKind: try authority(data),
                    startedAt: try time(data, "startedAt"), dataDeletedAt: try time(data, "dataDeletedAt"),
                    replayed: try bool(data, "replayed")
                ))
            case "account_deletion_auth_guarding":
                try exactKeys(data, ["schemaVersion", "kind", "operationId", "authorityKind", "startedAt", "dataDeletedAt", "authAbsenceObservedAt", "authGuardAfter", "replayed"])
                return .authGuarding(AccountDeletionAuthGuardingWireV1(
                    operationId: try string(data, "operationId"), authorityKind: try authority(data),
                    startedAt: try time(data, "startedAt"), dataDeletedAt: try time(data, "dataDeletedAt"),
                    authAbsenceObservedAt: try time(data, "authAbsenceObservedAt"), authGuardAfter: try time(data, "authGuardAfter"),
                    replayed: try bool(data, "replayed")
                ))
            case "account_deletion_account_deleted":
                try exactKeys(data, ["schemaVersion", "kind", "operationId", "authorityKind", "startedAt", "dataDeletedAt", "authAbsenceObservedAt", "authGuardAfter", "authGuardCompletedAt", "accountDeletedAt", "replayed"])
                return .accountDeleted(AccountDeletionAccountDeletedWireV1(
                    operationId: try string(data, "operationId"), authorityKind: try authority(data),
                    startedAt: try time(data, "startedAt"), dataDeletedAt: try time(data, "dataDeletedAt"),
                    authAbsenceObservedAt: try time(data, "authAbsenceObservedAt"), authGuardAfter: try time(data, "authGuardAfter"),
                    authGuardCompletedAt: try time(data, "authGuardCompletedAt"), accountDeletedAt: try time(data, "accountDeletedAt"),
                    replayed: try bool(data, "replayed")
                ))
            default:
                throw AccountDeletionRemoteError.protocolAmbiguity
            }
        }

        /// Maps a thrown callable error: exact `details` reasons to the typed
        /// union, absent details to `transport`, anything else to ambiguity.
        static func mapError(_ error: Swift.Error) -> AccountDeletionRemoteError {
            let nsError = error as NSError
            guard let details = nsError.userInfo["details"] as? [String: Any] else { return .transport }
            guard TaskGenerationEpochStamp.safeInteger(details["schemaVersion"]) == 1,
                  let reason = details["reason"] as? String else { return .protocolAmbiguity }
            switch (reason, details.count) {
            case ("REQUEST_INVALID", 3):
                guard let field = details["field"] as? String, !field.isEmpty else { return .protocolAmbiguity }
                return .requestInvalid(field: field)
            case ("AUTH_REQUIRED", 2): return .authRequired
            case ("DELETION_CAPABILITY_INVALID", 2): return .capabilityInvalid
            case ("DELETION_RETRY_REQUIRED", 2): return .retryRequired
            default: return .protocolAmbiguity
            }
        }

        private static func exactKeys(_ data: [String: Any], _ keys: [String]) throws {
            guard Set(data.keys) == Set(keys) else { throw AccountDeletionRemoteError.protocolAmbiguity }
        }

        private static func string(_ data: [String: Any], _ key: String) throws -> String {
            guard let value = data[key] as? String, !value.isEmpty else { throw AccountDeletionRemoteError.protocolAmbiguity }
            return value
        }

        /// Canonical UTC RFC 3339 millisecond instant, copied byte-for-byte.
        private static func time(_ data: [String: Any], _ key: String) throws -> String {
            let value = try string(data, key)
            guard value.range(of: timePattern, options: .regularExpression) != nil else { throw AccountDeletionRemoteError.protocolAmbiguity }
            return value
        }

        private static func bool(_ data: [String: Any], _ key: String) throws -> Bool {
            guard let number = data[key] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw AccountDeletionRemoteError.protocolAmbiguity
            }
            return number.boolValue
        }

        private static func authority(_ data: [String: Any]) throws -> AccountDeletionAuthorityKind {
            guard let raw = data["authorityKind"] as? String, let kind = AccountDeletionAuthorityKind(rawValue: raw) else {
                throw AccountDeletionRemoteError.protocolAmbiguity
            }
            return kind
        }
    }
}

// MARK: - Atomic durable-file replacement (§7; spec v5:760)

enum DurableFileReplacement {
    struct Failure: Error, Equatable {
        let code: StorageIOErrorCode
    }

    /// unique-temp → complete write → file fsync → atomic rename → directory fsync,
    /// with `.completeUntilFirstUserAuthentication` protection on the new file.
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
        guard rename(temporary.path, target.path) == 0 else { throw Failure(code: .fileRenameFailed) }
        let directoryDescriptor = open(directory.path, O_RDONLY)
        guard directoryDescriptor >= 0 else { throw Failure(code: .directoryFsyncFailed) }
        defer { close(directoryDescriptor) }
        guard fsync(directoryDescriptor) == 0 else { throw Failure(code: .directoryFsyncFailed) }
    }
}

// MARK: - Reset registry vocabulary (§5; spec v5:1075)

enum ResetGesturePhase: String, Sendable, Equatable {
    case reserved, bound
}

/// `{gestureId,uid,authEpochUUID,credentialRevision,phase,alias,expectedEpoch?,gestureGeneration,reservedAt,boundAt?}`
struct ResetGestureV1: Sendable, Equatable {
    let gestureId: String
    let uid: String
    let authEpochUUID: String
    var credentialRevision: Int
    var phase: ResetGesturePhase
    let alias: String
    var expectedEpoch: Int?
    let gestureGeneration: String
    let reservedAt: String
    var boundAt: String?

    func map() -> [String: Any] {
        var map: [String: Any] = [
            "gestureId": gestureId, "uid": uid, "authEpochUUID": authEpochUUID, "credentialRevision": credentialRevision,
            "phase": phase.rawValue, "alias": alias, "gestureGeneration": gestureGeneration, "reservedAt": reservedAt
        ]
        if let expectedEpoch { map["expectedEpoch"] = expectedEpoch }
        if let boundAt { map["boundAt"] = boundAt }
        return map
    }

    static func from(_ map: [String: Any]) -> ResetGestureV1? {
        var keys = Set(map.keys)
        let required: Set<String> = ["gestureId", "uid", "authEpochUUID", "credentialRevision", "phase", "alias", "gestureGeneration", "reservedAt"]
        guard required.isSubset(of: keys) else { return nil }
        keys.subtract(required)
        guard keys.isSubset(of: ["expectedEpoch", "boundAt"]),
              let gestureId = map["gestureId"] as? String, ResetOperationRegistry.isGestureId(gestureId),
              let uid = map["uid"] as? String, !uid.isEmpty,
              let authEpochUUID = map["authEpochUUID"] as? String,
              let credentialRevision = TaskGenerationEpochStamp.safeInteger(map["credentialRevision"]),
              let phaseRaw = map["phase"] as? String, let phase = ResetGesturePhase(rawValue: phaseRaw),
              let alias = map["alias"] as? String, ResetOperationRegistry.isAlias(alias),
              let gestureGeneration = map["gestureGeneration"] as? String,
              let reservedAt = map["reservedAt"] as? String, CanonicalInstant.isCanonical(reservedAt) else { return nil }
        var expectedEpoch: Int?
        if let raw = map["expectedEpoch"] {
            guard let value = TaskGenerationEpochStamp.safeInteger(raw) else { return nil }
            expectedEpoch = value
        }
        var boundAt: String?
        if let raw = map["boundAt"] {
            guard let value = raw as? String, CanonicalInstant.isCanonical(value) else { return nil }
            boundAt = value
        }
        switch phase {
        case .reserved: guard expectedEpoch == nil, boundAt == nil else { return nil }
        case .bound: guard expectedEpoch != nil, boundAt != nil else { return nil }
        }
        return ResetGestureV1(gestureId: gestureId, uid: uid, authEpochUUID: authEpochUUID, credentialRevision: credentialRevision, phase: phase, alias: alias, expectedEpoch: expectedEpoch, gestureGeneration: gestureGeneration, reservedAt: reservedAt, boundAt: boundAt)
    }
}

/// `{uid,suggestedOperationId,canonicalOperationId?,expectedTaskGenerationEpoch,phase,progressReceipt?,finalReceipt?,applicationId?,createdAt,updatedAt}`
struct ResetOperationRegistryRecordV2: Sendable, Equatable {
    let uid: String
    let suggestedOperationId: String
    var canonicalOperationId: String?
    var expectedTaskGenerationEpoch: Int
    var phase: ResetRowPhase
    var progressReceipt: Data?
    var finalReceipt: Data?
    var applicationId: String?
    let createdAt: String
    var updatedAt: String

    static let receiptCap = 8_192

    var recoveryAction: ResetRecoveryAction {
        switch phase {
        case .prepared, .resetDispatched: return .retryReset
        case .resetReceiptDeleting: return .resumeServerDeletion
        case .resetReceiptAwaitingLocalReset: return .runLocalCleanup
        case .finalizeDispatched: return .retryFinalize
        case .finalReceipt, .applying: return .applyFinal
        }
    }

    var handleId: String {
        "rho1_" + TaskCanonicalV1.sha256Hex(["uid": uid, "suggested_operation_id": suggestedOperationId, "created_at": createdAt])
    }

    func map() -> [String: Any] {
        var map: [String: Any] = [
            "uid": uid, "suggestedOperationId": suggestedOperationId, "expectedTaskGenerationEpoch": expectedTaskGenerationEpoch,
            "phase": phase.rawValue, "createdAt": createdAt, "updatedAt": updatedAt
        ]
        if let canonicalOperationId { map["canonicalOperationId"] = canonicalOperationId }
        if let progressReceipt, let object = try? JSONSerialization.jsonObject(with: progressReceipt) { map["progressReceipt"] = object }
        if let finalReceipt, let object = try? JSONSerialization.jsonObject(with: finalReceipt) { map["finalReceipt"] = object }
        if let applicationId { map["applicationId"] = applicationId }
        return map
    }

    static func from(_ map: [String: Any]) -> ResetOperationRegistryRecordV2? {
        var keys = Set(map.keys)
        let required: Set<String> = ["uid", "suggestedOperationId", "expectedTaskGenerationEpoch", "phase", "createdAt", "updatedAt"]
        guard required.isSubset(of: keys) else { return nil }
        keys.subtract(required)
        guard keys.isSubset(of: ["canonicalOperationId", "progressReceipt", "finalReceipt", "applicationId"]),
              let uid = map["uid"] as? String, !uid.isEmpty,
              let suggested = map["suggestedOperationId"] as? String, ResetOperationRegistry.isAlias(suggested),
              let epoch = TaskGenerationEpochStamp.safeInteger(map["expectedTaskGenerationEpoch"]),
              let phaseRaw = map["phase"] as? String, let phase = ResetRowPhase(rawValue: phaseRaw),
              let createdAt = map["createdAt"] as? String, CanonicalInstant.isCanonical(createdAt),
              let updatedAt = map["updatedAt"] as? String, CanonicalInstant.isCanonical(updatedAt) else { return nil }
        func receipt(_ key: String) -> Data?? {
            guard let raw = map[key] else { return .some(nil) }
            guard let object = raw as? [String: Any], let data = TaskCanonicalV1.data(object), data.count <= receiptCap else { return nil }
            return .some(data)
        }
        guard let progress = receipt("progressReceipt"), let final = receipt("finalReceipt") else { return nil }
        if let raw = map["canonicalOperationId"], !(raw is String) { return nil }
        if let raw = map["applicationId"], !(raw is String) { return nil }
        return ResetOperationRegistryRecordV2(
            uid: uid, suggestedOperationId: suggested, canonicalOperationId: map["canonicalOperationId"] as? String,
            expectedTaskGenerationEpoch: epoch, phase: phase, progressReceipt: progress, finalReceipt: final,
            applicationId: map["applicationId"] as? String, createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

struct ResetReservation: Sendable, Equatable {
    let gestureId: String
    let gestureGeneration: String
}

/// `{uid,handleId}`; never carries a caller-supplied alias or epoch.
struct ResetOperationHandle: Sendable, Hashable {
    let uid: String
    let handleId: String
}

/// §6.5 local-only surfaces.
enum LegacyMigrationPhase: String, Sendable, Equatable { case prepared, dispatched, receipt, applying, blocked }
struct ResetMigrationPending: Sendable, Equatable { let uid: String; let phase: LegacyMigrationPhase }
struct LegacyResetCompleted: Sendable, Equatable { let uid: String; let applicationId: String }
struct LegacyResetRetryRequired: Sendable, Equatable { let uid: String; let applicationId: String }

enum ResetReserveOutcome: Sendable, Equatable {
    case binding(ResetReservation)
    case operation(ResetOperationHandle)
    case migrationPending(ResetMigrationPending)
    case legacyCompleted(LegacyResetCompleted)
    case legacyRetryRequired(LegacyResetRetryRequired)
}

struct RegistryOccupant: Sendable, Equatable {
    let uid: String
    let expectedTaskGenerationEpoch: Int
    let phase: ResetRowPhase
    let recoveryAction: ResetRecoveryAction
}

struct RegistrySnapshot: Sendable {
    let records: [ResetOperationRegistryRecordV2]
    let gesture: ResetGestureV1?
    let generationId: String?
    let sha256: String?
}

enum StoreClassification: Sendable, Equatable {
    case ready
    case blocked(BlockedSnapshot)
}

// MARK: - ResetOperationRegistry (§5): sole reader/writer of PeezyTaskPlanReset-v2.json

/// S1 scope (owner decision 2026-09-06): envelope, reserve → bind → prepared row,
/// phase vocabulary, epoch-conflict snapshot. The drive reducer, cleanup
/// authority, and legacy migration transitions belong to S3.
actor ResetOperationRegistry {
    enum RegistryError: Error, Equatable {
        case authRequired
        case invalidGestureId(String)
        case registryFull(capacity: Int, occupants: [RegistryOccupant])
        case epochConflict(uid: String, occupants: [ResetEpochOccupant])
        case gestureStale(gestureId: String, gestureGeneration: String)
        case operationStale(uid: String, handleId: String)
        case migrationBlocked(uid: String, errorCode: String)
        case credentialRevisionRegressed
        case envelopeCorrupt
        case clockInvalid
        case storageIO(StorageIOErrorCode)
    }

    enum LoadResult: Sendable, Equatable {
        case absent
        case present(records: Int, gesture: Bool)
        case corrupt
    }

    static let fileName = "PeezyTaskPlanReset-v2.json"
    static let capacity = 4
    private static let gesturePattern = #"^rsg1_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#
    private static let aliasPattern = #"^rsa1_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#

    static func isGestureId(_ value: String) -> Bool { value.range(of: gesturePattern, options: .regularExpression) != nil }
    static func isAlias(_ value: String) -> Bool { value.range(of: aliasPattern, options: .regularExpression) != nil }

    static let production: ResetOperationRegistry = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return ResetOperationRegistry(
            directory: support, clock: SystemDurableClock(),
            auth: TransitionalFirebaseAuthAuthority(), epochAuthority: FirestoreResetEpochAuthority()
        )
    }()

    nonisolated let directory: URL
    private let clock: any LocalDurableClock
    private let auth: any AuthAuthorityProviding
    private let epochAuthority: any ResetEpochAuthorityProviding
    /// S3: epoch-conflict recovery drives with this bundle; nil until the owner attaches it.
    fileprivate var recoveryBundle: ResetRecoveryBundle?
    /// The store owner's single `(RecoveryAttemptKey, Task)` slot: an identical key
    /// coalesces onto the task; a different key is `busy` before any callback, call, or write.
    fileprivate var recoverySlot: (key: String, task: Task<RecoveryResult, Never>)?
    /// S4 (C9.7.8): process-local `validatedReceiptProvenance`, keyed by the RESET identity digest; an entry exists only when this
    /// actor validated the exact response and durably committed the envelope; cleared on load and on any signed-auth change.
    fileprivate var validatedReceiptProvenance: [String: String] = [:]
    fileprivate var provenanceAuth: SignedAuthTuple?
    /// S4 (C9.4.5): the store holding `phase1.pendingRetakeOperation.{uid}` (compare/remove authority only in APPLYING) and
    /// the per-UID `inflightLegacyMigration` singleflight.
    fileprivate var legacyKeyDefaults: UserDefaults = .standard
    fileprivate var inflightLegacyMigration: [String: Task<ResetReserveOutcome, Error>] = [:]
    /// C9.5.8/C9.5.12 `inflightResetOperation`: one drive per handle; installed before the first suspension, cleared in
    /// `defer`; joiners with the same UID/auth epoch and a revision at or above the baseline receive the outcome only.
    fileprivate var inflightResetOperation: [ResetOperationHandle: (uid: String, authEpochUUID: String, credentialBaseline: Int, task: Task<ResetDriveOutcome, Error>)] = [:]

    init(directory: URL, clock: any LocalDurableClock, auth: any AuthAuthorityProviding, epochAuthority: any ResetEpochAuthorityProviding) {
        self.directory = directory
        self.clock = clock
        self.auth = auth
        self.epochAuthority = epochAuthority
    }

    fileprivate struct Envelope {
        var generationId: String
        var sha256: String
        var records: [ResetOperationRegistryRecordV2]
        var migrations: [[String: Any]]
        var gesture: ResetGestureV1?
    }

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    // MARK: Public surface

    func load() -> LoadResult {
        do {
            guard let envelope = try read() else { return .absent }
            return .present(records: envelope.records.count, gesture: envelope.gesture != nil)
        } catch {
            return .corrupt
        }
    }

    func snapshot() -> RegistrySnapshot {
        guard let envelope = try? read() else { return RegistrySnapshot(records: [], gesture: nil, generationId: nil, sha256: nil) }
        return RegistrySnapshot(records: envelope.records, gesture: envelope.gesture, generationId: envelope.generationId, sha256: envelope.sha256)
    }

    /// Deterministic point lookup; there is no alias lookup.
    func row(uid: String, expectedTaskGenerationEpoch: Int) -> ResetOperationRegistryRecordV2? {
        (try? read())?.records.first { $0.uid == uid && $0.expectedTaskGenerationEpoch == expectedTaskGenerationEpoch }
    }

    /// `ready`, or `blocked(reset_epoch_conflict)` when the current signed-in UID
    /// holds more than one valid row. Foreign-UID multiplicity never blocks.
    func classification() async -> StoreClassification {
        guard case let .signedIn(tuple) = await auth.currentSignedAuth() else { return .ready }
        guard let envelope = try? read() else { return .ready }
        let mine = envelope.records.filter { $0.uid == tuple.uid }
        guard mine.count > 1 else { return .ready }
        return .blocked(conflictSnapshot(mine, tuple: tuple, envelope: envelope))
    }

    func reserve(gestureId: String) async throws -> ResetReserveOutcome {
        guard Self.isGestureId(gestureId) else { throw RegistryError.invalidGestureId(gestureId) }
        let tuple = try await signedAuth()
        var envelope = try read() ?? Envelope(generationId: "", sha256: "", records: [], migrations: [], gesture: nil)
        try normalize(&envelope, tuple: tuple)

        // S4 (C9.4.5, C9.5.9 step 2): same-UID migration rows precede any materialization or reset-row drive
        if let outcome = try legacyMigrationOnReserve(&envelope, tuple: tuple, gestureId: gestureId) { return outcome }

        // A loaded bound gesture materializes its prepared row without rereading the epoch.
        if let gesture = envelope.gesture, gesture.uid == tuple.uid, gesture.phase == .bound, let epoch = gesture.expectedEpoch {
            let row = ResetOperationRegistryRecordV2(
                uid: gesture.uid, suggestedOperationId: gesture.alias, canonicalOperationId: nil,
                expectedTaskGenerationEpoch: epoch, phase: .prepared, progressReceipt: nil, finalReceipt: nil,
                applicationId: nil, createdAt: gesture.reservedAt, updatedAt: try writeTime(advancing: [gesture.reservedAt, gesture.boundAt])
            )
            envelope.records = Self.sorted(envelope.records + [row])
            envelope.gesture = nil
            try write(&envelope)
            return .operation(ResetOperationHandle(uid: row.uid, handleId: row.handleId))
        }

        let mine = envelope.records.filter { $0.uid == tuple.uid }
        if mine.count > 1 {
            throw RegistryError.epochConflict(uid: tuple.uid, occupants: Self.epochOccupants(mine))
        }
        if let row = mine.first {
            return .operation(ResetOperationHandle(uid: row.uid, handleId: row.handleId))
        }
        if let gesture = envelope.gesture, gesture.uid == tuple.uid {
            return .binding(ResetReservation(gestureId: gesture.gestureId, gestureGeneration: gesture.gestureGeneration))
        }
        if envelope.records.count >= Self.capacity {
            throw RegistryError.registryFull(capacity: Self.capacity, occupants: envelope.records.map {
                RegistryOccupant(uid: $0.uid, expectedTaskGenerationEpoch: $0.expectedTaskGenerationEpoch, phase: $0.phase, recoveryAction: $0.recoveryAction)
            })
        }
        let generation = UUID().uuidString.lowercased()
        let gesture = ResetGestureV1(
            gestureId: gestureId, uid: tuple.uid, authEpochUUID: tuple.authEpochUUID, credentialRevision: tuple.credentialRevision,
            phase: .reserved, alias: "rsa1_" + UUID().uuidString.lowercased(), expectedEpoch: nil,
            gestureGeneration: generation, reservedAt: try writeTime(advancing: []), boundAt: nil
        )
        envelope.gesture = gesture
        try write(&envelope, generationId: generation)
        return .binding(ResetReservation(gestureId: gesture.gestureId, gestureGeneration: gesture.gestureGeneration))
    }

    func bind(reservation: ResetReservation) async throws -> ResetOperationHandle {
        let stale = RegistryError.gestureStale(gestureId: reservation.gestureId, gestureGeneration: reservation.gestureGeneration)
        let tuple = try await signedAuth()
        var envelope = try read() ?? Envelope(generationId: "", sha256: "", records: [], migrations: [], gesture: nil)
        try normalize(&envelope, tuple: tuple)
        guard let gesture = envelope.gesture, gesture.gestureId == reservation.gestureId,
              gesture.gestureGeneration == reservation.gestureGeneration, gesture.uid == tuple.uid,
              gesture.authEpochUUID == tuple.authEpochUUID, gesture.phase == .reserved else { throw stale }
        guard !envelope.migrations.contains(where: { $0["uid"] as? String == tuple.uid }) else { throw stale }

        let authority = try await epochAuthority.current(uid: tuple.uid, expectedAuth: tuple)

        // Reread auth and the envelope after the await; drift writes nothing.
        let rereadTuple = try await signedAuth()
        guard rereadTuple.uid == tuple.uid, rereadTuple.authEpochUUID == tuple.authEpochUUID,
              rereadTuple.credentialRevision >= tuple.credentialRevision else { throw stale }
        envelope = try read() ?? envelope
        guard var bound = envelope.gesture, bound.gestureId == gesture.gestureId,
              bound.gestureGeneration == gesture.gestureGeneration, bound.phase == .reserved else { throw stale }

        // Write 1: reserved → bound with the exact epoch.
        bound.phase = .bound
        bound.expectedEpoch = authority.taskGenerationEpoch
        bound.boundAt = try writeTime(advancing: [bound.reservedAt])
        bound.credentialRevision = rereadTuple.credentialRevision
        envelope.gesture = bound
        try write(&envelope)

        // Write 2: the prepared row from the bound gesture; the gesture is removed.
        let row = ResetOperationRegistryRecordV2(
            uid: bound.uid, suggestedOperationId: bound.alias, canonicalOperationId: nil,
            expectedTaskGenerationEpoch: authority.taskGenerationEpoch, phase: .prepared, progressReceipt: nil, finalReceipt: nil,
            applicationId: nil, createdAt: bound.reservedAt, updatedAt: try writeTime(advancing: [bound.reservedAt, bound.boundAt])
        )
        envelope.records = Self.sorted(envelope.records + [row])
        envelope.gesture = nil
        try write(&envelope)
        return ResetOperationHandle(uid: row.uid, handleId: row.handleId)
    }

    /// S1: removes the row once today's retake sequence has finalized. Idempotent.
    func retire(handle: ResetOperationHandle) async throws {
        let tuple = try await signedAuth()
        guard tuple.uid == handle.uid else { throw RegistryError.operationStale(uid: handle.uid, handleId: handle.handleId) }
        guard var envelope = try read() else { return }
        guard let index = envelope.records.firstIndex(where: { $0.uid == handle.uid && $0.handleId == handle.handleId }) else { return }
        envelope.records.remove(at: index)
        try write(&envelope)
    }

    // MARK: Internals

    private func signedAuth() async throws -> SignedAuthTuple {
        guard case let .signedIn(tuple) = await auth.currentSignedAuth() else { throw RegistryError.authRequired }
        return tuple
    }

    /// Signed-out state or a gesture whose uid/auth epoch mismatches is removed
    /// atomically; a higher same-epoch credential revision rebases it; a lower
    /// one is corruption.
    private func normalize(_ envelope: inout Envelope, tuple: SignedAuthTuple) throws {
        guard let gesture = envelope.gesture else { return }
        if gesture.uid != tuple.uid || gesture.authEpochUUID != tuple.authEpochUUID {
            envelope.gesture = nil
            try write(&envelope)
            return
        }
        if tuple.credentialRevision < gesture.credentialRevision { throw RegistryError.credentialRevisionRegressed }
        if tuple.credentialRevision > gesture.credentialRevision {
            var rebased = gesture
            rebased.credentialRevision = tuple.credentialRevision
            envelope.gesture = rebased
            try write(&envelope)
        }
    }

    private func writeTime(advancing instants: [String?]) throws -> String {
        let sample = clock.now()
        guard CanonicalInstant.isCanonical(sample) else { throw RegistryError.clockInvalid }
        return ([sample] + instants.compactMap { $0 }).max() ?? sample
    }

    private func read() throws -> Envelope? {
        let path = fileURL.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let bytes = FileManager.default.contents(atPath: path) else { throw RegistryError.storageIO(.fileReadFailed) }
        guard let decoded = DurableEnvelopeCodec.decode(bytes, fileKind: .taskPlanResetV2) else { throw RegistryError.envelopeCorrupt }
        let payload = decoded.payload
        let keys = Set(payload.keys)
        guard keys.isSubset(of: ["records", "legacyMigrations", "gesture"]), keys.isSuperset(of: ["records", "legacyMigrations"]),
              let rawRecords = payload["records"] as? [[String: Any]], rawRecords.count <= Self.capacity,
              let rawMigrations = payload["legacyMigrations"] as? [[String: Any]], rawMigrations.count <= Self.capacity else {
            throw RegistryError.envelopeCorrupt
        }
        let records = rawRecords.compactMap(ResetOperationRegistryRecordV2.from)
        guard records.count == rawRecords.count,
              Set(records.map { "\($0.uid)|\($0.expectedTaskGenerationEpoch)" }).count == records.count,
              Set(records.map(\.handleId)).count == records.count,
              records == Self.sorted(records) else { throw RegistryError.envelopeCorrupt }
        var gesture: ResetGestureV1?
        if let rawGesture = payload["gesture"] {
            guard let map = rawGesture as? [String: Any], let parsed = ResetGestureV1.from(map) else { throw RegistryError.envelopeCorrupt }
            gesture = parsed
        }
        return Envelope(generationId: decoded.generationId, sha256: decoded.sha256, records: records, migrations: rawMigrations, gesture: gesture)
    }

    private func write(_ envelope: inout Envelope, generationId: String? = nil) throws {
        let generation = generationId ?? UUID().uuidString.lowercased()
        var payload: [String: Any] = ["records": envelope.records.map { $0.map() }, "legacyMigrations": envelope.migrations]
        if let gesture = envelope.gesture { payload["gesture"] = gesture.map() }
        guard let bytes = DurableEnvelopeCodec.encode(fileKind: .taskPlanResetV2, generationId: generation, payload: payload) else {
            throw RegistryError.envelopeCorrupt
        }
        do {
            try DurableFileReplacement.replace(at: fileURL, bytes: bytes)
        } catch let failure as DurableFileReplacement.Failure {
            throw RegistryError.storageIO(failure.code)
        }
        envelope.generationId = generation
        envelope.sha256 = TaskCanonicalV1.sha256Hex(data: bytes)
    }

    private static func sorted(_ records: [ResetOperationRegistryRecordV2]) -> [ResetOperationRegistryRecordV2] {
        records.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            if $0.uid != $1.uid { return Array($0.uid.utf8).lexicographicallyPrecedes(Array($1.uid.utf8)) }
            return $0.expectedTaskGenerationEpoch < $1.expectedTaskGenerationEpoch
        }
    }

    private static func epochOccupants(_ rows: [ResetOperationRegistryRecordV2]) -> [ResetEpochOccupant] {
        sorted(rows).map { ResetEpochOccupant(expectedTaskGenerationEpoch: $0.expectedTaskGenerationEpoch, phase: $0.phase, recoveryAction: $0.recoveryAction) }
    }

    /// S4 (C9.7.12): the conflict digest is the `RecoveryObservedStateV1` digest over the observed target, so the
    /// protocol path and `recoverEpoch` CAS the same value.
    private func conflictSnapshot(_ rows: [ResetOperationRegistryRecordV2], tuple: SignedAuthTuple, envelope: Envelope) -> BlockedSnapshot {
        let occupants = Self.epochOccupants(rows)
        let actionable = occupants.map(\.expectedTaskGenerationEpoch).min() ?? 0
        let target = (try? targetRead())?.observation ?? .absent
        let quarantine = (try? quarantineRead())?.observation ?? .absent
        let observed = RecoveryObservedStateV1.files(store: .reset, baseState: "reset_epoch_conflict", target: target, quarantine: quarantine, availableActions: ["recover_epoch"], auth: tuple, epochOccupants: occupants)
        return .resetEpochConflict(recoveryStateDigest: observed.recoveryStateDigest, actionableExpectedTaskGenerationEpoch: actionable, occupants: occupants)
    }

    // MARK: S4 file observation (S4-CD2: the `DurableStoreRecovering` conformance over the existing slot)

    static let quarantineFileName = "PeezyTaskPlanReset-v2.quarantine-v1.json"
    fileprivate var quarantineURL: URL { directory.appendingPathComponent(Self.quarantineFileName) }

    fileprivate func targetRead() throws -> DurableFileObserver.Read {
        try DurableFileObserver.read(at: fileURL, cap: DurableFileKind.taskPlanResetV2.storeCap) { bytes in
            guard let decoded = DurableEnvelopeCodec.decode(bytes, fileKind: .taskPlanResetV2), Self.parse(decoded) != nil else { return nil }
            return (decoded.generationId, decoded.sha256)
        }
    }

    fileprivate func quarantineRead() throws -> DurableFileObserver.Read {
        try DurableFileObserver.read(at: quarantineURL, cap: DurableFileKind.taskPlanResetV2.storeCap) { bytes in
            guard let decoded = DurableEnvelopeCodec.decode(bytes, fileKind: .taskPlanResetV2), Self.parse(decoded) != nil else { return nil }
            return (decoded.generationId, decoded.sha256)
        }
    }

    /// The registry's own strict payload rule (the same one `read()` applies), over an already-decoded envelope.
    fileprivate static func parse(_ decoded: DecodedDurableEnvelope) -> Envelope? {
        let payload = decoded.payload
        let keys = Set(payload.keys)
        guard keys.isSubset(of: ["records", "legacyMigrations", "gesture"]), keys.isSuperset(of: ["records", "legacyMigrations"]),
              let rawRecords = payload["records"] as? [[String: Any]], rawRecords.count <= capacity,
              let rawMigrations = payload["legacyMigrations"] as? [[String: Any]], rawMigrations.count <= capacity else { return nil }
        let records = rawRecords.compactMap(ResetOperationRegistryRecordV2.from)
        guard records.count == rawRecords.count,
              Set(records.map { "\($0.uid)|\($0.expectedTaskGenerationEpoch)" }).count == records.count,
              Set(records.map(\.handleId)).count == records.count,
              records == sorted(records) else { return nil }
        var gesture: ResetGestureV1?
        if let rawGesture = payload["gesture"] {
            guard let map = rawGesture as? [String: Any], let parsed = ResetGestureV1.from(map) else { return nil }
            gesture = parsed
        }
        return Envelope(generationId: decoded.generationId, sha256: decoded.sha256, records: records, migrations: rawMigrations, gesture: gesture)
    }

    fileprivate func writeRecovered(_ envelope: Envelope, receipt: [String: Any]?) throws -> String {
        let generation = UUID().uuidString.lowercased()
        var payload: [String: Any] = ["records": envelope.records.map { $0.map() }, "legacyMigrations": envelope.migrations]
        if let gesture = envelope.gesture { payload["gesture"] = gesture.map() }
        guard let bytes = DurableEnvelopeCodec.encode(fileKind: .taskPlanResetV2, generationId: generation, payload: payload, recoveryReceipt: receipt) else {
            throw RegistryError.envelopeCorrupt
        }
        do { try DurableFileReplacement.replace(at: fileURL, bytes: bytes) } catch let failure as DurableFileReplacement.Failure { throw RegistryError.storageIO(failure.code) }
        return generation
    }

    fileprivate func targetReceipt() -> (quarantineSHA256: String, recoveredCount: Int, droppedCount: Int)? {
        guard let bytes = FileManager.default.contents(atPath: fileURL.path), let decoded = DurableEnvelopeCodec.decode(bytes, fileKind: .taskPlanResetV2),
              let receipt = decoded.recoveryReceipt, let sha = receipt["quarantineSHA256"] as? String,
              let recovered = TaskGenerationEpochStamp.safeInteger(receipt["recoveredCount"]), let dropped = TaskGenerationEpochStamp.safeInteger(receipt["droppedCount"]) else { return nil }
        return (sha, recovered, dropped)
    }

    fileprivate func liveEnvelope() -> Envelope? { try? read() }

    fileprivate func currentProvenanceAuth(_ tuple: SignedAuthTuple?) {
        if provenanceAuth != tuple { validatedReceiptProvenance = [:]; provenanceAuth = tuple }
    }

    fileprivate func installProvenance(identityDigest: String, receiptSHA256: String) { validatedReceiptProvenance[identityDigest] = receiptSHA256 }
    fileprivate func provenance(for identityDigest: String) -> String? { validatedReceiptProvenance[identityDigest] }
    fileprivate var slot: (key: String, task: Task<RecoveryResult, Never>)? {
        get { recoverySlot }
        set { recoverySlot = newValue }
    }
    fileprivate var bundleRemote: (any ResetRemoteProviding)? { recoveryBundle?.remote }
}

// MARK: - Production conformers (S1 transitional auth; D15 epoch point path)

/// Transitional S1 conformer: Firebase's current user with a fixed legacy auth
/// epoch and revision 0. S5 replaces it with the durable auth-epoch authority.
struct TransitionalFirebaseAuthAuthority: AuthAuthorityProviding {
    static let legacyAuthEpochUUID = "00000000-0000-0000-0000-000000000000"

    func currentSignedAuth() async -> SignedAuthAuthority {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return .signedOut }
        return .signedIn(SignedAuthTuple(uid: uid, authEpochUUID: Self.legacyAuthEpochUUID, credentialRevision: 0))
    }

    func forceRefresh(expected: SignedAuthTuple) async -> AuthRefreshOutcome { .notCommitted }

    func confirmAccountDeleted(expected: AuthIdentity) async -> AccountDeletionAuthObservation { .notProven }
}

/// D15: the user-root authority is read at its deterministic point path
/// `users/{uid}` through the Firestore runtime seam; no alias or collection scan.
struct FirestoreResetEpochAuthority: ResetEpochAuthorityProviding {
    func current(uid: String, expectedAuth: SignedAuthTuple) async throws -> ResetEpochAuthority {
        guard !uid.isEmpty, expectedAuth.uid == uid, Auth.auth().currentUser?.uid == uid else {
            throw ResetOperationRegistry.RegistryError.authRequired
        }
        let firestore = try await FirestoreRuntime.provider.acquire().firestore
        let root = try await firestore.collection("users").document(uid).getDocument()
        let epoch = try TaskGenerationEpochStamp.effectiveRootEpoch(root.data(), requireResetAbsent: false)
        return ResetEpochAuthority(uid: uid, taskGenerationEpoch: epoch)
    }
}

// MARK: - Phase 2 reset wires consumed by the reset client (PHASE2_CONTRACT.md C2.8; S3)

/// Thrown union of `changeTaskPlan`'s reset, inspection, and reconciliation errors
/// (C2.8 §6.2:653–664, §4.2:1025, Reconciled 11). A detail-less `unavailable` and
/// every transport failure are `transport`: durable bytes are retained and the same
/// message is retried. Anything outside the table is `protocolAmbiguity`.
enum ResetRemoteError: Error, Equatable {
    case authRequired
    case requestInvalid(field: String)
    case operationReused(operationId: String)
    case legacyResetCorrupt(context: String, legacyOperationId: String?, recordClass: String, markerClass: String)
    case legacyResetMigrationRequired(legacyOperationId: String)
    case legacyResetAliasOccupied(legacyOperationId: String, migrationAlias: String)
    case clientUpgradeRequired(requiredProtocol: String)
    case staleState
    case resetActive(operationId: String, expectedTaskGenerationEpoch: Int)
    case transport
    case protocolAmbiguity
}

/// Exact `{tasks,notificationIntents,taskDeadlineEvidence,confirmationSnapshots}`.
struct ResetDeletedCountsV1: Equatable, Sendable {
    let tasks: Int
    let notificationIntents: Int
    let taskDeadlineEvidence: Int
    let confirmationSnapshots: Int

    var sum: Int { tasks + notificationIntents + taskDeadlineEvidence + confirmationSnapshots }

    static func decode(_ raw: Any?) -> ResetDeletedCountsV1? {
        guard let map = raw as? [String: Any], Set(map.keys) == ["tasks", "notificationIntents", "taskDeadlineEvidence", "confirmationSnapshots"],
              let tasks = TaskGenerationEpochStamp.safeInteger(map["tasks"]),
              let intents = TaskGenerationEpochStamp.safeInteger(map["notificationIntents"]),
              let evidence = TaskGenerationEpochStamp.safeInteger(map["taskDeadlineEvidence"]),
              let snapshots = TaskGenerationEpochStamp.safeInteger(map["confirmationSnapshots"]) else { return nil }
        return ResetDeletedCountsV1(tasks: tasks, notificationIntents: intents, taskDeadlineEvidence: evidence, confirmationSnapshots: snapshots)
    }

    func map() -> [String: Any] {
        ["tasks": tasks, "notificationIntents": notificationIntents, "taskDeadlineEvidence": taskDeadlineEvidence, "confirmationSnapshots": confirmationSnapshots]
    }
}

enum ResetReceiptKind: String, Sendable, Equatable {
    case progress = "reset_progress"
    case final = "reset_final"
}

enum ResetReceiptState: String, Sendable, Equatable {
    case deleting
    case awaitingLocalReset = "awaiting_local_reset"
    case finalized
}

/// The exact reset response union (spec v5 §4.2:1005 via C2.8):
/// `{schemaVersion:1,kind:"reset_progress"|"reset_final",operationId,replayed,accountUid,
///   expectedTaskGenerationEpoch,taskGenerationEpoch,activeMoveEventId,deletedCount,deletedCounts,state}`.
struct ResetReceiptV1: Equatable, Sendable {
    static let keys: Set<String> = ["schemaVersion", "kind", "operationId", "replayed", "accountUid", "expectedTaskGenerationEpoch", "taskGenerationEpoch", "activeMoveEventId", "deletedCount", "deletedCounts", "state"]
    static let canonicalIdPattern = #"^rso1_[0-9a-f]{40}$"#
    static let moveEventIdPattern = #"^me1_[0-9a-f]{40}$"#

    let kind: ResetReceiptKind
    let operationId: String
    let replayed: Bool
    let accountUid: String
    let expectedTaskGenerationEpoch: Int
    let taskGenerationEpoch: Int
    let activeMoveEventId: String
    let deletedCount: Int
    let deletedCounts: ResetDeletedCountsV1
    let state: ResetReceiptState

    /// Exact-member decode; kind/state coherence, `r == e + 1`, and the count sum are required.
    static func decode(_ data: [String: Any]) throws -> ResetReceiptV1 {
        guard Set(data.keys) == keys, TaskGenerationEpochStamp.safeInteger(data["schemaVersion"]) == 1,
              let kindRaw = data["kind"] as? String, let kind = ResetReceiptKind(rawValue: kindRaw),
              let operationId = data["operationId"] as? String, operationId.range(of: canonicalIdPattern, options: .regularExpression) != nil,
              let replayed = ResetWireDecoding.bool(data["replayed"]),
              let accountUid = data["accountUid"] as? String, !accountUid.isEmpty,
              let expected = TaskGenerationEpochStamp.safeInteger(data["expectedTaskGenerationEpoch"]),
              let result = TaskGenerationEpochStamp.safeInteger(data["taskGenerationEpoch"]), result == expected + 1,
              let moveEventId = data["activeMoveEventId"] as? String, moveEventId.range(of: moveEventIdPattern, options: .regularExpression) != nil,
              let deletedCount = TaskGenerationEpochStamp.safeInteger(data["deletedCount"]),
              let counts = ResetDeletedCountsV1.decode(data["deletedCounts"]), counts.sum == deletedCount,
              let stateRaw = data["state"] as? String, let state = ResetReceiptState(rawValue: stateRaw) else { throw ResetRemoteError.protocolAmbiguity }
        switch (kind, state) {
        case (.progress, .deleting), (.progress, .awaitingLocalReset), (.final, .finalized): break
        default: throw ResetRemoteError.protocolAmbiguity
        }
        return ResetReceiptV1(kind: kind, operationId: operationId, replayed: replayed, accountUid: accountUid, expectedTaskGenerationEpoch: expected, taskGenerationEpoch: result, activeMoveEventId: moveEventId, deletedCount: deletedCount, deletedCounts: counts, state: state)
    }

    func map() -> [String: Any] {
        ["schemaVersion": 1, "kind": kind.rawValue, "operationId": operationId, "replayed": replayed, "accountUid": accountUid,
         "expectedTaskGenerationEpoch": expectedTaskGenerationEpoch, "taskGenerationEpoch": taskGenerationEpoch, "activeMoveEventId": activeMoveEventId,
         "deletedCount": deletedCount, "deletedCounts": deletedCounts.map(), "state": state.rawValue]
    }

    /// Canonical bytes for the registry row (`progressReceipt`/`finalReceipt`, cap 8,192).
    func canonicalData() -> Data? { TaskCanonicalV1.data(map()) }

    static func decode(data: Data) -> ResetReceiptV1? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return try? decode(object)
    }
}

enum ResetWireDecoding {
    /// Booleans only: an NSNumber that is a CFBoolean.
    static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}

enum ResetInspectionOutcome: String, Sendable, Equatable {
    case absent, pending, committed
}

/// `inspectCommittedOperation` for the RESET family (C2.8 §7:843): exact
/// `{schemaVersion:1,kind:"committed_operation_inspection",accountUid,family:"RESET",
///   authority:{operationId},requestAuthority:{requestFingerprint},identityDigest,outcome,receipt?}`.
/// `receipt` exists only for `committed` and is the reconstructed `reset_final` with `replayed:true`.
struct ResetInspectionV1: Equatable, Sendable {
    let accountUid: String
    let operationId: String
    let requestFingerprint: String
    let identityDigest: String
    let outcome: ResetInspectionOutcome
    let receipt: ResetReceiptV1?

    static func decode(_ data: [String: Any]) throws -> ResetInspectionV1 {
        var expected: Set<String> = ["schemaVersion", "kind", "accountUid", "family", "authority", "requestAuthority", "identityDigest", "outcome"]
        guard let outcomeRaw = data["outcome"] as? String, let outcome = ResetInspectionOutcome(rawValue: outcomeRaw) else { throw ResetRemoteError.protocolAmbiguity }
        if outcome == .committed { expected.insert("receipt") }
        guard Set(data.keys) == expected, TaskGenerationEpochStamp.safeInteger(data["schemaVersion"]) == 1,
              data["kind"] as? String == "committed_operation_inspection", data["family"] as? String == "RESET",
              let accountUid = data["accountUid"] as? String, !accountUid.isEmpty,
              let authority = data["authority"] as? [String: Any], Set(authority.keys) == ["operationId"],
              let operationId = authority["operationId"] as? String, operationId.range(of: ResetReceiptV1.canonicalIdPattern, options: .regularExpression) != nil,
              let requestAuthority = data["requestAuthority"] as? [String: Any], Set(requestAuthority.keys) == ["requestFingerprint"],
              let fingerprint = requestAuthority["requestFingerprint"] as? String, fingerprint.range(of: #"^reset1_[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              let identityDigest = data["identityDigest"] as? String, identityDigest.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else { throw ResetRemoteError.protocolAmbiguity }
        var receipt: ResetReceiptV1?
        if outcome == .committed {
            guard let raw = data["receipt"] as? [String: Any] else { throw ResetRemoteError.protocolAmbiguity }
            let decoded = try ResetReceiptV1.decode(raw)
            guard decoded.kind == .final, decoded.replayed, decoded.operationId == operationId, decoded.accountUid == accountUid else { throw ResetRemoteError.protocolAmbiguity }
            receipt = decoded
        }
        return ResetInspectionV1(accountUid: accountUid, operationId: operationId, requestFingerprint: fingerprint, identityDigest: identityDigest, outcome: outcome, receipt: receipt)
    }
}

/// `{schemaVersion:1,kind:"legacy_reset_final",operationId,replayed:false,accountUid,deletedCount,state:"finalized"}`.
struct LegacyResetFinalReceiptV1: Equatable, Sendable {
    let operationId: String
    let accountUid: String
    let deletedCount: Int

    static func decode(_ raw: Any?) throws -> LegacyResetFinalReceiptV1 {
        guard let data = raw as? [String: Any], Set(data.keys) == ["schemaVersion", "kind", "operationId", "replayed", "accountUid", "deletedCount", "state"],
              TaskGenerationEpochStamp.safeInteger(data["schemaVersion"]) == 1, data["kind"] as? String == "legacy_reset_final",
              let operationId = data["operationId"] as? String, !operationId.isEmpty,
              ResetWireDecoding.bool(data["replayed"]) == false,
              let accountUid = data["accountUid"] as? String, !accountUid.isEmpty,
              let deletedCount = TaskGenerationEpochStamp.safeInteger(data["deletedCount"]),
              data["state"] as? String == "finalized" else { throw ResetRemoteError.protocolAmbiguity }
        return LegacyResetFinalReceiptV1(operationId: operationId, accountUid: accountUid, deletedCount: deletedCount)
    }
}

/// `reconcileLegacyTaskReset` success union (C2.8 §6.2:626–651). The inner
/// receipt replay flags are frozen: `upgraded` carries `replayed:false`,
/// `phase2_active` carries `replayed:true`; only the outer flag changes on replay.
enum LegacyResetReconciliationV1: Equatable, Sendable {
    struct Base: Equatable, Sendable {
        let migrationId: String
        let legacyOperationId: String
        let migrationAlias: String
        let accountUid: String
        let replayed: Bool
    }

    case notDispatched(Base)
    case upgraded(Base, sourceState: String, progress: ResetReceiptV1)
    case phase2Active(Base, progress: ResetReceiptV1)
    case finalizedCompat(Base, legacyFinal: LegacyResetFinalReceiptV1)

    var base: Base {
        switch self {
        case let .notDispatched(base), let .upgraded(base, _, _), let .phase2Active(base, _), let .finalizedCompat(base, _): return base
        }
    }

    static let migrationIdPattern = #"^rlm1_[0-9a-f]{40}$"#

    /// §6.2:608–618 derivations over UID and legacy operation ID only.
    static func migrationId(uid: String, legacyOperationId: String) -> String {
        "rlm1_" + String(TaskCanonicalV1.sha256Hex(["account_uid": uid, "legacy_operation_id": legacyOperationId]).prefix(40))
    }

    static func requestFingerprint(uid: String, legacyOperationId: String) -> String {
        "rlmreq1_" + TaskCanonicalV1.sha256Hex(["account_uid": uid, "legacy_operation_id": legacyOperationId])
    }

    static func decode(_ data: [String: Any]) throws -> LegacyResetReconciliationV1 {
        let common: Set<String> = ["schemaVersion", "kind", "outcome", "migrationId", "legacyOperationId", "migrationAlias", "accountUid", "replayed"]
        guard TaskGenerationEpochStamp.safeInteger(data["schemaVersion"]) == 1, data["kind"] as? String == "legacy_reset_reconciliation",
              let outcome = data["outcome"] as? String,
              let migrationId = data["migrationId"] as? String, migrationId.range(of: migrationIdPattern, options: .regularExpression) != nil,
              let legacyOperationId = data["legacyOperationId"] as? String, !legacyOperationId.isEmpty,
              let migrationAlias = data["migrationAlias"] as? String, ResetOperationRegistry.isAlias(migrationAlias),
              let accountUid = data["accountUid"] as? String, !accountUid.isEmpty,
              let replayed = ResetWireDecoding.bool(data["replayed"]) else { throw ResetRemoteError.protocolAmbiguity }
        let base = Base(migrationId: migrationId, legacyOperationId: legacyOperationId, migrationAlias: migrationAlias, accountUid: accountUid, replayed: replayed)
        let keys = Set(data.keys)
        switch outcome {
        case "not_dispatched":
            guard keys == common else { throw ResetRemoteError.protocolAmbiguity }
            return .notDispatched(base)
        case "upgraded":
            guard keys == common.union(["sourceState", "progressReceipt"]),
                  let sourceState = data["sourceState"] as? String, sourceState == "deleting" || sourceState == "tasks_deleted",
                  let raw = data["progressReceipt"] as? [String: Any] else { throw ResetRemoteError.protocolAmbiguity }
            let progress = try ResetReceiptV1.decode(raw)
            guard progress.kind == .progress, progress.replayed == false, progress.accountUid == accountUid else { throw ResetRemoteError.protocolAmbiguity }
            return .upgraded(base, sourceState: sourceState, progress: progress)
        case "phase2_active":
            guard keys == common.union(["progressReceipt"]), let raw = data["progressReceipt"] as? [String: Any] else { throw ResetRemoteError.protocolAmbiguity }
            let progress = try ResetReceiptV1.decode(raw)
            guard progress.kind == .progress, progress.replayed == true, progress.accountUid == accountUid else { throw ResetRemoteError.protocolAmbiguity }
            return .phase2Active(base, progress: progress)
        case "finalized_compat":
            guard keys == common.union(["sourceState", "legacyFinalReceipt"]), data["sourceState"] as? String == "finalized" else { throw ResetRemoteError.protocolAmbiguity }
            let final = try LegacyResetFinalReceiptV1.decode(data["legacyFinalReceipt"])
            guard final.operationId == legacyOperationId, final.accountUid == accountUid else { throw ResetRemoteError.protocolAmbiguity }
            return .finalizedCompat(base, legacyFinal: final)
        default:
            throw ResetRemoteError.protocolAmbiguity
        }
    }
}

enum ResetRemoteAction: String, Sendable, Equatable {
    case resetAllTasks, finalizeTaskReset
}

/// The reset client's remote seam: the two reset messages, the RESET inspection,
/// and the legacy reconciliation. Every implementation computes the frozen
/// fingerprint and identity digest itself; callers pass identity only.
protocol ResetRemoteProviding: Sendable {
    func reset(_ action: ResetRemoteAction, alias: String, expectedTaskGenerationEpoch: Int) async throws -> ResetReceiptV1
    func inspectReset(uid: String, canonicalOperationId: String, expectedTaskGenerationEpoch: Int) async throws -> ResetInspectionV1
    func reconcileLegacyReset(legacyOperationId: String, migrationAlias: String) async throws -> LegacyResetReconciliationV1
    /// S4 (C9.4.5): `{action:"inspectLegacyTaskReset"}`, authenticated and read-only; offered only by `LEGACY_ALIAS_INVALID`.
    func inspectLegacyReset() async throws -> LegacyResetInspectionV1
}

extension ResetRemoteProviding {
    func inspectLegacyReset() async throws -> LegacyResetInspectionV1 { throw ResetRemoteError.protocolAmbiguity }
}

/// `{schemaVersion:1,kind:"legacy_reset_inspection",outcome:"none"|"legacy_active"|"phase2_active",accountUid,legacyOperationId?,canonicalOperationId?,expectedTaskGenerationEpoch?}` (C9.4.5).
enum LegacyResetInspectionV1: Equatable, Sendable {
    case none(accountUid: String)
    case legacyActive(accountUid: String, legacyOperationId: String)
    case phase2Active(accountUid: String, canonicalOperationId: String, expectedTaskGenerationEpoch: Int)

    var accountUid: String {
        switch self {
        case let .none(uid), let .legacyActive(uid, _), let .phase2Active(uid, _, _): return uid
        }
    }

    static func decode(_ data: [String: Any]) throws -> LegacyResetInspectionV1 {
        let common: Set<String> = ["schemaVersion", "kind", "outcome", "accountUid"]
        guard TaskGenerationEpochStamp.safeInteger(data["schemaVersion"]) == 1, data["kind"] as? String == "legacy_reset_inspection",
              let outcome = data["outcome"] as? String, let accountUid = data["accountUid"] as? String, !accountUid.isEmpty else { throw ResetRemoteError.protocolAmbiguity }
        let keys = Set(data.keys)
        switch outcome {
        case "none":
            guard keys == common else { throw ResetRemoteError.protocolAmbiguity }
            return .none(accountUid: accountUid)
        case "legacy_active":
            guard keys == common.union(["legacyOperationId"]), let legacy = data["legacyOperationId"] as? String, LegacyResetMigrationV1.isValidLegacyOperationId(legacy) else { throw ResetRemoteError.protocolAmbiguity }
            return .legacyActive(accountUid: accountUid, legacyOperationId: legacy)
        case "phase2_active":
            guard keys == common.union(["canonicalOperationId", "expectedTaskGenerationEpoch"]),
                  let canonical = data["canonicalOperationId"] as? String, canonical.range(of: ResetReceiptV1.canonicalIdPattern, options: .regularExpression) != nil,
                  let epoch = TaskGenerationEpochStamp.safeInteger(data["expectedTaskGenerationEpoch"]), epoch < TaskGenerationEpochStamp.maxSafeInteger else { throw ResetRemoteError.protocolAmbiguity }
            return .phase2Active(accountUid: accountUid, canonicalOperationId: canonical, expectedTaskGenerationEpoch: epoch)
        default:
            throw ResetRemoteError.protocolAmbiguity
        }
    }
}

extension TaskPlanService {
    /// Typed transport over `changeTaskPlan` for the Phase 2 reset protocol (C2.8).
    struct ResetTransport: ResetRemoteProviding, @unchecked Sendable {
        static let callableName = "changeTaskPlan"
        static let reason = "retake_assessment"

        private let callable: Callable

        init(callable: @escaping Callable = TaskPlanService.productionCallable) {
            self.callable = callable
        }

        /// `"reset1_" + SHA-256(TaskCanonicalV1({kind:"reset",reason:"retake_assessment",expected_task_generation_epoch:e}))` (§4.4:1071).
        static func requestFingerprint(expectedTaskGenerationEpoch: Int) -> String {
            "reset1_" + TaskCanonicalV1.sha256Hex(["kind": "reset", "reason": reason, "expected_task_generation_epoch": expectedTaskGenerationEpoch])
        }

        /// The RESET row's private identity map: `{kind:"reset",uid,expectedTaskGenerationEpoch}` (§7:841).
        static func identityDigest(uid: String, expectedTaskGenerationEpoch: Int) -> String {
            TaskCanonicalV1.sha256Hex(["kind": "reset", "uid": uid, "expectedTaskGenerationEpoch": expectedTaskGenerationEpoch])
        }

        func reset(_ action: ResetRemoteAction, alias: String, expectedTaskGenerationEpoch: Int) async throws -> ResetReceiptV1 {
            let payload: [String: Any] = ["action": action.rawValue, "operationId": alias, "reason": Self.reason, "expectedTaskGenerationEpoch": expectedTaskGenerationEpoch]
            return try ResetReceiptV1.decode(try await invoke(payload))
        }

        func inspectReset(uid: String, canonicalOperationId: String, expectedTaskGenerationEpoch: Int) async throws -> ResetInspectionV1 {
            let payload: [String: Any] = [
                "action": "inspectCommittedOperation", "family": "RESET",
                "authority": ["operationId": canonicalOperationId],
                "requestAuthority": ["requestFingerprint": Self.requestFingerprint(expectedTaskGenerationEpoch: expectedTaskGenerationEpoch)],
                "identityDigest": Self.identityDigest(uid: uid, expectedTaskGenerationEpoch: expectedTaskGenerationEpoch)
            ]
            let inspection = try ResetInspectionV1.decode(try await invoke(payload))
            guard inspection.accountUid == uid, inspection.operationId == canonicalOperationId,
                  inspection.requestFingerprint == Self.requestFingerprint(expectedTaskGenerationEpoch: expectedTaskGenerationEpoch),
                  inspection.identityDigest == Self.identityDigest(uid: uid, expectedTaskGenerationEpoch: expectedTaskGenerationEpoch) else { throw ResetRemoteError.protocolAmbiguity }
            return inspection
        }

        func reconcileLegacyReset(legacyOperationId: String, migrationAlias: String) async throws -> LegacyResetReconciliationV1 {
            let payload: [String: Any] = ["action": "reconcileLegacyTaskReset", "legacyOperationId": legacyOperationId, "migrationAlias": migrationAlias]
            return try LegacyResetReconciliationV1.decode(try await invoke(payload))
        }

        /// S4 (C9.4.5): the `LEGACY_RESET_MIGRATION` inspection transport, exactly `{action:"inspectLegacyTaskReset"}`.
        func inspectLegacyReset() async throws -> LegacyResetInspectionV1 {
            try LegacyResetInspectionV1.decode(try await invoke(["action": "inspectLegacyTaskReset"]))
        }

        private func invoke(_ payload: [String: Any]) async throws -> [String: Any] {
            do {
                return try await callable(Self.callableName, payload)
            } catch let error as ResetRemoteError {
                throw error
            } catch {
                throw Self.mapError(error)
            }
        }

        /// The C2.8 error table. Absent `details` (transport failures and the
        /// four detail-less `unavailable` responses) is `transport`.
        static func mapError(_ error: Swift.Error) -> ResetRemoteError {
            let nsError = error as NSError
            guard let details = nsError.userInfo["details"] as? [String: Any] else { return .transport }
            guard TaskGenerationEpochStamp.safeInteger(details["schemaVersion"]) == 1, let reason = details["reason"] as? String else { return .protocolAmbiguity }
            let keys = Set(details.keys)
            switch reason {
            case "AUTH_REQUIRED" where keys.count == 2: return .authRequired
            case "REQUEST_INVALID" where keys == ["schemaVersion", "reason", "field"]:
                guard let field = details["field"] as? String, !field.isEmpty else { return .protocolAmbiguity }
                return .requestInvalid(field: field)
            case "OPERATION_REUSED" where keys == ["schemaVersion", "reason", "operationId"]:
                guard let id = details["operationId"] as? String, !id.isEmpty else { return .protocolAmbiguity }
                return .operationReused(operationId: id)
            case "LEGACY_RESET_CORRUPT":
                guard let context = details["context"] as? String, let recordClass = details["recordClass"] as? String, let markerClass = details["markerClass"] as? String else { return .protocolAmbiguity }
                if context == "reconcile", keys == ["schemaVersion", "reason", "context", "legacyOperationId", "recordClass", "markerClass"], let legacy = details["legacyOperationId"] as? String, !legacy.isEmpty {
                    return .legacyResetCorrupt(context: context, legacyOperationId: legacy, recordClass: recordClass, markerClass: markerClass)
                }
                if context == "inspect", keys == ["schemaVersion", "reason", "context", "recordClass", "markerClass"] {
                    return .legacyResetCorrupt(context: context, legacyOperationId: nil, recordClass: recordClass, markerClass: markerClass)
                }
                return .protocolAmbiguity
            case "LEGACY_RESET_MIGRATION_REQUIRED" where keys == ["schemaVersion", "reason", "legacyOperationId"]:
                guard let legacy = details["legacyOperationId"] as? String, !legacy.isEmpty else { return .protocolAmbiguity }
                return .legacyResetMigrationRequired(legacyOperationId: legacy)
            case "LEGACY_RESET_ALIAS_OCCUPIED" where keys == ["schemaVersion", "reason", "legacyOperationId", "migrationAlias"]:
                guard let legacy = details["legacyOperationId"] as? String, !legacy.isEmpty, let alias = details["migrationAlias"] as? String, !alias.isEmpty else { return .protocolAmbiguity }
                return .legacyResetAliasOccupied(legacyOperationId: legacy, migrationAlias: alias)
            case "CLIENT_UPGRADE_REQUIRED" where keys == ["schemaVersion", "reason", "requiredProtocol"]:
                guard let required = details["requiredProtocol"] as? String, !required.isEmpty else { return .protocolAmbiguity }
                return .clientUpgradeRequired(requiredProtocol: required)
            case "STALE_STATE" where keys.count == 2: return .staleState
            case "RESET_ACTIVE" where keys == ["schemaVersion", "reason", "operationId", "expectedTaskGenerationEpoch"]:
                guard let id = details["operationId"] as? String, !id.isEmpty, let epoch = TaskGenerationEpochStamp.safeInteger(details["expectedTaskGenerationEpoch"]) else { return .protocolAmbiguity }
                return .resetActive(operationId: id, expectedTaskGenerationEpoch: epoch)
            default: return .protocolAmbiguity
            }
        }
    }
}

// MARK: - Local cleanup authority and the exact awaiting marker (Reconciled 9; §5:543)

/// The authority every local cleanup callback takes. It exists only when a RESET
/// inspection is `pending` for the same canonical operation whose stored progress
/// receipt is `awaiting_local_reset`; nothing else constructs it.
struct ResetLocalCleanupAuthorityV1: Equatable, Sendable {
    let accountUid: String
    let operationId: String
    let requestFingerprint: String
    let expectedTaskGenerationEpoch: Int
    let taskGenerationEpoch: Int
    let activeMoveEventId: String
    let deletedCount: Int
    let deletedCounts: ResetDeletedCountsV1

    init?(inspection: ResetInspectionV1, progress: ResetReceiptV1) {
        guard inspection.outcome == .pending, progress.kind == .progress, progress.state == .awaitingLocalReset,
              inspection.accountUid == progress.accountUid, inspection.operationId == progress.operationId,
              inspection.requestFingerprint == TaskPlanService.ResetTransport.requestFingerprint(expectedTaskGenerationEpoch: progress.expectedTaskGenerationEpoch),
              inspection.identityDigest == TaskPlanService.ResetTransport.identityDigest(uid: progress.accountUid, expectedTaskGenerationEpoch: progress.expectedTaskGenerationEpoch) else { return nil }
        accountUid = progress.accountUid
        operationId = progress.operationId
        requestFingerprint = inspection.requestFingerprint
        expectedTaskGenerationEpoch = progress.expectedTaskGenerationEpoch
        taskGenerationEpoch = progress.taskGenerationEpoch
        activeMoveEventId = progress.activeMoveEventId
        deletedCount = progress.deletedCount
        deletedCounts = progress.deletedCounts
    }
}

enum ResetCleanupError: Error, Equatable {
    /// The user root does not carry the exact awaiting marker for the authority; nothing was written.
    case markerMismatch
    /// `RESET_LOCAL_GENERATION_INVALID`: a document carries no stamp outside the legacy 0→1 bridge; it is preserved and finalization is blocked.
    case localGenerationInvalid(path: String)
    /// The local dose v2 bytes are malformed: preserved, legacy keys untouched, finalization blocked (C9.5.16).
    case localDoseMalformed
    /// The local dose store is at a newer epoch than the authority's result epoch: preserved and reported (C9.5.16).
    case localDoseDrift(currentEpoch: Int)
}

/// Generation relation for one stamped document under the authority (C9.5.14): a stamp below the
/// result epoch is deletable, a stamp at or above it is preserved, and a missing stamp is legacy
/// zero only for the 0→1 bridge.
enum ResetStampDisposition: Equatable {
    case delete, preserve, invalid

    static func of(_ data: [String: Any]?, authority: ResetLocalCleanupAuthorityV1) -> ResetStampDisposition {
        guard let raw = data?[TaskGenerationEpochStamp.fieldName] else {
            return authority.expectedTaskGenerationEpoch == 0 && authority.taskGenerationEpoch == 1 ? .delete : .invalid
        }
        guard let stamp = TaskGenerationEpochStamp.safeInteger(raw) else { return .invalid }
        return stamp < authority.taskGenerationEpoch ? .delete : .preserve
    }
}

/// The `taskReset` marker of `users/{uid}` in its terminal `awaiting_local_reset`
/// projection (Reconciled 9): exact members, `targetIndex` 4, no cursor or lease,
/// `createdAt <= awaitingLocalResetAt <= updatedAt`, and every identity member equal
/// to the authority. The root's own `taskGenerationEpoch` must already be `r`.
enum ResetMarkerV1 {
    static let awaitingKeys: Set<String> = ["schemaVersion", "kind", "operationId", "requestFingerprint", "state", "expectedTaskGenerationEpoch", "taskGenerationEpoch", "activeMoveEventId", "targetIndex", "deletedCounts", "deletedCount", "createdAt", "updatedAt", "awaitingLocalResetAt"]

    static func matchesAwaiting(_ root: [String: Any]?, authority: ResetLocalCleanupAuthorityV1) -> Bool {
        guard let root, let marker = root["taskReset"] as? [String: Any], Set(marker.keys) == awaitingKeys,
              TaskGenerationEpochStamp.safeInteger(root[TaskGenerationEpochStamp.rootFieldName]) == authority.taskGenerationEpoch,
              TaskGenerationEpochStamp.safeInteger(marker["schemaVersion"]) == 1, marker["kind"] as? String == "reset",
              marker["operationId"] as? String == authority.operationId,
              marker["requestFingerprint"] as? String == authority.requestFingerprint,
              marker["state"] as? String == ResetReceiptState.awaitingLocalReset.rawValue,
              TaskGenerationEpochStamp.safeInteger(marker["expectedTaskGenerationEpoch"]) == authority.expectedTaskGenerationEpoch,
              TaskGenerationEpochStamp.safeInteger(marker["taskGenerationEpoch"]) == authority.taskGenerationEpoch,
              marker["activeMoveEventId"] as? String == authority.activeMoveEventId,
              TaskGenerationEpochStamp.safeInteger(marker["targetIndex"]) == 4,
              let counts = ResetDeletedCountsV1.decode(marker["deletedCounts"]), counts == authority.deletedCounts,
              let deletedCount = TaskGenerationEpochStamp.safeInteger(marker["deletedCount"]), deletedCount == authority.deletedCount, counts.sum == deletedCount,
              let createdAt = marker["createdAt"] as? Timestamp, let updatedAt = marker["updatedAt"] as? Timestamp,
              let awaitingAt = marker["awaitingLocalResetAt"] as? Timestamp else { return false }
        return createdAt.compare(awaitingAt) != .orderedDescending && awaitingAt.compare(updatedAt) != .orderedDescending
    }
}

/// Per-document exact-marker transactions through the Firestore-runtime seam:
/// each delete reads the owner root, requires the exact awaiting marker for the
/// authority, and deletes one document; a mismatch writes nothing.
enum ResetLocalCleanupV1 {
    static func deleteAssessments(authority: ResetLocalCleanupAuthorityV1) async throws {
        let firestore = try await FirestoreRuntime.provider.acquire().firestore
        let rootRef = firestore.collection("users").document(authority.accountUid)
        let documents = try await rootRef.collection("user_assessments").getDocuments().documents
        var invalid: String?
        for document in documents {
            let ref = document.reference
            let disposition: ResetStampDisposition = try await firestore.runTypedTransaction { transaction in
                let root = try transaction.getDocument(rootRef)
                guard ResetMarkerV1.matchesAwaiting(root.data(), authority: authority) else { throw ResetCleanupError.markerMismatch }
                let current = try transaction.getDocument(ref)
                guard current.exists else { return .preserve }
                let disposition = ResetStampDisposition.of(current.data(), authority: authority)
                if disposition == .delete { transaction.deleteDocument(ref) }
                return disposition
            }
            if disposition == .invalid, invalid == nil { invalid = ref.path }
        }
        if let invalid { throw ResetCleanupError.localGenerationInvalid(path: invalid) }
    }

    static func deleteUserKnowledge(authority: ResetLocalCleanupAuthorityV1) async throws {
        let firestore = try await FirestoreRuntime.provider.acquire().firestore
        let rootRef = firestore.collection("users").document(authority.accountUid)
        let ref = firestore.collection("userKnowledge").document(authority.accountUid)
        let disposition: ResetStampDisposition = try await firestore.runTypedTransaction { transaction in
            let root = try transaction.getDocument(rootRef)
            guard ResetMarkerV1.matchesAwaiting(root.data(), authority: authority) else { throw ResetCleanupError.markerMismatch }
            let current = try transaction.getDocument(ref)
            guard current.exists else { return .preserve }
            let disposition = ResetStampDisposition.of(current.data(), authority: authority)
            if disposition == .delete { transaction.deleteDocument(ref) }
            return disposition
        }
        if disposition == .invalid { throw ResetCleanupError.localGenerationInvalid(path: ref.path) }
    }
}

// MARK: - Drive reducer (§5 phase table; C2.8 receipts; trace resetDispatch,inspect,…,finalize)

/// The three cleanup callbacks; each takes the authority and nothing else.
struct ResetCleanupCallbacks: Sendable {
    let deleteAssessments: @Sendable (ResetLocalCleanupAuthorityV1) async throws -> Void
    let deleteUserKnowledge: @Sendable (ResetLocalCleanupAuthorityV1) async throws -> Void
    let resetDose: @Sendable (ResetLocalCleanupAuthorityV1) async throws -> Void
}

struct ResetDriveOutcome: Equatable, Sendable {
    let finalReceipt: ResetReceiptV1
    /// `true` when the final receipt was replayed (a committed inspection or a
    /// replayed finalize).
    let replayed: Bool
    /// `true` only for the invocation that itself stored the first `reset_final`
    /// with `replayed:false` and committed `final_receipt → applying`; a row loaded
    /// at `final_receipt` or `applying` never yields it (at-most-once notification).
    let notify: Bool
}

enum ResetDriveError: Error, Equatable {
    case rowMissing(handleId: String)
    /// The canonical record is absent while a progress receipt is held; the row stays for `retry_reset`.
    case inspectionAbsent(operationId: String)
    /// A wire disagreed with the row's stored identity; the row is untouched.
    case receiptMismatch(detail: String)
    case stepBudgetExceeded
}

extension ResetOperationRegistry {
    private static let driveStepBudget = 16

    /// Drives one row to its final receipt and retires it. Entry reads fresh signed
    /// auth for the handle's UID; a drive already in flight for the handle is joined
    /// (outcome only, no callbacks) when the UID/auth epoch match and the credential
    /// revision is at or above the baseline; a foreign caller waits for the slot,
    /// discards its result, rereads auth, and restarts.
    func drive(handle: ResetOperationHandle, remote: any ResetRemoteProviding, cleanup: ResetCleanupCallbacks) async throws -> ResetDriveOutcome {
        // the nonthrowing read: a signed-out caller is still a foreign caller of an occupied slot (C9.5.8) and must wait
        let authority = await auth.currentSignedAuth()
        if let slot = inflightResetOperation[handle] {
            // an occupied slot is consulted before the handle is judged: a foreign caller (different account, epoch,
            // or signed out) waits for slot retirement, discards the prior result, rereads auth, and restarts
            if case let .signedIn(tuple) = authority, slot.uid == tuple.uid, slot.authEpochUUID == tuple.authEpochUUID {
                guard tuple.credentialRevision >= slot.credentialBaseline else { throw RegistryError.credentialRevisionRegressed }
                // post-task reread: every joiner rereads signed auth after the task settles (outcome or error) and
                // exposes the outcome only when UID/epoch match and the revision is at or above the baseline
                let settled = await slot.task.result
                let again = try await signedAuth()
                guard again.uid == slot.uid, again.authEpochUUID == slot.authEpochUUID, again.credentialRevision >= slot.credentialBaseline else { throw RegistryError.authRequired }
                let outcome = try settled.get()
                // C9.5.17: only the winner's invocation notifies
                return ResetDriveOutcome(finalReceipt: outcome.finalReceipt, replayed: outcome.replayed, notify: false)
            }
            _ = try? await slot.task.value
            await Task.yield()
            return try await drive(handle: handle, remote: remote, cleanup: cleanup)
        }
        guard case let .signedIn(tuple) = authority else { throw RegistryError.authRequired }
        guard tuple.uid == handle.uid else { throw RegistryError.operationStale(uid: handle.uid, handleId: handle.handleId) }
        let task = Task { try await self.runDrive(handle: handle, remote: remote, cleanup: cleanup, baseline: tuple) }
        inflightResetOperation[handle] = (uid: tuple.uid, authEpochUUID: tuple.authEpochUUID, credentialBaseline: tuple.credentialRevision, task: task)
        defer { inflightResetOperation[handle] = nil }
        return try await task.value
    }

    /// The winner revalidates signed auth after every suspension and before every
    /// server call, protected callback, and return: a different UID or auth epoch or
    /// signed-out state preserves the durable phase and returns the frozen auth
    /// branch; a lower same-epoch revision is corruption; a higher one rebases.
    private func revalidated(_ baseline: SignedAuthTuple) async throws -> SignedAuthTuple {
        let now = try await signedAuth()
        guard now.uid == baseline.uid, now.authEpochUUID == baseline.authEpochUUID else { throw RegistryError.authRequired }
        guard now.credentialRevision >= baseline.credentialRevision else { throw RegistryError.credentialRevisionRegressed }
        return now
    }

    /// The reducer. Each remote dispatch is recorded durably before its await; after
    /// every await the auth is revalidated and the envelope reread. Before each cleanup
    /// callback and before finalize the canonical record is inspected: `pending`
    /// yields the callback's authority, `committed` short-circuits to the replayed
    /// final receipt with no further callback, `absent` stops with the row intact.
    /// After a callback error the record is re-inspected: committed adopts the final
    /// receipt; a byte-identical pending authority retains the phase and rethrows;
    /// anything else blocks.
    private func runDrive(handle: ResetOperationHandle, remote: any ResetRemoteProviding, cleanup: ResetCleanupCallbacks, baseline: SignedAuthTuple) async throws -> ResetDriveOutcome {
        var auth = baseline
        var storedFreshFinal = false
        for _ in 0..<Self.driveStepBudget {
            // before every server call, callback, or return: the task hop and each earlier await are suspensions
            auth = try await revalidated(auth)
            var row = try currentRow(handle)
            switch row.phase {
            case .prepared, .resetDispatched, .resetReceiptDeleting:
                if row.phase != .resetReceiptDeleting {
                    row.phase = .resetDispatched
                    try store(row)
                }
                let receipt = try await remote.reset(.resetAllTasks, alias: row.suggestedOperationId, expectedTaskGenerationEpoch: row.expectedTaskGenerationEpoch)
                auth = try await revalidated(auth)
                try Self.requireIdentity(receipt, row: row)
                row = try currentRow(handle)
                row.canonicalOperationId = receipt.operationId
                switch receipt.kind {
                case .progress:
                    row.progressReceipt = receipt.canonicalData()
                    row.phase = receipt.state == .deleting ? .resetReceiptDeleting : .resetReceiptAwaitingLocalReset
                case .final:
                    row.finalReceipt = receipt.canonicalData()
                    row.phase = .finalReceipt
                    storedFreshFinal = !receipt.replayed
                }
                try store(row)
            case .resetReceiptAwaitingLocalReset:
                guard let canonical = row.canonicalOperationId, let bytes = row.progressReceipt, let progress = ResetReceiptV1.decode(data: bytes),
                      progress.state == .awaitingLocalReset else { throw ResetDriveError.receiptMismatch(detail: "progress") }
                let steps: [(String, @Sendable (ResetLocalCleanupAuthorityV1) async throws -> Void)] = [
                    ("deleteAssessments", cleanup.deleteAssessments), ("deleteUserKnowledge", cleanup.deleteUserKnowledge), ("resetDose", cleanup.resetDose)
                ]
                var shortCircuited = false
                for (_, callback) in steps {
                    let inspection = try await remote.inspectReset(uid: row.uid, canonicalOperationId: canonical, expectedTaskGenerationEpoch: row.expectedTaskGenerationEpoch)
                    auth = try await revalidated(auth)
                    if try adoptCommitted(inspection, handle: handle) { shortCircuited = true; break }
                    guard let authority = ResetLocalCleanupAuthorityV1(inspection: inspection, progress: progress) else { throw ResetDriveError.receiptMismatch(detail: "authority") }
                    do {
                        try await callback(authority)
                        auth = try await revalidated(auth)
                    } catch let callbackError {
                        auth = try await revalidated(auth)
                        let again = try await remote.inspectReset(uid: row.uid, canonicalOperationId: canonical, expectedTaskGenerationEpoch: row.expectedTaskGenerationEpoch)
                        auth = try await revalidated(auth)
                        if try adoptCommitted(again, handle: handle) { shortCircuited = true; break }
                        guard let retained = ResetLocalCleanupAuthorityV1(inspection: again, progress: progress), retained == authority else {
                            throw ResetDriveError.receiptMismatch(detail: "post-error inspection")
                        }
                        throw callbackError
                    }
                }
                if shortCircuited { continue }
                let inspection = try await remote.inspectReset(uid: row.uid, canonicalOperationId: canonical, expectedTaskGenerationEpoch: row.expectedTaskGenerationEpoch)
                auth = try await revalidated(auth)
                if try adoptCommitted(inspection, handle: handle) { continue }
                guard ResetLocalCleanupAuthorityV1(inspection: inspection, progress: progress) != nil else { throw ResetDriveError.receiptMismatch(detail: "authority") }
                row = try currentRow(handle)
                row.phase = .finalizeDispatched
                try store(row)
            case .finalizeDispatched:
                let receipt = try await remote.reset(.finalizeTaskReset, alias: row.suggestedOperationId, expectedTaskGenerationEpoch: row.expectedTaskGenerationEpoch)
                auth = try await revalidated(auth)
                try Self.requireIdentity(receipt, row: row)
                guard receipt.kind == .final else { throw ResetDriveError.receiptMismatch(detail: "finalize") }
                row = try currentRow(handle)
                row.finalReceipt = receipt.canonicalData()
                row.phase = .finalReceipt
                storedFreshFinal = !receipt.replayed
                try store(row)
            case .finalReceipt:
                row.phase = .applying
                try store(row)
            case .applying:
                guard let bytes = row.finalReceipt, let final = ResetReceiptV1.decode(data: bytes), final.kind == .final else { throw ResetDriveError.receiptMismatch(detail: "final") }
                try remove(handle)
                return ResetDriveOutcome(finalReceipt: final, replayed: final.replayed, notify: storedFreshFinal && !final.replayed)
            }
        }
        throw ResetDriveError.stepBudgetExceeded
    }

    // Row access: every helper rereads the envelope so post-await state is never stale.

    private func currentRow(_ handle: ResetOperationHandle) throws -> ResetOperationRegistryRecordV2 {
        guard let envelope = try read(), let row = envelope.records.first(where: { $0.uid == handle.uid && $0.handleId == handle.handleId }) else {
            throw ResetDriveError.rowMissing(handleId: handle.handleId)
        }
        return row
    }

    private func store(_ row: ResetOperationRegistryRecordV2) throws {
        guard var envelope = try read(), let index = envelope.records.firstIndex(where: { $0.uid == row.uid && $0.handleId == row.handleId }) else {
            throw ResetDriveError.rowMissing(handleId: row.handleId)
        }
        var next = row
        next.updatedAt = try writeTime(advancing: [row.updatedAt])
        envelope.records[index] = next
        try write(&envelope)
    }

    private func remove(_ handle: ResetOperationHandle) throws {
        guard var envelope = try read(), let index = envelope.records.firstIndex(where: { $0.uid == handle.uid && $0.handleId == handle.handleId }) else {
            throw ResetDriveError.rowMissing(handleId: handle.handleId)
        }
        envelope.records.remove(at: index)
        try write(&envelope)
    }

    /// A `committed` inspection adopts its replayed final receipt; `absent` stops.
    private func adoptCommitted(_ inspection: ResetInspectionV1, handle: ResetOperationHandle) throws -> Bool {
        switch inspection.outcome {
        case .pending: return false
        case .absent: throw ResetDriveError.inspectionAbsent(operationId: inspection.operationId)
        case .committed:
            guard let receipt = inspection.receipt else { throw ResetDriveError.receiptMismatch(detail: "committed") }
            var row = try currentRow(handle)
            try Self.requireIdentity(receipt, row: row)
            row.canonicalOperationId = receipt.operationId
            row.finalReceipt = receipt.canonicalData()
            row.phase = .finalReceipt
            try store(row)
            return true
        }
    }

    private static func requireIdentity(_ receipt: ResetReceiptV1, row: ResetOperationRegistryRecordV2) throws {
        guard receipt.accountUid == row.uid, receipt.expectedTaskGenerationEpoch == row.expectedTaskGenerationEpoch,
              row.canonicalOperationId == nil || row.canonicalOperationId == receipt.operationId else { throw ResetDriveError.receiptMismatch(detail: "identity") }
    }
}

// MARK: - Epoch-conflict recovery (§5; BlockedSnapshot.resetEpochConflict → recover_epoch)

/// The protected callback bundle a recovery action drives with; wired by the
/// coordinator's owner and never by a view.
struct ResetRecoveryBundle: Sendable {
    let remote: any ResetRemoteProviding
    let cleanup: ResetCleanupCallbacks
}

extension ResetOperationRegistry: ResetEpochConflictRecovering {
    /// Accepts only the current conflict digest, the actionable (lowest) epoch,
    /// and that row's exact phase and recovery action, then runs that row's own
    /// reducer branch (`drive`) and never touches another occupant. Completion
    /// reclassifies: the next-minimum conflict, `ready`, or the blocked snapshot.
    /// An identical in-flight call coalesces; a different one is `busy`, decided
    /// synchronously before any suspension so the slot cannot be claimed twice.
    func recoverEpoch(recoveryStateDigest: String, expectedTaskGenerationEpoch: Int, expectedPhase: ResetRowPhase, action: ResetRecoveryAction) async -> RecoveryResult {
        let key = "\(recoveryStateDigest)|\(expectedTaskGenerationEpoch)|\(expectedPhase.rawValue)|\(action.rawValue)"
        if let slot = recoverySlot {
            return slot.key == key ? await slot.task.value : .busy(store: .reset)
        }
        let task = Task {
            await self.performRecovery(recoveryStateDigest: recoveryStateDigest, expectedTaskGenerationEpoch: expectedTaskGenerationEpoch, expectedPhase: expectedPhase, action: action)
        }
        recoverySlot = (key: key, task: task)
        defer { recoverySlot = nil }
        return await task.value
    }

    private func performRecovery(recoveryStateDigest: String, expectedTaskGenerationEpoch: Int, expectedPhase: ResetRowPhase, action: ResetRecoveryAction) async -> RecoveryResult {
        guard case let .blocked(snapshot) = await classification() else { return .ready }
        guard case let .resetEpochConflict(digest, actionable, occupants) = snapshot else { return .blocked(snapshot) }
        guard digest == recoveryStateDigest else { return .blocked(snapshot) }
        guard expectedTaskGenerationEpoch == actionable,
              let target = occupants.first(where: { $0.expectedTaskGenerationEpoch == actionable }),
              target.phase == expectedPhase, target.recoveryAction == action else { return .unavailable(store: .reset) }
        guard let bundle = recoveryBundle else { return .unavailable(store: .reset) }
        guard case let .signedIn(tuple) = await auth.currentSignedAuth(),
              let row = (try? read())?.records.first(where: { $0.uid == tuple.uid && $0.expectedTaskGenerationEpoch == actionable }),
              row.phase == expectedPhase else { return .unavailable(store: .reset) }
        do {
            _ = try await drive(handle: ResetOperationHandle(uid: row.uid, handleId: row.handleId), remote: bundle.remote, cleanup: bundle.cleanup)
        } catch {
            // The row keeps its phase; the caller reclassifies and may retry the same action.
        }
        switch await classification() {
        case .ready: return .ready
        case let .blocked(next): return .blocked(next)
        }
    }

    /// Owner wiring (S7): the bundle every recovery action drives with.
    func attachRecovery(_ bundle: ResetRecoveryBundle) { recoveryBundle = bundle }
}

// MARK: - S4: `DurableStoreRecovering` conformance of the reset store (S4-CD2/S4-CD5; C9.7.2–C9.7.6, C9.7.8, C9.7.12)

extension ResetOperationRegistry: DurableStoreRecovering {
    fileprivate struct QuarantineCandidates {
        let records: [ResetOperationRegistryRecordV2]
        let migrations: [[String: Any]]
        let gesture: ResetGestureV1?
        /// records + legacy-migration elements + 1 when a gesture is present (C9.7.6 counted universe).
        let rawCount: Int
        /// Every candidate complete, identity-unique, within caps (C9.7.6 unresolved is any failure).
        let allValid: Bool
    }

    private static var cap: Int { DurableFileKind.taskPlanResetV2.storeCap }

    /// Enumerability (C9.7.5) and the counted universe (C9.7.6) of quarantine bytes, with candidate validity.
    fileprivate static func enumerate(_ bytes: Data) -> (enumerable: Bool, candidates: QuarantineCandidates?) {
        guard let object = JSONObjectScanner.object(bytes), let payload = object["payload"] as? [String: Any],
              let rawRecords = payload["records"] as? [Any], let rawMigrations = payload["legacyMigrations"] as? [Any] else { return (false, nil) }
        let gesturePresent = payload["gesture"] != nil
        if gesturePresent, !(payload["gesture"] is [String: Any]) { return (false, nil) }
        let records = rawRecords.compactMap { ($0 as? [String: Any]).flatMap(ResetOperationRegistryRecordV2.from) }
        let migrations = rawMigrations.compactMap { $0 as? [String: Any] }
        var gesture: ResetGestureV1?
        var gestureValid = true
        if gesturePresent { gesture = (payload["gesture"] as? [String: Any]).flatMap(ResetGestureV1.from); gestureValid = gesture != nil }
        let uniqueRows = Set(records.map { "\($0.uid)|\($0.expectedTaskGenerationEpoch)" }).count == records.count
        let migrationUIDs = migrations.compactMap { $0["uid"] as? String }
        let uniqueMigrations = migrationUIDs.count == migrations.count && Set(migrationUIDs).count == migrations.count
        let allValid = records.count == rawRecords.count && migrations.count == rawMigrations.count && gestureValid && uniqueRows && uniqueMigrations
            && records.count <= capacity && migrations.count <= capacity
        let rawCount = rawRecords.count + rawMigrations.count + (gesturePresent ? 1 : 0)
        return (true, QuarantineCandidates(records: records, migrations: migrations, gesture: gesture, rawCount: rawCount, allValid: allValid))
    }

    func observe() async -> RecoveryObservation {
        var tuple: SignedAuthTuple?
        if case let .signedIn(signed) = await auth.currentSignedAuth() { tuple = signed }
        currentProvenanceAuth(tuple)
        return observeFiles(tuple: tuple)
    }

    /// The C9.7.3 order over the reset store's two files.
    private func observeFiles(tuple: SignedAuthTuple?) -> RecoveryObservation {
        func unavailable(_ code: StorageIOErrorCode) -> RecoveryObservation { .unavailable(UnavailableToken(store: .reset, state: "storage_io_unavailable", errorCode: code.rawValue)) }
        var target: DurableFileObserver.Read
        var quarantine: DurableFileObserver.Read
        do { target = try targetRead(); quarantine = try quarantineRead() } catch let failure as PrivacyDurableFile.Failure { return unavailable(failure.code) } catch { return unavailable(.fileReadFailed) }
        // a malformed (or over-cap) target beside no quarantine is renamed to the fixed sibling at once, directory fsync
        if case .absent = quarantine.observation, target.bytes != nil || target.identity != nil, !Self.isValid(target.observation) {
            do { try PrivacyDurableFile.rename(fileURL, to: quarantineURL) } catch let failure as PrivacyDurableFile.Failure { return unavailable(failure.code) } catch { return unavailable(.fileRenameFailed) }
            do { target = try targetRead(); quarantine = try quarantineRead() } catch let failure as PrivacyDurableFile.Failure { return unavailable(failure.code) } catch { return unavailable(.fileReadFailed) }
        }
        let targetValid = Self.isValid(target.observation)
        let quarantinePresent: Bool = { if case .absent = quarantine.observation { return false }; return true }()
        var enumerable = false
        var candidates: QuarantineCandidates?
        if let bytes = quarantine.bytes { (enumerable, candidates) = Self.enumerate(bytes) }
        let count = enumerable ? candidates?.rawCount : nil
        let quarantineSHA: String? = {
            switch quarantine.observation {
            case let .valid(_, sha, _, _), let .malformed(_, sha): return sha
            default: return nil
            }
        }()
        func files(_ base: String, _ actions: [String], auth: SignedAuthTuple? = nil, mismatch: String? = nil, occupants: [ResetEpochOccupant]? = nil) -> RecoveryObservation {
            .observed(.files(store: .reset, baseState: base, target: target.observation, quarantine: quarantine.observation, availableActions: actions,
                             auth: auth, mismatchIdentityDigest: mismatch, quarantineEnumerable: enumerable, pendingRecordCount: count, epochOccupants: occupants))
        }
        // step 3: a valid target whose receipt names the quarantine's digest and counts
        if targetValid, quarantinePresent, let receipt = targetReceipt(), let sha = quarantineSHA, receipt.quarantineSHA256 == sha, enumerable, let raw = count,
           receipt.recoveredCount + receipt.droppedCount == raw {
            return files("recovered_pending_cleanup", ["retry_cleanup"])
        }
        // step 5: structural
        if quarantinePresent {
            let recoverable = enumerable && (candidates?.allValid ?? false)
            switch target.observation {
            case .absent:
                return files("quarantined", recoverable ? ["recover", "discard_quarantine"] : ["discard_quarantine"])
            case .malformed, .overCap:
                var targetEmpty = false
                if let bytes = target.bytes { let parsed = Self.enumerate(bytes); if parsed.enumerable, parsed.candidates?.rawCount == 0 { targetEmpty = true } }
                return files("collision", recoverable && targetEmpty ? ["recover", "discard_quarantine"] : ["discard_quarantine"])
            case .valid:
                var mergeable = recoverable
                if mergeable, let live = liveEnvelope(), let cands = candidates {
                    for row in cands.records {
                        if let existing = live.records.first(where: { $0.uid == row.uid && $0.expectedTaskGenerationEpoch == row.expectedTaskGenerationEpoch }), existing != row { mergeable = false }
                    }
                    if let gesture = cands.gesture, let live = live.gesture, gesture != live { mergeable = false }
                    if Self.merged(live, cands).records.count > Self.capacity || Self.merged(live, cands).migrations.count > Self.capacity { mergeable = false }
                }
                return files("quarantine_conflict", mergeable ? ["merge", "discard_quarantine"] : ["discard_quarantine"])
            }
        }
        guard targetValid, let tuple, let live = liveEnvelope() else { return files("ready", []) }
        // step 6: the first current-auth receipt-bearing row lacking or disagreeing with live provenance
        for row in live.records where row.uid == tuple.uid && (row.progressReceipt != nil || row.finalReceipt != nil) {
            let identity = Self.identityDigest(uid: row.uid, expectedTaskGenerationEpoch: row.expectedTaskGenerationEpoch)
            if provenance(for: identity) != Self.receiptSHA256(row) { return files("receipt_mismatch", ["reconcile"], auth: tuple, mismatch: identity) }
        }
        // step 7: the current UID's epoch conflict
        let mine = live.records.filter { $0.uid == tuple.uid }
        if mine.count > 1 { return files("reset_epoch_conflict", ["recover_epoch"], auth: tuple, occupants: Self.epochOccupants(mine)) }
        return files("ready", [])
    }

    private static func isValid(_ observation: FileObservationV1) -> Bool { if case .valid = observation { return true }; return false }

    /// `{kind:"reset",uid,expectedTaskGenerationEpoch}` (C9.7.8 identity map).
    static func identityDigest(uid: String, expectedTaskGenerationEpoch: Int) -> String {
        TaskCanonicalV1.sha256Hex(["kind": "reset", "uid": uid, "expectedTaskGenerationEpoch": expectedTaskGenerationEpoch])
    }

    private static func receiptSHA256(_ row: ResetOperationRegistryRecordV2) -> String {
        TaskCanonicalV1.sha256Hex(data: row.finalReceipt ?? row.progressReceipt ?? Data())
    }

    /// Live rows plus valid quarantine rows (same key byte-equal: no insertion; the live gesture is never replaced).
    fileprivate static func merged(_ live: Envelope, _ candidates: QuarantineCandidates) -> (records: [ResetOperationRegistryRecordV2], migrations: [[String: Any]], gesture: ResetGestureV1?, recovered: Int) {
        var records = live.records
        var migrations = live.migrations
        var gesture = live.gesture
        var recovered = 0
        for row in candidates.records {
            if !records.contains(where: { $0.uid == row.uid && $0.expectedTaskGenerationEpoch == row.expectedTaskGenerationEpoch }) { records.append(row) }
            recovered += 1
        }
        for migration in candidates.migrations {
            if !migrations.contains(where: { ($0["uid"] as? String) == (migration["uid"] as? String) }) { migrations.append(migration) }
            recovered += 1
        }
        if let candidate = candidates.gesture { if gesture == nil { gesture = candidate }; recovered += 1 }
        return (sorted(records), migrations, gesture, recovered)
    }

    nonisolated func classify(_ observation: RecoveryObservation) -> RecoveryClassification {
        switch observation {
        case let .unavailable(token):
            return .blocked(.storageIOUnavailable(store: .reset, errorCode: StorageIOErrorCode(rawValue: token.errorCode) ?? .fileReadFailed))
        case let .observed(state):
            guard case let .files(_, base, _, _, actions, _, _, _, mismatch, _, count, occupants) = state else { return .ready }
            let digest = state.recoveryStateDigest
            // S1's snapshot derives its action list from `quarantineEnumerable`; the precedence fallback (enumerable but
            // unrecoverable) therefore reports `false` and no count so the displayed actions stay exact.
            let recoverable = actions.contains("recover") || actions.contains("merge")
            switch base {
            case "quarantined": return .blocked(.quarantined(store: .reset, recoveryStateDigest: digest, quarantineEnumerable: recoverable, pendingRecordCount: recoverable ? count : nil))
            case "collision": return .blocked(.collision(store: .reset, recoveryStateDigest: digest, quarantineEnumerable: recoverable, pendingRecordCount: recoverable ? count : nil))
            case "recovered_pending_cleanup": return .blocked(.recoveredPendingCleanup(store: .reset, recoveryStateDigest: digest))
            case "quarantine_conflict": return .blocked(.quarantineConflict(store: .reset, recoveryStateDigest: digest, quarantineEnumerable: recoverable, pendingRecordCount: recoverable ? count : nil))
            case "receipt_mismatch": return .blocked(.receiptMismatch(store: .reset, recoveryStateDigest: digest, mismatchIdentityDigest: mismatch ?? ""))
            case "reset_epoch_conflict":
                let occupants = occupants ?? []
                return .blocked(.resetEpochConflict(recoveryStateDigest: digest, actionableExpectedTaskGenerationEpoch: occupants.map(\.expectedTaskGenerationEpoch).min() ?? 0, occupants: occupants))
            default: return .ready
            }
        }
    }

    func perform(_ action: RecoveryAction, expecting expectation: RecoveryExpectation) async -> RecoveryResult {
        guard let key = action.attemptKey(expecting: expectation) else { return .unavailable(store: .reset) }
        switch action {
        case .recover, .discardQuarantine, .retryCleanup, .merge, .reconcile, .retry: break
        default: return .unavailable(store: .reset)
        }
        let keyString = String(decoding: TaskCanonicalV1.data(key.canonical) ?? Data(), as: UTF8.self)
        if let slot { return slot.key == keyString ? await slot.task.value : .busy(store: .reset) }
        let task = Task { await self.performRecovery(action, key: key) }
        slot = (keyString, task)
        defer { slot = nil }
        return await task.value
    }

    private static func result(_ classification: RecoveryClassification) -> RecoveryResult {
        switch classification {
        case .ready: return .ready
        case let .blocked(snapshot): return .blocked(snapshot)
        }
    }

    private func reclassified() async -> RecoveryResult { Self.result(classify(await observe())) }

    private func performRecovery(_ action: RecoveryAction, key: RecoveryAttemptKey) async -> RecoveryResult {
        let current = await observe()
        // pre-call whole-state CAS (C9.7.12): drift returns the complete current classification with zero call/write
        if case let .unavailable(_, state, errorCode, _) = key {
            guard case let .unavailable(token) = current, token.state == state, token.errorCode == errorCode else { return Self.result(classify(current)) }
            if errorCode == StorageIOErrorCode.directoryFsyncFailed.rawValue { try? PrivacyDurableFile.syncDirectory(directory) }
            return await reclassified()
        }
        guard case let .observed(state) = current, case let .files(_, base, targetObservation, quarantineObservation, actions, _, _, _, mismatch, _, _, _) = state,
              let expected = Self.digest(of: key), state.recoveryStateDigest == expected else { return Self.result(classify(current)) }
        guard actions.contains(action.name) else { return .unavailable(store: .reset) }
        switch action {
        case .discardQuarantine:
            guard DurableFileObserver.matches(quarantineObservation, at: quarantineURL, cap: Self.cap) else { return await reclassified() }
            try? PrivacyDurableFile.unlink(at: quarantineURL)
        case .retryCleanup:
            guard base == "recovered_pending_cleanup", DurableFileObserver.matches(targetObservation, at: fileURL, cap: Self.cap),
                  DurableFileObserver.matches(quarantineObservation, at: quarantineURL, cap: Self.cap) else { return await reclassified() }
            try? PrivacyDurableFile.unlink(at: quarantineURL)
        case .recover, .merge:
            guard DurableFileObserver.matches(quarantineObservation, at: quarantineURL, cap: Self.cap),
                  let bytes = try? PrivacyDurableFile.observe(at: quarantineURL, limit: Self.cap)?.bytes else { return await reclassified() }
            let parsed = Self.enumerate(bytes)
            guard parsed.enumerable, let candidates = parsed.candidates, candidates.allValid else { return await reclassified() }
            let live: Envelope = (action == .merge ? liveEnvelope() : nil) ?? Envelope(generationId: "", sha256: "", records: [], migrations: [], gesture: nil)
            let merged = Self.merged(live, candidates)
            guard merged.records.count <= Self.capacity, merged.migrations.count <= Self.capacity else { return await reclassified() }
            let receipt: [String: Any] = ["schemaVersion": 1, "quarantineSHA256": TaskCanonicalV1.sha256Hex(data: bytes), "recoveredCount": merged.recovered, "droppedCount": 0]
            do { _ = try writeRecovered(Envelope(generationId: "", sha256: "", records: merged.records, migrations: merged.migrations, gesture: merged.gesture), receipt: receipt) } catch { return await reclassified() }
            // durability barrier passed; a crash before this unlink reloads as `recovered_pending_cleanup`
            try? PrivacyDurableFile.unlink(at: quarantineURL)
        case let .reconcile(identity):
            guard base == "receipt_mismatch", mismatch == identity, let remote = bundleRemote, let live = liveEnvelope(),
                  case .signedIn(let tuple) = await auth.currentSignedAuth(),
                  let row = live.records.first(where: { $0.uid == tuple.uid && (($0.progressReceipt != nil) || ($0.finalReceipt != nil)) && Self.identityDigest(uid: $0.uid, expectedTaskGenerationEpoch: $0.expectedTaskGenerationEpoch) == identity }),
                  let operationId = row.canonicalOperationId else { return .unavailable(store: .reset) }
            let inspection: ResetInspectionV1
            do { inspection = try await remote.inspectReset(uid: row.uid, canonicalOperationId: operationId, expectedTaskGenerationEpoch: row.expectedTaskGenerationEpoch) } catch { return Self.result(classify(current)) }
            // post-await: auth, observed state, and the first mismatch are recomputed before any write
            let after = await observe()
            guard case let .observed(afterState) = after, afterState.recoveryStateDigest == expected else { return Self.result(classify(after)) }
            var next = row
            switch inspection.outcome {
            case .committed:
                guard let receipt = inspection.receipt, receipt.accountUid == row.uid, receipt.expectedTaskGenerationEpoch == row.expectedTaskGenerationEpoch, receipt.operationId == operationId,
                      let data = receipt.canonicalData(), data.count <= ResetOperationRegistryRecordV2.receiptCap else { return Self.result(classify(after)) }
                next.finalReceipt = data
                next.phase = .finalReceipt
                do { try store(next) } catch { return await reclassified() }
                installProvenance(identityDigest: identity, receiptSHA256: TaskCanonicalV1.sha256Hex(data: data))
            case .absent, .pending:
                next.progressReceipt = nil
                next.finalReceipt = nil
                next.applicationId = nil
                next.canonicalOperationId = nil
                next.phase = .resetDispatched
                do { try store(next) } catch { return await reclassified() }
            }
        default:
            return .unavailable(store: .reset)
        }
        return await reclassified()
    }

    private static func digest(of key: RecoveryAttemptKey) -> String? {
        switch key {
        case let .recover(d), let .merge(d), let .discard(d), let .cleanup(d), let .foreignReconcile(d), let .doseQuarantine(d), let .receiptReconcile(d, _), let .resolveForeign(d, _, _), let .recoverEpoch(d, _, _, _): return d
        case .unavailable: return nil
        }
    }
}

// MARK: - S4: C9.4.5 client per-UID legacy migration rows (S4-CD2 scope: the rows inside `ResetOperationRegistry`)

enum LegacyMigrationErrorCode: String, CaseIterable, Sendable, Equatable {
    case legacyResetCorrupt = "LEGACY_RESET_CORRUPT"
    case operationReused = "OPERATION_REUSED"
    case aliasCollisionExhausted = "LEGACY_ALIAS_COLLISION_EXHAUSTED"
    case aliasInvalid = "LEGACY_ALIAS_INVALID"
}

enum LegacyValueClass: String, CaseIterable, Sendable, Equatable {
    case nonString = "non_string"
    case invalidString = "invalid_string"
}

/// `{kind:"absent"} | {kind:"valid_string",value} | {kind:"invalid_value",valueClass,utf8Length?,sha256?}`; immutable per row.
enum LegacyKeyGuard: Equatable, Sendable {
    case absent
    case validString(value: String)
    case invalidValue(valueClass: LegacyValueClass, utf8Length: Int?, sha256: String?)

    func map() -> [String: Any] {
        switch self {
        case .absent: return ["kind": "absent"]
        case let .validString(value): return ["kind": "valid_string", "value": value]
        case let .invalidValue(valueClass, length, sha):
            var map: [String: Any] = ["kind": "invalid_value", "valueClass": valueClass.rawValue]
            if let length { map["utf8Length"] = length }
            if let sha { map["sha256"] = sha }
            return map
        }
    }

    static func from(_ map: [String: Any]) -> LegacyKeyGuard? {
        switch map["kind"] as? String {
        case "absent": return Set(map.keys) == ["kind"] ? .absent : nil
        case "valid_string":
            guard Set(map.keys) == ["kind", "value"], let value = map["value"] as? String, LegacyResetMigrationV1.isValidLegacyOperationId(value) else { return nil }
            return .validString(value: value)
        case "invalid_value":
            guard let valueClass = (map["valueClass"] as? String).flatMap(LegacyValueClass.init(rawValue:)) else { return nil }
            let keys = Set(map.keys)
            switch valueClass {
            case .nonString:
                return keys == ["kind", "valueClass"] ? .invalidValue(valueClass: .nonString, utf8Length: nil, sha256: nil) : nil
            case .invalidString:
                guard keys == ["kind", "valueClass", "utf8Length", "sha256"], let length = TaskGenerationEpochStamp.safeInteger(map["utf8Length"]),
                      let sha = map["sha256"] as? String, sha.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else { return nil }
                return .invalidValue(valueClass: .invalidString, utf8Length: length, sha256: sha)
            }
        default: return nil
        }
    }
}

/// `{kind:"reserved_gesture",gestureId,gestureGeneration,alias} | {kind:"reset_dispatched",expectedTaskGenerationEpoch,suggestedOperationId}`.
enum LegacyInitiatingAuthority: Equatable, Sendable {
    case reservedGesture(gestureId: String, gestureGeneration: String, alias: String)
    case resetDispatched(expectedTaskGenerationEpoch: Int, suggestedOperationId: String)

    /// The alias the materialized row keeps (C9.4.5 materialization alias).
    var alias: String {
        switch self {
        case let .reservedGesture(_, _, alias): return alias
        case let .resetDispatched(_, suggested): return suggested
        }
    }

    func map() -> [String: Any] {
        switch self {
        case let .reservedGesture(gestureId, generation, alias): return ["kind": "reserved_gesture", "gestureId": gestureId, "gestureGeneration": generation, "alias": alias]
        case let .resetDispatched(epoch, suggested): return ["kind": "reset_dispatched", "expectedTaskGenerationEpoch": epoch, "suggestedOperationId": suggested]
        }
    }

    static func from(_ map: [String: Any]) -> LegacyInitiatingAuthority? {
        switch map["kind"] as? String {
        case "reserved_gesture":
            guard Set(map.keys) == ["kind", "gestureId", "gestureGeneration", "alias"], let gestureId = map["gestureId"] as? String, ResetOperationRegistry.isGestureId(gestureId),
                  let generation = map["gestureGeneration"] as? String, !generation.isEmpty, let alias = map["alias"] as? String, ResetOperationRegistry.isAlias(alias) else { return nil }
            return .reservedGesture(gestureId: gestureId, gestureGeneration: generation, alias: alias)
        case "reset_dispatched":
            guard Set(map.keys) == ["kind", "expectedTaskGenerationEpoch", "suggestedOperationId"], let epoch = TaskGenerationEpochStamp.safeInteger(map["expectedTaskGenerationEpoch"]),
                  let suggested = map["suggestedOperationId"] as? String, ResetOperationRegistry.isAlias(suggested) else { return nil }
            return .resetDispatched(expectedTaskGenerationEpoch: epoch, suggestedOperationId: suggested)
        default: return nil
        }
    }
}

/// The exact C9.4.5 row (the reconciliation member and the invalid-alias member share one struct; `isValid` applies the member rules).
struct LegacyResetMigrationV1: Equatable, Sendable {
    static let legacyKeyPrefix = "phase1.pendingRetakeOperation."
    static let maxLegacyOperationIdBytes = 1_500

    let uid: String
    var authEpochUUID: String
    var credentialRevision: Int
    var initiatingAuthority: LegacyInitiatingAuthority?
    var phase: LegacyMigrationPhase
    let createdAt: String
    var updatedAt: String
    var legacyOperationId: String?
    var migrationAlias: String?
    var aliasCandidateOrdinal: Int?
    var legacyKeyGuard: LegacyKeyGuard?
    /// Canonical bytes of the complete validated reconciliation response.
    var receipt: Data?
    var applicationId: String?
    var errorCode: LegacyMigrationErrorCode?
    var legacyValueClass: LegacyValueClass?
    var legacyValueUtf8Length: Int?
    var legacyValueSHA256: String?

    static func legacyKey(uid: String) -> String { legacyKeyPrefix + uid }

    /// A legacy Phase-1 operation ID: its own trimmed form, nonempty, without a path separator, at most 1,500 UTF-8 bytes.
    static func isValidLegacyOperationId(_ value: String) -> Bool {
        !value.isEmpty && value == value.trimmingCharacters(in: .whitespacesAndNewlines) && !value.contains("/") && value.utf8.count <= maxLegacyOperationIdBytes
    }

    static func requestCanonicalJSON(legacyOperationId: String, migrationAlias: String) -> String {
        String(decoding: TaskCanonicalV1.data(["action": "reconcileLegacyTaskReset", "legacyOperationId": legacyOperationId, "migrationAlias": migrationAlias]) ?? Data(), as: UTF8.self)
    }

    static func applicationId(uid: String, migrationId: String, outcome: String) -> String {
        "rla1_" + String(TaskCanonicalV1.sha256Hex(["uid": uid, "migration_id": migrationId, "outcome": outcome]).prefix(40))
    }

    static func clearApplicationId(uid: String, legacyValueClass: LegacyValueClass, utf8Length: Int?, sha256: String?, outcome: String) -> String {
        var map: [String: Any] = ["uid": uid, "legacy_value_class": legacyValueClass.rawValue, "outcome": outcome]
        if let utf8Length { map["legacy_value_utf8_length"] = utf8Length }
        if let sha256 { map["legacy_value_sha256"] = sha256 }
        return "rlic1_" + String(TaskCanonicalV1.sha256Hex(map).prefix(40))
    }

    var isInvalidAliasMember: Bool { errorCode == .aliasInvalid }
    var requestFingerprint: String? { legacyOperationId.map { LegacyResetReconciliationV1.requestFingerprint(uid: uid, legacyOperationId: $0) } }
    var migrationId: String? { legacyOperationId.map { LegacyResetReconciliationV1.migrationId(uid: uid, legacyOperationId: $0) } }
    var decodedReceipt: LegacyResetReconciliationV1? {
        guard let receipt, let object = try? JSONSerialization.jsonObject(with: receipt) as? [String: Any] else { return nil }
        return try? LegacyResetReconciliationV1.decode(object)
    }

    var isValid: Bool {
        guard !uid.isEmpty, !authEpochUUID.isEmpty, credentialRevision >= 0, CanonicalInstant.isCanonical(createdAt), CanonicalInstant.isCanonical(updatedAt) else { return false }
        if isInvalidAliasMember {
            guard phase == .blocked, let valueClass = legacyValueClass, legacyOperationId == nil, migrationAlias == nil, aliasCandidateOrdinal == nil, legacyKeyGuard == nil,
                  receipt == nil, applicationId == nil else { return false }
            switch initiatingAuthority {
            case .none, .reservedGesture: break
            case .resetDispatched: return false
            }
            switch valueClass {
            case .nonString: return legacyValueUtf8Length == nil && legacyValueSHA256 == nil
            case .invalidString: return legacyValueUtf8Length != nil && legacyValueSHA256?.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
            }
        }
        guard let legacyOperationId, Self.isValidLegacyOperationId(legacyOperationId), let migrationAlias, ResetOperationRegistry.isAlias(migrationAlias),
              let ordinal = aliasCandidateOrdinal, (1...4).contains(ordinal), legacyKeyGuard != nil,
              legacyValueClass == nil, legacyValueUtf8Length == nil, legacyValueSHA256 == nil else { return false }
        switch phase {
        case .prepared, .dispatched:
            return receipt == nil && applicationId == nil && errorCode == nil
        case .receipt:
            guard let decoded = decodedReceipt, decoded.base.accountUid == uid, decoded.base.legacyOperationId == legacyOperationId else { return false }
            return applicationId == nil && errorCode == nil
        case .applying:
            guard let decoded = decodedReceipt, decoded.base.accountUid == uid, decoded.base.legacyOperationId == legacyOperationId, initiatingAuthority == nil, errorCode == nil else { return false }
            switch decoded {
            case .notDispatched, .finalizedCompat: return applicationId != nil
            case .upgraded, .phase2Active: return applicationId == nil
            }
        case .blocked:
            guard let errorCode, errorCode != .aliasInvalid else { return false }
            return receipt == nil && applicationId == nil
        }
    }

    func map() -> [String: Any] {
        var map: [String: Any] = ["schemaVersion": 1, "uid": uid, "authEpochUUID": authEpochUUID, "credentialRevision": credentialRevision, "phase": phase.rawValue, "createdAt": createdAt, "updatedAt": updatedAt]
        if let initiatingAuthority { map["initiatingAuthority"] = initiatingAuthority.map() }
        if let errorCode { map["errorCode"] = errorCode.rawValue }
        if isInvalidAliasMember {
            if let legacyValueClass { map["legacyValueClass"] = legacyValueClass.rawValue }
            if let legacyValueUtf8Length { map["legacyValueUtf8Length"] = legacyValueUtf8Length }
            if let legacyValueSHA256 { map["legacyValueSHA256"] = legacyValueSHA256 }
            return map
        }
        if let legacyOperationId, let migrationAlias {
            map["legacyOperationId"] = legacyOperationId
            map["migrationAlias"] = migrationAlias
            map["requestFingerprint"] = LegacyResetReconciliationV1.requestFingerprint(uid: uid, legacyOperationId: legacyOperationId)
            let request = Self.requestCanonicalJSON(legacyOperationId: legacyOperationId, migrationAlias: migrationAlias)
            map["requestCanonicalJSON"] = request
            map["requestSHA256"] = TaskCanonicalV1.sha256Hex(data: Data(request.utf8))
        }
        if let aliasCandidateOrdinal { map["aliasCandidateOrdinal"] = aliasCandidateOrdinal }
        if let legacyKeyGuard { map["legacyKeyGuard"] = legacyKeyGuard.map() }
        if let receipt, let object = try? JSONSerialization.jsonObject(with: receipt) { map["receipt"] = object }
        if let applicationId { map["applicationId"] = applicationId }
        return map
    }

    static func from(_ map: [String: Any]) -> LegacyResetMigrationV1? {
        let allowed: Set<String> = ["schemaVersion", "uid", "authEpochUUID", "credentialRevision", "initiatingAuthority", "phase", "createdAt", "updatedAt", "legacyOperationId", "migrationAlias",
                                    "aliasCandidateOrdinal", "requestFingerprint", "legacyKeyGuard", "requestCanonicalJSON", "requestSHA256", "receipt", "applicationId", "errorCode",
                                    "legacyValueClass", "legacyValueUtf8Length", "legacyValueSHA256"]
        guard Set(map.keys).isSubset(of: allowed), TaskGenerationEpochStamp.safeInteger(map["schemaVersion"]) == 1,
              let uid = map["uid"] as? String, let authEpochUUID = map["authEpochUUID"] as? String, let credentialRevision = TaskGenerationEpochStamp.safeInteger(map["credentialRevision"]),
              let phase = (map["phase"] as? String).flatMap(LegacyMigrationPhase.init(rawValue:)), let createdAt = map["createdAt"] as? String, let updatedAt = map["updatedAt"] as? String else { return nil }
        var authority: LegacyInitiatingAuthority?
        if let raw = map["initiatingAuthority"] { guard let object = raw as? [String: Any], let parsed = LegacyInitiatingAuthority.from(object) else { return nil }; authority = parsed }
        var errorCode: LegacyMigrationErrorCode?
        if let raw = map["errorCode"] { guard let parsed = (raw as? String).flatMap(LegacyMigrationErrorCode.init(rawValue:)) else { return nil }; errorCode = parsed }
        var keyGuard: LegacyKeyGuard?
        if let raw = map["legacyKeyGuard"] { guard let object = raw as? [String: Any], let parsed = LegacyKeyGuard.from(object) else { return nil }; keyGuard = parsed }
        var receipt: Data?
        if let raw = map["receipt"] { guard let object = raw as? [String: Any], let data = TaskCanonicalV1.data(object) else { return nil }; receipt = data }
        func string(_ key: String) -> String?? { guard let raw = map[key] else { return .some(nil) }; guard let value = raw as? String else { return nil }; return .some(value) }
        func integer(_ key: String) -> Int?? { guard let raw = map[key] else { return .some(nil) }; guard let value = TaskGenerationEpochStamp.safeInteger(raw) else { return nil }; return .some(value) }
        guard let legacyOperationId = string("legacyOperationId"), let migrationAlias = string("migrationAlias"), let ordinal = integer("aliasCandidateOrdinal"),
              let applicationId = string("applicationId"), let valueClassRaw = string("legacyValueClass"), let valueLength = integer("legacyValueUtf8Length"), let valueSHA = string("legacyValueSHA256") else { return nil }
        var valueClass: LegacyValueClass?
        if let valueClassRaw { guard let parsed = LegacyValueClass(rawValue: valueClassRaw) else { return nil }; valueClass = parsed }
        let row = LegacyResetMigrationV1(uid: uid, authEpochUUID: authEpochUUID, credentialRevision: credentialRevision, initiatingAuthority: authority, phase: phase, createdAt: createdAt, updatedAt: updatedAt,
                                         legacyOperationId: legacyOperationId, migrationAlias: migrationAlias, aliasCandidateOrdinal: ordinal, legacyKeyGuard: keyGuard, receipt: receipt,
                                         applicationId: applicationId, errorCode: errorCode, legacyValueClass: valueClass, legacyValueUtf8Length: valueLength, legacyValueSHA256: valueSHA)
        guard row.isValid, TaskCanonicalV1.data(row.map()) == TaskCanonicalV1.data(map) else { return nil }
        return row
    }
}

extension LegacyResetReconciliationV1 {
    /// The complete response map (the bytes the row's `receipt` member carries).
    func map() -> [String: Any] {
        var map: [String: Any] = ["schemaVersion": 1, "kind": "legacy_reset_reconciliation", "migrationId": base.migrationId, "legacyOperationId": base.legacyOperationId,
                                  "migrationAlias": base.migrationAlias, "accountUid": base.accountUid, "replayed": base.replayed]
        switch self {
        case .notDispatched:
            map["outcome"] = "not_dispatched"
        case let .upgraded(_, sourceState, progress):
            map["outcome"] = "upgraded"; map["sourceState"] = sourceState; map["progressReceipt"] = progress.map()
        case let .phase2Active(_, progress):
            map["outcome"] = "phase2_active"; map["progressReceipt"] = progress.map()
        case let .finalizedCompat(_, legacyFinal):
            map["outcome"] = "finalized_compat"; map["sourceState"] = "finalized"
            map["legacyFinalReceipt"] = ["schemaVersion": 1, "kind": "legacy_reset_final", "operationId": legacyFinal.operationId, "replayed": false, "accountUid": legacyFinal.accountUid, "deletedCount": legacyFinal.deletedCount, "state": "finalized"]
        }
        return map
    }

    var outcomeName: String {
        switch self {
        case .notDispatched: return "not_dispatched"
        case .upgraded: return "upgraded"
        case .phase2Active: return "phase2_active"
        case .finalizedCompat: return "finalized_compat"
        }
    }
}

/// The C9.4.5 local-only surfaces (never decoded as Firebase details).
enum LegacyMigrationSurface: Equatable, Sendable {
    case pending(uid: String, phase: LegacyMigrationPhase)
    case completed(uid: String, applicationId: String)
    case retryRequired(uid: String, applicationId: String)
    case blocked(uid: String, errorCode: LegacyMigrationErrorCode)

    var map: [String: Any] {
        switch self {
        case let .pending(uid, phase): return ["schemaVersion": 1, "kind": "RESET_MIGRATION_PENDING", "uid": uid, "phase": phase.rawValue]
        case let .completed(uid, applicationId): return ["schemaVersion": 1, "kind": "LEGACY_RESET_COMPLETED", "uid": uid, "applicationId": applicationId]
        case let .retryRequired(uid, applicationId): return ["schemaVersion": 1, "kind": "LEGACY_RESET_RETRY_REQUIRED", "uid": uid, "applicationId": applicationId]
        case let .blocked(uid, errorCode): return ["schemaVersion": 1, "reason": "RESET_MIGRATION_BLOCKED", "uid": uid, "errorCode": errorCode.rawValue]
        }
    }
}

extension ResetOperationRegistry {
    enum LegacyKeyClassification: Equatable, Sendable {
        case absent
        case valid(String)
        case invalid(LegacyValueClass, utf8Length: Int?, sha256: String?)
    }

    /// Owner wiring (S7): the store holding the legacy key; `.standard` until attached.
    func attachLegacyKeyStore(_ defaults: UserDefaults) { legacyKeyDefaults = defaults }

    /// Classifies `phase1.pendingRetakeOperation.{uid}` once, at row creation.
    func classifyLegacyKey(uid: String) -> LegacyKeyClassification {
        guard let raw = legacyKeyDefaults.object(forKey: LegacyResetMigrationV1.legacyKey(uid: uid)) else { return .absent }
        guard let value = raw as? String else { return .invalid(.nonString, utf8Length: nil, sha256: nil) }
        if LegacyResetMigrationV1.isValidLegacyOperationId(value) { return .valid(value) }
        return .invalid(.invalidString, utf8Length: value.utf8.count, sha256: TaskCanonicalV1.sha256Hex(data: Data(value.utf8)))
    }

    private static func keyGuard(_ classification: LegacyKeyClassification) -> LegacyKeyGuard {
        switch classification {
        case .absent: return .absent
        case let .valid(value): return .validString(value: value)
        case let .invalid(valueClass, length, sha): return .invalidValue(valueClass: valueClass, utf8Length: length, sha256: sha)
        }
    }

    fileprivate func typedMigrations(_ envelope: Envelope) throws -> [LegacyResetMigrationV1] {
        let rows = envelope.migrations.compactMap(LegacyResetMigrationV1.from)
        guard rows.count == envelope.migrations.count, Set(rows.map(\.uid)).count == rows.count else { throw RegistryError.envelopeCorrupt }
        return rows
    }

    fileprivate func setMigration(_ envelope: inout Envelope, uid: String, _ row: LegacyResetMigrationV1?) {
        envelope.migrations.removeAll { ($0["uid"] as? String) == uid }
        if let row { envelope.migrations.append(row.map()) }
    }

    func legacyMigration(uid: String) -> LegacyResetMigrationV1? {
        guard let envelope = try? read(), let rows = try? typedMigrations(envelope) else { return nil }
        return rows.first { $0.uid == uid }
    }

    private static func freshAlias() -> String { "rsa1_" + UUID().uuidString.lowercased() }

    /// Same-UID auth normalization (C9.4.5 last rows): a new epoch rebinds the tuple and discards an old-epoch reserved
    /// gesture with its member; a lower same-epoch revision is corruption; a higher one rebases.
    private func normalizeMigration(_ row: inout LegacyResetMigrationV1, _ envelope: inout Envelope, tuple: SignedAuthTuple) throws -> Bool {
        var changed = false
        if row.authEpochUUID != tuple.authEpochUUID {
            row.authEpochUUID = tuple.authEpochUUID
            row.credentialRevision = tuple.credentialRevision
            if case .reservedGesture = row.initiatingAuthority {
                row.initiatingAuthority = nil
                if let gesture = envelope.gesture, gesture.uid == row.uid { envelope.gesture = nil }
            }
            changed = true
        } else if tuple.credentialRevision < row.credentialRevision {
            throw RegistryError.credentialRevisionRegressed
        } else if tuple.credentialRevision > row.credentialRevision {
            row.credentialRevision = tuple.credentialRevision
            changed = true
        }
        if changed { row.updatedAt = try writeTime(advancing: [row.updatedAt]) }
        return changed
    }

    /// The reserved gesture a confirmed reserve adopts or writes (durable before any await), and its initiating member.
    private func adoptReservedGesture(_ envelope: inout Envelope, tuple: SignedAuthTuple, gestureId: String) throws -> LegacyInitiatingAuthority {
        if let gesture = envelope.gesture, gesture.uid == tuple.uid, gesture.phase == .reserved {
            return .reservedGesture(gestureId: gesture.gestureId, gestureGeneration: gesture.gestureGeneration, alias: gesture.alias)
        }
        let generation = UUID().uuidString.lowercased()
        let gesture = ResetGestureV1(gestureId: gestureId, uid: tuple.uid, authEpochUUID: tuple.authEpochUUID, credentialRevision: tuple.credentialRevision, phase: .reserved,
                                     alias: Self.freshAlias(), expectedEpoch: nil, gestureGeneration: generation, reservedAt: try writeTime(advancing: []), boundAt: nil)
        envelope.gesture = gesture
        return .reservedGesture(gestureId: gesture.gestureId, gestureGeneration: generation, alias: gesture.alias)
    }

    /// C9.5.9 steps 2 and the confirmed-reserve transitions of a sole blocked migration; nil lets the ordinary S1 path continue.
    fileprivate func legacyMigrationOnReserve(_ envelope: inout Envelope, tuple: SignedAuthTuple, gestureId: String) throws -> ResetReserveOutcome? {
        let rows = try typedMigrations(envelope)
        let mine = rows.filter { $0.uid == tuple.uid }
        guard mine.count <= 1 else { throw RegistryError.envelopeCorrupt }
        if var row = mine.first {
            if let gesture = envelope.gesture, gesture.uid == tuple.uid, gesture.phase == .bound { throw RegistryError.envelopeCorrupt }
            var changed = try normalizeMigration(&row, &envelope, tuple: tuple)
            switch row.phase {
            case .prepared, .dispatched, .receipt, .applying:
                if changed { setMigration(&envelope, uid: row.uid, row); try write(&envelope) }
                return .migrationPending(ResetMigrationPending(uid: row.uid, phase: row.phase))
            case .blocked:
                switch row.errorCode {
                case .aliasInvalid?:
                    switch row.initiatingAuthority {
                    case .none:
                        row.initiatingAuthority = try adoptReservedGesture(&envelope, tuple: tuple, gestureId: gestureId)
                        changed = true
                    case let .reservedGesture(id, generation, alias)?:
                        guard let gesture = envelope.gesture, gesture.uid == tuple.uid, gesture.phase == .reserved, gesture.gestureId == id, gesture.gestureGeneration == generation, gesture.alias == alias else { throw RegistryError.envelopeCorrupt }
                    case .resetDispatched?:
                        throw RegistryError.envelopeCorrupt
                    }
                case .legacyResetCorrupt?:
                    row.phase = .prepared
                    row.errorCode = nil
                    changed = true
                case .aliasCollisionExhausted?:
                    if row.initiatingAuthority == nil { row.initiatingAuthority = try adoptReservedGesture(&envelope, tuple: tuple, gestureId: gestureId) }
                    row.migrationAlias = Self.freshAlias()
                    row.aliasCandidateOrdinal = 1
                    row.phase = .prepared
                    row.errorCode = nil
                    changed = true
                case .operationReused?:
                    throw RegistryError.migrationBlocked(uid: row.uid, errorCode: LegacyMigrationErrorCode.operationReused.rawValue)
                case nil:
                    throw RegistryError.envelopeCorrupt
                }
                if changed {
                    row.updatedAt = try writeTime(advancing: [row.updatedAt])
                    setMigration(&envelope, uid: row.uid, row)
                    try write(&envelope)
                }
                return .migrationPending(ResetMigrationPending(uid: row.uid, phase: row.phase))
            }
        }
        // no row: a bound gesture or an existing reset row keeps the ordinary path (a legacy marker surfaces as MIGRATION_REQUIRED on dispatch)
        if let gesture = envelope.gesture, gesture.uid == tuple.uid, gesture.phase == .bound { return nil }
        if envelope.records.contains(where: { $0.uid == tuple.uid }) { return nil }
        let classification = classifyLegacyKey(uid: tuple.uid)
        if case .absent = classification { return nil }
        let authority = try adoptReservedGesture(&envelope, tuple: tuple, gestureId: gestureId)
        let now = try writeTime(advancing: [])
        var row = LegacyResetMigrationV1(uid: tuple.uid, authEpochUUID: tuple.authEpochUUID, credentialRevision: tuple.credentialRevision, initiatingAuthority: authority, phase: .prepared,
                                         createdAt: now, updatedAt: now, legacyOperationId: nil, migrationAlias: nil, aliasCandidateOrdinal: nil, legacyKeyGuard: nil, receipt: nil,
                                         applicationId: nil, errorCode: nil, legacyValueClass: nil, legacyValueUtf8Length: nil, legacyValueSHA256: nil)
        switch classification {
        case let .valid(value):
            row.legacyOperationId = value
            row.migrationAlias = Self.freshAlias()
            row.aliasCandidateOrdinal = 1
            row.legacyKeyGuard = .validString(value: value)
        case let .invalid(valueClass, length, sha):
            row.phase = .blocked
            row.errorCode = .aliasInvalid
            row.legacyValueClass = valueClass
            row.legacyValueUtf8Length = length
            row.legacyValueSHA256 = sha
        case .absent:
            return nil
        }
        guard row.isValid else { throw RegistryError.envelopeCorrupt }
        setMigration(&envelope, uid: row.uid, row)
        try write(&envelope)
        return .migrationPending(ResetMigrationPending(uid: row.uid, phase: row.phase))
    }

    /// The drive's caller reports `LEGACY_RESET_MIGRATION_REQUIRED(B)` for a `reset_dispatched` row that carries no canonical
    /// ID or receipt: the migration row is created with that row as its initiating authority (never before the error).
    func noteMigrationRequired(handle: ResetOperationHandle, legacyOperationId: String) async throws -> ResetMigrationPending {
        let tuple = try await signedAuth()
        guard tuple.uid == handle.uid, LegacyResetMigrationV1.isValidLegacyOperationId(legacyOperationId) else { throw RegistryError.operationStale(uid: handle.uid, handleId: handle.handleId) }
        guard var envelope = try read(), let row = envelope.records.first(where: { $0.uid == handle.uid && $0.handleId == handle.handleId }),
              row.phase == .resetDispatched, row.canonicalOperationId == nil, row.progressReceipt == nil else { throw RegistryError.operationStale(uid: handle.uid, handleId: handle.handleId) }
        if let existing = try typedMigrations(envelope).first(where: { $0.uid == tuple.uid }) { return ResetMigrationPending(uid: tuple.uid, phase: existing.phase) }
        let now = try writeTime(advancing: [])
        let migration = LegacyResetMigrationV1(uid: tuple.uid, authEpochUUID: tuple.authEpochUUID, credentialRevision: tuple.credentialRevision,
                                               initiatingAuthority: .resetDispatched(expectedTaskGenerationEpoch: row.expectedTaskGenerationEpoch, suggestedOperationId: row.suggestedOperationId),
                                               phase: .prepared, createdAt: now, updatedAt: now, legacyOperationId: legacyOperationId, migrationAlias: Self.freshAlias(), aliasCandidateOrdinal: 1,
                                               legacyKeyGuard: Self.keyGuard(classifyLegacyKey(uid: tuple.uid)), receipt: nil, applicationId: nil, errorCode: nil,
                                               legacyValueClass: nil, legacyValueUtf8Length: nil, legacyValueSHA256: nil)
        guard migration.isValid else { throw RegistryError.envelopeCorrupt }
        setMigration(&envelope, uid: tuple.uid, migration)
        try write(&envelope)
        return ResetMigrationPending(uid: tuple.uid, phase: .prepared)
    }

    /// Drives the current UID's migration row through the C9.4.5 machine to a rest state; one in-flight drive per UID.
    func driveLegacyMigration(remote: any ResetRemoteProviding) async throws -> ResetReserveOutcome {
        let tuple = try await signedAuth()
        if let inflight = inflightLegacyMigration[tuple.uid] { return try await inflight.value }
        let task = Task { try await self.runLegacyMigration(uid: tuple.uid, remote: remote) }
        inflightLegacyMigration[tuple.uid] = task
        defer { inflightLegacyMigration[tuple.uid] = nil }
        return try await task.value
    }

    private func currentMigration(uid: String) throws -> (Envelope, LegacyResetMigrationV1) {
        guard let envelope = try read(), let row = try typedMigrations(envelope).first(where: { $0.uid == uid }) else { throw RegistryError.operationStale(uid: uid, handleId: "migration") }
        return (envelope, row)
    }

    private func storeMigration(_ row: LegacyResetMigrationV1, in envelope: inout Envelope) throws {
        var next = row
        next.updatedAt = try writeTime(advancing: [row.updatedAt])
        guard next.isValid else { throw RegistryError.envelopeCorrupt }
        setMigration(&envelope, uid: row.uid, next)
        try write(&envelope)
    }

    private func blockMigration(_ row: LegacyResetMigrationV1, _ code: LegacyMigrationErrorCode, in envelope: inout Envelope) throws -> Error {
        var blocked = row
        blocked.phase = .blocked
        blocked.errorCode = code
        blocked.receipt = nil
        blocked.applicationId = nil
        try storeMigration(blocked, in: &envelope)
        return RegistryError.migrationBlocked(uid: row.uid, errorCode: code.rawValue)
    }

    /// Whether the live key matches the row's immutable guard (`absent` counts as a crash-resume after an earlier clear).
    private func keyMatches(_ keyGuard: LegacyKeyGuard, uid: String) -> Bool {
        let raw = legacyKeyDefaults.object(forKey: LegacyResetMigrationV1.legacyKey(uid: uid))
        switch keyGuard {
        case .absent: return raw == nil
        case let .validString(value): return raw == nil || (raw as? String) == value
        case let .invalidValue(valueClass, length, sha):
            guard let raw else { return true }
            switch valueClass {
            case .nonString: return !(raw is String)
            case .invalidString:
                guard let value = raw as? String else { return false }
                return value.utf8.count == length && TaskCanonicalV1.sha256Hex(data: Data(value.utf8)) == sha
            }
        }
    }

    /// APPLYING compare-and-remove: the exact stored value is removed; a different value remains; `non_string` is never auto-removed.
    private func compareAndRemoveKey(_ keyGuard: LegacyKeyGuard, uid: String) {
        let key = LegacyResetMigrationV1.legacyKey(uid: uid)
        guard let raw = legacyKeyDefaults.object(forKey: key) else { return }
        switch keyGuard {
        case .absent, .invalidValue(.nonString, _, _): return
        case let .validString(value): if (raw as? String) == value { legacyKeyDefaults.removeObject(forKey: key) }
        case let .invalidValue(.invalidString, length, sha):
            if let value = raw as? String, value.utf8.count == length, TaskCanonicalV1.sha256Hex(data: Data(value.utf8)) == sha { legacyKeyDefaults.removeObject(forKey: key) }
        }
    }

    private func runLegacyMigration(uid: String, remote: any ResetRemoteProviding) async throws -> ResetReserveOutcome {
        var auth = try await signedAuth()
        guard auth.uid == uid else { throw RegistryError.authRequired }
        for _ in 0..<16 {
            auth = try await revalidated(auth)
            var (envelope, row) = try currentMigration(uid: uid)
            if try normalizeMigration(&row, &envelope, tuple: auth) { setMigration(&envelope, uid: uid, row); try write(&envelope) }
            switch row.phase {
            case .prepared:
                row.phase = .dispatched
                try storeMigration(row, in: &envelope)
            case .dispatched:
                guard let legacy = row.legacyOperationId, let alias = row.migrationAlias, let ordinal = row.aliasCandidateOrdinal else { throw RegistryError.envelopeCorrupt }
                let result: LegacyResetReconciliationV1
                do {
                    result = try await remote.reconcileLegacyReset(legacyOperationId: legacy, migrationAlias: alias)
                } catch let error as ResetRemoteError {
                    auth = try await revalidated(auth)
                    (envelope, row) = try currentMigration(uid: uid)
                    guard row.phase == .dispatched, row.legacyOperationId == legacy, row.migrationAlias == alias else { continue }
                    switch error {
                    case let .legacyResetAliasOccupied(occupiedLegacy, occupiedAlias):
                        guard occupiedLegacy == legacy, occupiedAlias == alias else { throw ResetRemoteError.protocolAmbiguity }
                        if ordinal >= 4 { throw try blockMigration(row, .aliasCollisionExhausted, in: &envelope) }
                        row.migrationAlias = Self.freshAlias()
                        row.aliasCandidateOrdinal = ordinal + 1
                        row.phase = .prepared
                        try storeMigration(row, in: &envelope)
                    case let .legacyResetMigrationRequired(redirected):
                        guard redirected != legacy, LegacyResetMigrationV1.isValidLegacyOperationId(redirected) else { throw ResetRemoteError.protocolAmbiguity }
                        row.legacyOperationId = redirected
                        row.migrationAlias = Self.freshAlias()
                        row.aliasCandidateOrdinal = 1
                        row.phase = .prepared
                        try storeMigration(row, in: &envelope)
                    case .operationReused:
                        throw try blockMigration(row, .operationReused, in: &envelope)
                    case .legacyResetCorrupt, .requestInvalid:
                        throw try blockMigration(row, .legacyResetCorrupt, in: &envelope)
                    case .resetActive:
                        throw ResetRemoteError.protocolAmbiguity
                    case .authRequired, .transport, .protocolAmbiguity, .staleState, .clientUpgradeRequired:
                        throw error
                    }
                    continue
                }
                auth = try await revalidated(auth)
                (envelope, row) = try currentMigration(uid: uid)
                guard row.phase == .dispatched, row.legacyOperationId == legacy, row.migrationAlias == alias else { continue }
                guard result.base.accountUid == uid, result.base.legacyOperationId == legacy, result.base.replayed || result.base.migrationAlias == alias,
                      let bytes = TaskCanonicalV1.data(result.map()) else { throw ResetRemoteError.protocolAmbiguity }
                row.receipt = bytes
                row.phase = .receipt
                try storeMigration(row, in: &envelope)
            case .receipt:
                guard let receipt = row.decodedReceipt, let migrationId = row.migrationId else { throw RegistryError.envelopeCorrupt }
                let authority = row.initiatingAuthority
                switch receipt {
                case let .upgraded(_, _, progress), let .phase2Active(_, progress):
                    try materialize(progress: progress, authority: authority, receiptAlias: receipt.base.migrationAlias, uid: uid, in: &envelope)
                case .notDispatched, .finalizedCompat:
                    try retireAuthority(authority, uid: uid, in: &envelope)
                    row.applicationId = LegacyResetMigrationV1.applicationId(uid: uid, migrationId: migrationId, outcome: receipt.outcomeName)
                }
                row.initiatingAuthority = nil
                row.phase = .applying
                try storeMigration(row, in: &envelope)
            case .applying:
                guard let receipt = row.decodedReceipt, let keyGuard = row.legacyKeyGuard else { throw RegistryError.envelopeCorrupt }
                compareAndRemoveKey(keyGuard, uid: uid)
                setMigration(&envelope, uid: uid, nil)
                try write(&envelope)
                switch receipt {
                case let .upgraded(_, _, progress), let .phase2Active(_, progress):
                    guard let materialized = envelope.records.first(where: { $0.uid == uid && $0.expectedTaskGenerationEpoch == progress.expectedTaskGenerationEpoch }) else { throw RegistryError.envelopeCorrupt }
                    return .operation(ResetOperationHandle(uid: uid, handleId: materialized.handleId))
                case .notDispatched:
                    return .legacyRetryRequired(LegacyResetRetryRequired(uid: uid, applicationId: row.applicationId ?? ""))
                case .finalizedCompat:
                    return .legacyCompleted(LegacyResetCompleted(uid: uid, applicationId: row.applicationId ?? ""))
                }
            case .blocked:
                guard row.errorCode == .aliasInvalid else { throw RegistryError.migrationBlocked(uid: uid, errorCode: row.errorCode?.rawValue ?? LegacyMigrationErrorCode.legacyResetCorrupt.rawValue) }
                return try await inspectInvalidAlias(row, remote: remote, uid: uid, auth: &auth)
            }
        }
        throw ResetDriveError.stepBudgetExceeded
    }

    /// `receipt → applying` for upgraded/phase2_active: the progress receipt materializes (or transforms in place) the
    /// `(uid, expectedTaskGenerationEpoch)` row under the bound alias; the gesture is removed.
    private func materialize(progress: ResetReceiptV1, authority: LegacyInitiatingAuthority?, receiptAlias: String, uid: String, in envelope: inout Envelope) throws {
        let epoch = progress.expectedTaskGenerationEpoch
        let phase: ResetRowPhase = progress.state == .deleting ? .resetReceiptDeleting : .resetReceiptAwaitingLocalReset
        if let index = envelope.records.firstIndex(where: { $0.uid == uid }) {
            var existing = envelope.records[index]
            guard case let .resetDispatched(expected, suggested)? = authority, existing.phase == .resetDispatched, existing.canonicalOperationId == nil, existing.progressReceipt == nil,
                  existing.expectedTaskGenerationEpoch == expected, existing.suggestedOperationId == suggested else { throw RegistryError.envelopeCorrupt }
            existing.expectedTaskGenerationEpoch = epoch
            existing.canonicalOperationId = progress.operationId
            existing.progressReceipt = progress.canonicalData()
            existing.phase = phase
            existing.updatedAt = try writeTime(advancing: [existing.updatedAt])
            envelope.records[index] = existing
            envelope.records = Self.sorted(envelope.records)
            return
        }
        guard envelope.records.count < Self.capacity else {
            throw RegistryError.registryFull(capacity: Self.capacity, occupants: envelope.records.map { RegistryOccupant(uid: $0.uid, expectedTaskGenerationEpoch: $0.expectedTaskGenerationEpoch, phase: $0.phase, recoveryAction: $0.recoveryAction) })
        }
        var createdAt = try writeTime(advancing: [])
        var alias = receiptAlias
        if case let .reservedGesture(gestureId, generation, boundAlias)? = authority {
            guard let gesture = envelope.gesture, gesture.gestureId == gestureId, gesture.gestureGeneration == generation, gesture.alias == boundAlias else { throw RegistryError.envelopeCorrupt }
            createdAt = gesture.reservedAt
            alias = boundAlias
            envelope.gesture = nil
        }
        let row = ResetOperationRegistryRecordV2(uid: uid, suggestedOperationId: alias, canonicalOperationId: progress.operationId, expectedTaskGenerationEpoch: epoch, phase: phase,
                                                 progressReceipt: progress.canonicalData(), finalReceipt: nil, applicationId: nil, createdAt: createdAt, updatedAt: try writeTime(advancing: [createdAt]))
        envelope.records = Self.sorted(envelope.records + [row])
    }

    /// `receipt → applying` for not_dispatched/finalized_compat: the initiating gesture or reset-dispatched row is retired; no epoch read, no reset row.
    private func retireAuthority(_ authority: LegacyInitiatingAuthority?, uid: String, in envelope: inout Envelope) throws {
        switch authority {
        case let .reservedGesture(gestureId, generation, _)?:
            if let gesture = envelope.gesture, gesture.gestureId == gestureId, gesture.gestureGeneration == generation { envelope.gesture = nil }
        case let .resetDispatched(epoch, suggested)?:
            envelope.records.removeAll { $0.uid == uid && $0.expectedTaskGenerationEpoch == epoch && $0.suggestedOperationId == suggested && $0.phase == .resetDispatched && $0.canonicalOperationId == nil }
        case nil:
            break
        }
    }

    /// The `LEGACY_ALIAS_INVALID` inspection transitions (consent = the reserved-gesture initiating authority).
    private func inspectInvalidAlias(_ row: LegacyResetMigrationV1, remote: any ResetRemoteProviding, uid: String, auth: inout SignedAuthTuple) async throws -> ResetReserveOutcome {
        guard case .reservedGesture? = row.initiatingAuthority, let valueClass = row.legacyValueClass else {
            throw RegistryError.migrationBlocked(uid: uid, errorCode: LegacyMigrationErrorCode.aliasInvalid.rawValue)
        }
        let inspection: LegacyResetInspectionV1
        do { inspection = try await remote.inspectLegacyReset() } catch { throw RegistryError.migrationBlocked(uid: uid, errorCode: LegacyMigrationErrorCode.aliasInvalid.rawValue) }
        auth = try await revalidated(auth)
        var (envelope, current) = try currentMigration(uid: uid)
        guard current == row, inspection.accountUid == uid else { throw RegistryError.migrationBlocked(uid: uid, errorCode: LegacyMigrationErrorCode.aliasInvalid.rawValue) }
        let keyGuard = LegacyKeyGuard.invalidValue(valueClass: valueClass, utf8Length: row.legacyValueUtf8Length, sha256: row.legacyValueSHA256)
        switch inspection {
        case let .legacyActive(_, legacy):
            current.phase = .prepared
            current.errorCode = nil
            current.legacyValueClass = nil
            current.legacyValueUtf8Length = nil
            current.legacyValueSHA256 = nil
            current.legacyOperationId = legacy
            current.migrationAlias = Self.freshAlias()
            current.aliasCandidateOrdinal = 1
            current.legacyKeyGuard = keyGuard
            try storeMigration(current, in: &envelope)
            return .migrationPending(ResetMigrationPending(uid: uid, phase: .prepared))
        case let .phase2Active(_, canonical, epoch):
            guard canonical.range(of: ResetReceiptV1.canonicalIdPattern, options: .regularExpression) != nil else { throw RegistryError.migrationBlocked(uid: uid, errorCode: LegacyMigrationErrorCode.aliasInvalid.rawValue) }
            let matches = keyMatches(keyGuard, uid: uid)
            try retireAuthority(nil, uid: uid, in: &envelope)
            guard let gesture = envelope.gesture, gesture.uid == uid else { throw RegistryError.envelopeCorrupt }
            envelope.gesture = nil
            setMigration(&envelope, uid: uid, nil)
            if matches {
                compareAndRemoveKey(keyGuard, uid: uid)
                guard !envelope.records.contains(where: { $0.uid == uid }), envelope.records.count < Self.capacity else { throw RegistryError.envelopeCorrupt }
                let adopted = ResetOperationRegistryRecordV2(uid: uid, suggestedOperationId: gesture.alias, canonicalOperationId: nil, expectedTaskGenerationEpoch: epoch, phase: .resetDispatched,
                                                             progressReceipt: nil, finalReceipt: nil, applicationId: nil, createdAt: gesture.reservedAt, updatedAt: try writeTime(advancing: [gesture.reservedAt]))
                envelope.records = Self.sorted(envelope.records + [adopted])
                try write(&envelope)
                return .operation(ResetOperationHandle(uid: uid, handleId: adopted.handleId))
            }
            try write(&envelope)
            return .legacyRetryRequired(LegacyResetRetryRequired(uid: uid, applicationId: LegacyResetMigrationV1.clearApplicationId(uid: uid, legacyValueClass: valueClass, utf8Length: row.legacyValueUtf8Length, sha256: row.legacyValueSHA256, outcome: "legacy_value_changed")))
        case .none:
            let matches = keyMatches(keyGuard, uid: uid)
            if matches { compareAndRemoveKey(keyGuard, uid: uid) }
            envelope.gesture = envelope.gesture?.uid == uid ? nil : envelope.gesture
            setMigration(&envelope, uid: uid, nil)
            try write(&envelope)
            let outcome = matches ? "none" : "legacy_value_changed"
            return .legacyRetryRequired(LegacyResetRetryRequired(uid: uid, applicationId: LegacyResetMigrationV1.clearApplicationId(uid: uid, legacyValueClass: valueClass, utf8Length: row.legacyValueUtf8Length, sha256: row.legacyValueSHA256, outcome: outcome)))
        }
    }
}
