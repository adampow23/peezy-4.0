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
}
