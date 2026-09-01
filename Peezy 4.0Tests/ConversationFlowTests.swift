//
//  ConversationFlowTests.swift
//  Peezy 4.0Tests
//
//  Spec 09 Phase 4: additive FlowDefinition decode, spawn resolution
//  (guards, per-selection expansion, zero-spawn), and the remembered-answer
//  (skipIfKnown) advance walk.
//

import Foundation
import Testing
@testable import Peezy_4_0

struct ConversationFlowTests {

    private func decodeDefinition(_ json: String) throws -> FlowDefinition {
        try JSONDecoder().decode(FlowDefinition.self, from: Data(json.utf8))
    }

    // MARK: - Additive decode

    @Test func existingDefinitionShapeDecodesUnchanged() throws {
        let json = #"""
        {
          "workflowId": "update_gym",
          "taskTitle": "Handle my gym",
          "steps": [
            { "id": "intro", "kind": "title", "icon": "figure.run", "next": "handling" },
            { "id": "handling", "kind": "decision",
              "branches": [ { "value": "peezy", "next": "summary" } ],
              "next": "summary" },
            { "id": "summary", "kind": "summary" }
          ]
        }
        """#
        let definition = try decodeDefinition(json)
        #expect(definition.steps.count == 3)
        #expect(definition.steps.allSatisfy { $0.skipIfKnown == nil && $0.spawns == nil })
    }

    @Test func spawnStepDecodesAdditively() throws {
        let json = #"""
        {
          "workflowId": "update_auto_insurance",
          "taskTitle": "Auto insurance",
          "steps": [
            { "id": "intent", "kind": "select", "skipIfKnown": "insurance_intent",
              "options": [ { "id": "update", "label": "Update my policy", "icon": "car" } ],
              "next": "wrap" },
            { "id": "wrap", "kind": "spawn",
              "spawns": [
                { "taskId": "AUTO_INSURANCE_UPDATE", "when": { "intent": "update" } },
                { "taskId": "UPDATE_INSTITUTION", "perSelectionFrom": "provider" }
              ] }
          ]
        }
        """#
        let definition = try decodeDefinition(json)
        let wrap = try #require(definition.step(withId: "wrap"))
        #expect(wrap.kind == .spawn)
        #expect(definition.step(withId: "intent")?.skipIfKnown == "insurance_intent")
        #expect(wrap.spawns == [
            FlowSpawnDef(taskId: "AUTO_INSURANCE_UPDATE", when: ["intent": "update"], perSelectionFrom: nil),
            FlowSpawnDef(taskId: "UPDATE_INSTITUTION", when: nil, perSelectionFrom: "provider")
        ])
    }

    // MARK: - Guarded selection

    @Test func whenGuardSelectsSpawnByRecordedIntent() {
        let spawns = [
            FlowSpawnDef(taskId: "AUTO_INSURANCE_UPDATE", when: ["intent": "update"], perSelectionFrom: nil),
            FlowSpawnDef(taskId: "AUTO_INSURANCE_SHOP", when: ["intent": "shop"], perSelectionFrom: nil)
        ]
        let resolved = FlowEngineView.resolveSpawns(spawns, answers: ["intent": ["shop"]], steps: [])
        #expect(resolved.count == 1)
        #expect(resolved.first?.taskId == "AUTO_INSURANCE_SHOP")
        #expect(resolved.first?.titleParams == nil)
    }

    // MARK: - Per-selection expansion

    @Test func perSelectionExpandsWithOptionLabels() throws {
        let providerStep = try JSONDecoder().decode(FlowStep.self, from: Data(#"""
        {
          "id": "provider", "kind": "select",
          "options": [
            { "id": "chase", "label": "Chase", "icon": "building.columns" },
            { "id": "ally", "label": "Ally", "icon": "building.columns" },
            { "id": "fidelity", "label": "Fidelity", "icon": "building.columns" }
          ]
        }
        """#.utf8))
        let spawns = [FlowSpawnDef(taskId: "UPDATE_INSTITUTION", when: nil, perSelectionFrom: "provider")]
        let resolved = FlowEngineView.resolveSpawns(
            spawns,
            answers: ["provider": ["chase", "ally", "fidelity"]],
            steps: [providerStep]
        )
        #expect(resolved.count == 3)
        #expect(resolved.map { $0.titleParams?["institution"] } == ["Chase", "Ally", "Fidelity"])
        #expect(resolved.map(\.institutionId) == ["chase", "ally", "fidelity"])
        #expect(resolved.map(\.institution) == ["Chase", "Ally", "Fidelity"])
        #expect(resolved.map { $0.subject?.kind } == ["service", "service", "service"])
        #expect(resolved.map { $0.subject?.id } == ["chase", "ally", "fidelity"])
        #expect(resolved.allSatisfy { $0.taskId == "UPDATE_INSTITUTION" })
    }

    @Test func rowExpandedFinancialProvidersProduceOneSubjectAwareSpawnPerRow() throws {
        let base = try JSONDecoder().decode(FlowStep.self, from: Data(#"{"id":"provider","kind":"select","options":[{"id":"chase","label":"Chase","icon":"bank"}]}"#.utf8))
        var first = base
        first.id = "checking_1.provider"
        first.rowSubjectId = "subject-a"
        var second = base
        second.id = "checking_2.provider"
        second.rowSubjectId = "subject-b"
        let resolved = FlowEngineView.resolveSpawns(
            [FlowSpawnDef(taskId: "UPDATE_INSTITUTION", perSelectionFrom: "provider")],
            answers: [first.id: ["chase"], second.id: ["chase", "chase"]],
            answerIdentities: [:],
            steps: [first, second]
        )
        #expect(resolved.count == 3)
        #expect(resolved.map { $0.subject?.id } == ["subject-a", "subject-b", "subject-b"])
        #expect(resolved.map(\.institutionId) == ["chase", "chase", "chase"])
        #expect(resolved.map(\.institution) == ["Chase", "Chase", "Chase"])
    }

    @Test func makePayloadPreservesLegacyShapeAndSerializesT2Identity() throws {
        let legacy = SpawnService.makePayload(
            requestToken: "token", source: .init(kind: "nudge", id: "n"),
            expectedUserId: "u", spawns: [.init(taskId: "TASK")], answers: nil
        )
        #expect(legacy.keys.sorted() == ["expectedUserId", "source", "spawns", "token"])
        #expect((legacy["spawns"] as? [[String: Any]])?.first?.keys.sorted() == ["taskId"])

        let t2 = SpawnService.makePayload(
            requestToken: "token", source: .init(kind: "conversation", id: "flow"),
            expectedUserId: nil,
            spawns: [.init(taskId: "TASK", titleParams: ["institution": "Bank"], subject: .init(kind: "service", id: "row"), institutionId: "bank-id", institution: "Bank")],
            answers: nil
        )
        let entry = try #require((t2["spawns"] as? [[String: Any]])?.first)
        #expect(entry["subject"] as? [String: String] == ["kind": "service", "id": "row"])
        #expect(entry["institutionId"] as? String == "bank-id")
        #expect(entry["institution"] as? String == "Bank")
    }

    @Test func businessIdentityMigrationGeneratesOneStableUUID() {
        var generated = 0
        var identity: FlowAnswerIdentity?
        identity = BusinessSearchIdentity.makeManual(label: "Old Bank", existing: identity) {
            generated += 1
            return "uuid-one"
        }
        identity = BusinessSearchIdentity.makeManual(label: "Renamed Bank", existing: identity) {
            generated += 1
            return "uuid-two"
        }
        #expect(identity == FlowAnswerIdentity(id: "uuid-one", label: "Renamed Bank", source: .manual))
        #expect(generated == 1)
    }

    @Test func flowRowsHaveDurableSubjectFallback() throws {
        let legacy = try #require(FlowRow(firestoreData: ["id": "checking_1", "category": "Checking"]))
        let modern = try #require(FlowRow(firestoreData: ["id": "checking_1", "subjectId": "uuid", "category": "Checking"]))
        #expect(legacy.subjectId == "checking_1")
        #expect(modern.subjectId == "uuid")
    }

    @Test func rowSubjectIdentitySurvivesReorderAndInstitutionLabelRename() throws {
        let first = try JSONDecoder().decode(FlowStep.self, from: Data(#"{"id":"checking_1.provider","kind":"select","options":[{"id":"bank-id","label":"Old Bank","icon":"bank"}]}"#.utf8))
        var firstWithSubject = first
        firstWithSubject.rowSubjectId = "subject-1"
        var secondWithSubject = first
        secondWithSubject.id = "checking_2.provider"
        secondWithSubject.rowSubjectId = "subject-2"
        secondWithSubject.options = [FlowOptionDef(id: "bank-id", label: "Renamed Bank", icon: "bank")]
        let spawn = [FlowSpawnDef(taskId: "UPDATE_INSTITUTION", perSelectionFrom: "provider")]
        let answers = [firstWithSubject.id: ["bank-id"], secondWithSubject.id: ["bank-id"]]

        let original = FlowEngineView.resolveSpawns(
            spawn, answers: answers, steps: [firstWithSubject, secondWithSubject]
        )
        let reordered = FlowEngineView.resolveSpawns(
            spawn, answers: answers, steps: [secondWithSubject, firstWithSubject]
        )

        #expect(original.map { $0.subject?.id } == ["subject-1", "subject-2"])
        #expect(reordered.map { $0.subject?.id } == ["subject-2", "subject-1"])
        #expect(Set(original.compactMap(\.subject?.id)).count == 2)
        #expect(original.map(\.institutionId) == ["bank-id", "bank-id"])
        #expect(original.map(\.institution) == ["Old Bank", "Renamed Bank"])
    }

    @Test func medicalAndMembershipRowExpansionStillChainsWithoutSpawnMutation() throws {
        let definition = try decodeDefinition(#"""
        {
          "workflowId":"providers", "taskTitle":"Providers",
          "steps":[
            {"id":"provider","kind":"businessSearch","forEachRow":true,
             "rowConfigs":{
               "Medical":{"question":"Doctor?","placeholder":"Search","searchHint":"doctor"},
               "Membership":{"question":"Membership?","placeholder":"Search","searchHint":"club"}
             }, "next":"summary"},
            {"id":"summary","kind":"summary"}
          ]
        }
        """#)
        let rows = [
            FlowRow(firestoreData: ["id": "medical_1", "category": "Medical", "subjectId": "medical-subject"])!,
            FlowRow(firestoreData: ["id": "membership_1", "category": "Membership", "subjectId": "membership-subject"])!
        ]
        let resolved = definition.resolvedSteps(rows: rows)
        #expect(resolved.map(\.id) == ["medical_1.provider", "membership_1.provider", "summary"])
        #expect(resolved[0].next == "membership_1.provider")
        #expect(resolved[1].next == "summary")
        #expect(resolved.prefix(2).allSatisfy { $0.spawns == nil })
    }

    @Test func terminalClearRemovesAnswerIdentityAndRestartGeneratesFreshIdentity() {
        #expect(TaskActionService.flowStateFields == [
            "flowPath", "flowAnswers", "flowAnswerIdentities", "flowAttemptId"
        ])
        let old = BusinessSearchIdentity.makeManual(label: "Provider", existing: nil) { "old-id" }
        let fresh = BusinessSearchIdentity.makeManual(label: "Provider", existing: nil) { "fresh-id" }
        #expect(old.id != fresh.id)
    }

    @MainActor
    @Test func terminalCleanupWaitsForSuccessAndFailureCannotAdvanceOrReopenWithoutIdentity() async throws {
        let oldIdentity = FlowAnswerIdentity(id: "old-id", label: "Provider", source: .manual)
        var persistedIdentities = ["provider": oldIdentity]
        var didAdvance = false
        let failing = ControlledVoidOperation()

        let failedTask = Task { @MainActor in
            try await FlowTerminalCleanup.run(
                clear: {
                    try await failing.call()
                    persistedIdentities.removeAll()
                },
                onSuccess: { didAdvance = true }
            )
        }
        await failing.waitUntilStarted()
        #expect(!didAdvance)
        #expect(persistedIdentities["provider"] == oldIdentity)
        failing.fail()
        await #expect(throws: ControlledTestError.failed) { try await failedTask.value }
        #expect(!didAdvance)
        #expect(persistedIdentities["provider"] == oldIdentity)

        let succeeding = ControlledVoidOperation()
        let successTask = Task { @MainActor in
            try await FlowTerminalCleanup.run(
                clear: {
                    try await succeeding.call()
                    persistedIdentities.removeAll()
                },
                onSuccess: { didAdvance = true }
            )
        }
        await succeeding.waitUntilStarted()
        #expect(!didAdvance)
        succeeding.succeed()
        try await successTask.value
        #expect(didAdvance)
        #expect(persistedIdentities.isEmpty)
        let reopened = BusinessSearchIdentity.makeManual(label: "Provider", existing: persistedIdentities["provider"]) {
            "fresh-id"
        }
        #expect(reopened.id == "fresh-id")
    }

    @MainActor
    @Test func successfulSubmissionWithFailedCleanupRetriesDurableBoundaryAndAdvancesOnce() async throws {
        let phase = FlowTerminalSubmissionState()
        var submitCount = 0
        var clearCount = 0
        var advanceCount = 0

        await #expect(throws: ControlledTestError.failed) {
            try await phase.run(
                submit: { submitCount += 1 },
                clear: {
                    clearCount += 1
                    throw ControlledTestError.failed
                },
                onSuccess: { advanceCount += 1 }
            )
        }
        #expect(phase.submissionSucceeded)
        #expect(submitCount == 1)
        #expect(clearCount == 1)
        #expect(advanceCount == 0)

        try await phase.run(
            submit: { submitCount += 1 },
            clear: { clearCount += 1 },
            onSuccess: { advanceCount += 1 }
        )
        #expect(submitCount == 2)
        #expect(clearCount == 2)
        #expect(advanceCount == 1)
    }

    @MainActor
    @Test func submissionTokenIsStableAcrossFreshFlowStateAndDistinctForEveryIdentityDimension() throws {
        let firstState = FlowTerminalSubmissionState()
        let recreatedState = FlowTerminalSubmissionState()
        _ = firstState
        _ = recreatedState

        let original = WorkflowSubmissionToken.make(
            userId: "user-a", taskId: "task-a", workflowId: "workflow-a", flowAttemptId: "attempt-a"
        )
        let afterRecreation = WorkflowSubmissionToken.make(
            userId: "user-a", taskId: "task-a", workflowId: "workflow-a", flowAttemptId: "attempt-a"
        )
        let variants = [
            original,
            WorkflowSubmissionToken.make(userId: "user-b", taskId: "task-a", workflowId: "workflow-a", flowAttemptId: "attempt-a"),
            WorkflowSubmissionToken.make(userId: "user-a", taskId: "task-b", workflowId: "workflow-a", flowAttemptId: "attempt-a"),
            WorkflowSubmissionToken.make(userId: "user-a", taskId: "task-a", workflowId: "workflow-b", flowAttemptId: "attempt-a"),
            WorkflowSubmissionToken.make(userId: "user-a", taskId: "task-a", workflowId: "workflow-a", flowAttemptId: "attempt-b")
        ]

        #expect(original == afterRecreation)
        #expect(Set(variants).count == variants.count)
        #expect(original.utf8.count <= 80)

        var answers = WorkflowAnswers(workflowId: "workflow-a")
        answers.answers = ["answer": ["yes"]]
        let payload = WorkflowService.makePayload(
            workflowId: "workflow-a",
            answers: answers,
            userId: "user-a",
            submissionToken: original
        )
        #expect(payload["submissionToken"] as? String == original)
        let legacyPayload = WorkflowService.makePayload(
            workflowId: "workflow-a", answers: answers, userId: "user-a", submissionToken: nil
        )
        #expect(legacyPayload["submissionToken"] == nil)
    }

    @MainActor
    @Test func flowAttemptIdPersistsRoundTripsMigratesLegacyAndRenewsAfterClear() async throws {
        let legacy = FlowProgressSnapshot(
            path: ["card.2"],
            answers: ["services": ["deep"]],
            answerIdentities: [:]
        )
        var migrationWrites: [FlowProgressSnapshot] = []
        let firstLifecycle = FlowExitCoordinator(
            userId: "user",
            taskId: "task",
            loadProgress: { legacy },
            flowAttemptIdGenerator: { "attempt-one" },
            writeProgress: { migrationWrites.append($0) }
        )

        let migrated = await firstLifecycle.restore()
        #expect(migrated.flowAttemptId == "attempt-one")
        #expect(firstLifecycle.flowAttemptId == "attempt-one")
        while migrationWrites.isEmpty { await Task.yield() }
        #expect(migrationWrites == [migrated])

        let persistedData = TaskActionService.flowProgressData(for: migrated)
        #expect(persistedData["flowAttemptId"] as? String == "attempt-one")
        let roundTripped = TaskActionService.flowProgressSnapshot(from: persistedData)
        #expect(roundTripped == migrated)

        let recreated = FlowExitCoordinator(
            userId: "user",
            taskId: "task",
            loadProgress: { roundTripped },
            flowAttemptIdGenerator: { "must-not-replace-persisted-attempt" },
            writeProgress: { _ in }
        )
        #expect(await recreated.restore().flowAttemptId == "attempt-one")

        var clearedData = persistedData
        for field in TaskActionService.flowStateFields {
            clearedData.removeValue(forKey: field)
        }
        #expect(TaskActionService.flowStateFields.contains("flowAttemptId"))
        let secondLifecycle = FlowExitCoordinator(
            userId: "user",
            taskId: "task",
            loadProgress: { TaskActionService.flowProgressSnapshot(from: clearedData) },
            flowAttemptIdGenerator: { "attempt-two" },
            writeProgress: { _ in }
        )
        #expect(await secondLifecycle.restore().flowAttemptId == "attempt-two")
        #expect(secondLifecycle.flowAttemptId != firstLifecycle.flowAttemptId)
    }

    @Test func setDerivedWorkflowAnswersHaveCanonicalArraysAndFingerprintInput() throws {
        var forward = Set<String>()
        forward.insert("standard")
        forward.insert("deep")
        var reverse = Set<String>()
        reverse.insert("deep")
        reverse.insert("standard")

        let first = FlowProgressCoding.workflowAnswers(
            workflowId: "book_cleaners", setAnswers: ["services": forward]
        )
        let second = FlowProgressCoding.workflowAnswers(
            workflowId: "book_cleaners", setAnswers: ["services": reverse]
        )
        #expect(first.answers["services"] == ["deep", "standard"])
        #expect(second.answers == first.answers)

        let token = WorkflowSubmissionToken.make(
            userId: "user", taskId: "task", workflowId: "book_cleaners", flowAttemptId: "attempt"
        )
        let firstPayload = WorkflowService.makePayload(
            workflowId: "book_cleaners", answers: first, userId: "user", submissionToken: token
        )
        let secondPayload = WorkflowService.makePayload(
            workflowId: "book_cleaners", answers: second, userId: "user", submissionToken: token
        )
        let firstEnvelope = try #require(firstPayload["answers"] as? [String: Any])
        let secondEnvelope = try #require(secondPayload["answers"] as? [String: Any])
        #expect(firstEnvelope["answers"] as? [String: [String]] == secondEnvelope["answers"] as? [String: [String]])
        #expect(firstPayload["submissionToken"] as? String == secondPayload["submissionToken"] as? String)
    }

    @MainActor
    @Test func findCleanersRejectsAnswerMutationDuringSubmitAndAfterCleanupFailure() async throws {
        let coordinator = FlowExitCoordinator(
            userId: "user", taskId: "task", writeProgress: { _ in }
        )
        let cleanup = ControlledVoidOperation()
        let submission = FlowTerminalSubmissionState()
        var answers: [String: Set<String>] = ["which_place": ["move_out"]]
        var isSubmitting = true

        let attempt = Task { @MainActor in
            try await submission.run(
                submit: {},
                clear: {
                    try await coordinator.terminalize { try await cleanup.call() }
                },
                onSuccess: {}
            )
        }
        await cleanup.waitUntilStarted()
        #expect(coordinator.isTerminalizing)

        let changedDuringSubmit = FlowAnswerMutationGate.apply(
            isSubmitting: isSubmitting,
            isTerminalizing: coordinator.isTerminalizing
        ) {
            answers["which_place"] = ["both"]
        }
        #expect(!changedDuringSubmit)
        #expect(answers["which_place"] == ["move_out"])

        cleanup.fail()
        await #expect(throws: ControlledTestError.failed) { try await attempt.value }
        isSubmitting = false
        let changedAfterFailure = FlowAnswerMutationGate.apply(
            isSubmitting: isSubmitting,
            isTerminalizing: coordinator.isTerminalizing
        ) {
            answers["which_place"] = ["both"]
        }
        #expect(!changedAfterFailure)
        #expect(answers["which_place"] == ["move_out"])
    }

    @MainActor
    @Test func preSubmitBarrierWaitsForLegacyAttemptMigrationBeforeCallableAndRecreationReusesToken() async throws {
        let migrationWrite = ControlledVoidOperation()
        var persistedData: [String: Any]?
        let firstCoordinator = FlowExitCoordinator(
            userId: "user",
            taskId: "task",
            loadProgress: {
                FlowProgressSnapshot(path: ["summary"], answers: ["answer": ["yes"]])
            },
            flowAttemptIdGenerator: { "attempt-one" },
            writeProgress: { snapshot in
                try await migrationWrite.call()
                persistedData = TaskActionService.flowProgressData(for: snapshot)
            }
        )
        _ = await firstCoordinator.restore()
        await migrationWrite.waitUntilStarted()

        let barrier = firstCoordinator.beginPreSubmitBarrier()
        var callableStarted = false
        let callable = Task { @MainActor in
            let attemptId = try await barrier.value
            callableStarted = true
            return attemptId
        }
        await Task.yield()
        #expect(firstCoordinator.isSubmissionLocked)
        #expect(firstCoordinator.isExitLocked)
        #expect(!callableStarted)

        migrationWrite.succeed()
        let firstAttemptId = try await callable.value
        #expect(callableStarted)
        #expect(firstAttemptId == "attempt-one")
        #expect(firstCoordinator.persistedFlowAttemptId == firstAttemptId)

        let persistedSnapshot = TaskActionService.flowProgressSnapshot(
            from: try #require(persistedData)
        )
        let recreatedCoordinator = FlowExitCoordinator(
            userId: "user",
            taskId: "task",
            loadProgress: { persistedSnapshot },
            flowAttemptIdGenerator: { "must-not-replace-persisted" },
            writeProgress: { _ in }
        )
        _ = await recreatedCoordinator.restore()
        let recreatedAttemptId = try await recreatedCoordinator.beginPreSubmitBarrier().value
        let originalToken = WorkflowSubmissionToken.make(
            userId: "user", taskId: "task", workflowId: "workflow", flowAttemptId: firstAttemptId
        )
        let recreatedToken = WorkflowSubmissionToken.make(
            userId: "user", taskId: "task", workflowId: "workflow", flowAttemptId: recreatedAttemptId
        )
        #expect(recreatedAttemptId == firstAttemptId)
        #expect(recreatedToken == originalToken)
    }

    @MainActor
    @Test func preSubmitBarrierFailedAttemptWritePreventsCallableAndUnlocksWithoutTerminalizing() async throws {
        let failedWrite = ControlledVoidOperation()
        let coordinator = FlowExitCoordinator(
            userId: "user",
            taskId: "task",
            loadProgress: { .empty },
            flowAttemptIdGenerator: { "attempt" },
            writeProgress: { _ in try await failedWrite.call() }
        )
        _ = await coordinator.restore()
        await failedWrite.waitUntilStarted()

        let barrier = coordinator.beginPreSubmitBarrier()
        var callableStarted = false
        let callable = Task { @MainActor in
            _ = try await barrier.value
            callableStarted = true
        }
        #expect(coordinator.isSubmissionLocked)
        #expect(coordinator.isExitLocked)
        failedWrite.fail()

        await #expect(throws: FlowPreSubmitBarrierError.self) {
            try await callable.value
        }
        #expect(!callableStarted)
        #expect(!coordinator.isSubmissionLocked)
        #expect(!coordinator.isExitLocked)
        #expect(!coordinator.isTerminalizing)
        #expect(coordinator.persistedFlowAttemptId == nil)
    }

    @MainActor
    @Test func terminalizationDrainsQueuedWritesRejectsNewPersistenceAndRetriesOnlyClear() async throws {
        let delayedWrite = ControlledVoidOperation()
        var writeCount = 0
        let coordinator = FlowExitCoordinator(
            userId: "user",
            taskId: "task",
            writeProgress: { _ in
                writeCount += 1
                try await delayedWrite.call()
            }
        )
        let queued = FlowProgressSnapshot(
            path: ["queued"],
            answers: ["answer": ["yes"]],
            flowAttemptId: coordinator.flowAttemptId
        )
        coordinator.persist(queued)
        await delayedWrite.waitUntilStarted()

        let firstClear = ControlledVoidOperation()
        var clearCount = 0
        let firstTerminalization = Task { @MainActor in
            try await coordinator.terminalize {
                clearCount += 1
                try await firstClear.call()
            }
        }
        await Task.yield()
        #expect(coordinator.isTerminalizing)
        #expect(coordinator.isExitLocked)
        #expect(clearCount == 0)

        coordinator.persist(.init(path: ["ignored"], answers: ["answer": ["no"]]))
        #expect(coordinator.snapshot == queued)
        #expect(writeCount == 1)

        delayedWrite.succeed()
        await firstClear.waitUntilStarted()
        #expect(clearCount == 1)
        firstClear.fail()
        await #expect(throws: ControlledTestError.failed) {
            try await firstTerminalization.value
        }
        #expect(coordinator.isTerminalizing)
        #expect(coordinator.isExitLocked)

        coordinator.persist(.init(path: ["still-ignored"], answers: [:]))
        #expect(coordinator.snapshot == queued)
        #expect(writeCount == 1)

        let retryClear = ControlledVoidOperation()
        let retry = Task { @MainActor in
            try await coordinator.terminalize {
                clearCount += 1
                try await retryClear.call()
            }
        }
        await retryClear.waitUntilStarted()
        #expect(clearCount == 2)
        #expect(writeCount == 1)
        retryClear.succeed()
        try await retry.value
    }

    @MainActor
    @Test func businessSelectionCancelsStaleResolutionAndGatesImmediateContinueAndFieldInput() async {
        let controller = BusinessSearchSelectionController(uuid: { "fallback-id" })
        let first = ControlledStringOperation()
        let second = ControlledStringOperation()

        controller.beginAutocompleteSelection(label: "Provider A", resolveID: first.call)
        await first.waitUntilStarted()
        #expect(controller.isResolving)
        #expect(!controller.canConfirm)
        #expect(!controller.allowsFieldInteraction)
        #expect(controller.confirm() == nil)

        controller.beginAutocompleteSelection(label: "Provider B", resolveID: second.call)
        await second.waitUntilStarted()
        second.succeed("mapkit-b")
        await controller.waitUntilResolutionFinishes()
        first.succeed("mapkit-a") // stale result arrives after B
        await Task.yield()

        #expect(controller.selectedIdentity == .init(id: "mapkit-b", label: "Provider B", source: .mapkit))
        #expect(controller.confirm()?.id == "mapkit-b")
    }

    @MainActor
    @Test func mapKitSelectionClearThenManualProviderGetsFreshIdentityWhileManualEditsStayStable() async {
        var generated = ["manual-b", "unused"]
        let controller = BusinessSearchSelectionController(uuid: { generated.removeFirst() })
        controller.beginAutocompleteSelection(label: "Provider A", resolveID: { "mapkit-a" })
        await controller.waitUntilResolutionFinishes()
        #expect(controller.selectedIdentity?.id == "mapkit-a")

        controller.clear()
        #expect(controller.selectedIdentity == nil)
        controller.userEditedText("Provider B")
        let providerB = controller.confirm()
        #expect(providerB == .init(id: "manual-b", label: "Provider B", source: .manual))

        controller.userEditedText("Provider B renamed")
        let renamed = controller.confirm()
        #expect(renamed?.id == "manual-b")
        #expect(renamed?.label == "Provider B renamed")
        #expect(renamed?.source == .manual)
    }

    @Test func rowExpandedBusinessSearchIdentityPersistsResumesAndSpawnsWithDurableSubject() throws {
        let definition = try decodeDefinition(#"""
        {
          "workflowId":"financial_accounts", "taskTitle":"Accounts",
          "steps":[
            {"id":"provider","kind":"businessSearch","forEachRow":true,
             "rowConfigs":{"Checking":{"question":"Bank?","placeholder":"Search","searchHint":"bank"}},
             "next":"spawn"},
            {"id":"spawn","kind":"spawn","spawns":[{"taskId":"UPDATE_INSTITUTION","perSelectionFrom":"provider"}]}
          ]
        }
        """#)
        let rows = [FlowRow(firestoreData: [
            "id": "checking_1", "category": "Checking", "subjectId": "row-subject-uuid"
        ])!]
        let resolved = definition.resolvedSteps(rows: rows)
        let provider = try #require(resolved.first)
        #expect(provider.id == "checking_1.provider")
        #expect(provider.kind == .businessSearch)

        let snapshot = FlowProgressSnapshot(
            path: [provider.id],
            answers: [provider.id: ["Renamed Bank"]],
            answerIdentities: [
                provider.id: .init(id: "mapkit-stable", label: "Renamed Bank", source: .mapkit)
            ]
        )
        let fields = TaskActionService.flowProgressData(for: snapshot)
        let resumed = TaskActionService.flowProgressSnapshot(from: fields)
        #expect(resumed == snapshot)

        let spawnStep = try #require(resolved.last)
        let spawns = FlowEngineView.resolveSpawns(
            spawnStep.spawns ?? [], answers: resumed.answers,
            answerIdentities: resumed.answerIdentities, steps: resolved
        )
        #expect(spawns.count == 1)
        #expect(spawns.first?.subject == .init(kind: "service", id: "row-subject-uuid"))
        #expect(spawns.first?.institutionId == "mapkit-stable")
        #expect(spawns.first?.institution == "Renamed Bank")
    }

    // MARK: - Zero spawn

    @Test func unsatisfiedGuardsResolveToZeroSpawns() {
        let guarded = [
            FlowSpawnDef(taskId: "RETURN_ISP_EQUIPMENT", when: ["current": "yes"], perSelectionFrom: nil)
        ]
        #expect(FlowEngineView.resolveSpawns(guarded, answers: ["current": ["no"]], steps: []).isEmpty)

        let unselected = [
            FlowSpawnDef(taskId: "UPDATE_INSTITUTION", when: nil, perSelectionFrom: "provider")
        ]
        #expect(FlowEngineView.resolveSpawns(unselected, answers: [:], steps: []).isEmpty)
    }

    // MARK: - Remembered-step advance

    @Test func knownAnswerStepsAdoptAndAdvance() throws {
        let definition = try decodeDefinition(#"""
        {
          "workflowId": "setup_internet",
          "taskTitle": "Internet",
          "steps": [
            { "id": "current", "kind": "select", "skipIfKnown": "isp_current",
              "options": [
                { "id": "yes", "label": "Yes", "icon": "wifi" },
                { "id": "no", "label": "No", "icon": "wifi.slash" }
              ],
              "branches": [ { "value": "no", "next": "wrap" } ],
              "next": "speed" },
            { "id": "speed", "kind": "select", "skipIfKnown": "isp_speed", "next": "wrap" },
            { "id": "wrap", "kind": "spawn" }
          ]
        }
        """#)

        // Firestore flattening: NSNumber numerics/bools become flat strings.
        let known = MoveAnswersStore.flattened([
            "isp_current": "yes",
            "isp_speed": NSNumber(value: 300),
            "has_car": true
        ])
        #expect(known["isp_speed"] == "300")
        #expect(known["has_car"] == "true")

        var answers: [String: [String]] = [:]
        let landing = FlowEngineView.resolveKnownAnswerSkips(
            from: "current",
            steps: definition.steps,
            knownAnswers: known,
            answers: &answers
        )
        #expect(landing == "wrap")
        #expect(answers["current"] == ["yes"])
        #expect(answers["speed"] == ["300"])

        // Branch semantics: a remembered "no" takes the branch past "speed".
        var branchAnswers: [String: [String]] = [:]
        let branchLanding = FlowEngineView.resolveKnownAnswerSkips(
            from: "current",
            steps: definition.steps,
            knownAnswers: ["isp_current": "no"],
            answers: &branchAnswers
        )
        #expect(branchLanding == "wrap")
        #expect(branchAnswers["speed"] == nil)
    }
}

private enum ControlledTestError: Swift.Error { case failed }

@MainActor
private final class ControlledVoidOperation {
    private var continuation: CheckedContinuation<Void, any Error>?
    private(set) var started = false

    func call() async throws {
        started = true
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func succeed() { continuation?.resume(); continuation = nil }
    func fail() { continuation?.resume(throwing: ControlledTestError.failed); continuation = nil }
}

@MainActor
private final class ControlledStringOperation {
    private var continuation: CheckedContinuation<String?, Never>?
    private(set) var started = false

    func call() async -> String? {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func succeed(_ value: String) { continuation?.resume(returning: value); continuation = nil }
}
