import Foundation
import CoreFoundation
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
