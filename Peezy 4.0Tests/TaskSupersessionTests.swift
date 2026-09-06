import FirebaseFirestore
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

    // MARK: - S4 contributions (S4-CD3; C9.5.20–C9.5.24): D18–D21. S2's cases above are never edited.

    @Test func d18ByteExactV1FixtureAndEveryMalformedShape() throws {
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(TaskRowLegacySnapshotTests.legacyFixtureJSON.utf8)) as? [String: Any])
        guard case let .superseded(legacy) = SupersededContractDecoder.decode(fixture) else { Issue.record("v1"); return }
        #expect(legacy.source == .legacyV1 && legacy.supersededBy == "a2_b6c1f0d9" && legacy.copy == "Replaced by an updated task" && legacy.supersededAt == nil && legacy.detailAt == nil)
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let v2: [String: Any] = ["schema_version": 2, "terminal_kind": "superseded", "superseded_by": "inst_2", "superseded_at": Timestamp(date: at), "visible_status_copy": "Replaced", "visible_status_detail": ["kind": "DATE", "at": Timestamp(date: at)]]
        guard case let .superseded(fresh) = SupersededContractDecoder.decode(v2) else { Issue.record("v2"); return }
        #expect(fresh.source == .v2 && fresh.supersededBy == "inst_2" && fresh.supersededAt == at && fresh.detailAt == at && fresh.copy == "Replaced")
        var missingDetail = v2; missingDetail["visible_status_detail"] = nil
        var extra = v2; extra["profile_version"] = 1
        var noAt = v2; noAt["superseded_at"] = nil
        var badBy = v2; badBy["superseded_by"] = ""
        var v1Extra = fixture; v1Extra["superseded_at"] = Timestamp(date: at)
        var v1Schemaless = fixture; v1Schemaless["schema_version"] = nil
        for (name, shape) in [("v2 missing detail", missingDetail), ("v2 surplus", extra), ("v2 no superseded_at", noAt), ("v2 blank by", badBy), ("v1 hybrid", v1Extra), ("schema-less", v1Schemaless)] {
            #expect(SupersededContractDecoder.decode(shape) == .malformedPresent, Comment(rawValue: name))
        }
    }

    @Test func d19GoldenStringsAcrossLocaleAndTimeZoneDayRollover() {
        // 2027-01-15T23:30:00Z: still Jan 15 in UTC, already Jan 16 in Tokyo, Jan 15 in Los Angeles
        let instant = Date(timeIntervalSince1970: 1_800_055_800)
        let posix = Locale(identifier: "en_US_POSIX")
        let presentation = SupersededPresentation(source: .v2, supersededBy: "inst", supersededAt: instant, copy: "Replaced", detailAt: instant)
        #expect(presentation.renderedCopy(locale: posix, timeZone: TimeZone(identifier: "UTC")!) == "Replaced \u{2014} Jan 15, 2027")
        #expect(presentation.renderedCopy(locale: posix, timeZone: TimeZone(identifier: "Asia/Tokyo")!) == "Replaced \u{2014} Jan 16, 2027")
        #expect(presentation.renderedCopy(locale: posix, timeZone: TimeZone(identifier: "America/Los_Angeles")!) == "Replaced \u{2014} Jan 15, 2027")
        #expect(presentation.renderedCopy(locale: Locale(identifier: "de_DE"), timeZone: TimeZone(identifier: "UTC")!) == "Replaced \u{2014} 15.01.2027")
        let legacy = SupersededPresentation(source: .legacyV1, supersededBy: "doc", supersededAt: nil, copy: "Replaced by an updated task", detailAt: nil)
        #expect(legacy.renderedCopy(locale: posix, timeZone: TimeZone(identifier: "Asia/Tokyo")!) == "Replaced by an updated task")
        #expect(PlanChangeDateFormatter.string(from: instant, locale: posix, timeZone: TimeZone(identifier: "UTC")!) == "Jan 15, 2027")
    }

    @Test func d20UndoEligibilityIsDecidedOnlyByTheServerWriteTime() {
        let until = Date(timeIntervalSince1970: 1_800_000_000)
        let live = PlanChangeUndoDescriptor(firstConfirmationUndoUntil: until, used: false, inFirstConfirmation: true)
        #expect(PlanChangeUndo.isAvailable(live, serverWriteTime: until.addingTimeInterval(-1)))
        #expect(PlanChangeUndo.isAvailable(live, serverWriteTime: until), "equal survives")
        #expect(!PlanChangeUndo.isAvailable(live, serverWriteTime: until.addingTimeInterval(0.001)), "past the deadline disappears")
        #expect(!PlanChangeUndo.isAvailable(PlanChangeUndoDescriptor(firstConfirmationUndoUntil: until, used: true, inFirstConfirmation: true), serverWriteTime: until.addingTimeInterval(-60)), "used")
        #expect(!PlanChangeUndo.isAvailable(PlanChangeUndoDescriptor(firstConfirmationUndoUntil: until, used: false, inFirstConfirmation: false), serverWriteTime: until.addingTimeInterval(-60)), "only the first CF")
        #expect(!PlanChangeUndo.isAvailable(nil, serverWriteTime: until.addingTimeInterval(-60)), "a stale instance without a descriptor dismisses")
    }

    @Test func d21HistoryLinesRollupAndOrderAreGolden() {
        let posix = Locale(identifier: "en_US_POSIX")
        let utc = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = [
            PlanChangeHistoryRow(action: .supersede, occurredAt: day),
            PlanChangeHistoryRow(action: .replacementOutcome, occurredAt: day.addingTimeInterval(3600)),
            PlanChangeHistoryRow(action: .confirmAmendment, occurredAt: day.addingTimeInterval(86_400)),
            PlanChangeHistoryRow(action: .undoConfirmation, occurredAt: day.addingTimeInterval(90_000)),
            PlanChangeHistoryRow(action: .reopen, occurredAt: day.addingTimeInterval(200_000))
        ]
        #expect(PlanChangeHistoryRow.Action.allCases.map(\.title) == ["Plan update started", "Updated task outcome recorded", "Plan update confirmed", "Confirmation undone", "Original task reopened"])
        #expect(PlanChangeHistoryPresentation.line(rows[0], locale: posix, timeZone: utc) == "Plan update started \u{00B7} Jan 15, 2027")
        #expect(PlanChangeHistoryPresentation.line(rows[1], locale: posix, timeZone: utc) == "Updated task outcome recorded \u{00B7} Jan 15, 2027", "same local day, different time")
        #expect(PlanChangeHistoryPresentation.line(rows[2], locale: posix, timeZone: utc) == "Plan update confirmed \u{00B7} Jan 16, 2027", "different day")
        let sameDay = PlanChangeHistoryRollup(count: 3, firstAt: day, lastAt: day.addingTimeInterval(7200))
        #expect(PlanChangeHistoryPresentation.rollupLine(sameDay, locale: posix, timeZone: utc) == "Earlier plan changes (3) \u{00B7} Jan 15, 2027")
        let span = PlanChangeHistoryRollup(count: 5, firstAt: day, lastAt: day.addingTimeInterval(86_400 * 3))
        #expect(PlanChangeHistoryPresentation.rollupLine(span, locale: posix, timeZone: utc) == "Earlier plan changes (5) \u{00B7} Jan 15, 2027\u{2013}Jan 18, 2027")
        let lines = PlanChangeHistoryPresentation.lines(rows: rows, rollup: span, locale: posix, timeZone: utc)
        #expect(lines.count == 6 && lines.first == "Original task reopened \u{00B7} Jan 17, 2027" && lines[4] == "Plan update started \u{00B7} Jan 15, 2027" && lines.last?.hasPrefix("Earlier plan changes (5)") == true, "reverse append order, the sole rollup once as the final row")
        #expect(PlanChangeHistoryPresentation.lines(rows: rows, rollup: nil, locale: posix, timeZone: utc).count == 5)
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

private enum RetakeTestError: Swift.Error { case failed 
}
