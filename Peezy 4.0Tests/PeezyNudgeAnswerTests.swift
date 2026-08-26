/*
 testGuardKeepsAppProductionDisconnectedUnderXCTest
 testNoClaimFailureKeepsCardAndState
 testNoSuccessDismissesWithZeroCredit
 testYesSpawnSucceedsClaimFailsOffersSameChoiceRetryOnly
 testYesSpawnFailureIsPreSpawnSameChoiceRetryOnly
 testDoubleTapWhileInFlightIsSingleFlight
 testAlreadyTerminalByOtherActorRemovesWithoutCredit
 testClaimTimeoutThenRetryObservesAlreadyMineCreditsExactlyOnce
 testMissingAuthOrIdsSurfaceExplicitFailure
 testAuthSwitchBeforeSpawnIsRejectedServerSideNothingLandsElsewhere
 testAuthSwitchAfterSpawnUsesCapturedUidForClaimAndAccounting
 testHeldSpawnTimesOutSameChoiceRetryLateResultDiscarded
 testHappyPathsPersistClaimBeforeRemovalAndAdvance
 testClaimApiEmptyIdsThrowMissingIdentity
 */

import FirebaseCore
import Foundation
import UIKit
import XCTest
@testable import Peezy_4_0

@MainActor
final class PeezyNudgeAnswerTests: XCTestCase {
    func testGuardKeepsAppProductionDisconnectedUnderXCTest() {
        #if DEBUG
        XCTAssertTrue(PeezyRuntime.isRunningUnderXCTest)
        let app = PeezyV1App()
        _ = app.body
        XCTAssertTrue(AppDelegate().application(
            UIApplication.shared,
            didFinishLaunchingWithOptions: nil
        ))
        XCTAssertNil(FirebaseApp.app())
        #else
        XCTFail("The production-disconnection guard is DEBUG-only by contract.")
        #endif
    }

    func testNoClaimFailureKeepsCardAndState() async {
        let setup = makeSetup(uid: uniqueUID())
        setup.runner.failures[1] = TestFailure("claim unavailable")

        setup.viewModel.answerNudge(yes: false)
        await waitUntil { setup.viewModel.nudgeAnswerState == .failed(.dismissed, .claim) }

        XCTAssertEqual(setup.viewModel.currentTask?.id, setup.nudge.id)
        XCTAssertTrue(setup.viewModel.allActiveTasks.contains { $0.id == setup.nudge.id })
        XCTAssertEqual(setup.viewModel.completedThisSession, 0)
        XCTAssertEqual(doseCount(for: setup.uid), 0)
        XCTAssertEqual(setup.runner.calls.count, 1)
        XCTAssertTrue(setup.viewModel.nudgeAnswerError?.contains("claim unavailable") == true)
    }

    func testNoSuccessDismissesWithZeroCredit() async {
        let setup = makeSetup(uid: uniqueUID())

        setup.viewModel.answerNudge(yes: false)
        await waitUntil { setup.viewModel.currentTask?.id == setup.next.id }

        XCTAssertEqual(setup.runner.document["status"] as? String, "Dismissed")
        let answeredBy = setup.runner.document["answeredBy"] as? [String: Any]
        XCTAssertEqual(answeredBy?["choice"] as? String, "Dismissed")
        XCTAssertNotNil(answeredBy?["opId"] as? String)
        XCTAssertEqual(setup.spawn.calls.count, 0)
        XCTAssertEqual(setup.viewModel.completedThisSession, 0)
        XCTAssertEqual(doseCount(for: setup.uid), 0)
        XCTAssertFalse(setup.viewModel.allActiveTasks.contains { $0.id == setup.nudge.id })
        XCTAssertEqual(setup.viewModel.nudgeAnswerState, .idle)
    }

