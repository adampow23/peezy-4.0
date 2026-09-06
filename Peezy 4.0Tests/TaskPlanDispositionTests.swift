import FirebaseFirestore
import Foundation
import Testing
@testable import Peezy_4_0

/// S1 owns only D15 here (briefs/S1_BRIEF.md); S2 extends this file.
struct TaskPlanDispositionTests {

    // D15: reset authority resolves by the deterministic UID/epoch point path, never an alias scan.

    @Test(.enabled(if: FirebaseEmulator.isConfigured))
    func epochAuthorityReadsTheUserRootPointPath() async throws {
        _ = try FirebaseEmulator.firestore()
        try await FirebaseEmulator.clearFirestore()
        let uid = try await FirebaseEmulator.signInFreshUser()
        defer { try? FirebaseEmulator.signOut() }
        let authority = FirestoreResetEpochAuthority()
        let expected = SignedAuthTuple(uid: uid, authEpochUUID: TransitionalFirebaseAuthAuthority.legacyAuthEpochUUID, credentialRevision: 0)
        #expect(try await authority.current(uid: uid, expectedAuth: expected) == ResetEpochAuthority(uid: uid, taskGenerationEpoch: 0))
        try await FirebaseEmulator.adminSet("users/\(uid)", ["name": "A", "taskGenerationEpoch": 7])
        #expect(try await authority.current(uid: uid, expectedAuth: expected) == ResetEpochAuthority(uid: uid, taskGenerationEpoch: 7))
        try await FirebaseEmulator.adminSet("users/\(uid)", ["name": "A", "taskGenerationEpoch": "seven"])
        await #expect(throws: TaskGenerationEpochError.malformedRootEpoch) { _ = try await authority.current(uid: uid, expectedAuth: expected) }
        await #expect(throws: ResetOperationRegistry.RegistryError.authRequired) {
            _ = try await authority.current(uid: "someone-else", expectedAuth: SignedAuthTuple(uid: "someone-else", authEpochUUID: expected.authEpochUUID, credentialRevision: 0))
        }
    }

    @Test func registryResolvesRowsByExactUIDAndEpochKey() async throws {
        let directory = try temporaryDirectory()
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: SignedAuthStub(.signedIn(tupleA)), epochAuthority: EpochStub(epoch: 2))
        try await seedPreparedRow(registry, uid: "B", epoch: 2, createdAt: "2026-09-06T09:00:00.000Z")
        try await seedPreparedRow(registry, uid: "A", epoch: 2, createdAt: "2026-09-06T09:00:01.000Z")
        let row = try #require(await registry.row(uid: "A", expectedTaskGenerationEpoch: 2))
        #expect(row.uid == "A" && row.expectedTaskGenerationEpoch == 2)
        #expect(await registry.row(uid: "A", expectedTaskGenerationEpoch: 1) == nil)
        #expect(await registry.row(uid: "C", expectedTaskGenerationEpoch: 2) == nil)
        // Resume derives the handle from the row's own identity, never from a caller-supplied alias.
        let outcome = try await registry.reserve(gestureId: "rsg1_11111111-1111-4111-8111-111111111111")
        let expectedHandle = "rho1_" + TaskCanonicalV1.sha256Hex(["uid": "A", "suggested_operation_id": row.suggestedOperationId, "created_at": row.createdAt])
        #expect(outcome == .operation(ResetOperationHandle(uid: "A", handleId: expectedHandle)))
    }

    // S2 (briefs/S2_BRIEF.md): D15 server-path parity. The Swift canonical bytes must reproduce the
    // Node derivations frozen in functions/tests/taskPlan.test.js and PHASE2_CONTRACT.md C7, so the
    // deterministic (uid, epoch) point path resolves to the same record on both sides.

    @Test func serverPathDerivationsMatchTheNodeFixtures() {
        let canonical = "rso1_" + String(TaskCanonicalV1.sha256Hex(["account_uid": "u2", "task_generation_epoch": 4]).prefix(40))
        #expect(canonical == "rso1_9c1f02b257ea87bc0dbc8f304850b67552f48788")
        let moveEvent = "me1_" + String(TaskCanonicalV1.sha256Hex(["uid": "u2", "new_task_generation_epoch": 4, "reset_operation_id": canonical]).prefix(40))
        #expect(moveEvent == "me1_9c4ef635c2c2a3983df861f2ca2ce0f1597a0103")
        let phase2Fingerprint = "reset1_" + TaskCanonicalV1.sha256Hex(["kind": "reset", "reason": "retake_assessment", "expected_task_generation_epoch": 3])
        #expect(phase2Fingerprint == "reset1_edd2b5c85b89c38cc2537b47a68dc36efd59609f55beaeaf0377efd4b7e36035")
        let legacyFingerprint = "reset1_" + TaskCanonicalV1.sha256Hex(["kind": "reset", "reason": "retake_assessment"])
        #expect(legacyFingerprint == "reset1_862fe3fc8a08ce3eced6f25dfd2a8765b408e8386fa28f081f393d36f04e94a1")
        let migrationPreimage: [String: Any] = ["account_uid": "phase2-rule-owner", "legacy_operation_id": "20000000-0000-4000-8000-000000000001"]
        let migrationHash = TaskCanonicalV1.sha256Hex(migrationPreimage)
        #expect("rlm1_" + String(migrationHash.prefix(40)) == "rlm1_0a4d53a438873090f69e4255426310b0feb4cfd6")
        #expect("rlmreq1_" + migrationHash == "rlmreq1_0a4d53a438873090f69e4255426310b0feb4cfd63eabd6ce68c851ce827ad8e1")
    }
}
