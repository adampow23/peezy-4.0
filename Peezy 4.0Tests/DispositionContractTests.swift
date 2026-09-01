import Foundation
import FirebaseFirestore
import Testing
@testable import Peezy_4_0

struct DispositionContractTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func contractMapDecodesAllKnownFieldsAndPreservesRecursivePayload() throws {
        let at = now.addingTimeInterval(3_600)
        let card = try #require(PeezyCardFirestoreMapper.card(from: [
            "id": "CONTRACTED",
            "title": "Contracted",
            "status": "Snoozed",
            "dispositionContract": [
                "disposition": "DEFERRED",
                "owner": "user:u1",
                "next_action": "Return to the task",
                "next_trigger": [
                    "kind": "date",
                    "at": Timestamp(date: at),
                    "payload": [
                        "bool": true,
                        "int": NSNumber(value: 7),
                        "double": NSNumber(value: 2.5),
                        "string": "value",
                        "date": Timestamp(date: at),
                        "array": [NSNull(), NSNumber(value: 3), ["nested": false]]
                    ]
                ],
                "resume_destination": "flow://contracted",
                "visible_status_copy": "Scheduled for later",
                "profile_version": NSNumber(value: 4),
                "external_submission": true
            ]
        ], documentID: "CONTRACTED"))

        let contract = try #require(card.dispositionContract)
        #expect(contract.disposition == .deferred)
        #expect(contract.nextTrigger?.at == at)
        #expect(contract.profileVersion == 4)
        #expect(contract.externalSubmission)
        #expect(contract.nextTrigger?.payload?["bool"] == .bool(true))
        #expect(contract.nextTrigger?.payload?["int"] == .int(7))
        #expect(contract.nextTrigger?.payload?["double"] == .double(2.5))
        #expect(contract.nextTrigger?.payload?["array"] == .array([.null, .int(3), .map(["nested": .bool(false)])]))
    }

    @Test func unsupportedPayloadLeafIsDroppedWithoutRejectingCard() throws {
        let card = try #require(PeezyCardFirestoreMapper.card(from: [
            "status": "InProgress",
            "dispositionContract": [
                "disposition": "USER_ACTION_TRACKED",
                "next_trigger": ["kind": "event", "payload": ["valid": "yes", "bad": URL(string: "https://example.com")!]]
            ]
        ], documentID: "task"))
        #expect(card.dispositionContract?.nextTrigger?.payload == ["valid": .string("yes")])
    }

    @Test func missingContractProducesByteIdenticalLegacyCardSnapshot() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let dueDate = createdAt.addingTimeInterval(86_400)
        let legacy = try #require(PeezyCardFirestoreMapper.card(from: [
            "id": "catalog-task",
            "taskId": "catalog-task",
            "title": "Legacy task",
            "desc": "Legacy detail",
            "priority": "High",
            "createdAt": Timestamp(date: createdAt),
            "status": "Snoozed",
            "dueDate": Timestamp(date: dueDate),
            "category": "utilities",
            "urgencyPercentage": NSNumber(value: 71),
            "selfServiceOnly": true,
            "actionType": "off-app",
            "taskType": "provide_info",
            "tier": "task"
        ], documentID: "legacy"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let actualBytes = try encoder.encode(legacy)
        let actual = try #require(String(data: actualBytes, encoding: .utf8))
        let prePhase1Bytes = #"{"actionType":"off-app","colorName":"orange","createdAt":721692800,"dueDate":721779200,"id":"legacy","notesEnabled":false,"onCompleteSpawns":[],"priority":2,"quoteTracker":"none","selfServiceOnly":true,"status":"Snoozed","subtitle":"Legacy detail","taskCategory":"utilities","taskId":"catalog-task","taskType":"provide_info","tier":"task","title":"Legacy task","type":"task","urgencyPercentage":71}"#
        #expect(actual == prePhase1Bytes)
        #expect(legacy.dispositionContract == nil)
        #expect(legacy.visibleStatusCopy == nil)
    }

    @Test func emptyVisibleCopyFallsBackToNil() {
        let empty = PeezyCard(
            type: .task,
            title: "Empty",
            subtitle: "",
            dispositionContract: .init(visibleStatusCopy: "  \n ")
        )
        #expect(empty.visibleStatusCopy == nil)
    }

    @Test func existingContractSurvivesPackingAndReadinessReplacementBuilders() throws {
        let scheduled = now.addingTimeInterval(86_400)
        let contract: [String: Any] = [
            "disposition": "DEFERRED",
            "visible_status_copy": "Scheduled",
            "profile_version": 2
        ]
        let previous: [String: Any] = [
            "status": "Snoozed",
            "dueDate": Timestamp(date: scheduled),
            "dispositionContract": contract
        ]
        let session = PackingSession(
            taskId: "PACKING_SESSION_1", sessionKey: "session-1", sourceKeys: ["room-1"],
            rooms: ["Kitchen"], roomLabel: "Kitchen", estMinutes: 30,
            scheduledDate: scheduled, itemSummary: ["Dishes"], isFirstNightBag: false,
            completedAt: nil, isBehindPace: false
        )

        let packing = TaskActionService.packingTaskData(
            session, previousData: previous, matchingSessionData: nil
        )
        let readiness = TaskActionService.readinessTaskData(
            scheduledDate: scheduled, previousData: previous
        )

        #expect((packing["dispositionContract"] as? [String: Any])?["profile_version"] as? Int == 2)
        #expect((readiness["dispositionContract"] as? [String: Any])?["visible_status_copy"] as? String == "Scheduled")
    }

    @Test func upcomingWithClearedSnoozedUntilIsNotSnoozedAndHasNoScheduledDate() {
        let card = PeezyCard(
            id: "woken", type: .task, title: "Woken", subtitle: "", status: .upcoming,
            snoozedUntil: nil,
            dispositionContract: .init(visibleStatusCopy: "Ready now")
        )
        #expect(!TaskGrouping.isSnoozedEffective(card, now: now))
        #expect(card.snoozedUntil == nil)
        #expect(card.visibleStatusCopy == "Ready now")
    }

    @Test func contractProjectionIsReadOnlyAndMalformedIsFailSafe() {
        let valid = PeezyCard(
            type: .task,
            title: "Waiting",
            subtitle: "",
            status: .matchingInProgress,
            dispositionContract: .init(
                disposition: .waitingOnExternal,
                owner: "institution",
                nextAction: "Wait",
                nextTrigger: .init(kind: .event, eventName: "accepted", canonicalKey: "k", afterSourceVersion: 0),
                resumeDestination: "flow://wait",
                visibleStatusCopy: "Waiting on institution"
            )
        )
        let malformed = PeezyCard(
            type: .task,
            title: "Malformed",
            subtitle: "",
            status: .completed,
            dispositionContract: .init(disposition: .waitingOnExternal)
        )
        let groups = TaskGrouping.partition([valid, malformed], now: now)
        #expect(groups.peezyOnIt.map(\.title) == ["Malformed", "Waiting"])
        #expect(groups.completed.isEmpty)
        #expect(valid.visibleStatusCopy == "Waiting on institution")
        #expect(malformed.visibleStatusCopy == nil)
        if case .none = TaskRowButtons.layout(for: valid, section: .peezyOnIt) {
            #expect(Bool(true))
        } else {
            Issue.record("Contracted rows must expose no direct lifecycle buttons")
        }
    }

    @Test func distinctTerminalKindsProjectDone() {
        for kind in [PeezyCard.DispositionContract.TerminalKind.notApplicable, .retired, .superseded] {
            let disposition: PeezyCard.DispositionContract.Disposition? = kind == .notApplicable ? .notApplicable : nil
            let card = PeezyCard(
                type: .task,
                title: kind.rawValue,
                subtitle: "",
                status: .dismissed,
                dispositionContract: .init(disposition: disposition, terminalKind: kind, visibleStatusCopy: "Terminal")
            )
            #expect(TaskGrouping.partition([card], now: now).completed.count == 1)
        }
    }

    @Test func replacementBuildersPreserveExistingContract() {
        let contract: [String: Any] = ["disposition": "DEFERRED", "profile_version": 2]
        let preserved = TaskActionService.preservingDispositionContract(previousData: ["dispositionContract": contract], in: ["status": "Upcoming"])
        #expect((preserved["dispositionContract"] as? [String: Any])?["disposition"] as? String == "DEFERRED")
    }

    @Test func homeProjectionKeepsEveryContractPassiveAndLegacyQueueUnchanged() {
        let legacy = PeezyCard(
            id: "legacy", type: .task, title: "Legacy", subtitle: "",
            urgencyPercentage: 80
        )
        let statuses: [TaskStatus] = [
            .upcoming, .inProgress, .pending, .matchingInProgress, .userInProgress,
            .snoozed, .completed, .skipped, .dismissed, .converted
        ]
        let contracted = statuses.enumerated().map { index, status in
            PeezyCard(
                id: "contract-\(index)", type: .task, title: "Contract \(index)", subtitle: "",
                status: status,
                dispositionContract: .init(visibleStatusCopy: "Server status \(index)")
            )
        }
        let projection = PeezyHomeViewModel.projectHomeTasks([legacy] + contracted, now: now)
        #expect(projection.actionableLegacy == [legacy])
        #expect(projection.userInProgressLegacy.isEmpty)
        #expect(Set(projection.readOnlyContractStatus.map(\.id)) == Set(contracted.map(\.id)))
        #expect(projection.readOnlyContractStatus.allSatisfy { !$0.shouldShow })
    }

    @MainActor
    @Test func passiveContractCannotStartOrFocusFlowOrLeaveQueue() {
        let contracted = PeezyCard(
            id: "passive", type: .task, title: "Passive", subtitle: "",
            workflowId: "some_flow",
            dispositionContract: .init(visibleStatusCopy: "Waiting")
        )
        let viewModel = PeezyHomeViewModel()
        viewModel.taskQueue = [contracted]

        viewModel.startNextTask()
        #expect(viewModel.taskQueue == [contracted])
        #expect(viewModel.currentTask == nil)
        #expect(!viewModel.showTaskFlow)

        viewModel.focusTask(contracted)
        #expect(viewModel.taskQueue == [contracted])
        #expect(viewModel.currentTask == nil)
        #expect(!viewModel.showTaskFlow)
    }

    @MainActor
    @Test func bothGenerationPathsDoNotRewriteExistingCompletedSnoozedOrSupersededTasks() async throws {
        let runner = RetryingGenerationRunner(stored: [
            "completed": ["id": "completed", "status": "Completed"],
            "snoozed": ["id": "snoozed", "status": "Snoozed"],
            "superseded": [
                "id": "superseded", "status": "Dismissed",
                "dispositionContract": ["terminal_kind": "superseded"]
            ]
        ])
        let candidates: [[String: Any]] = [
            ["id": "completed", "status": "Upcoming"],
            ["id": "snoozed", "status": "Upcoming"],
            ["id": "superseded", "status": "Upcoming"],
            [
                "id": "new", "status": "Upcoming",
                "flowRows": [["id": "checking_1", "subjectId": "stable-row-uuid"]]
            ]
        ]

        let initialCount = try await TaskGenerationService.createMissingTasks(
            userId: "u", candidates: candidates, runner: runner
        )
        let incrementalCount = try await TaskGenerationService.createMissingTasks(
            userId: "u", candidates: candidates, runner: runner
        )

        #expect(initialCount == 1)
        #expect(incrementalCount == 0)
        #expect(runner.stored["completed"]?["status"] as? String == "Completed")
        #expect(runner.stored["snoozed"]?["status"] as? String == "Snoozed")
        #expect(runner.stored["superseded"]?["status"] as? String == "Dismissed")
        #expect(runner.observedRowSubjectIDs == ["stable-row-uuid", "stable-row-uuid"])
    }

    @MainActor
    @Test func productionTransactionRunnerRetryReadsEverythingBeforeWritesAndKeepsFirstRowUUID() async throws {
        let executor = RetryingProductionTransactionExecutor(candidateCount: 2)
        let runner = FirestoreTaskGenerationTransactionRunner(execute: executor.execute)
        let candidates: [[String: Any]] = [
            ["id": "existing", "status": "Upcoming"],
            [
                "id": "new", "status": "Upcoming",
                "flowRows": [["id": "checking_1", "subjectId": "stable-production-row"]]
            ]
        ]

        let created = try await runner.createMissingTasks(userId: "user", candidates: candidates)

        #expect(created == 0)
        #expect(executor.attempts.count == 2)
        #expect(executor.attempts[0].readIDs == ["existing", "new"])
        #expect(executor.attempts[0].writeIDs == ["new"])
        #expect(executor.attempts[1].readIDs == ["existing", "new"])
        #expect(executor.attempts[1].writeIDs.isEmpty)
        #expect(executor.attempts.flatMap(\.observedRowSubjectIDs) == [
            "stable-production-row", "stable-production-row"
        ])
        #expect(executor.attempts[1].existing["new"]?["status"] as? String == "Snoozed")
    }

    @MainActor
    @Test func productionTransactionBodyRunsOffMainWithoutActorHop() async throws {
        let executor = OffMainProductionTransactionExecutor()
        let runner = FirestoreTaskGenerationTransactionRunner(execute: executor.execute)

        let created = try await runner.createMissingTasks(
            userId: "user",
            candidates: [["id": "background-safe", "status": "Upcoming"]]
        )

        #expect(created == 1)
        #expect(executor.didRunOffMainThread)
        #expect(executor.attempt?.readIDs == ["background-safe"])
        #expect(executor.attempt?.writeIDs == ["background-safe"])
    }
}

