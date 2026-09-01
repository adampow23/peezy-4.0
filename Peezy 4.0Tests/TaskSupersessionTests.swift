import Foundation
import Testing
@testable import Peezy_4_0

@MainActor
struct TaskSupersessionTests {
    @Test func serviceSerializesExactActionsAndIdentity() async throws {
        let recorder = CallableRecorder(response: [
            "taskId": "ORIGINAL", "status": "matching_in_progress",
            "replacementTaskId": "a2_x", "lifecycleState": "pending_amendment",
            "revision": 1, "replayed": false
        ])
        let service = TaskPlanService(callable: recorder.call)
        let amendmentTrigger = TaskPlanService.Trigger(
            kind: "event", eventName: "accepted", canonicalKey: "institution:1",
            afterSourceVersion: 4, payload: ["source_evidence_id": "evidence-1"]
        )
        let verificationTrigger = TaskPlanService.Trigger(
            kind: "date", at: Date(timeIntervalSince1970: 1_900_000_000),
            payload: ["source_evidence_id": "evidence-2", "basis": "institution_promised_date"]
        )
        let amendment = TaskPlanService.ActionDescriptor(
            nextTrigger: amendmentTrigger, resumeDestination: "flow://amend"
        )
        let verification = TaskPlanService.ActionDescriptor(
            nextTrigger: verificationTrigger, resumeDestination: "flow://verify"
        )
        let replacement = TaskPlanService.Replacement(
            taskId: "AMENDMENT", subject: .init(kind: "service", id: "row-uuid"),
            institutionId: "inst-1", institution: "First Bank",
            amendmentAction: amendment, verification: verification
        )
        let result = try await service.supersedeTask(
            taskId: "ORIGINAL", reason: "changed", operationId: "op-1", replacement: replacement
        )

        #expect(result.lifecycleState == .pendingAmendment)
        #expect(await recorder.names == ["changeTaskPlan"])
        let payload = try #require(await recorder.payloads.first)
        #expect(payload["action"] as? String == "supersede")
        #expect(payload["operationId"] as? String == "op-1")
        let encodedReplacement = try #require(payload["replacement"] as? [String: Any])
        #expect((encodedReplacement["subject"] as? [String: String]) == ["kind": "service", "id": "row-uuid"])
        #expect(encodedReplacement["institutionId"] as? String == "inst-1")
        #expect(encodedReplacement["institution"] as? String == "First Bank")
        let encodedAmendment = try #require(encodedReplacement["amendmentAction"] as? [String: Any])
        let encodedVerification = try #require(encodedReplacement["verification"] as? [String: Any])
        let expectedAmendment: [String: Any] = [
            "resumeDestination": "flow://amend",
            "nextTrigger": [
                "kind": "event", "event_name": "accepted",
                "canonical_key": "institution:1", "after_source_version": 4,
                "payload": ["source_evidence_id": "evidence-1"]
            ]
        ]
        let expectedVerification: [String: Any] = [
            "resumeDestination": "flow://verify",
            "nextTrigger": [
                "kind": "date",
                "at": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_900_000_000)),
                "payload": [
                    "source_evidence_id": "evidence-2",
                    "basis": "institution_promised_date"
                ]
            ]
        ]
        let encodedAmendmentJSON = try JSONSerialization.data(withJSONObject: encodedAmendment, options: [.sortedKeys])
        let expectedAmendmentJSON = try JSONSerialization.data(withJSONObject: expectedAmendment, options: [.sortedKeys])
        let encodedVerificationJSON = try JSONSerialization.data(withJSONObject: encodedVerification, options: [.sortedKeys])
        let expectedVerificationJSON = try JSONSerialization.data(withJSONObject: expectedVerification, options: [.sortedKeys])
        #expect(encodedAmendmentJSON == expectedAmendmentJSON)
        #expect(encodedVerificationJSON == expectedVerificationJSON)
        let amendmentPayload = try #require((encodedAmendment["nextTrigger"] as? [String: Any])?["payload"] as? [String: String])
        let verificationPayload = try #require((encodedVerification["nextTrigger"] as? [String: Any])?["payload"] as? [String: String])
        #expect(amendmentPayload != verificationPayload)
    }

    @Test func serviceSerializesAllSimpleActions() async throws {
        let recorder = CallableRecorder(response: [
            "taskId": "t", "status": "Dismissed", "replacementTaskId": NSNull(),
            "lifecycleState": "retired", "revision": 1, "replayed": false
        ])
        let service = TaskPlanService(callable: recorder.call)
        _ = try await service.confirmAmendment(taskId: "t", reason: "confirm", operationId: "c")
        _ = try await service.undoConfirmation(taskId: "t", reason: "undo", operationId: "u")
        _ = try await service.reopenTask(taskId: "t", reason: "reopen", operationId: "r")
        #expect(await recorder.payloads.compactMap { $0["action"] as? String } == ["confirmAmendment", "undoConfirmation", "reopen"])
        #expect(await recorder.names == ["changeTaskPlan", "changeTaskPlan", "changeTaskPlan"])
        #expect(await recorder.payloads.compactMap { $0["operationId"] as? String } == ["c", "u", "r"])
        #expect(await recorder.payloads.compactMap { $0["reason"] as? String } == ["confirm", "undo", "reopen"])
    }

    @Test func resetResponseAndInvalidResponseAreValidated() async throws {
        let valid = TaskPlanService(callable: { _, _ in ["reset": true, "deletedCount": 42, "replayed": true] })
        let reset = try await valid.resetAllTasks(reason: "retake_assessment", operationId: "op")
        #expect(reset.deletedCount == 42)
        #expect(reset.replayed)

        let recorder = CallableRecorder(response: ["reset": true, "deletedCount": 42, "replayed": false])
        let resetService = TaskPlanService(callable: recorder.call)
        _ = try await resetService.resetAllTasks(operationId: "reset-op")
        _ = try await resetService.finalizeTaskReset(operationId: "finalize-op")
        #expect(await recorder.names == ["changeTaskPlan", "changeTaskPlan"])
        #expect(await recorder.payloads.compactMap { $0["action"] as? String } == ["resetAllTasks", "finalizeTaskReset"])
        #expect(await recorder.payloads.compactMap { $0["operationId"] as? String } == ["reset-op", "finalize-op"])
        #expect(await recorder.payloads.allSatisfy { $0["reason"] as? String == "retake_assessment" })

        let invalid = TaskPlanService(callable: { _, _ in ["taskId": "missing-shape"] })
        await #expect(throws: TaskPlanService.Error.invalidResponse) {
            _ = try await invalid.reopenTask(taskId: "t", reason: "r", operationId: "o")
        }

        let propagation = TaskPlanService(callable: { _, _ in throw RetakeTestError.failed })
        await #expect(throws: RetakeTestError.failed) {
            _ = try await propagation.reopenTask(taskId: "t", reason: "r", operationId: "o")
        }
    }

    @Test func strictResponseSchemaRejectsMissingUnknownFractionalNegativeBooleanAndZeroFields() async {
        let valid: [String: Any] = [
            "taskId": "t", "status": "Dismissed", "replacementTaskId": NSNull(),
            "lifecycleState": "retired", "revision": 1, "replayed": false
        ]
        var invalidResponses: [[String: Any]] = []
        var missingReplacement = valid
        missingReplacement.removeValue(forKey: "replacementTaskId")
        invalidResponses.append(missingReplacement)
        for badStatus in ["", "mystery"] {
            var response = valid; response["status"] = badStatus; invalidResponses.append(response)
        }
        for badRevision: Any in [NSNumber(value: 1.5), NSNumber(value: -1), NSNumber(value: 0), NSNumber(value: true)] {
            var response = valid; response["revision"] = badRevision; invalidResponses.append(response)
        }
        var emptyReplacement = valid
        emptyReplacement["replacementTaskId"] = ""
        invalidResponses.append(emptyReplacement)

        for response in invalidResponses {
            let service = TaskPlanService(callable: { _, _ in response })
            await #expect(throws: TaskPlanService.Error.invalidResponse) {
                _ = try await service.reopenTask(taskId: "t", reason: "r", operationId: "o")
            }
        }

        let invalidResets: [[String: Any]] = [
            ["reset": true, "deletedCount": NSNumber(value: 1.5), "replayed": false],
            ["reset": true, "deletedCount": NSNumber(value: -1), "replayed": false],
            ["reset": true, "deletedCount": NSNumber(value: true), "replayed": false],
            ["reset": true, "replayed": false]
        ]
        for response in invalidResets {
            let service = TaskPlanService(callable: { _, _ in response })
            await #expect(throws: TaskPlanService.Error.invalidResponse) {
                _ = try await service.resetAllTasks(operationId: "o")
            }
        }
    }

    @Test func coordinatorRetainsOperationAcrossFailureAndPostsOnlyAfterFinalize() async throws {
        let store = MemoryOperationStore()
        let calls = RetakeCalls()
        store.onClear = calls.noteClear
        calls.failStep = .finalize
        let coordinator = RetakeAssessmentCoordinator(
            currentUser: { "user-1" },
            taskPlan: calls.taskPlan,
            deleteAssessments: calls.assessment,
            deleteUserKnowledge: calls.knowledge,
            resetDose: calls.dose,
            operationStore: store,
            postNotification: calls.notify
        )
        await #expect(throws: RetakeTestError.failed) { try await coordinator.retake() }
        let retained = await store.load(userId: "user-1")
        #expect(retained != nil)
        #expect(await calls.notifications == 0)

        calls.failStep = nil
        let reconstructed = RetakeAssessmentCoordinator(
            currentUser: { "user-1" }, taskPlan: calls.taskPlan,
            deleteAssessments: calls.assessment, deleteUserKnowledge: calls.knowledge,
            resetDose: calls.dose, operationStore: store, postNotification: calls.notify
        )
        try await reconstructed.retake()
        #expect(await store.load(userId: "user-1") == nil)
        #expect(await calls.operationIds.count == 4)
        #expect(Set(await calls.operationIds).count == 1)
        #expect(await calls.notifications == 1)
        #expect(await calls.order.suffix(3) == ["finalize", "clear", "notify"])
    }

    @Test func coordinatorPropagatesEachLocalFailureAndSafelyReplaysWithSameOperation() async throws {
        for failedStep in [RetakeCalls.Step.assessment, .knowledge, .dose] {
            let store = MemoryOperationStore()
            let calls = RetakeCalls()
            store.onClear = calls.noteClear
            calls.failStep = failedStep
            let coordinator = RetakeAssessmentCoordinator(
                currentUser: { "user-\(failedStep.rawValue)" }, taskPlan: calls.taskPlan,
                deleteAssessments: calls.assessment, deleteUserKnowledge: calls.knowledge,
                resetDose: calls.dose, operationStore: store, postNotification: calls.notify
            )

            await #expect(throws: RetakeTestError.failed) { try await coordinator.retake() }
            let retained = await store.load(userId: "user-\(failedStep.rawValue)")
            #expect(retained != nil)
            #expect(await calls.notifications == 0)
            #expect(await calls.order.last == failedStep.rawValue)

            calls.failStep = nil
            try await coordinator.retake()
            #expect(Set(await calls.operationIds).count == 1)
            #expect(await store.load(userId: "user-\(failedStep.rawValue)") == nil)
            #expect(await calls.notifications == 1)
            #expect(await calls.order.suffix(3) == ["finalize", "clear", "notify"])
        }
    }
}

