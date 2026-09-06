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

    // S3 (Decision 10, 2026-09-06): the two pre-S3 coordinator cases pinned the operation store and the
    // (String) closures. Their properties are asserted under the drive path here and in
    // DurableStoreRecoveryTests: one identity across failure and resume, notification only after finalize.

    @Test func coordinatorRetainsIdentityAcrossFinalizeFailureAndPostsOnlyAfterFinalize() async throws {
        let wires = try frozenResetWires()
        let (registry, handle) = try await preparedRegistry()
        let remote = ScriptedResetRemote(wires: wires)
        await remote.setFailFinalizeOnce()
        let trace = DriveTrace()
        await remote.attach(trace, registry: registry, handle: handle)
        let notifications = NotificationCounter()
        let coordinator = RetakeAssessmentCoordinator(
            currentUser: { "A" }, remote: remote, registry: registry,
            gestureId: { "rsg1_11111111-1111-4111-8111-111111111111" },
            cleanup: await trace.callbacks(), postNotification: { await notifications.bump(); await trace.record("notification") }
        )
        await #expect(throws: DriveTraceError.failed) { try await coordinator.retake() }
        #expect(await registry.snapshot().records.count == 1)
        #expect(await notifications.count == 0)
        try await coordinator.retake()
        let aliases = await remote.aliases
        #expect(aliases.count == 3 && Set(aliases).count == 1)
        #expect(await notifications.count == 1)
        #expect(await trace.order.suffix(2) == ["finalize", "notification"])
        #expect(await registry.snapshot().records.isEmpty)
    }

    @Test func coordinatorPropagatesEachLocalFailureAndReplaysWithTheSameIdentity() async throws {
        for failedStep in ["deleteAssessments", "deleteUserKnowledge", "resetDose"] {
            let wires = try frozenResetWires()
            let (registry, handle) = try await preparedRegistry()
            let remote = ScriptedResetRemote(wires: wires)
            let trace = DriveTrace()
            await remote.attach(trace, registry: registry, handle: handle)
            await trace.setFailing(failedStep)
            let notifications = NotificationCounter()
            let coordinator = RetakeAssessmentCoordinator(
                currentUser: { "A" }, remote: remote, registry: registry,
                gestureId: { "rsg1_11111111-1111-4111-8111-111111111111" },
                cleanup: await trace.callbacks(), postNotification: { await notifications.bump(); await trace.record("notification") }
            )
            await #expect(throws: DriveTraceError.failed) { try await coordinator.retake() }
            // C9.5.14: the failed callback is followed by exactly one post-error inspection (byte-identical pending → the error propagates)
            #expect(await trace.order.suffix(2) == [failedStep, "inspect"])
            #expect(await notifications.count == 0)
            let row = try #require(await registry.snapshot().records.first)
            #expect(row.phase == .resetReceiptAwaitingLocalReset)
            await trace.setFailing(nil)
            try await coordinator.retake()
            let aliases = await remote.aliases
            #expect(Set(aliases).count == 1)
            #expect(await notifications.count == 1)
            #expect(await trace.order.suffix(2) == ["finalize", "notification"])
            #expect(await registry.snapshot().records.isEmpty)
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