    func testYesSpawnSucceedsClaimFailsOffersSameChoiceRetryOnly() async {
        let setup = makeSetup(uid: uniqueUID())
        setup.runner.failures[1] = TestFailure("claim rejected")

        setup.viewModel.answerNudge(yes: true)
        await waitUntil { setup.viewModel.nudgeAnswerState == .failed(.converted, .postSpawn) }

        XCTAssertEqual(setup.spawn.calls.count, 1)
        XCTAssertEqual(setup.runner.calls.count, 1)
        XCTAssertEqual(setup.viewModel.currentTask?.id, setup.nudge.id)
        XCTAssertTrue(setup.viewModel.allActiveTasks.contains { $0.id == setup.nudge.id })
        XCTAssertEqual(setup.viewModel.completedThisSession, 0)
        XCTAssertEqual(doseCount(for: setup.uid), 0)

        setup.viewModel.answerNudge(yes: false)
        XCTAssertEqual(setup.spawn.calls.count, 1)
        XCTAssertEqual(setup.runner.calls.count, 1)
        XCTAssertEqual(setup.viewModel.nudgeAnswerState, .failed(.converted, .postSpawn))

        setup.viewModel.retryNudgeAnswer()
        await waitUntil { setup.viewModel.currentTask?.id == setup.next.id }

        XCTAssertEqual(setup.spawn.calls.count, 2)
        XCTAssertEqual(setup.spawn.calls.first?.token, setup.spawn.calls.last?.token)
        XCTAssertEqual(setup.runner.calls.count, 2)
        XCTAssertEqual(setup.viewModel.completedThisSession, 1)
        XCTAssertEqual(doseCount(for: setup.uid), 1)
    }

    func testYesSpawnFailureIsPreSpawnSameChoiceRetryOnly() async {
        let setup = makeSetup(uid: uniqueUID())
        setup.spawn.failures[1] = TestFailure("ambiguous transport failure")

        setup.viewModel.answerNudge(yes: true)
        await waitUntil { setup.viewModel.nudgeAnswerState == .failed(.converted, .preSpawn) }

        XCTAssertEqual(setup.runner.calls.count, 0)
        XCTAssertEqual(setup.viewModel.currentTask?.id, setup.nudge.id)
        XCTAssertTrue(setup.viewModel.allActiveTasks.contains { $0.id == setup.nudge.id })
        XCTAssertEqual(setup.viewModel.completedThisSession, 0)
        XCTAssertEqual(doseCount(for: setup.uid), 0)
        setup.viewModel.answerNudge(yes: false)
        XCTAssertEqual(setup.spawn.calls.count, 1)
        XCTAssertEqual(setup.viewModel.nudgeAnswerState, .failed(.converted, .preSpawn))

        setup.viewModel.retryNudgeAnswer()
        await waitUntil { setup.viewModel.currentTask?.id == setup.next.id }

        XCTAssertEqual(setup.spawn.calls.count, 2)
        XCTAssertEqual(setup.spawn.calls.first?.token, setup.spawn.calls.last?.token)
        XCTAssertEqual(setup.runner.calls.count, 1)
        XCTAssertEqual(doseCount(for: setup.uid), 1)
    }

    func testDoubleTapWhileInFlightIsSingleFlight() async {
        let setup = makeSetup(uid: uniqueUID())
        setup.spawn.heldCalls = [1]

        setup.viewModel.answerNudge(yes: true)
        setup.viewModel.answerNudge(yes: true)
        await waitUntil { setup.spawn.isHeld(call: 1) }

        XCTAssertEqual(setup.spawn.calls.count, 1)
        XCTAssertEqual(setup.viewModel.nudgeAnswerState, .inFlight(.converted))
        setup.spawn.resume(call: 1)
        await waitUntil { setup.viewModel.currentTask?.id == setup.next.id }

        XCTAssertEqual(setup.spawn.calls.count, 1)
        XCTAssertEqual(setup.runner.calls.count, 1)
        XCTAssertEqual(setup.viewModel.completedThisSession, 1)
        XCTAssertEqual(doseCount(for: setup.uid), 1)
    }

    func testAlreadyTerminalByOtherActorRemovesWithoutCredit() async {
        let setup = makeSetup(uid: uniqueUID())
        setup.runner.document = [
            "status": "Converted",
            "answeredBy": ["choice": "Converted", "opId": "another-operation"]
        ]

        setup.viewModel.answerNudge(yes: true)
        await waitUntil { setup.viewModel.currentTask?.id == setup.next.id }

        XCTAssertEqual(setup.spawn.calls.count, 1)
        XCTAssertEqual(setup.runner.calls.count, 1)
        XCTAssertEqual(setup.viewModel.completedThisSession, 0)
        XCTAssertEqual(doseCount(for: setup.uid), 0)
        XCTAssertFalse(setup.viewModel.allActiveTasks.contains { $0.id == setup.nudge.id })
    }