@MainActor
private final class RetryingGenerationRunner: TaskGenerationTransactionRunning {
    var stored: [String: [String: Any]]
    var observedRowSubjectIDs: [String] = []

    init(stored: [String: [String: Any]]) {
        self.stored = stored
    }

    func createMissingTasks(userId: String, candidates: [[String: Any]]) async throws -> Int {
        if let new = candidates.first(where: { $0["id"] as? String == "new" }),
           let rows = new["flowRows"] as? [[String: Any]],
           let subjectID = rows.first?["subjectId"] as? String {
            observedRowSubjectIDs.append(subjectID)
        }
        // Model an SDK transaction retry: a concurrent lifecycle mutation is
        // visible on the retry and existing documents are never rewritten.
        if var snoozed = stored["snoozed"] {
            snoozed["lastSnoozedAt"] = "concurrent-write"
            stored["snoozed"] = snoozed
        }
        var created = 0
        for candidate in candidates {
            guard let id = candidate["id"] as? String else { continue }
            if stored[id] == nil {
                stored[id] = candidate
                created += 1
            }
        }
        return created
    }
}

@MainActor
private final class RetryingProductionTransactionExecutor {
    let candidateCount: Int
    var attempts: [ProductionTransactionAttempt] = []

    init(candidateCount: Int) { self.candidateCount = candidateCount }

