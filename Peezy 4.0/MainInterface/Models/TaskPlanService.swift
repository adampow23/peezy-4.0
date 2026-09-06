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