    func testClaimTimeoutThenRetryObservesAlreadyMineCreditsExactlyOnce() async {
        let converted = makeSetup(uid: uniqueUID())
        converted.runner.holdAfterCommitCalls = [1]

        converted.viewModel.answerNudge(yes: true)
        await waitUntil {
            converted.runner.isHeld(call: 1)
                && converted.clock.hasSleeper(for: .seconds(10))
        }
        converted.clock.fire(.seconds(10))
        await waitUntil {
            converted.viewModel.nudgeAnswerState == .failed(.converted, .postSpawn)
        }

        XCTAssertEqual(doseCount(for: converted.uid), 0)
        XCTAssertEqual(converted.viewModel.completedThisSession, 0)
        XCTAssertEqual(converted.viewModel.currentTask?.id, converted.nudge.id)
        converted.runner.resume(call: 1)
        await waitUntil { converted.runner.didFinish(call: 1) }
        converted.viewModel.retryNudgeAnswer()
        await waitUntil { converted.viewModel.currentTask?.id == converted.next.id }

        XCTAssertEqual(converted.runner.calls.count, 2)
        XCTAssertEqual(converted.spawn.calls.count, 2)
        XCTAssertEqual(converted.spawn.calls.first?.token, converted.spawn.calls.last?.token)
        XCTAssertEqual(converted.viewModel.completedThisSession, 1)
        XCTAssertEqual(doseCount(for: converted.uid), 1)

        let dismissed = makeSetup(uid: uniqueUID())
        dismissed.runner.holdAfterCommitCalls = [1]

        dismissed.viewModel.answerNudge(yes: false)
        await waitUntil {
            dismissed.runner.isHeld(call: 1)
                && dismissed.clock.hasSleeper(for: .seconds(10))
        }
        dismissed.clock.fire(.seconds(10))
        await waitUntil {
            dismissed.viewModel.nudgeAnswerState == .failed(.dismissed, .claim)
        }
        XCTAssertEqual(dismissed.viewModel.completedThisSession, 0)
        XCTAssertEqual(doseCount(for: dismissed.uid), 0)
        dismissed.runner.resume(call: 1)
        await waitUntil { dismissed.runner.didFinish(call: 1) }
        dismissed.viewModel.retryNudgeAnswer()
        await waitUntil { dismissed.viewModel.currentTask?.id == dismissed.next.id }

        XCTAssertEqual(dismissed.runner.calls.count, 2)
        XCTAssertEqual(dismissed.spawn.calls.count, 0)
        XCTAssertEqual(dismissed.viewModel.completedThisSession, 0)
        XCTAssertEqual(doseCount(for: dismissed.uid), 0)
    }

    func testMissingAuthOrIdsSurfaceExplicitFailure() async {
        let missingAuth = makeSetup(uid: nil)
        missingAuth.viewModel.answerNudge(yes: true)
        await waitUntil {
            missingAuth.viewModel.nudgeAnswerState == .failed(.converted, .preSpawn)
        }
        XCTAssertEqual(missingAuth.viewModel.currentTask?.id, missingAuth.nudge.id)
        XCTAssertFalse(missingAuth.viewModel.nudgeAnswerError?.isEmpty ?? true)
        XCTAssertEqual(missingAuth.spawn.calls.count, 0)
        XCTAssertEqual(missingAuth.runner.calls.count, 0)

        let emptyTaskID = makeSetup(
            uid: uniqueUID(),
            nudgeID: ""
        )
        emptyTaskID.viewModel.answerNudge(yes: false)
        await waitUntil {
            emptyTaskID.viewModel.nudgeAnswerState == .failed(.dismissed, .claim)
        }
        XCTAssertFalse(emptyTaskID.viewModel.nudgeAnswerError?.isEmpty ?? true)
        XCTAssertEqual(emptyTaskID.runner.calls.count, 0)

        let missingSpawnID = makeSetup(
            uid: uniqueUID(),
            spawnID: nil
        )
        missingSpawnID.viewModel.answerNudge(yes: true)
        await waitUntil {
            missingSpawnID.viewModel.nudgeAnswerState == .failed(.converted, .preSpawn)
        }
        XCTAssertFalse(missingSpawnID.viewModel.nudgeAnswerError?.isEmpty ?? true)
        XCTAssertEqual(missingSpawnID.spawn.calls.count, 0)
        XCTAssertEqual(missingSpawnID.runner.calls.count, 0)
    }