    func execute(
        _ body: @escaping TaskGenerationTransactionBody
    ) async throws -> Int {
        let first = ProductionTransactionAttempt(
            candidateCount: candidateCount,
            existing: ["existing": ["id": "existing", "status": "Completed"]]
        )
        attempts.append(first)
        _ = try body(first) // discarded SDK attempt

        let retry = ProductionTransactionAttempt(
            candidateCount: candidateCount,
            existing: [
                "existing": ["id": "existing", "status": "Completed"],
                "new": [
                    "id": "new", "status": "Snoozed",
                    "dispositionContract": ["disposition": "DEFERRED"]
                ]
            ]
        )
        attempts.append(retry)
        return try body(retry)
    }
}

@MainActor
private final class OffMainProductionTransactionExecutor {
    private(set) var didRunOffMainThread = false
    private(set) var attempt: ProductionTransactionAttempt?

    func execute(
        _ body: @escaping TaskGenerationTransactionBody
    ) async throws -> Int {
        let attempt = ProductionTransactionAttempt(candidateCount: 1, existing: [:])
        let (created, ranOffMain) = try await Task.detached {
            (try body(attempt), !Thread.isMainThread)
        }.value
        self.attempt = attempt
        didRunOffMainThread = ranOffMain
        return created
    }
}

nonisolated private final class ProductionTransactionAttempt:
    TaskGenerationTransactionAccess,
    @unchecked Sendable
{
    let candidateCount: Int
    let existing: [String: [String: Any]]
    var readIDs: [String] = []
    var writeIDs: [String] = []
    var observedRowSubjectIDs: [String] = []

    init(candidateCount: Int, existing: [String: [String: Any]]) {
        self.candidateCount = candidateCount
        self.existing = existing
    }

    func userData() throws -> [String: Any]? { [:] }

    func taskExists(id: String, candidate: [String: Any]) throws -> Bool {
        readIDs.append(id)
        if let rows = candidate["flowRows"] as? [[String: Any]],
           let subjectID = rows.first?["subjectId"] as? String {
            observedRowSubjectIDs.append(subjectID)
        }
        return existing[id] != nil
    }

    func createTask(id: String, data: [String: Any]) throws {
        #expect(readIDs.count == candidateCount, "Every candidate read must precede the first write")
        writeIDs.append(id)
    }
}
