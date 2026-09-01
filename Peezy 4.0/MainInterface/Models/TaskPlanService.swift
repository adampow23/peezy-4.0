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