    func testAuthSwitchBeforeSpawnIsRejectedServerSideNothingLandsElsewhere() async {
        let originalUID = uniqueUID()
        let switchedUID = uniqueUID()
        let uid = MutableUID(originalUID)
        let setup = makeSetup(uid: uid)
        setup.spawn.serverUID = { uid.value }
        setup.spawn.rejectExpectedUserMismatch = true

        setup.viewModel.answerNudge(yes: true)
        uid.value = switchedUID
        await waitUntil { setup.viewModel.nudgeAnswerState == .failed(.converted, .preSpawn) }

        XCTAssertEqual(setup.spawn.calls.count, 1)
        XCTAssertEqual(setup.spawn.calls.first?.expectedUserId, originalUID)
        XCTAssertEqual(setup.spawn.createdTaskCount, 0)
        XCTAssertEqual(setup.runner.calls.count, 0)
        XCTAssertEqual(setup.viewModel.currentTask?.id, setup.nudge.id)
        XCTAssertEqual(doseCount(for: originalUID), 0)
        XCTAssertEqual(doseCount(for: switchedUID), 0)
        XCTAssertEqual(uid.readCount, 1)
    }

    func testAuthSwitchAfterSpawnUsesCapturedUidForClaimAndAccounting() async {
        let originalUID = uniqueUID()
        let switchedUID = uniqueUID()
        let uid = MutableUID(originalUID)
        let setup = makeSetup(uid: uid)
        setup.spawn.serverUID = { uid.value }
        setup.spawn.rejectExpectedUserMismatch = true
        setup.spawn.onSuccessfulCall = { uid.value = switchedUID }

        setup.viewModel.answerNudge(yes: true)
        await waitUntil { setup.viewModel.currentTask?.id == setup.next.id }

        XCTAssertEqual(setup.spawn.calls.first?.expectedUserId, originalUID)
        XCTAssertEqual(setup.runner.calls.map(\.userId), [originalUID])
        XCTAssertEqual(doseCount(for: originalUID), 1)
        XCTAssertEqual(totalCount(for: originalUID), 2)
        XCTAssertEqual(doseCount(for: switchedUID), 0)
        XCTAssertEqual(totalCount(for: switchedUID), 0)
        XCTAssertEqual(uid.readCount, 1)
    }

    func testHeldSpawnTimesOutSameChoiceRetryLateResultDiscarded() async {
        let setup = makeSetup(uid: uniqueUID())
        setup.spawn.heldCalls = [1]

        setup.viewModel.answerNudge(yes: true)
        await waitUntil {
            setup.spawn.isHeld(call: 1)
                && setup.clock.hasSleeper(for: .seconds(15))
        }
        setup.clock.fire(.seconds(15))
        await waitUntil { setup.viewModel.nudgeAnswerState == .failed(.converted, .preSpawn) }

        XCTAssertEqual(setup.viewModel.currentTask?.id, setup.nudge.id)
        XCTAssertEqual(setup.runner.calls.count, 0)
        XCTAssertTrue(setup.viewModel.allActiveTasks.contains { $0.id == setup.nudge.id })
        XCTAssertEqual(setup.viewModel.completedThisSession, 0)
        XCTAssertEqual(doseCount(for: setup.uid), 0)
        setup.viewModel.answerNudge(yes: false)
        XCTAssertEqual(setup.spawn.calls.count, 1)

        setup.spawn.resume(call: 1)
        await waitUntil { setup.spawn.didFinish(call: 1) }
        XCTAssertEqual(setup.runner.calls.count, 0)
        XCTAssertEqual(setup.viewModel.currentTask?.id, setup.nudge.id)
        XCTAssertTrue(setup.viewModel.allActiveTasks.contains { $0.id == setup.nudge.id })
        XCTAssertEqual(setup.viewModel.completedThisSession, 0)
        XCTAssertEqual(doseCount(for: setup.uid), 0)

        setup.viewModel.retryNudgeAnswer()
        await waitUntil { setup.viewModel.currentTask?.id == setup.next.id }

        XCTAssertEqual(setup.spawn.calls.count, 2)
        XCTAssertEqual(setup.spawn.calls.first?.token, setup.spawn.calls.last?.token)
        XCTAssertEqual(setup.spawn.createdTaskCount, 1)
        XCTAssertEqual(setup.runner.calls.count, 1)
        XCTAssertEqual(setup.viewModel.completedThisSession, 1)
        XCTAssertEqual(doseCount(for: setup.uid), 1)
        XCTAssertEqual(setup.uidBox.readCount, 1)
    }