@MainActor
private final class CallableRecorder {
    let response: [String: Any]
    var names: [String] = []
    var payloads: [[String: Any]] = []
    init(response: [String: Any]) { self.response = response }
    func call(_ name: String, _ payload: [String: Any]) async throws -> [String: Any] {
        names.append(name); payloads.append(payload); return response
    }
}

private enum RetakeTestError: Swift.Error { case failed }

@MainActor
private final class MemoryOperationStore: RetakeOperationStore {
    var values: [String: String] = [:]
    var onClear: (() -> Void)?
    func load(userId: String) -> String? { values[userId] }
    func save(_ operationId: String, userId: String) { values[userId] = operationId }
    func clear(userId: String) { values[userId] = nil; onClear?() }
}

@MainActor
private final class RetakeCalls {
    enum Step: String { case assessment, knowledge, dose, finalize }

    var operationIds: [String] = []
    var order: [String] = []
    var notifications = 0
    var failStep: Step?

    func taskPlan(_ action: RetakeAssessmentCoordinator.TaskPlanAction, _ operationId: String) async throws {
        operationIds.append(operationId)
        order.append(action == .reset ? "reset" : "finalize")
        if action == .finalize && failStep == .finalize { throw RetakeTestError.failed }
    }
    func assessment(_ uid: String) async throws {
        order.append("assessment")
        if failStep == .assessment { throw RetakeTestError.failed }
    }
    func knowledge(_ uid: String) async throws {
        order.append("knowledge")
        if failStep == .knowledge { throw RetakeTestError.failed }
    }
    func dose(_ uid: String) async throws {
        order.append("dose")
        if failStep == .dose { throw RetakeTestError.failed }
    }
    func notify() async { notifications += 1; order.append("notify") }
    func noteClear() { order.append("clear") }
}
