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
    /// C9.5.8/C9.5.12 `inflightResetOperation`: one drive per handle; installed before the first suspension, cleared in
    /// `defer`; joiners with the same UID/auth epoch and a revision at or above the baseline receive the outcome only.
    fileprivate var inflightResetOperation: [ResetOperationHandle: (uid: String, authEpochUUID: String, credentialBaseline: Int, task: Task<ResetDriveOutcome, Error>)] = [:]

    init(directory: URL, clock: any LocalDurableClock, auth: any AuthAuthorityProviding, epochAuthority: any ResetEpochAuthorityProviding) {
        self.directory = directory
        self.clock = clock
        self.auth = auth
        self.epochAuthority = epochAuthority
    }

    private struct Envelope {
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

        if let migration = envelope.migrations.first(where: { $0["uid"] as? String == tuple.uid }) {
            let phase = (migration["phase"] as? String).flatMap(LegacyMigrationPhase.init(rawValue:)) ?? .blocked
            if phase == .blocked { throw RegistryError.migrationBlocked(uid: tuple.uid, errorCode: migration["errorCode"] as? String ?? "LEGACY_RESET_CORRUPT") }
            return .migrationPending(ResetMigrationPending(uid: tuple.uid, phase: phase))
        }

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

    private func conflictSnapshot(_ rows: [ResetOperationRegistryRecordV2], tuple: SignedAuthTuple, envelope: Envelope) -> BlockedSnapshot {
        let occupants = Self.epochOccupants(rows)
        let actionable = occupants.map(\.expectedTaskGenerationEpoch).min() ?? 0
        let digest = TaskCanonicalV1.sha256Hex([
            "schemaVersion": 1, "store": "reset", "baseState": "reset_epoch_conflict",
            "uid": tuple.uid, "authEpochUUID": tuple.authEpochUUID, "credentialRevision": tuple.credentialRevision,
            "envelopeGeneration": envelope.generationId, "envelopeSHA256": envelope.sha256,
            "actionableExpectedTaskGenerationEpoch": actionable,
            "occupants": occupants.map { ["expectedTaskGenerationEpoch": $0.expectedTaskGenerationEpoch, "phase": $0.phase.rawValue, "recoveryAction": $0.recoveryAction.rawValue] }
        ])
        return .resetEpochConflict(recoveryStateDigest: digest, actionableExpectedTaskGenerationEpoch: actionable, occupants: occupants)
    }
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
        let tuple = try await signedAuth()
        guard tuple.uid == handle.uid else { throw RegistryError.operationStale(uid: handle.uid, handleId: handle.handleId) }
        if let slot = inflightResetOperation[handle] {
            if slot.uid == tuple.uid && slot.authEpochUUID == tuple.authEpochUUID {
                guard tuple.credentialRevision >= slot.credentialBaseline else { throw RegistryError.credentialRevisionRegressed }
                let outcome = try await slot.task.value
                let again = try await signedAuth()
                guard again.uid == slot.uid, again.authEpochUUID == slot.authEpochUUID, again.credentialRevision >= slot.credentialBaseline else { throw RegistryError.authRequired }
                return outcome
            }
            _ = try? await slot.task.value
            await Task.yield()
            return try await drive(handle: handle, remote: remote, cleanup: cleanup)
        }
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