    func testHappyPathsPersistClaimBeforeRemovalAndAdvance() async throws {
        let convertedEvents = EventLog()
        let converted = makeSetup(uid: uniqueUID())
        converted.spawn.onSuccessfulCall = { convertedEvents.append("spawn") }
        converted.runner.onCommit = {
            convertedEvents.append("claim")
            XCTAssertEqual(converted.viewModel.currentTask?.id, converted.nudge.id)
            XCTAssertTrue(converted.viewModel.allActiveTasks.contains { $0.id == converted.nudge.id })
            XCTAssertEqual(converted.viewModel.completedThisSession, 0)
        }

        converted.viewModel.answerNudge(yes: true)
        await waitUntil { converted.viewModel.currentTask?.id == converted.next.id }
        XCTAssertEqual(convertedEvents.values, ["spawn", "claim"])
        XCTAssertEqual(converted.viewModel.completedThisSession, 1)
        XCTAssertEqual(converted.runner.document["status"] as? String, "Converted")
        let convertedAnswer = converted.runner.document["answeredBy"] as? [String: Any]
        XCTAssertEqual(convertedAnswer?["choice"] as? String, "Converted")
        XCTAssertNotNil(convertedAnswer?["opId"] as? String)
        XCTAssertFalse(converted.viewModel.allActiveTasks.contains { $0.id == converted.nudge.id })
        XCTAssertEqual(converted.viewModel.nudgeAnswerState, .idle)

        let dismissedEvents = EventLog()
        let dismissed = makeSetup(uid: uniqueUID())
        dismissed.runner.onCommit = {
            dismissedEvents.append("claim")
            XCTAssertEqual(dismissed.viewModel.currentTask?.id, dismissed.nudge.id)
            XCTAssertTrue(dismissed.viewModel.allActiveTasks.contains { $0.id == dismissed.nudge.id })
            XCTAssertEqual(dismissed.viewModel.completedThisSession, 0)
        }

        dismissed.viewModel.answerNudge(yes: false)
        await waitUntil { dismissed.viewModel.currentTask?.id == dismissed.next.id }
        XCTAssertEqual(dismissedEvents.values, ["claim"])
        XCTAssertEqual(dismissed.viewModel.completedThisSession, 0)
        XCTAssertEqual(doseCount(for: dismissed.uid), 0)
        XCTAssertFalse(dismissed.viewModel.allActiveTasks.contains { $0.id == dismissed.nudge.id })
        XCTAssertEqual(dismissed.viewModel.nudgeAnswerState, .idle)

        for status in [
            "Upcoming",
            "InProgress",
            "pending",
            "matching_in_progress",
            "UserInProgress",
            "Snoozed"
        ] {
            let runner = FakeTransactionRunner()
            runner.document = ["status": status]
            let result = try await TaskActionService().claimNudgeTerminal(
                userId: "status-user",
                taskId: "status-task",
                choice: .converted,
                opId: "status-operation",
                runner: runner
            )
            XCTAssertEqual(result, .won, "Expected \(status) to be claimable")
            XCTAssertEqual(runner.document["status"] as? String, "Converted")
        }
    }

    func testClaimApiEmptyIdsThrowMissingIdentity() async {
        let runner = FakeTransactionRunner()
        let service = TaskActionService()

        await assertMissingIdentity {
            try await service.claimNudgeTerminal(
                userId: "",
                taskId: "task",
                choice: .dismissed,
                opId: "operation",
                runner: runner
            )
        }
        await assertMissingIdentity {
            try await service.claimNudgeTerminal(
                userId: "user",
                taskId: "",
                choice: .converted,
                opId: "operation",
                runner: runner
            )
        }
        XCTAssertEqual(runner.calls.count, 0)
    }

    private func makeSetup(
        uid: String?,
        nudgeID: String = "NUDGE",
        spawnID: String? = "SPAWNED_TASK"
    ) -> TestSetup {
        makeSetup(uid: MutableUID(uid), nudgeID: nudgeID, spawnID: spawnID)
    }

    private func makeSetup(
        uid: MutableUID,
        nudgeID: String = "NUDGE",
        spawnID: String? = "SPAWNED_TASK"
    ) -> TestSetup {
        let runner = FakeTransactionRunner()
        let spawn = FakeNudgeSpawnClient()
        let clock = FakeNudgeAnswerClock()
        let viewModel = PeezyHomeViewModel(
            transactionRunner: runner,
            spawnClient: spawn,
            uidProvider: { uid.read() },
            clock: clock,
            spawnTimeout: .seconds(15),
            claimTimeout: .seconds(10)
        )
        let nudge = PeezyCard(
            id: nudgeID,
            type: .task,
            title: "Nudge",
            subtitle: "",
            taskId: "NUDGE_CATALOG_ID",
            tier: "nudge",
            nudgePrompt: "Want help?",
            nudgeSpawnsId: spawnID
        )
        let next = PeezyCard(
            id: "NEXT_\(UUID().uuidString)",
            type: .task,
            title: "Next",
            subtitle: "",
            taskId: "NEXT_TASK"
        )
        viewModel.state = .activeTask
        viewModel.currentTask = nudge
        viewModel.allActiveTasks = [nudge, next]
        viewModel.taskQueue = [next]
        viewModel.frozenDoseTaskIds = [nudge.id, next.id]

        if let value = uid.value, !value.isEmpty {
            clearAccounting(for: value)
            UserDefaults.standard.set(1, forKey: totalKey(for: value))
        }
        return TestSetup(
            viewModel: viewModel,
            runner: runner,
            spawn: spawn,
            clock: clock,
            uidBox: uid,
            nudge: nudge,
            next: next
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not reached", file: file, line: line)
    }

    private func assertMissingIdentity(
        _ operation: () async throws -> ClaimResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected missingIdentity", file: file, line: line)
        } catch let error as FlowProgressPersistenceError {
            switch error {
            case .missingIdentity:
                break
            }
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func uniqueUID() -> String {
        "nudge-test-\(UUID().uuidString)"
    }

    private func doseKey(for uid: String) -> String {
        "peezy.\(uid).dailyDose.completedCount"
    }

    private func totalKey(for uid: String) -> String {
        "peezy.\(uid).totalCompletedCount"
    }

    private func doseCount(for uid: String) -> Int {
        UserDefaults.standard.integer(forKey: doseKey(for: uid))
    }

    private func totalCount(for uid: String) -> Int {
        UserDefaults.standard.integer(forKey: totalKey(for: uid))
    }

    private func clearAccounting(for uid: String) {
        UserDefaults.standard.removeObject(forKey: doseKey(for: uid))
        UserDefaults.standard.removeObject(forKey: totalKey(for: uid))
        UserDefaults.standard.removeObject(forKey: "peezy.\(uid).dailyDose.firstLaunchDate")
    }
}

@MainActor
private struct TestSetup {
    let viewModel: PeezyHomeViewModel
    let runner: FakeTransactionRunner
    let spawn: FakeNudgeSpawnClient
    let clock: FakeNudgeAnswerClock
    let uidBox: MutableUID
    let nudge: PeezyCard
    let next: PeezyCard

    var uid: String {
        uidBox.value ?? ""
    }
}

@MainActor
private final class MutableUID {
    var value: String?
    private(set) var readCount = 0

    init(_ value: String?) {
        self.value = value
    }

    func read() -> String? {
        readCount += 1
        return value
    }
}

@MainActor
private final class EventLog {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

private struct TestFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

@MainActor
private final class FakeTransactionRunner: TransactionRunner {
    struct Call {
        let userId: String
        let taskId: String
    }

    var document: [String: Any] = ["status": "Upcoming"]
    var failures: [Int: Error] = [:]
    var holdAfterCommitCalls: Set<Int> = []
    var onCommit: (() -> Void)?
    private(set) var calls: [Call] = []
    private(set) var finishedCalls: Set<Int> = []
    private var heldContinuations: [Int: CheckedContinuation<Void, Never>] = [:]

    func runTransaction(
        userId: String,
        taskId: String,
        _ body: @escaping ([String: Any]) -> TransactionMutation
    ) async throws -> ClaimResult {
        calls.append(Call(userId: userId, taskId: taskId))
        let call = calls.count
        defer { finishedCalls.insert(call) }
        if let failure = failures[call] {
            throw failure
        }

        let mutation = body(document)
        for (key, value) in mutation.updates {
            document[key] = value
        }
        onCommit?()

        if holdAfterCommitCalls.contains(call) {
            await withCheckedContinuation { continuation in
                heldContinuations[call] = continuation
            }
        }
        return mutation.result
    }

    func isHeld(call: Int) -> Bool {
        heldContinuations[call] != nil
    }

    func resume(call: Int) {
        heldContinuations.removeValue(forKey: call)?.resume()
    }

    func didFinish(call: Int) -> Bool {
        finishedCalls.contains(call)
    }
}

@MainActor
private final class FakeNudgeSpawnClient: NudgeSpawnClient {
    struct Call {
        let token: String
        let source: SpawnService.Source
        let spawns: [SpawnService.Spawn]
        let answers: [String: Any]?
        let expectedUserId: String?
    }

    var failures: [Int: Error] = [:]
    var heldCalls: Set<Int> = []
    var serverUID: () -> String? = { nil }
    var rejectExpectedUserMismatch = false
    var onSuccessfulCall: (() -> Void)?
    private(set) var calls: [Call] = []
    private(set) var createdTokens: Set<String> = []
    private(set) var finishedCalls: Set<Int> = []
    private var heldContinuations: [Int: CheckedContinuation<Void, Never>] = [:]

    var createdTaskCount: Int { createdTokens.count }

    func spawn(
        token: String,
        source: SpawnService.Source,
        spawns: [SpawnService.Spawn],
        answers: [String: Any]?,
        expectedUserId: String?
    ) async throws -> SpawnService.Response {
        calls.append(Call(
            token: token,
            source: source,
            spawns: spawns,
            answers: answers,
            expectedUserId: expectedUserId
        ))
        let call = calls.count
        defer { finishedCalls.insert(call) }

        if heldCalls.contains(call) {
            await withCheckedContinuation { continuation in
                heldContinuations[call] = continuation
            }
        }
        if let failure = failures[call] {
            throw failure
        }
        if rejectExpectedUserMismatch, expectedUserId != serverUID() {
            throw TestFailure("expected user mismatch")
        }

        createdTokens.insert(token)
        onSuccessfulCall?()
        return SpawnService.Response(created: [])
    }

    func isHeld(call: Int) -> Bool {
        heldContinuations[call] != nil
    }

    func resume(call: Int) {
        heldContinuations.removeValue(forKey: call)?.resume()
    }

    func didFinish(call: Int) -> Bool {
        finishedCalls.contains(call)
    }
}

@MainActor
private final class FakeNudgeAnswerClock: NudgeAnswerClock {
    private struct Sleeper {
        let id: UUID
        let duration: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private var sleepers: [Sleeper] = []

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepers.append(Sleeper(
                    id: id,
                    duration: duration,
                    continuation: continuation
                ))
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(id: id)
            }
        }
    }

    func hasSleeper(for duration: Duration) -> Bool {
        sleepers.contains { $0.duration == duration }
    }

    func fire(_ duration: Duration) {
        guard let index = sleepers.firstIndex(where: { $0.duration == duration }) else {
            return
        }
        sleepers.remove(at: index).continuation.resume()
    }

    private func cancel(id: UUID) {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
        sleepers.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
