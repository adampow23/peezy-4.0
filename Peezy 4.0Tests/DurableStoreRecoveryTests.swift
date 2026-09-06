import FirebaseFirestore
import Foundation
import Testing
@testable import Peezy_4_0

/// S1 families (briefs/S1_BRIEF.md): readiness (D23/D28). S4 extends this
/// file; S1 owns only the families named in the brief.
struct DurableStoreRecoveryTests {

    // MARK: - Readiness family (D23/D28): required sets, gate, projection, admission

    @Test func requiredSetsAreExact() {
        #expect(GatedOperation.handoffOperation.requiredSet == [.handoff])
        for op in [GatedOperation.routeClaim, .routeRefresh, .routeReturnedSessionPresentation] {
            #expect(op.requiredSet == [.route, .handoff])
        }
        for op in [GatedOperation.resetReserve, .resetBind, .resetDispatch, .resetApplication] {
            #expect(op.requiredSet == [.reset, .handoff])
        }
        for op in [GatedOperation.workflowPrepare, .workflowDispatch, .workflowApplication] {
            #expect(op.requiredSet == [.workflow, .handoff])
        }
        #expect(GatedOperation.directTaskCallable.requiredSet.isEmpty)
    }

    @Test func readinessVectorStartsLoadingForEveryStore() async {
        let barrier = StartupBarrier(currentUID: UIDProbe(nil))
        let vector = await barrier.readiness()
        for store in DurableStore.allCases { #expect(vector[store] == .loading) }
        #expect(await barrier.gate() == .loading)
    }

    @Test func storeReadinessIsHeldUntilTheGateIsClassified() async {
        let barrier = StartupBarrier(currentUID: UIDProbe(nil))
        await barrier.publish(.route, .ready)
        #expect(await barrier.readiness()[.route] == .loading)
        await barrier.setGate(.clear)
        #expect(await barrier.readiness()[.route] == .ready)
        #expect(await barrier.readiness()[.handoff] == .loading)
    }

    @Test func emptyRequiredSetIsAdmittedUnderClearGateWithoutStoreDependency() async {
        let barrier = StartupBarrier(currentUID: UIDProbe("A"))
        await barrier.setGate(.clear)
        // Every store still loading: a clear gate adds no store dependency.
        guard case .admitted = await barrier.admission(of: .directTaskCallable, uid: "A") else {
            Issue.record("direct callable must be admitted under a clear gate with all stores loading")
            return
        }
    }

    @Test func emptyRequiredSetNeverBypassesANonclearGate() async {
        let probe = UIDProbe("A")
        for gate in [AccountDeletionGate.loading, .active(uid: "A"), .blocked, .guarding(uid: "A", authGuardAfter: "2026-09-03T00:00:00.000Z")] {
            let barrier = StartupBarrier(currentUID: probe)
            await barrier.setGate(gate)
            let admission = await barrier.admission(of: .directTaskCallable, uid: "A")
            if case .admitted = admission { Issue.record("gate \(gate) must not admit an empty-required-set callable") }
        }
    }

    @Test func guardingAdmitsAnotherUIDButRefusesTheDeletedUID() async {
        let probe = UIDProbe("B")
        let barrier = StartupBarrier(currentUID: probe)
        for store in DurableStore.allCases { await barrier.publish(store, .ready) }
        await barrier.setGate(.guarding(uid: "A", authGuardAfter: "2026-09-03T00:00:00.000Z"))
        #expect(await barrier.admission(of: .handoffOperation, uid: "A") == .refused(.guardingSameUID))
        guard case .admitted = await barrier.admission(of: .handoffOperation, uid: "B") else {
            Issue.record("a different UID dispatches ordinary work during guarding once stores are ready")
            return
        }
    }

    @Test func projectionEnumeratesAllNineMembers() async {
        let probe = UIDProbe("A")
        let barrier = StartupBarrier(currentUID: probe)
        #expect(await barrier.projection() == .loading)
        await barrier.setGate(.clear)
        #expect(await barrier.projection() == .clear)
        await barrier.setGate(.blocked)
        #expect(await barrier.projection() == .blocked)
        await barrier.setGate(.active(uid: "A"))
        #expect(await barrier.projection() == .activeSameUID)
        probe.uid = "B"
        #expect(await barrier.projection() == .activeOtherUID)
        probe.uid = nil
        #expect(await barrier.projection() == .activeWithNilCurrentUID)
        await barrier.setGate(.guarding(uid: "A", authGuardAfter: "2026-09-03T00:00:00.000Z"))
        probe.uid = "A"
        #expect(await barrier.projection() == .guardingSameUID)
        probe.uid = "B"
        #expect(await barrier.projection() == .guardingOtherUID)
        await barrier.setGate(.active(uid: "A"))
        await barrier.setPendingTerminalPresentation(.localCleared)
        #expect(await barrier.projection() == .localCleared)
        #expect(AccountDeletionGateProjection.allCases.count == 9)
    }

    @Test func admissionCarriesTheGateGenerationAndItChangesWithTheGate() async {
        let barrier = StartupBarrier(currentUID: UIDProbe("A"))
        await barrier.setGate(.clear)
        guard case let .admitted(first) = await barrier.admission(of: .directTaskCallable, uid: "A") else {
            Issue.record("expected admission"); return
        }
        #expect(await barrier.gateGeneration() == first)
        await barrier.setGate(.active(uid: "A"))
        #expect(await barrier.gateGeneration() != first)
        await barrier.setGate(.clear)
        guard case let .admitted(second) = await barrier.admission(of: .directTaskCallable, uid: "A") else {
            Issue.record("expected admission"); return
        }
        #expect(second != first)
    }

    @Test func blockedStoreInRequiredSetRefusesWithItsSnapshot() async {
        let barrier = StartupBarrier(currentUID: UIDProbe("A"))
        let snapshot = BlockedSnapshot.storageIOUnavailable(store: .reset, errorCode: .fileOpenFailed)
        await barrier.publish(.reset, .blocked(snapshot))
        await barrier.publish(.handoff, .ready)
        await barrier.setGate(.clear)
        #expect(await barrier.admission(of: .resetReserve, uid: "A") == .blocked(store: .reset, snapshot))
        // An unrelated required set is unaffected by the reset store's block.
        guard case .admitted = await barrier.admission(of: .handoffOperation, uid: "A") else {
            Issue.record("handoff-only operation must not depend on the reset store"); return
        }
    }

    @Test func loadingStoreInRequiredSetDefersAdmission() async {
        let barrier = StartupBarrier(currentUID: UIDProbe("A"))
        await barrier.publish(.handoff, .ready)
        await barrier.setGate(.clear)
        #expect(await barrier.admission(of: .routeClaim, uid: "A") == .deferred(storesLoading: [.route]))
    }

    // MARK: - Seam exactness (D23): every §8:971 seam compiles against its exact shape

    @Test func authAuthoritySeamIsExact() async {
        struct Stub: AuthAuthorityProviding {
            func currentSignedAuth() async -> SignedAuthAuthority {
                .signedIn(SignedAuthTuple(uid: "A", authEpochUUID: "e", credentialRevision: 3))
            }
            func forceRefresh(expected: SignedAuthTuple) async -> AuthRefreshOutcome { .notCommitted }
            func confirmAccountDeleted(expected: AuthIdentity) async -> AccountDeletionAuthObservation { .notProven }
        }
        let stub: any AuthAuthorityProviding = Stub()
        #expect(await stub.currentSignedAuth() == .signedIn(SignedAuthTuple(uid: "A", authEpochUUID: "e", credentialRevision: 3)))
        #expect(await stub.forceRefresh(expected: SignedAuthTuple(uid: "A", authEpochUUID: "e", credentialRevision: 3)) == .notCommitted)
        #expect(await stub.confirmAccountDeleted(expected: AuthIdentity(uid: "A", authEpochUUID: "e")) == .notProven)
    }

    @Test func routeIngressSeamsAreExact() async {
        struct Receiver: RouteIngressReceiving {
            func receive(intentId: String, source: RouteIngressSource) async -> RouteIngressResult { .persisted }
        }
        final class Recorder: RouteIngressDiagnosticReporting, @unchecked Sendable {
            var reasons: [RouteIngressDiagnosticReason] = []
            func record(_ reason: RouteIngressDiagnosticReason) { reasons.append(reason) }
        }
        #expect(await Receiver().receive(intentId: "i", source: .notificationTap) == .persisted)
        #expect(RouteIngressSource.allCases.map(\.rawValue) == ["notification_tap", "url"])
        #expect(RouteIngressResult.allCases.map(\.rawValue) == ["persisted", "duplicate", "rejected_blocked", "rejected_full", "invalid"])
        let recorder = Recorder()
        for reason in RouteIngressDiagnosticReason.allCases { recorder.record(reason) }
        #expect(recorder.reasons.map(\.rawValue) == [
            "INTENT_ID_TYPE_INVALID", "INTENT_ID_INVALID", "TASK_URL_INVALID", "RECEIVED_AT_EPOCH_INVALID",
            "ROUTE_INBOX_BLOCKED", "ROUTE_INBOX_FULL", "ROUTE_INBOX_RECEIVED_EVICTED"
        ])
    }

    @Test func providerContextAndPresentationSeamsAreExact() async {
        struct Context: AccountDeletionProviderContextProviding {
            func dispositions(expectedUID: String) async -> AccountDeletionProviderDispositions {
                AccountDeletionProviderDispositions(appleRevocation: .manualRequired, googleRevocation: .sdkDisconnectRequired, googleProviderUid: "g")
            }
        }
        struct Presenter: AccountDeletionCompletionPresenting {
            func current() async -> CompletionSnapshotV1? { nil }
            func acknowledge(expectedGenerationId: String, expectedSHA256: String) async -> CompletionAcknowledgeResult { .stale }
            func open(expectedGenerationId: String, expectedSHA256: String, provider: CompletionProvider) async -> CompletionOpenResult { .notOffered }
        }
        let d = await Context().dispositions(expectedUID: "A")
        #expect(d.appleRevocation.rawValue == "manual_required")
        #expect(d.googleRevocation.rawValue == "sdk_disconnect_required")
        #expect(AppleRevocationDisposition.allCases.map(\.rawValue) == ["not_required", "manual_required"])
        #expect(GoogleRevocationDisposition.allCases.map(\.rawValue) == ["not_required", "sdk_disconnect_required", "manual_required"])
        #expect(await Presenter().current() == nil)
        #expect(await Presenter().acknowledge(expectedGenerationId: "g", expectedSHA256: "h") == .stale)
        #expect(await Presenter().open(expectedGenerationId: "g", expectedSHA256: "h", provider: .apple) == .notOffered)
    }

    @Test func identityAndTelemetrySeamsAreExact() async {
        struct Apple: AppleCredentialStateChecking {
            func credentialState(forProviderUID providerUID: String) async -> AppleCredentialStateOutcomeV1 { .unresolved }
        }
        struct Google: GoogleIdentityControlling {
            func currentProviderUID() async -> String? { nil }
            func handle(_ url: URL) async -> GoogleURLHandleOutcomeV1 { .notHandled }
            func signIn() async -> GoogleFirebaseSignInOutcomeV1 { .failed(.staleGeneration) }
            func disconnect(expectedProviderUID: String) async -> GoogleCredentialOutcomeV1 { .identityMismatch }
            func signOutAll() async -> GoogleCredentialOutcomeV1 { .signedOut }
        }
        struct Telemetry: ClientTelemetryPrivacyPurging {
            func purgeAll() async -> ClientTelemetryPurgeOutcomeV1 { .relaunchRequired }
        }
        #expect(await Apple().credentialState(forProviderUID: "p") == .unresolved)
        #expect(AppleCredentialStateOutcomeV1.allCases.count == 5)
        #expect(await Google().signIn() == .failed(.staleGeneration))
        #expect(GoogleFirebaseSignInFailureV1.allCases.map(\.rawValue) == ["missingClientID", "missingPresenter", "sdkFailure", "missingToken", "firebaseFailure", "staleGeneration"])
        #expect(GoogleCredentialOutcomeV1.allCases.count == 4)
        #expect(await Telemetry().purgeAll() == .relaunchRequired)
        #expect(ClientTelemetryPurgeOutcomeV1.allCases.map(\.rawValue) == ["cleared", "relaunchRequired", "failed"])
    }

    @Test func installationAndResetSeamsAreExact() async throws {
        struct Installation: InstallationIdentityProviding {
            func load() async -> InstallationIdentityLoadResult { .absent }
            func addIfAbsent(_ candidate: String) async -> InstallationIdentityAddResult { .inserted(candidate) }
            func rekeyEmptyContainer(_ candidate: String) async -> InstallationIdentityRekeyResult { .error(stage: .update) }
            func repairInvalid(_ candidate: String) async -> InstallationIdentityRepairResult { .stillInvalid }
        }
        struct Epoch: ResetEpochAuthorityProviding {
            func current(uid: String, expectedAuth: SignedAuthTuple) async throws -> ResetEpochAuthority {
                ResetEpochAuthority(uid: uid, taskGenerationEpoch: 4)
            }
        }
        struct Recoverer: ResetEpochConflictRecovering {
            func recoverEpoch(recoveryStateDigest: String, expectedTaskGenerationEpoch: Int, expectedPhase: ResetRowPhase, action: ResetRecoveryAction) async -> RecoveryResult {
                .unavailable(store: .reset)
            }
        }
        #expect(await Installation().addIfAbsent("u") == .inserted("u"))
        #expect(await Installation().rekeyEmptyContainer("u") == .error(stage: .update))
        #expect(await Installation().repairInvalid("u") == .stillInvalid)
        let authority = try await Epoch().current(uid: "A", expectedAuth: SignedAuthTuple(uid: "A", authEpochUUID: "e", credentialRevision: 1))
        #expect(authority.taskGenerationEpoch == 4)
        let result = await Recoverer().recoverEpoch(recoveryStateDigest: "d", expectedTaskGenerationEpoch: 1, expectedPhase: .prepared, action: .retryReset)
        #expect(result == .unavailable(store: .reset))
        #expect(ResetRecoveryAction.allCases.map(\.rawValue) == ["retry_reset", "resume_server_deletion", "run_local_cleanup", "retry_finalize", "apply_final"])
    }

    @Test func purgeSeamsShareOneScopeAndAckVocabulary() async {
        struct Route: RouteAccountDeletionPurging { func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck { .acknowledged } }
        struct Handoff: HandoffAccountDeletionPurging { func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck { .acknowledged } }
        struct Reset: ResetAccountDeletionPurging { func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck { .failed } }
        struct Workflow: WorkflowAccountDeletionPurging { func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck { .acknowledged } }
        struct Cache: FirestoreLocalCachePurging { func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck { .acknowledged } }
        struct Notifications: NotificationIdentityPurging { func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck { .acknowledged } }
        struct Room: RoomCaptureArtifactPurging { func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck { .acknowledged } }
        struct Coordinator: LocalPrivacyPurgeCoordinating {
            func purge(scope: LocalPurgeScope) async -> LocalPrivacyPurgeResult { .blocked(.localPrivacyPurgeFailed) }
        }
        #expect(await Route().purgeForAccountDeletion(scope: .all) == .acknowledged)
        #expect(await Reset().purgeForAccountDeletion(scope: .uid("A")) == .failed)
        #expect(await Coordinator().purge(scope: .uid("A")) == .blocked(.localPrivacyPurgeFailed))
        #expect(LocalPrivacyPurgeBlockedReason.allCases.map(\.rawValue) == ["FILE_IO", "REMOTE_UNAVAILABLE", "REMOTE_MALFORMED", "LOCAL_PRIVACY_PURGE_FAILED"])
        _ = (Handoff(), Workflow(), Cache(), Notifications(), Room())
    }

    @Test func blockedSnapshotUnionCarriesTheExactStoreAndActions() {
        let io = BlockedSnapshot.storageIOUnavailable(store: .route, errorCode: .fileRenameFailed)
        #expect(io.store == .route)
        #expect(io.availableActions == ["retry"])
        let conflict = BlockedSnapshot.resetEpochConflict(
            recoveryStateDigest: "d", actionableExpectedTaskGenerationEpoch: 2,
            occupants: [.init(expectedTaskGenerationEpoch: 2, phase: .prepared, recoveryAction: .retryReset)]
        )
        #expect(conflict.store == .reset)
        #expect(conflict.availableActions == ["recover_epoch"])
        let invalid = BlockedSnapshot.installationAuthorityInvalid
        #expect(invalid.store == .handoff)
        #expect(invalid.availableActions == ["repair_installation_identity"])
        #expect(StorageIOErrorCode.allCases.count == 8)
    }

    // MARK: - Firestore runtime seam (I3): consumers acquire Firestore only through the seam

    @Test func firestoreRuntimeSeamIsExact() async throws {
        struct Stub: FirestoreRuntimeProviding {
            func acquire() async throws -> FirestoreRuntimeLease {
                FirestoreRuntimeLease(firestore: Firestore.firestore(), generation: FirestoreRuntimeGeneration(rawValue: 7))
            }
            func published() -> FirestoreRuntimeLease {
                FirestoreRuntimeLease(firestore: Firestore.firestore(), generation: FirestoreRuntimeGeneration(rawValue: 7))
            }
            func isCurrent(_ generation: FirestoreRuntimeGeneration) -> Bool { generation.rawValue == 7 }
        }
        let stub: any FirestoreRuntimeProviding = Stub()
        #expect(stub.isCurrent(FirestoreRuntimeGeneration(rawValue: 7)))
        #expect(stub.isCurrent(FirestoreRuntimeGeneration(rawValue: 8)) == false)
        // `published()` needs a configured FirebaseApp; the emulator-gated lease test covers it.
    }

    /// Static gate from manifest §12.2:1866: zero production `Firestore.firestore()`
    /// in S1-owned files outside the runtime provider itself.
    @Test func s1OwnedFilesAcquireFirestoreOnlyThroughTheRuntimeSeam() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        // RetakeAssessmentCoordinator.swift joins this list when S3 replaces its pinned
        // closure slice whole per §6.6 (the two acquisitions live inside that slice).
        let owned = [
            "Peezy 4.0/Menu/PeezySettingsView.swift",
            "Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift",
            "Peezy 4.0/MainInterface/Models/UserKnowledgeService.swift",
            "Peezy 4.0/MainInterface/Models/DailyDoseEngine.swift",
            "Peezy 4.0/MainInterface/Models/TaskPlanService.swift",
            "Peezy 4.0/Assessment/AssessmentViews/Onboarding/GeneratingView.swift",
            "Peezy 4.0/Inventory/Services/InventoryStorageService.swift",
            "Peezy 4.0/MainInterface/Models/BoxReturnService.swift",
            "Peezy 4.0/MainInterface/Models/CheckInService.swift",
            "Peezy 4.0/MainInterface/Models/ISPPlanService.swift",
            "Peezy 4.0/MainInterface/Models/IdentityService.swift",
            "Peezy 4.0/MainInterface/Models/PeezyStackViewModel.swift",
            "Peezy 4.0/MainInterface/Models/SubscriptionManager.swift",
            "Peezy 4.0/MainInterface/Models/Vendor.swift",
            "Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift",
            "Peezy 4.0/Tasks/FlowEngine/FlowDefinition.swift",
            "Peezy 4.0/Tasks/FlowEngine/InAppTaskFlows.swift",
            "Peezy 4.0/Tasks/FlowEngine/MoveAnswersStore.swift",
            "Peezy 4.0/Tasks/Task Cards/ScanInventoryFlow.swift",
            "Peezy 4.0/Inventory/Models/InventorySessionManager.swift",
        ]
        var hits: [String] = []
        for relative in owned {
            let source = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            for (index, line) in source.components(separatedBy: "\n").enumerated()
            where line.contains("Firestore.firestore()") {
                hits.append("\(relative):\(index + 1)")
            }
        }
        #expect(hits.isEmpty, "direct acquisitions remain: \(hits)")
    }

    @Test(.enabled(if: FirebaseEmulator.isConfigured))
    func productionRuntimeLeaseTargetsTheEmulator() async throws {
        _ = try FirebaseEmulator.firestore()
        try await FirebaseEmulator.clearFirestore()
        let uid = try await FirebaseEmulator.signInFreshUser()
        let lease = try await FirestoreRuntime.provider.acquire()
        #expect(FirestoreRuntime.provider.isCurrent(lease.generation))
        #expect(FirestoreRuntime.provider.published().generation == lease.generation)
        let ref = lease.firestore.collection("users").document(uid)
        try await ref.setData(["name": "lease"])
        #expect(try await ref.getDocument().data()?["name"] as? String == "lease")
        try FirebaseEmulator.signOut()
    }

    // MARK: - Epoch stamps (I4, stamps only; manifest §5:540-546). Cleanup belongs to S3.

    @Test func dailyDoseLocalStoreWritesAStampedV2EnvelopeAndCASesRevision() async throws {
        let defaults = try isolatedDefaults()
        let store = DailyDoseLocalStore(defaults: defaults)
        #expect(await store.load(uid: "A") == .absent)
        let created = await store.ensure(uid: "A", taskGenerationEpoch: 2)
        #expect(created == DailyDoseLocalStateV1(taskGenerationEpoch: 2, revision: 0, completedCount: 0, lastDate: nil, firstLaunchDate: nil))
        let raw = try #require(defaults.data(forKey: "peezy.A.dailyDose.v2"))
        #expect(String(decoding: raw, as: UTF8.self) == #"{"completedCount":0,"firstLaunchDate":null,"lastDate":null,"revision":0,"schemaVersion":1,"taskGenerationEpoch":2}"#)
        let mutated = await store.mutate(uid: "A", expectedTaskGenerationEpoch: 2, expectedRevision: 0) { $0.completedCount = 3; $0.lastDate = "2026-09-03" }
        guard case let .committed(after) = mutated else { Issue.record("expected committed, got \(mutated)"); return }
        #expect(after.revision == 1 && after.completedCount == 3 && after.lastDate == "2026-09-03")
        let stale = await store.mutate(uid: "A", expectedTaskGenerationEpoch: 2, expectedRevision: 0) { $0.completedCount = 9 }
        guard case .drift = stale else { Issue.record("stale revision must drift, got \(stale)"); return }
        let wrongEpoch = await store.mutate(uid: "A", expectedTaskGenerationEpoch: 1, expectedRevision: 1) { $0.completedCount = 9 }
        guard case .drift = wrongEpoch else { Issue.record("wrong epoch must drift, got \(wrongEpoch)"); return }
        #expect(await store.load(uid: "A") == .present(after))
        #expect(await store.ensure(uid: "A", taskGenerationEpoch: 5) == after)
    }

    @Test func dailyDoseLocalStorePreservesMalformedBytesAndBlocksMutation() async throws {
        let defaults = try isolatedDefaults()
        let store = DailyDoseLocalStore(defaults: defaults)
        let malformed = Data(#"{"schemaVersion":1,"taskGenerationEpoch":-1}"#.utf8)
        defaults.set(malformed, forKey: "peezy.A.dailyDose.v2")
        #expect(await store.load(uid: "A") == .malformed)
        guard case .malformed = await store.mutate(uid: "A", expectedTaskGenerationEpoch: 1, expectedRevision: 0, { $0.completedCount = 1 }) else {
            Issue.record("malformed envelope must block mutation"); return
        }
        #expect(defaults.data(forKey: "peezy.A.dailyDose.v2") == malformed)
        let oversized = Data(("{\"schemaVersion\":1,\"taskGenerationEpoch\":0,\"revision\":0,\"completedCount\":0,\"lastDate\":\"" + String(repeating: "x", count: 1_100) + "\",\"firstLaunchDate\":null}").utf8)
        defaults.set(oversized, forKey: "peezy.B.dailyDose.v2")
        #expect(await store.load(uid: "B") == .malformed)
    }

    @Test(.enabled(if: FirebaseEmulator.isConfigured))
    func stampedAssessmentCreateReadsRootAndStampsTheEffectiveEpoch() async throws {
        let db = try FirebaseEmulator.firestore()
        try await FirebaseEmulator.clearFirestore()
        let uid = try await FirebaseEmulator.signInFreshUser()
        defer { try? FirebaseEmulator.signOut() }
        try await FirebaseEmulator.adminSet("users/\(uid)", ["name": "A"])
        let first = try await AssessmentDataManager.createStampedAssessment(["moveDate": "2026-10-01"], userId: uid, db: db)
        #expect(try await db.collection("users").document(uid).collection("user_assessments").document(first).getDocument().data()?["task_generation_epoch"] as? Int == 0)
        try await FirebaseEmulator.adminSet("users/\(uid)", ["name": "A", "taskGenerationEpoch": 3])
        let second = try await AssessmentDataManager.createStampedAssessment(["moveDate": "2026-10-02"], userId: uid, db: db)
        #expect(try await db.collection("users").document(uid).collection("user_assessments").document(second).getDocument().data()?["task_generation_epoch"] as? Int == 3)
        try await FirebaseEmulator.adminSet("users/\(uid)", ["name": "A", "taskGenerationEpoch": 3, "taskReset": ["state": "deleting"]])
        await #expect(throws: (any Error).self) {
            try await AssessmentDataManager.createStampedAssessment(["moveDate": "2026-10-03"], userId: uid, db: db)
        }
        try await FirebaseEmulator.adminSet("users/\(uid)", ["name": "A", "taskGenerationEpoch": "three"])
        await #expect(throws: (any Error).self) {
            try await AssessmentDataManager.createStampedAssessment(["moveDate": "2026-10-04"], userId: uid, db: db)
        }
        let count = try await db.collection("users").document(uid).collection("user_assessments").getDocuments().documents.count
        #expect(count == 2)
    }

    @Test(.enabled(if: FirebaseEmulator.isConfigured))
    func userKnowledgeMergePreservesMatchingStampUpgradesUnstampedAtZeroAndRejectsDrift() async throws {
        let db = try FirebaseEmulator.firestore()
        try await FirebaseEmulator.clearFirestore()
        let uid = try await FirebaseEmulator.signInFreshUser()
        defer { try? FirebaseEmulator.signOut() }
        let ref = db.collection("userKnowledge").document(uid)
        try await FirebaseEmulator.adminSet("users/\(uid)", ["name": "A"])
        try await UserKnowledgeService.merge(["a": 1], source: .assessment, userId: uid)
        #expect(try await ref.getDocument().data()?["task_generation_epoch"] as? Int == 0)
        try await UserKnowledgeService.merge(["b": 2], source: .settings, userId: uid)
        let merged = try await ref.getDocument().data()
        #expect(merged?["task_generation_epoch"] as? Int == 0)
        #expect(Set((merged?["entries"] as? [String: Any])?.keys.map { $0 } ?? []) == ["a", "b"])
        try await FirebaseEmulator.adminSet("userKnowledge/\(uid)", ["entries": ["legacy": ["value": 1]]])
        try await UserKnowledgeService.merge(["c": 3], source: .settings, userId: uid)
        let upgraded = try await ref.getDocument().data()
        #expect(upgraded?["task_generation_epoch"] as? Int == 0)
        #expect(Set((upgraded?["entries"] as? [String: Any])?.keys.map { $0 } ?? []) == ["legacy", "c"])
        try await FirebaseEmulator.adminSet("users/\(uid)", ["name": "A", "taskGenerationEpoch": 2])
        await #expect(throws: (any Error).self) { try await UserKnowledgeService.merge(["d": 4], source: .settings, userId: uid) }
        try await FirebaseEmulator.adminSet("userKnowledge/\(uid)", ["entries": ["legacy": ["value": 1]]])
        await #expect(throws: (any Error).self) { try await UserKnowledgeService.merge(["d": 4], source: .settings, userId: uid) }
        #expect(try await ref.getDocument().data()?["task_generation_epoch"] == nil)
        try await FirebaseEmulator.adminSet("users/\(uid)", ["name": "A", "taskGenerationEpoch": 2, "taskReset": ["state": "deleting"]])
        try await FirebaseEmulator.adminSet("userKnowledge/\(uid)", ["entries": ["legacy": ["value": 1]], "task_generation_epoch": 2])
        await #expect(throws: (any Error).self) { try await UserKnowledgeService.merge(["e": 5], source: .settings, userId: uid) }
    }

    @Test(.enabled(if: FirebaseEmulator.isConfigured))
    func dailyDoseFreezeWritesTheExactStampedMapAndLegacyReadsOnlyAtEpochZero() async throws {
        let db = try FirebaseEmulator.firestore()
        try await FirebaseEmulator.clearFirestore()
        let uid = try await FirebaseEmulator.signInFreshUser()
        defer { try? FirebaseEmulator.signOut() }
        try await FirebaseEmulator.adminSet("users/\(uid)", ["name": "A", "dailyDose": ["date": "2026-09-03", "taskIds": ["t1"]]])
        let engine = DailyDoseEngine()
        #expect(await engine.loadFrozenDose(userId: uid) == DailyDoseEngine.FrozenDose(date: "2026-09-03", taskIds: ["t1"]))
        await engine.freeze(DailyDoseEngine.FrozenDose(date: "2026-09-04", taskIds: ["t2"]), userId: uid)
        let stored = try await db.collection("users").document(uid).getDocument().data()?["dailyDose"] as? [String: Any]
        #expect(stored?["schema_version"] as? Int == 1)
        #expect(stored?["task_generation_epoch"] as? Int == 0)
        #expect(stored?["date"] as? String == "2026-09-04")
        #expect(stored?["taskIds"] as? [String] == ["t2"])
        #expect(stored?.count == 4)
        #expect(await engine.loadFrozenDose(userId: uid) == DailyDoseEngine.FrozenDose(date: "2026-09-04", taskIds: ["t2"]))
        try await FirebaseEmulator.adminSet("users/\(uid)", ["name": "A", "taskGenerationEpoch": 1, "dailyDose": ["date": "2026-09-03", "taskIds": ["t1"]]])
        #expect(await engine.loadFrozenDose(userId: uid) == nil)
        await engine.freeze(DailyDoseEngine.FrozenDose(date: "2026-09-05", taskIds: []), userId: uid)
        let restamped = try await db.collection("users").document(uid).getDocument().data()?["dailyDose"] as? [String: Any]
        #expect(restamped?["task_generation_epoch"] as? Int == 1)
        try await FirebaseEmulator.adminSet("users/\(uid)", ["name": "A", "taskGenerationEpoch": 1, "dailyDose": ["schema_version": 1, "task_generation_epoch": 0, "date": "2026-09-03", "taskIds": ["t1"]]])
        #expect(await engine.loadFrozenDose(userId: uid) == nil)
    }

    // MARK: - Account-deletion DTO/transport (I5; C2.3, manifest v9:1435, v7:1307)

    @Test func accountDeletionRequestsSerializeTheClosedUnion() async throws {
        let recorder = DeletionCallableRecorder(result: .success(["schemaVersion": 1, "kind": "account_deletion_discovery", "state": "absent", "operationId": "adel1_op"]))
        let transport = TaskPlanService.AccountDeletionTransport(callable: recorder.call)
        let requests: [(AccountDeletionRequestV1, String)] = [
            (.discover(uid: "A", operationId: "adel1_op", proofNonce: "nonce"), "discover"),
            (.begin(uid: "A", operationId: "adel1_op", proofNonce: "nonce"), "begin"),
            (.resume(uid: "A", operationId: "adel1_op", proofNonce: "nonce"), "resume"),
            (.finalize(uid: "A", operationId: "adel1_op", proofNonce: "nonce"), "finalize")
        ]
        for (request, action) in requests { _ = try await transport.perform(request) }
        #expect(recorder.calls.map(\.name) == Array(repeating: "deleteAccount", count: 4))
        for (index, (_, action)) in requests.enumerated() {
            let expected: [String: Any] = ["schemaVersion": 1, "action": action, "uid": "A", "operationId": "adel1_op", "proofNonce": "nonce"]
            #expect(recorder.calls[index].payload as NSDictionary == expected as NSDictionary)
        }
    }

    @Test func accountDeletionDecodesTheFourWiresExactly() throws {
        typealias T = TaskPlanService.AccountDeletionTransport
        #expect(try T.decode(["schemaVersion": 1, "kind": "account_deletion_discovery", "state": "absent", "operationId": "adel1_op"]) == .absent(operationId: "adel1_op"))
        let dataFinal = try T.decode([
            "schemaVersion": 1, "kind": "account_deletion_data_final", "operationId": "adel1_op", "authorityKind": "member",
            "startedAt": "2026-09-01T00:00:00.000Z", "dataDeletedAt": "2026-09-08T00:00:00.000Z", "replayed": false
        ])
        #expect(dataFinal == .dataFinal(AccountDeletionDataFinalWireV1(
            operationId: "adel1_op", authorityKind: .member,
            startedAt: "2026-09-01T00:00:00.000Z", dataDeletedAt: "2026-09-08T00:00:00.000Z", replayed: false
        )))
        let guarding = try T.decode([
            "schemaVersion": 1, "kind": "account_deletion_auth_guarding", "operationId": "adel1_op", "authorityKind": "authenticatedOverflow",
            "startedAt": "2026-09-01T00:00:00.000Z", "dataDeletedAt": "2026-09-08T00:00:00.000Z",
            "authAbsenceObservedAt": "2026-09-08T00:00:01.000Z", "authGuardAfter": "2026-10-08T00:00:01.000Z", "replayed": true
        ])
        #expect(guarding == .authGuarding(AccountDeletionAuthGuardingWireV1(
            operationId: "adel1_op", authorityKind: .authenticatedOverflow,
            startedAt: "2026-09-01T00:00:00.000Z", dataDeletedAt: "2026-09-08T00:00:00.000Z",
            authAbsenceObservedAt: "2026-09-08T00:00:01.000Z", authGuardAfter: "2026-10-08T00:00:01.000Z", replayed: true
        )))
        let deleted = try T.decode([
            "schemaVersion": 1, "kind": "account_deletion_account_deleted", "operationId": "adel1_op", "authorityKind": "member",
            "startedAt": "2026-09-01T00:00:00.000Z", "dataDeletedAt": "2026-09-08T00:00:00.000Z",
            "authAbsenceObservedAt": "2026-09-08T00:00:01.000Z", "authGuardAfter": "2026-10-08T00:00:01.000Z",
            "authGuardCompletedAt": "2026-10-08T00:05:00.000Z", "accountDeletedAt": "2026-10-08T00:05:00.000Z", "replayed": false
        ])
        guard case let .accountDeleted(wire) = deleted else { Issue.record("expected accountDeleted"); return }
        #expect(wire.accountDeletedAt == "2026-10-08T00:05:00.000Z" && wire.authGuardCompletedAt == "2026-10-08T00:05:00.000Z")
    }

    @Test func accountDeletionRejectsSurplusMissingAndUnknownMembers() {
        typealias T = TaskPlanService.AccountDeletionTransport
        let base: [String: Any] = [
            "schemaVersion": 1, "kind": "account_deletion_data_final", "operationId": "adel1_op", "authorityKind": "member",
            "startedAt": "2026-09-01T00:00:00.000Z", "dataDeletedAt": "2026-09-08T00:00:00.000Z", "replayed": false
        ]
        var variants: [[String: Any]] = []
        var surplus = base; surplus["extra"] = 1; variants.append(surplus)
        var missing = base; missing.removeValue(forKey: "replayed"); variants.append(missing)
        var unknownKind = base; unknownKind["kind"] = "account_deletion_unknown"; variants.append(unknownKind)
        var badAuthority = base; badAuthority["authorityKind"] = "owner"; variants.append(badAuthority)
        var numericReplayed = base; numericReplayed["replayed"] = 1; variants.append(numericReplayed)
        var badTime = base; badTime["startedAt"] = "2026-09-01"; variants.append(badTime)
        var wrongVersion = base; wrongVersion["schemaVersion"] = 2; variants.append(wrongVersion)
        variants.append(["schemaVersion": 1, "kind": "account_deletion_discovery", "state": "present", "operationId": "adel1_op"])
        variants.append(["schemaVersion": 1, "kind": "account_deletion_discovery", "state": "absent", "operationId": "adel1_op", "extra": true])
        for variant in variants {
            #expect(throws: AccountDeletionRemoteError.protocolAmbiguity) { try T.decode(variant) }
        }
    }

    @Test func accountDeletionMapsThrownCodesAndTransportFailures() async {
        func error(_ details: [String: Any]?) -> NSError {
            NSError(domain: "com.firebase.functions", code: 9, userInfo: details.map { ["details": $0] } ?? [:])
        }
        let cases: [(NSError, AccountDeletionRemoteError)] = [
            (error(["schemaVersion": 1, "reason": "REQUEST_INVALID", "field": "proofNonce"]), .requestInvalid(field: "proofNonce")),
            (error(["schemaVersion": 1, "reason": "AUTH_REQUIRED"]), .authRequired),
            (error(["schemaVersion": 1, "reason": "DELETION_CAPABILITY_INVALID"]), .capabilityInvalid),
            (error(["schemaVersion": 1, "reason": "DELETION_RETRY_REQUIRED"]), .retryRequired),
            (error(["schemaVersion": 1, "reason": "SOMETHING_ELSE"]), .protocolAmbiguity),
            (error(["reason": "AUTH_REQUIRED"]), .protocolAmbiguity),
            (error(["schemaVersion": 1, "reason": "REQUEST_INVALID"]), .protocolAmbiguity),
            (NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet), .transport),
            (NSError(domain: "com.firebase.functions", code: 14, userInfo: [:]), .transport)
        ]
        for (thrown, expected) in cases {
            let recorder = DeletionCallableRecorder(result: .failure(thrown))
            let transport = TaskPlanService.AccountDeletionTransport(callable: recorder.call)
            await #expect(throws: expected) {
                try await transport.perform(.discover(uid: "A", operationId: "adel1_op", proofNonce: "nonce"))
            }
        }
    }

    @Test func accountDeletionTransportConformsToTheSeam() async throws {
        let recorder = DeletionCallableRecorder(result: .success(["schemaVersion": 1, "kind": "account_deletion_discovery", "state": "absent", "operationId": "adel1_op"]))
        let provider: any AccountDeletionRemoteProviding = TaskPlanService.AccountDeletionTransport(callable: recorder.call)
        #expect(try await provider.perform(.resume(uid: "A", operationId: "adel1_op", proofNonce: "nonce")) == .absent(operationId: "adel1_op"))
    }

    // MARK: - Reset envelope and registry (I6; §5, §7 envelope, D14/D24/B2)

    @Test func taskCanonicalV1IsSortedCompactJSON() throws {
        let data = try #require(TaskCanonicalV1.data(["b": 1, "a": "x"]))
        #expect(String(decoding: data, as: UTF8.self) == #"{"a":"x","b":1}"#)
        #expect(TaskCanonicalV1.sha256Hex(["b": 1, "a": "x"]) == "cdab067e9f3beb32d1252cfd63e492592fecbf591b0d08cadb24bb17f3864246")
        #expect(TaskCanonicalV1.data(["path": "a/b"]).map { String(decoding: $0, as: UTF8.self) } == #"{"path":"a/b"}"#)
    }

    @Test func resetEnvelopeRoundTripsWithCanonicalHashAndFreshGeneration() async throws {
        let directory = try temporaryDirectory()
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: SignedAuthStub(.signedIn(tupleA)), epochAuthority: EpochStub(epoch: 0))
        _ = try await registry.reserve(gestureId: "rsg1_11111111-1111-4111-8111-111111111111")
        let url = directory.appendingPathComponent(ResetOperationRegistry.fileName)
        let bytes = try Data(contentsOf: url)
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(Set(object.keys) == ["schemaVersion", "fileKind", "generationId", "payload", "sha256"])
        #expect(object["fileKind"] as? String == "TASK_PLAN_RESET_V2")
        let generation = try #require(object["generationId"] as? String)
        #expect(generation.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: .regularExpression) != nil)
        var unsigned = object; unsigned.removeValue(forKey: "sha256")
        #expect(object["sha256"] as? String == TaskCanonicalV1.sha256Hex(unsigned))
        #expect(bytes == TaskCanonicalV1.data(object))
        #if !targetEnvironment(simulator)
        // The simulator's file system reports no data-protection class; the
        // attribute is asserted on device builds only.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(attributes[.protectionKey] as? FileProtectionType == .completeUntilFirstUserAuthentication)
        #endif
        let snapshot = await registry.snapshot()
        #expect(snapshot.generationId == generation)
        // A later write receives a fresh outer generation while the gesture keeps its own token.
        let auth = SignedAuthStub(.signedIn(tupleA))
        let reloaded = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: auth, epochAuthority: EpochStub(epoch: 0))
        auth.set(.signedIn(tupleB))
        _ = try await reloaded.reserve(gestureId: "rsg1_22222222-2222-4222-8222-222222222222")
        let after = await reloaded.snapshot()
        #expect(after.generationId != generation)
        #expect(after.gesture?.uid == "B" && after.gesture?.gestureGeneration == after.generationId)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [ResetOperationRegistry.fileName])
    }

    @Test func resetEnvelopeRejectsTamperingOverCapAndSurplusMembers() async throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent(ResetOperationRegistry.fileName)
        func write(_ object: [String: Any]) throws { try TaskCanonicalV1.data(object)!.write(to: url) }
        func valid() -> [String: Any] {
            var envelope: [String: Any] = ["schemaVersion": 1, "fileKind": "TASK_PLAN_RESET_V2", "generationId": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "payload": ["records": [], "legacyMigrations": []]]
            envelope["sha256"] = TaskCanonicalV1.sha256Hex(envelope)
            return envelope
        }
        let registry = { ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: SignedAuthStub(.signedIn(tupleA)), epochAuthority: EpochStub(epoch: 0)) }
        try write(valid())
        #expect(await registry().load() == .present(records: 0, gesture: false))
        var tampered = valid(); tampered["sha256"] = String(repeating: "0", count: 64); try write(tampered)
        #expect(await registry().load() == .corrupt)
        var surplus = valid(); surplus["extra"] = true; surplus["sha256"] = TaskCanonicalV1.sha256Hex(surplus.filter { $0.key != "sha256" }); try write(surplus)
        #expect(await registry().load() == .corrupt)
        var wrongKind = valid(); wrongKind["fileKind"] = "WORKFLOW_REQUESTS_V2"; wrongKind["sha256"] = TaskCanonicalV1.sha256Hex(wrongKind.filter { $0.key != "sha256" }); try write(wrongKind)
        #expect(await registry().load() == .corrupt)
        try Data(repeating: 0x20, count: 131_073).write(to: url)
        #expect(await registry().load() == .corrupt)
        let bytes = try Data(contentsOf: url)
        await #expect(throws: ResetOperationRegistry.RegistryError.envelopeCorrupt) {
            _ = try await registry().reserve(gestureId: "rsg1_11111111-1111-4111-8111-111111111111")
        }
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func reserveStoresAReservedGestureBeforeReturningBinding() async throws {
        let directory = try temporaryDirectory()
        let clock = ResetClockStub("2026-09-06T10:00:00.000Z")
        let registry = ResetOperationRegistry(directory: directory, clock: clock, auth: SignedAuthStub(.signedIn(tupleA)), epochAuthority: EpochStub(epoch: 0))
        let outcome = try await registry.reserve(gestureId: "rsg1_11111111-1111-4111-8111-111111111111")
        guard case let .binding(reservation) = outcome else { Issue.record("expected binding, got \(outcome)"); return }
        #expect(reservation.gestureId == "rsg1_11111111-1111-4111-8111-111111111111")
        let snapshot = await registry.snapshot()
        let gesture = try #require(snapshot.gesture)
        #expect(gesture.phase == .reserved && gesture.uid == "A" && gesture.authEpochUUID == tupleA.authEpochUUID && gesture.credentialRevision == tupleA.credentialRevision)
        #expect(gesture.alias.range(of: #"^rsa1_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#, options: .regularExpression) != nil)
        #expect(gesture.reservedAt == "2026-09-06T10:00:00.000Z" && gesture.boundAt == nil && gesture.expectedEpoch == nil)
        #expect(gesture.gestureGeneration == reservation.gestureGeneration && gesture.gestureGeneration == snapshot.generationId)
        #expect(snapshot.records.isEmpty)
        // A second reserve while reserved adopts the exact current reservation and mints nothing.
        let again = try await registry.reserve(gestureId: "rsg1_33333333-3333-4333-8333-333333333333")
        #expect(again == .binding(reservation))
        let adopted = await registry.snapshot().gesture?.alias
        #expect(adopted == gesture.alias)
    }

    @Test func bindReadsTheEpochWritesBoundThenPreparedRowAndRemovesTheGesture() async throws {
        let directory = try temporaryDirectory()
        let clock = ResetClockStub("2026-09-06T10:00:00.000Z")
        let epoch = EpochStub(epoch: 4)
        let registry = ResetOperationRegistry(directory: directory, clock: clock, auth: SignedAuthStub(.signedIn(tupleA)), epochAuthority: epoch)
        guard case let .binding(reservation) = try await registry.reserve(gestureId: "rsg1_11111111-1111-4111-8111-111111111111") else { Issue.record("expected binding"); return }
        let alias = try #require(await registry.snapshot().gesture?.alias)
        clock.set("2026-09-06T10:00:05.000Z")
        let handle = try await registry.bind(reservation: reservation)
        #expect(epoch.calls == [("A", tupleA)].map { "\($0.0)|\($0.1.uid)|\($0.1.authEpochUUID)|\($0.1.credentialRevision)" })
        let snapshot = await registry.snapshot()
        #expect(snapshot.gesture == nil)
        let row = try #require(snapshot.records.first)
        #expect(snapshot.records.count == 1)
        #expect(row.uid == "A" && row.suggestedOperationId == alias && row.expectedTaskGenerationEpoch == 4 && row.phase == .prepared)
        #expect(row.createdAt == "2026-09-06T10:00:00.000Z" && row.updatedAt == "2026-09-06T10:00:05.000Z")
        #expect(row.canonicalOperationId == nil && row.progressReceipt == nil && row.finalReceipt == nil && row.applicationId == nil)
        let expectedHandle = "rho1_" + TaskCanonicalV1.sha256Hex(["uid": "A", "suggested_operation_id": alias, "created_at": "2026-09-06T10:00:00.000Z"])
        #expect(handle == ResetOperationHandle(uid: "A", handleId: expectedHandle))
        #expect(await registry.row(uid: "A", expectedTaskGenerationEpoch: 4) == row)
        #expect(await registry.row(uid: "A", expectedTaskGenerationEpoch: 3) == nil)
        await #expect(throws: ResetOperationRegistry.RegistryError.gestureStale(gestureId: reservation.gestureId, gestureGeneration: reservation.gestureGeneration)) {
            _ = try await registry.bind(reservation: reservation)
        }
        // The single current-UID row resumes as the same handle; no gesture is minted.
        #expect(try await registry.reserve(gestureId: "rsg1_44444444-4444-4444-8444-444444444444") == .operation(handle))
        #expect(await registry.snapshot().gesture == nil)
        try await registry.retire(handle: handle)
        #expect(await registry.snapshot().records.isEmpty)
        try await registry.retire(handle: handle)
    }

    @Test func bindRefusesEpochReadFailureAndAuthDrift() async throws {
        let directory = try temporaryDirectory()
        let auth = SignedAuthStub(.signedIn(tupleA))
        let epoch = EpochStub(epoch: 0)
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: auth, epochAuthority: epoch)
        guard case let .binding(reservation) = try await registry.reserve(gestureId: "rsg1_11111111-1111-4111-8111-111111111111") else { Issue.record("expected binding"); return }
        epoch.failure = TaskGenerationEpochError.malformedRootEpoch
        await #expect(throws: TaskGenerationEpochError.malformedRootEpoch) { _ = try await registry.bind(reservation: reservation) }
        #expect(await registry.snapshot().gesture?.phase == .reserved)
        epoch.failure = nil
        auth.set(.signedIn(tupleB))
        await #expect(throws: ResetOperationRegistry.RegistryError.gestureStale(gestureId: reservation.gestureId, gestureGeneration: reservation.gestureGeneration)) {
            _ = try await registry.bind(reservation: reservation)
        }
        #expect(await registry.snapshot().gesture == nil)
        #expect(await registry.snapshot().records.isEmpty)
        auth.set(.signedOut)
        await #expect(throws: ResetOperationRegistry.RegistryError.authRequired) { _ = try await registry.reserve(gestureId: "rsg1_55555555-5555-4555-8555-555555555555") }
    }

    @Test func fourForeignRowsRefuseReserveWithoutWriting() async throws {
        let directory = try temporaryDirectory()
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: SignedAuthStub(.signedIn(tupleA)), epochAuthority: EpochStub(epoch: 0))
        for uid in ["B", "C", "D", "E"] { try await seedPreparedRow(registry, uid: uid, epoch: 1, createdAt: "2026-09-06T09:00:0\(uid.utf8.first! - 65).000Z") }
        let before = try Data(contentsOf: directory.appendingPathComponent(ResetOperationRegistry.fileName))
        await #expect(throws: ResetOperationRegistry.RegistryError.registryFull(capacity: 4, occupants: [
            .init(uid: "B", expectedTaskGenerationEpoch: 1, phase: .prepared, recoveryAction: .retryReset),
            .init(uid: "C", expectedTaskGenerationEpoch: 1, phase: .prepared, recoveryAction: .retryReset),
            .init(uid: "D", expectedTaskGenerationEpoch: 1, phase: .prepared, recoveryAction: .retryReset),
            .init(uid: "E", expectedTaskGenerationEpoch: 1, phase: .prepared, recoveryAction: .retryReset)
        ])) {
            _ = try await registry.reserve(gestureId: "rsg1_11111111-1111-4111-8111-111111111111")
        }
        #expect(try Data(contentsOf: directory.appendingPathComponent(ResetOperationRegistry.fileName)) == before)
    }

    @Test func twoCurrentUIDRowsAreAnEpochConflictAndForeignMultiplicityIsNot() async throws {
        let directory = try temporaryDirectory()
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: SignedAuthStub(.signedIn(tupleA)), epochAuthority: EpochStub(epoch: 0))
        // reserve never creates a second same-UID row, so the conflict is seeded as bytes.
        try writeEnvelopeRows(directory, rows: [
            ("A", 3, "2026-09-06T09:00:00.000Z"), ("A", 1, "2026-09-06T09:00:01.000Z"),
            ("B", 1, "2026-09-06T09:00:02.000Z"), ("B", 2, "2026-09-06T09:00:03.000Z")
        ])
        await #expect(throws: ResetOperationRegistry.RegistryError.epochConflict(uid: "A", occupants: [
            .init(expectedTaskGenerationEpoch: 3, phase: .prepared, recoveryAction: .retryReset),
            .init(expectedTaskGenerationEpoch: 1, phase: .prepared, recoveryAction: .retryReset)
        ])) {
            _ = try await registry.reserve(gestureId: "rsg1_11111111-1111-4111-8111-111111111111")
        }
        let classification = await registry.classification()
        guard case let .blocked(.resetEpochConflict(digest, actionable, occupants)) = classification else {
            Issue.record("expected reset_epoch_conflict, got \(classification)"); return
        }
        #expect(actionable == 1 && occupants.map(\.expectedTaskGenerationEpoch) == [3, 1])
        #expect(digest.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil)
        // Foreign multiplicity (A's and B's pairs) never blocks a UID holding at most one row, nor signed-out state.
        let tupleC = SignedAuthTuple(uid: "C", authEpochUUID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc", credentialRevision: 1)
        let asC = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: SignedAuthStub(.signedIn(tupleC)), epochAuthority: EpochStub(epoch: 0))
        #expect(await asC.classification() == .ready)
        let signedOut = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: SignedAuthStub(.signedOut), epochAuthority: EpochStub(epoch: 0))
        #expect(await signedOut.classification() == .ready)
    }

    @Test func authSwitchRemovesAStaleReservedGestureAndKeepsRows() async throws {
        let directory = try temporaryDirectory()
        let auth = SignedAuthStub(.signedIn(tupleA))
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: auth, epochAuthority: EpochStub(epoch: 0))
        try await seedPreparedRow(registry, uid: "C", epoch: 2, createdAt: "2026-09-06T09:00:00.000Z")
        _ = try await registry.reserve(gestureId: "rsg1_11111111-1111-4111-8111-111111111111")
        auth.set(.signedIn(tupleB))
        guard case let .binding(reservation) = try await registry.reserve(gestureId: "rsg1_22222222-2222-4222-8222-222222222222") else { Issue.record("expected binding for B"); return }
        #expect(reservation.gestureId == "rsg1_22222222-2222-4222-8222-222222222222")
        let snapshot = await registry.snapshot()
        #expect(snapshot.gesture?.uid == "B" && snapshot.records.map(\.uid) == ["C"])
    }

    // MARK: - Coordinator reserve-first with today's retake path unchanged (S1 condition, 2026-09-06)

    @Test func retakeReservesFirstThenRunsTodaysSequenceAndLeavesNothingUnowned() async throws {
        let directory = try temporaryDirectory()
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: SignedAuthStub(.signedIn(tupleA)), epochAuthority: EpochStub(epoch: 0))
        let store = InMemoryRetakeOperationStore()
        let trace = RetakeTrace(registry: registry)
        let coordinator = RetakeAssessmentCoordinator(
            currentUser: { "A" }, taskPlan: trace.taskPlan, registry: registry,
            gestureId: { "rsg1_11111111-1111-4111-8111-111111111111" },
            deleteAssessments: trace.assessment, deleteUserKnowledge: trace.knowledge, resetDose: trace.dose,
            operationStore: store, postNotification: trace.notify
        )
        try await coordinator.retake()
        #expect(await trace.order == ["reset", "assessment", "knowledge", "dose", "finalize", "notify"])
        let rowsAtFirstReset = await trace.rowsAtFirstReset
        let gestureAtFirstReset = await trace.gestureAtFirstReset
        #expect(rowsAtFirstReset == 1 && gestureAtFirstReset == false)
        let operationIds = await trace.operationIds
        #expect(Set(operationIds).count == 1 && operationIds.count == 2)
        #expect(operationIds.first?.hasPrefix("rsa1_") == false)
        #expect(await store.load(userId: "A") == nil)
        let snapshot = await registry.snapshot()
        #expect(snapshot.records.isEmpty && snapshot.gesture == nil)
    }

    @Test func retakeFailureLeavesARowTheNextRetakeResumesWithTheSameOperationId() async throws {
        let directory = try temporaryDirectory()
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: SignedAuthStub(.signedIn(tupleA)), epochAuthority: EpochStub(epoch: 0))
        let store = InMemoryRetakeOperationStore()
        let trace = RetakeTrace(registry: registry)
        await trace.setFailStep("finalize")
        let coordinator = RetakeAssessmentCoordinator(
            currentUser: { "A" }, taskPlan: trace.taskPlan, registry: registry,
            gestureId: { "rsg1_11111111-1111-4111-8111-111111111111" },
            deleteAssessments: trace.assessment, deleteUserKnowledge: trace.knowledge, resetDose: trace.dose,
            operationStore: store, postNotification: trace.notify
        )
        await #expect(throws: RetakeTraceError.failed) { try await coordinator.retake() }
        let afterFailure = await registry.snapshot()
        #expect(afterFailure.records.count == 1 && afterFailure.gesture == nil)
        #expect(await store.load(userId: "A") != nil)
        #expect(await trace.notifications == 0)
        await trace.setFailStep(nil)
        try await coordinator.retake()
        let operationIds = await trace.operationIds
        #expect(Set(operationIds).count == 1 && operationIds.count == 4)
        #expect(await trace.notifications == 1)
        #expect(await registry.snapshot().records.isEmpty)
        #expect(await store.load(userId: "A") == nil)
    }

    @Test func legacyOperationIdIsNeverImportedAsAnAlias() async throws {
        let directory = try temporaryDirectory()
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: SignedAuthStub(.signedIn(tupleA)), epochAuthority: EpochStub(epoch: 0))
        let store = InMemoryRetakeOperationStore()
        await store.save("LEGACY-OP-1", userId: "A")
        let trace = RetakeTrace(registry: registry)
        let coordinator = RetakeAssessmentCoordinator(
            currentUser: { "A" }, taskPlan: trace.taskPlan, registry: registry,
            gestureId: { "rsg1_11111111-1111-4111-8111-111111111111" },
            deleteAssessments: trace.assessment, deleteUserKnowledge: trace.knowledge, resetDose: trace.dose,
            operationStore: store, postNotification: trace.notify
        )
        try await coordinator.retake()
        #expect(await trace.operationIds == ["LEGACY-OP-1", "LEGACY-OP-1"])
        let alias = await trace.aliasAtFirstReset
        #expect(alias?.hasPrefix("rsa1_") == true && alias != "LEGACY-OP-1")
    }

    // MARK: - Emulator (I1): the support type binds the default app to the emulator

    @Test(.enabled(if: FirebaseEmulator.isConfigured))
    func emulatorRoundTripsADocument() async throws {
        let db = try FirebaseEmulator.firestore()
        try await FirebaseEmulator.clearFirestore()
        let uid = try await FirebaseEmulator.signInFreshUser()
        let ref = db.collection("users").document(uid)
        try await ref.setData(["name": "S1"])
        let read = try await ref.getDocument()
        #expect(read.data()?["name"] as? String == "S1")
        try FirebaseEmulator.signOut()
    }

    // MARK: - S3 reset client (briefs/S3_BRIEF.md; C2.8 wires, Reconciled 9 marker, §5 drive)
    // Decoder mirrors read the same fixture the Node suite freezes through the real handler:
    // functions/tests/fixtures/resetWiresV1.json.

    @Test func resetReceiptsDecodeExactlyAgainstTheFrozenWires() throws {
        let wires = try frozenResetWires()
        let awaiting = try ResetReceiptV1.decode(wires.map("progressAwaiting"))
        #expect(awaiting.kind == .progress && awaiting.state == .awaitingLocalReset && awaiting.replayed == false)
        #expect(awaiting.operationId == wires.string("canonicalOperationId"))
        #expect(awaiting.taskGenerationEpoch == awaiting.expectedTaskGenerationEpoch + 1)
        #expect(awaiting.deletedCounts.sum == awaiting.deletedCount)
        let deleting = try ResetReceiptV1.decode(wires.map("progressDeleting"))
        #expect(deleting.state == .deleting)
        let final = try ResetReceiptV1.decode(wires.map("final"))
        #expect(final.kind == .final && final.state == .finalized && final.replayed == false)
        let replayed = try ResetReceiptV1.decode(wires.map("replayedFinal"))
        #expect(replayed.replayed == true && replayed.operationId == final.operationId)
        // Round trip through the row bytes.
        let bytes = try #require(awaiting.canonicalData())
        #expect(ResetReceiptV1.decode(data: bytes) == awaiting)
        // Rejections: surplus, missing, coherence, relation, sum, booleans.
        var surplus = wires.map("final"); surplus["extra"] = 1
        #expect(throws: ResetRemoteError.protocolAmbiguity) { _ = try ResetReceiptV1.decode(surplus) }
        var missing = wires.map("final"); missing.removeValue(forKey: "activeMoveEventId")
        #expect(throws: ResetRemoteError.protocolAmbiguity) { _ = try ResetReceiptV1.decode(missing) }
        var incoherent = wires.map("final"); incoherent["state"] = "deleting"
        #expect(throws: ResetRemoteError.protocolAmbiguity) { _ = try ResetReceiptV1.decode(incoherent) }
        var relation = wires.map("final"); relation["taskGenerationEpoch"] = 3
        #expect(throws: ResetRemoteError.protocolAmbiguity) { _ = try ResetReceiptV1.decode(relation) }
        var sum = wires.map("final"); sum["deletedCount"] = 5
        #expect(throws: ResetRemoteError.protocolAmbiguity) { _ = try ResetReceiptV1.decode(sum) }
        var notBool = wires.map("final"); notBool["replayed"] = 1
        #expect(throws: ResetRemoteError.protocolAmbiguity) { _ = try ResetReceiptV1.decode(notBool) }
        var badId = wires.map("final"); badId["operationId"] = "rsa1_11111111-1111-4111-8111-111111111111"
        #expect(throws: ResetRemoteError.protocolAmbiguity) { _ = try ResetReceiptV1.decode(badId) }
    }

    @Test func resetInspectionDecodesAbsentPendingCommittedAndRejectsMisplacedReceipts() throws {
        let wires = try frozenResetWires()
        let inspection = wires.map("inspection")
        let pending = try ResetInspectionV1.decode(try #require(inspection["pending"] as? [String: Any]))
        #expect(pending.outcome == .pending && pending.receipt == nil && pending.operationId == wires.string("canonicalOperationId"))
        #expect(pending.requestFingerprint == TaskPlanService.ResetTransport.requestFingerprint(expectedTaskGenerationEpoch: 1))
        #expect(pending.identityDigest == TaskPlanService.ResetTransport.identityDigest(uid: wires.string("uid"), expectedTaskGenerationEpoch: 1))
        let absent = try ResetInspectionV1.decode(try #require(inspection["absent"] as? [String: Any]))
        #expect(absent.outcome == .absent && absent.receipt == nil)
        let committed = try ResetInspectionV1.decode(try #require(inspection["committed"] as? [String: Any]))
        #expect(committed.outcome == .committed && committed.receipt?.replayed == true && committed.receipt?.kind == .final)
        var pendingWithReceipt = try #require(inspection["pending"] as? [String: Any]); pendingWithReceipt["receipt"] = wires.map("final")
        #expect(throws: ResetRemoteError.protocolAmbiguity) { _ = try ResetInspectionV1.decode(pendingWithReceipt) }
        var committedNoReceipt = try #require(inspection["committed"] as? [String: Any]); committedNoReceipt.removeValue(forKey: "receipt")
        #expect(throws: ResetRemoteError.protocolAmbiguity) { _ = try ResetInspectionV1.decode(committedNoReceipt) }
        var committedFresh = try #require(inspection["committed"] as? [String: Any]); committedFresh["receipt"] = wires.map("final") // replayed:false
        #expect(throws: ResetRemoteError.protocolAmbiguity) { _ = try ResetInspectionV1.decode(committedFresh) }
        var wrongFamily = try #require(inspection["pending"] as? [String: Any]); wrongFamily["family"] = "WORKFLOW"
        #expect(throws: ResetRemoteError.protocolAmbiguity) { _ = try ResetInspectionV1.decode(wrongFamily) }
    }

    @Test func legacyReconciliationDecodesTheFourOutcomesWithFrozenInnerReplayFlagsAndParityDerivations() throws {
        let wires = try frozenResetWires()
        let reconciliation = wires.map("reconciliation")
        let parity = wires.map("parity")
        let uid = try #require(parity["uid"] as? String)
        let legacyId = try #require(parity["legacyOperationId"] as? String)
        #expect(LegacyResetReconciliationV1.migrationId(uid: uid, legacyOperationId: legacyId) == "rlm1_0a4d53a438873090f69e4255426310b0feb4cfd6")
        #expect(LegacyResetReconciliationV1.requestFingerprint(uid: uid, legacyOperationId: legacyId) == "rlmreq1_0a4d53a438873090f69e4255426310b0feb4cfd63eabd6ce68c851ce827ad8e1")
        guard case let .notDispatched(base) = try LegacyResetReconciliationV1.decode(try #require(reconciliation["notDispatched"] as? [String: Any])) else { Issue.record("not_dispatched"); return }
        #expect(base.migrationId == "rlm1_0a4d53a438873090f69e4255426310b0feb4cfd6" && base.replayed == false)
        guard case let .upgraded(_, sourceState, progress) = try LegacyResetReconciliationV1.decode(try #require(reconciliation["upgraded"] as? [String: Any])) else { Issue.record("upgraded"); return }
        #expect(sourceState == "deleting" && progress.replayed == false && progress.state == .deleting)
        guard case let .phase2Active(_, active) = try LegacyResetReconciliationV1.decode(try #require(reconciliation["phase2Active"] as? [String: Any])) else { Issue.record("phase2_active"); return }
        #expect(active.replayed == true)
        guard case let .finalizedCompat(_, legacyFinal) = try LegacyResetReconciliationV1.decode(try #require(reconciliation["finalizedCompat"] as? [String: Any])) else { Issue.record("finalized_compat"); return }
        #expect(legacyFinal.deletedCount == 3 && legacyFinal.operationId == legacyId)
        // Opposite inner replay flags are protocol errors (§6.2:651).
        var upgradedReplayed = try #require(reconciliation["upgraded"] as? [String: Any])
        var innerUp = try #require(upgradedReplayed["progressReceipt"] as? [String: Any]); innerUp["replayed"] = true; upgradedReplayed["progressReceipt"] = innerUp
        #expect(throws: ResetRemoteError.protocolAmbiguity) { _ = try LegacyResetReconciliationV1.decode(upgradedReplayed) }
        var activeFresh = try #require(reconciliation["phase2Active"] as? [String: Any])
        var innerActive = try #require(activeFresh["progressReceipt"] as? [String: Any]); innerActive["replayed"] = false; activeFresh["progressReceipt"] = innerActive
        #expect(throws: ResetRemoteError.protocolAmbiguity) { _ = try LegacyResetReconciliationV1.decode(activeFresh) }
        var surplus = try #require(reconciliation["notDispatched"] as? [String: Any]); surplus["sourceState"] = "finalized"
        #expect(throws: ResetRemoteError.protocolAmbiguity) { _ = try LegacyResetReconciliationV1.decode(surplus) }
    }

    @Test func resetTransportSendsExactRequestsAndMapsTheErrorTable() async throws {
        let wires = try frozenResetWires()
        let recorder = DeletionCallableRecorder(result: .success(wires.map("progressAwaiting")))
        let transport = TaskPlanService.ResetTransport(callable: recorder.call)
        _ = try await transport.reset(.resetAllTasks, alias: "rsa1_11111111-1111-4111-8111-111111111111", expectedTaskGenerationEpoch: 1)
        let first = try #require(recorder.calls.first)
        #expect(first.name == "changeTaskPlan")
        #expect(first.payload.keys.sorted() == ["action", "expectedTaskGenerationEpoch", "operationId", "reason"])
        #expect(first.payload["action"] as? String == "resetAllTasks" && first.payload["reason"] as? String == "retake_assessment" && first.payload["expectedTaskGenerationEpoch"] as? Int == 1)

        let inspecting = DeletionCallableRecorder(result: .success(try #require(wires.map("inspection")["pending"] as? [String: Any])))
        let inspection = try await TaskPlanService.ResetTransport(callable: inspecting.call).inspectReset(uid: wires.string("uid"), canonicalOperationId: wires.string("canonicalOperationId"), expectedTaskGenerationEpoch: 1)
        #expect(inspection.outcome == .pending)
        let request = try #require(inspecting.calls.first?.payload)
        #expect(request["action"] as? String == "inspectCommittedOperation" && request["family"] as? String == "RESET")
        #expect((request["authority"] as? [String: String]) == ["operationId": wires.string("canonicalOperationId")])
        #expect((request["requestAuthority"] as? [String: String]) == ["requestFingerprint": wires.string("requestFingerprint")])
        #expect(request["identityDigest"] as? String == wires.string("identityDigest"))
        // A wire for another identity is ambiguity even when well-formed.
        let foreign = DeletionCallableRecorder(result: .success(try #require(wires.map("inspection")["absent"] as? [String: Any])))
        await #expect(throws: ResetRemoteError.protocolAmbiguity) {
            _ = try await TaskPlanService.ResetTransport(callable: foreign.call).inspectReset(uid: wires.string("uid"), canonicalOperationId: wires.string("canonicalOperationId"), expectedTaskGenerationEpoch: 1)
        }

        func error(_ details: [String: Any]?) -> NSError {
            NSError(domain: "com.firebase.functions", code: 9, userInfo: details.map { ["details": $0] } ?? [:])
        }
        let canonical = wires.string("canonicalOperationId")
        let cases: [(NSError, ResetRemoteError)] = [
            (error(["schemaVersion": 1, "reason": "AUTH_REQUIRED"]), .authRequired),
            (error(["schemaVersion": 1, "reason": "REQUEST_INVALID", "field": "migrationAlias"]), .requestInvalid(field: "migrationAlias")),
            (error(["schemaVersion": 1, "reason": "OPERATION_REUSED", "operationId": canonical]), .operationReused(operationId: canonical)),
            (error(["schemaVersion": 1, "reason": "LEGACY_RESET_CORRUPT", "context": "reconcile", "legacyOperationId": "L", "recordClass": "deleting", "markerClass": "absent"]), .legacyResetCorrupt(context: "reconcile", legacyOperationId: "L", recordClass: "deleting", markerClass: "absent")),
            (error(["schemaVersion": 1, "reason": "LEGACY_RESET_CORRUPT", "context": "inspect", "recordClass": "phase2", "markerClass": "malformed"]), .legacyResetCorrupt(context: "inspect", legacyOperationId: nil, recordClass: "phase2", markerClass: "malformed")),
            (error(["schemaVersion": 1, "reason": "LEGACY_RESET_MIGRATION_REQUIRED", "legacyOperationId": "L"]), .legacyResetMigrationRequired(legacyOperationId: "L")),
            (error(["schemaVersion": 1, "reason": "LEGACY_RESET_ALIAS_OCCUPIED", "legacyOperationId": "L", "migrationAlias": "rsa1_x"]), .legacyResetAliasOccupied(legacyOperationId: "L", migrationAlias: "rsa1_x")),
            (error(["schemaVersion": 1, "reason": "CLIENT_UPGRADE_REQUIRED", "requiredProtocol": "phase2"]), .clientUpgradeRequired(requiredProtocol: "phase2")),
            (error(["schemaVersion": 1, "reason": "STALE_STATE"]), .staleState),
            (error(["schemaVersion": 1, "reason": "RESET_ACTIVE", "operationId": canonical, "expectedTaskGenerationEpoch": 1]), .resetActive(operationId: canonical, expectedTaskGenerationEpoch: 1)),
            (error(["schemaVersion": 1, "reason": "RESET_ACTIVE", "operationId": canonical]), .protocolAmbiguity),
            (error(["schemaVersion": 1, "reason": "SOMETHING_ELSE"]), .protocolAmbiguity),
            (error(["reason": "STALE_STATE"]), .protocolAmbiguity),
            (NSError(domain: "com.firebase.functions", code: 14, userInfo: [:]), .transport), // detail-less unavailable
            (NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet), .transport)
        ]
        for (thrown, expected) in cases {
            let failing = DeletionCallableRecorder(result: .failure(thrown))
            await #expect(throws: expected) {
                _ = try await TaskPlanService.ResetTransport(callable: failing.call).reset(.finalizeTaskReset, alias: "rsa1_11111111-1111-4111-8111-111111111111", expectedTaskGenerationEpoch: 1)
            }
        }
    }

    @Test func cleanupAuthorityIsConstructedOnlyFromAPendingInspectionAndAnAwaitingReceipt() throws {
        let wires = try frozenResetWires()
        let inspection = wires.map("inspection")
        let pending = try ResetInspectionV1.decode(try #require(inspection["pending"] as? [String: Any]))
        let awaiting = try ResetReceiptV1.decode(wires.map("progressAwaiting"))
        let authority = try #require(ResetLocalCleanupAuthorityV1(inspection: pending, progress: awaiting))
        #expect(authority.accountUid == wires.string("uid") && authority.operationId == awaiting.operationId && authority.taskGenerationEpoch == 2 && authority.expectedTaskGenerationEpoch == 1)
        let deleting = try ResetReceiptV1.decode(wires.map("progressDeleting"))
        #expect(ResetLocalCleanupAuthorityV1(inspection: pending, progress: deleting) == nil)
        let committed = try ResetInspectionV1.decode(try #require(inspection["committed"] as? [String: Any]))
        #expect(ResetLocalCleanupAuthorityV1(inspection: committed, progress: awaiting) == nil)
        let absent = try ResetInspectionV1.decode(try #require(inspection["absent"] as? [String: Any]))
        #expect(ResetLocalCleanupAuthorityV1(inspection: absent, progress: awaiting) == nil)
        let final = try ResetReceiptV1.decode(wires.map("final"))
        #expect(ResetLocalCleanupAuthorityV1(inspection: pending, progress: final) == nil)
    }

    @Test func resetMarkerMatchesOnlyTheExactAwaitingProjection() throws {
        let wires = try frozenResetWires()
        let pendingWire = try #require(wires.map("inspection")["pending"] as? [String: Any])
        let pending = try ResetInspectionV1.decode(pendingWire)
        let progress = try ResetReceiptV1.decode(wires.map("progressAwaiting"))
        let authority = try #require(ResetLocalCleanupAuthorityV1(inspection: pending, progress: progress))
        let marker = markerFixture(wires)
        let root: [String: Any] = ["taskGenerationEpoch": 2, "taskReset": marker]
        #expect(ResetMarkerV1.matchesAwaiting(root, authority: authority))
        #expect(ResetMarkerV1.matchesAwaiting(nil, authority: authority) == false)
        #expect(ResetMarkerV1.matchesAwaiting(["taskGenerationEpoch": 2], authority: authority) == false)
        #expect(ResetMarkerV1.matchesAwaiting(["taskGenerationEpoch": 1, "taskReset": marker], authority: authority) == false)
        var deleting = marker; deleting["state"] = "deleting"; deleting["targetIndex"] = 2
        #expect(ResetMarkerV1.matchesAwaiting(["taskGenerationEpoch": 2, "taskReset": deleting], authority: authority) == false)
        var leased = marker; leased["lease"] = ["ownerToken": "11111111-1111-4111-8111-111111111111", "expiresAt": Timestamp(date: Date())]
        #expect(ResetMarkerV1.matchesAwaiting(["taskGenerationEpoch": 2, "taskReset": leased], authority: authority) == false)
        var cursor = marker; cursor["pageAfterPath"] = "users/x/tasks/a"
        #expect(ResetMarkerV1.matchesAwaiting(["taskGenerationEpoch": 2, "taskReset": cursor], authority: authority) == false)
        var otherOperation = marker; otherOperation["operationId"] = "rso1_" + String(repeating: "0", count: 40)
        #expect(ResetMarkerV1.matchesAwaiting(["taskGenerationEpoch": 2, "taskReset": otherOperation], authority: authority) == false)
        var misordered = marker; misordered["awaitingLocalResetAt"] = Timestamp(date: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(ResetMarkerV1.matchesAwaiting(["taskGenerationEpoch": 2, "taskReset": misordered], authority: authority) == false)
        var stringTimes = marker; stringTimes["createdAt"] = "2026-09-06T12:00:00.000Z"
        #expect(ResetMarkerV1.matchesAwaiting(["taskGenerationEpoch": 2, "taskReset": stringTimes], authority: authority) == false)
    }

    @Test func driveRecordsTheExactTraceAndRetiresTheRow() async throws {
        let wires = try frozenResetWires()
        let (registry, handle) = try await preparedRegistry()
        let remote = ScriptedResetRemote(wires: wires)
        let trace = DriveTrace()
        await remote.attach(trace, registry: registry, handle: handle)
        let outcome = try await registry.drive(handle: handle, remote: remote, cleanup: trace.callbacks())
        #expect(await trace.order == ["resetDispatch", "inspect", "deleteAssessments", "inspect", "deleteUserKnowledge", "inspect", "resetDose", "inspect", "finalize"])
        #expect(outcome.replayed == false && outcome.finalReceipt.kind == .final)
        #expect(await registry.snapshot().records.isEmpty)
        let authorities = await trace.authorities
        #expect(authorities.count == 3 && Set(authorities.map(\.operationId)).count == 1 && authorities[0].taskGenerationEpoch == 2)
        #expect(await remote.dispatchPhases == [ResetRowPhase.resetDispatched, .finalizeDispatched], "each remote dispatch is durable before its await")
    }

    @Test func driveShortCircuitsOnACommittedInspectionWithZeroNotification() async throws {
        let wires = try frozenResetWires()
        let (registry, handle) = try await preparedRegistry()
        let remote = ScriptedResetRemote(wires: wires)
        await remote.setCommittedAtInspection(2) // device B finalized at epoch r while A was paused before its second callback
        let trace = DriveTrace()
        await remote.attach(trace, registry: registry, handle: handle)
        let outcome = try await registry.drive(handle: handle, remote: remote, cleanup: trace.callbacks())
        #expect(await trace.order == ["resetDispatch", "inspect", "deleteAssessments", "inspect"])
        #expect(outcome.replayed == true && outcome.finalReceipt.replayed == true)
        #expect(await registry.snapshot().records.isEmpty)
        #expect(await remote.finalizeCalls == 0)
    }

    @Test func driveResumesAfterACallbackFailureAndAdoptsACommittedRecordOnResume() async throws {
        let wires = try frozenResetWires()
        let (registry, handle) = try await preparedRegistry()
        let remote = ScriptedResetRemote(wires: wires)
        let trace = DriveTrace()
        await remote.attach(trace, registry: registry, handle: handle)
        await trace.setFailing("deleteUserKnowledge")
        await #expect(throws: DriveTraceError.failed) { _ = try await registry.drive(handle: handle, remote: remote, cleanup: trace.callbacks()) }
        let row = try #require(await registry.snapshot().records.first)
        #expect(row.phase == .resetReceiptAwaitingLocalReset && row.recoveryAction == .runLocalCleanup && row.canonicalOperationId == wires.string("canonicalOperationId"))
        await trace.setFailing(nil)
        await trace.clear()
        let resumed = try await registry.drive(handle: handle, remote: remote, cleanup: trace.callbacks())
        #expect(await trace.order == ["inspect", "deleteAssessments", "inspect", "deleteUserKnowledge", "inspect", "resetDose", "inspect", "finalize"])
        #expect(resumed.replayed == false)
        // Resume after the other device finalized: the first inspection is committed, no callback runs.
        let (registry2, handle2) = try await preparedRegistry()
        let remote2 = ScriptedResetRemote(wires: wires)
        let trace2 = DriveTrace()
        await remote2.attach(trace2, registry: registry2, handle: handle2)
        await trace2.setFailing("deleteAssessments")
        await #expect(throws: DriveTraceError.failed) { _ = try await registry2.drive(handle: handle2, remote: remote2, cleanup: trace2.callbacks()) }
        await remote2.setCommittedAtInspection(2) // the failed first drive already consumed inspection 1
        await trace2.setFailing(nil)
        await trace2.clear()
        let adopted = try await registry2.drive(handle: handle2, remote: remote2, cleanup: trace2.callbacks())
        #expect(await trace2.order == ["inspect"] && adopted.replayed == true)
        #expect(await registry2.snapshot().records.isEmpty)
    }

    @Test func driveResumesServerDeletionWhileTheReceiptIsDeletingAndStopsOnAnAbsentRecord() async throws {
        let wires = try frozenResetWires()
        let (registry, handle) = try await preparedRegistry()
        let remote = ScriptedResetRemote(wires: wires)
        await remote.setDeletingFirst()
        let trace = DriveTrace()
        await remote.attach(trace, registry: registry, handle: handle)
        let outcome = try await registry.drive(handle: handle, remote: remote, cleanup: trace.callbacks())
        #expect(await trace.order.prefix(3) == ["resetDispatch", "resetDispatch", "inspect"])
        #expect(outcome.replayed == false)
        let (registry2, handle2) = try await preparedRegistry()
        let remote2 = ScriptedResetRemote(wires: wires)
        await remote2.setAbsentAtInspection(1)
        let trace2 = DriveTrace()
        await remote2.attach(trace2, registry: registry2, handle: handle2)
        await #expect(throws: ResetDriveError.inspectionAbsent(operationId: wires.string("canonicalOperationId"))) {
            _ = try await registry2.drive(handle: handle2, remote: remote2, cleanup: trace2.callbacks())
        }
        let row = try #require(await registry2.snapshot().records.first)
        #expect(row.phase == .resetReceiptAwaitingLocalReset)
    }

    @Test func recoverEpochAcceptsOnlyTheActionableEpochWithItsExactPhaseAndAction() async throws {
        let directory = try temporaryDirectory()
        // Rows in createdAt order (the envelope's sorted invariant): B, then A at epoch 3, then A at epoch 1.
        try writeEnvelopeRows(directory, rows: [(uid: "B", epoch: 0, createdAt: "2026-09-06T09:00:00.000Z"), (uid: "A", epoch: 3, createdAt: "2026-09-06T10:00:00.000Z"), (uid: "A", epoch: 1, createdAt: "2026-09-06T11:00:00.000Z")])
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: SignedAuthStub(.signedIn(tupleA)), epochAuthority: EpochStub(epoch: 0))
        guard case let .blocked(.resetEpochConflict(digest, actionable, _)) = await registry.classification() else { Issue.record("expected conflict"); return }
        #expect(actionable == 1)
        #expect(await registry.recoverEpoch(recoveryStateDigest: "stale", expectedTaskGenerationEpoch: 1, expectedPhase: .prepared, action: .retryReset) == .blocked(.resetEpochConflict(recoveryStateDigest: digest, actionableExpectedTaskGenerationEpoch: 1, occupants: [ResetEpochOccupant(expectedTaskGenerationEpoch: 3, phase: .prepared, recoveryAction: .retryReset), ResetEpochOccupant(expectedTaskGenerationEpoch: 1, phase: .prepared, recoveryAction: .retryReset)])))
        #expect(await registry.recoverEpoch(recoveryStateDigest: digest, expectedTaskGenerationEpoch: 3, expectedPhase: .prepared, action: .retryReset) == .unavailable(store: .reset))
        #expect(await registry.recoverEpoch(recoveryStateDigest: digest, expectedTaskGenerationEpoch: 1, expectedPhase: .finalReceipt, action: .retryReset) == .unavailable(store: .reset))
        #expect(await registry.recoverEpoch(recoveryStateDigest: digest, expectedTaskGenerationEpoch: 1, expectedPhase: .prepared, action: .applyFinal) == .unavailable(store: .reset))
        #expect(await registry.recoverEpoch(recoveryStateDigest: digest, expectedTaskGenerationEpoch: 1, expectedPhase: .prepared, action: .retryReset) == .ready)
        let remaining = await registry.snapshot().records
        #expect(remaining.map { "\($0.uid)|\($0.expectedTaskGenerationEpoch)" }.sorted() == ["A|1", "B|0"])
        #expect(await registry.classification() == .ready)
        #expect(await registry.recoverEpoch(recoveryStateDigest: digest, expectedTaskGenerationEpoch: 1, expectedPhase: .prepared, action: .retryReset) == .ready)
    }

    @Test func dailyDoseCleanupWritesTheEmptyFloorAtTheResultEpochAndStaleWritersDrift() async throws {
        let defaults = try isolatedDefaults()
        let store = DailyDoseLocalStore(defaults: defaults)
        _ = await store.ensure(uid: "A", taskGenerationEpoch: 1)
        guard case .committed = await store.mutate(uid: "A", expectedTaskGenerationEpoch: 1, expectedRevision: 0, { $0.completedCount = 4; $0.lastDate = "2026-09-05" }) else { Issue.record("seed"); return }
        let cleaned = await store.cleanup(uid: "A", taskGenerationEpoch: 2)
        let floor = DailyDoseLocalStateV1(taskGenerationEpoch: 2, revision: 0, completedCount: 0, lastDate: nil, firstLaunchDate: nil)
        #expect(cleaned == .cleaned(floor))
        #expect(await store.load(uid: "A") == .present(floor))
        guard case .drift = await store.mutate(uid: "A", expectedTaskGenerationEpoch: 1, expectedRevision: 1, { $0.completedCount = 9 }) else { Issue.record("stale writer must drift"); return }
        #expect(await store.load(uid: "A") == .present(floor))
        let malformed = Data(#"{"schemaVersion":1,"taskGenerationEpoch":-1}"#.utf8)
        defaults.set(malformed, forKey: "peezy.M.dailyDose.v2")
        #expect(await store.cleanup(uid: "M", taskGenerationEpoch: 2) == .malformed)
        #expect(defaults.data(forKey: "peezy.M.dailyDose.v2") == malformed)
    }

    @Test func dailyDoseLegacyBridgeWritesV2BeforeRemovingLegacyKeysAndIsCrashSafe() async throws {
        let defaults = try isolatedDefaults()
        let store = DailyDoseLocalStore(defaults: defaults)
        #expect(await store.bridgeLegacy(uid: "A") == .none)
        defaults.set(3, forKey: "peezy.A.dailyDose.completedCount")
        defaults.set("2026-09-05", forKey: "peezy.A.dailyDose.lastDate")
        defaults.set("not a date", forKey: "peezy.A.dailyDose.firstLaunchDate")
        let bridged = DailyDoseLocalStateV1(taskGenerationEpoch: 0, revision: 0, completedCount: 3, lastDate: "2026-09-05", firstLaunchDate: nil)
        #expect(await store.bridgeLegacy(uid: "A") == .bridged(bridged))
        #expect(await store.load(uid: "A") == .present(bridged))
        #expect(DailyDoseLocalStore.legacyKeys(uid: "A").allSatisfy { defaults.object(forKey: $0) == nil })
        // Crash between the v2 write and the key removal: v2 present with leftover keys; the next call removes them.
        defaults.set(7, forKey: "peezy.A.dailyDose.completedCount")
        #expect(await store.bridgeLegacy(uid: "A") == .present)
        #expect(defaults.object(forKey: "peezy.A.dailyDose.completedCount") == nil)
        #expect(await store.load(uid: "A") == .present(bridged))
        // Malformed v2 preserves everything.
        defaults.set(Data(#"{"schemaVersion":1}"#.utf8), forKey: "peezy.B.dailyDose.v2")
        defaults.set(2, forKey: "peezy.B.dailyDose.completedCount")
        #expect(await store.bridgeLegacy(uid: "B") == .malformed)
        #expect(defaults.integer(forKey: "peezy.B.dailyDose.completedCount") == 2)
    }

    @Test(.enabled(if: FirebaseEmulator.isConfigured))
    func assessmentKnowledgeAndDoseCleanupsRequireTheExactAwaitingMarker() async throws {
        let wires = try frozenResetWires()
        let firestore = try FirebaseEmulator.firestore()
        try await FirebaseEmulator.clearFirestore()
        let uid = try await FirebaseEmulator.signInFreshUser()
        defer { try? FirebaseEmulator.signOut() }
        // Rebase the frozen wires onto this UID: identity digests and canonical IDs are UID-bound.
        let e = 1
        let canonical = "rso1_" + String(TaskCanonicalV1.sha256Hex(["account_uid": uid, "task_generation_epoch": e + 1]).prefix(40))
        let moveEvent = "me1_" + String(TaskCanonicalV1.sha256Hex(["uid": uid, "new_task_generation_epoch": e + 1, "reset_operation_id": canonical]).prefix(40))
        var progress = wires.map("progressAwaiting"); progress["accountUid"] = uid; progress["operationId"] = canonical; progress["activeMoveEventId"] = moveEvent
        var pending = try #require(wires.map("inspection")["pending"] as? [String: Any]); pending["accountUid"] = uid; pending["authority"] = ["operationId": canonical]
        pending["identityDigest"] = TaskPlanService.ResetTransport.identityDigest(uid: uid, expectedTaskGenerationEpoch: e)
        let pendingDecoded = try ResetInspectionV1.decode(pending)
        let progressDecoded = try ResetReceiptV1.decode(progress)
        let authority = try #require(ResetLocalCleanupAuthorityV1(inspection: pendingDecoded, progress: progressDecoded))
        var marker = markerFixture(wires); marker["operationId"] = canonical; marker["activeMoveEventId"] = moveEvent
        let now = Date()
        for key in ["createdAt", "updatedAt", "awaitingLocalResetAt"] { marker[key] = now }
        // JSON numbers arrive as NSNumber, which the REST seeder would encode as booleans; seed Swift Ints.
        try await FirebaseEmulator.adminSet("users/\(uid)", ["name": "R", "taskGenerationEpoch": 2, "taskReset": restIntegers(marker), "dailyDose": ["schema_version": 1, "task_generation_epoch": 2, "date": "2026-09-06", "taskIds": ["t"]]])
        try await FirebaseEmulator.adminSet("users/\(uid)/user_assessments/a1", ["task_generation_epoch": 2, "name": "one"])
        try await FirebaseEmulator.adminSet("users/\(uid)/user_assessments/a2", ["task_generation_epoch": 2, "name": "two"])
        try await FirebaseEmulator.adminSet("userKnowledge/\(uid)", ["task_generation_epoch": 2, "entries": [:]])

        // A wrong authority (another operation) writes nothing.
        var foreign = progress; foreign["operationId"] = "rso1_" + String(repeating: "0", count: 40)
        var foreignPending = pending; foreignPending["authority"] = ["operationId": "rso1_" + String(repeating: "0", count: 40)]
        let foreignPendingDecoded = try ResetInspectionV1.decode(foreignPending)
        let foreignDecoded = try ResetReceiptV1.decode(foreign)
        let wrong = try #require(ResetLocalCleanupAuthorityV1(inspection: foreignPendingDecoded, progress: foreignDecoded))
        await #expect(throws: ResetCleanupError.markerMismatch) { try await ResetLocalCleanupV1.deleteAssessments(authority: wrong) }
        await #expect(throws: ResetCleanupError.markerMismatch) { try await ResetLocalCleanupV1.deleteUserKnowledge(authority: wrong) }
        await #expect(throws: ResetCleanupError.markerMismatch) { try await DailyDoseEngine().resetForRetake(authority: wrong, localStore: DailyDoseLocalStore(defaults: try isolatedDefaults()), defaults: try isolatedDefaults()) }
        #expect(try await firestore.collection("users").document(uid).collection("user_assessments").getDocuments().documents.count == 2)
        #expect(try await firestore.collection("userKnowledge").document(uid).getDocument().exists)

        // The exact authority deletes each document in its own marker-checked transaction.
        try await ResetLocalCleanupV1.deleteAssessments(authority: authority)
        try await ResetLocalCleanupV1.deleteUserKnowledge(authority: authority)
        let defaults = try isolatedDefaults()
        defaults.set(5, forKey: "peezy.\(uid).dailyDose.completedCount")
        let localStore = DailyDoseLocalStore(defaults: defaults)
        _ = await localStore.ensure(uid: uid, taskGenerationEpoch: 1)
        try await DailyDoseEngine().resetForRetake(authority: authority, localStore: localStore, defaults: defaults)
        #expect(try await firestore.collection("users").document(uid).collection("user_assessments").getDocuments().documents.isEmpty)
        #expect(try await firestore.collection("userKnowledge").document(uid).getDocument().exists == false)
        let root = try await firestore.collection("users").document(uid).getDocument().data()
        #expect(root?["dailyDose"] == nil && root?["taskReset"] != nil)
        #expect(await localStore.load(uid: uid) == .present(DailyDoseLocalStateV1(taskGenerationEpoch: 2, revision: 0, completedCount: 0, lastDate: nil, firstLaunchDate: nil)))
        #expect(defaults.object(forKey: "peezy.\(uid).dailyDose.completedCount") == nil)
    }

}

/// Synchronous UID snapshot double for `CurrentFirebaseUIDProviding`.
final class UIDProbe: CurrentFirebaseUIDProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    init(_ value: String?) { self.value = value }
    var uid: String? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
    func currentFirebaseUID() -> String? { uid }
}

/// A throwaway UserDefaults suite for local-store tests.
func isolatedDefaults() throws -> UserDefaults {
    let name = "s1-tests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else { throw CocoaError(.fileNoSuchFile) }
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// Records callable invocations and returns one fixed result.
final class DeletionCallableRecorder: @unchecked Sendable {
    struct Call { let name: String; let payload: [String: Any] }
    private let lock = NSLock()
    private var recorded: [Call] = []
    let result: Result<[String: Any], Error>
    init(result: Result<[String: Any], Error>) { self.result = result }
    var calls: [Call] { lock.withLock { recorded } }
    func call(_ name: String, _ payload: [String: Any]) async throws -> [String: Any] {
        lock.withLock { recorded.append(Call(name: name, payload: payload)) }
        return try result.get()
    }
}

// MARK: - Reset registry test doubles

let tupleA = SignedAuthTuple(uid: "A", authEpochUUID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", credentialRevision: 1)
let tupleB = SignedAuthTuple(uid: "B", authEpochUUID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", credentialRevision: 1)

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("s1-reset-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Seeds one prepared row through the registry's own reserve/bind path.
func seedPreparedRow(_ registry: ResetOperationRegistry, uid: String, epoch: Int, createdAt: String) async throws {
    let directory = await registry.directory
    let tuple = SignedAuthTuple(uid: uid, authEpochUUID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc", credentialRevision: 1)
    let seeded = ResetOperationRegistry(directory: directory, clock: ResetClockStub(createdAt), auth: SignedAuthStub(.signedIn(tuple)), epochAuthority: EpochStub(epoch: epoch))
    guard case let .binding(reservation) = try await seeded.reserve(gestureId: "rsg1_" + UUID().uuidString.lowercased()) else { throw RetakeTraceError.failed }
    _ = try await seeded.bind(reservation: reservation)
}

final class ResetClockStub: LocalDurableClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: String
    init(_ instant: String = "2026-09-06T12:00:00.000Z") { self.instant = instant }
    func set(_ value: String) { lock.withLock { instant = value } }
    func now() -> String { lock.withLock { instant } }
}

final class SignedAuthStub: AuthAuthorityProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var value: SignedAuthAuthority
    init(_ value: SignedAuthAuthority) { self.value = value }
    func set(_ newValue: SignedAuthAuthority) { lock.withLock { value = newValue } }
    func currentSignedAuth() async -> SignedAuthAuthority { lock.withLock { value } }
    func forceRefresh(expected: SignedAuthTuple) async -> AuthRefreshOutcome { .notCommitted }
    func confirmAccountDeleted(expected: AuthIdentity) async -> AccountDeletionAuthObservation { .notProven }
}

final class EpochStub: ResetEpochAuthorityProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var epoch: Int
    private var recorded: [String] = []
    private var failureValue: Error?
    init(epoch: Int) { self.epoch = epoch }
    var failure: Error? {
        get { lock.withLock { failureValue } }
        set { lock.withLock { failureValue = newValue } }
    }
    var calls: [String] { lock.withLock { recorded } }
    func current(uid: String, expectedAuth: SignedAuthTuple) async throws -> ResetEpochAuthority {
        lock.withLock { recorded.append("\(uid)|\(expectedAuth.uid)|\(expectedAuth.authEpochUUID)|\(expectedAuth.credentialRevision)") }
        if let failureValue = lock.withLock({ failureValue }) { throw failureValue }
        return ResetEpochAuthority(uid: uid, taskGenerationEpoch: lock.withLock { epoch })
    }
}

actor InMemoryRetakeOperationStore: RetakeOperationStore {
    private var values: [String: String] = [:]
    func load(userId: String) async -> String? { values[userId] }
    func save(_ operationId: String, userId: String) async { values[userId] = operationId }
    func clear(userId: String) async { values[userId] = nil }
}

enum RetakeTraceError: Error { case failed }

/// Records today's callback order and, at the first reset dispatch, what the
/// registry already holds (the reserve-first proof).
actor RetakeTrace {
    private let registry: ResetOperationRegistry
    var order: [String] = []
    var operationIds: [String] = []
    var notifications = 0
    var rowsAtFirstReset = -1
    var gestureAtFirstReset = true
    var aliasAtFirstReset: String?
    private var failStep: String?

    init(registry: ResetOperationRegistry) { self.registry = registry }
    func setFailStep(_ step: String?) { failStep = step }

    func taskPlan(_ action: RetakeAssessmentCoordinator.TaskPlanAction, _ operationId: String) async throws {
        operationIds.append(operationId)
        let name = action == .reset ? "reset" : "finalize"
        order.append(name)
        if action == .reset, rowsAtFirstReset < 0 {
            let snapshot = await registry.snapshot()
            rowsAtFirstReset = snapshot.records.count
            gestureAtFirstReset = snapshot.gesture != nil
            aliasAtFirstReset = snapshot.records.first?.suggestedOperationId
        }
        if failStep == name { throw RetakeTraceError.failed }
    }
    func assessment(_ uid: String) async throws { order.append("assessment"); if failStep == "assessment" { throw RetakeTraceError.failed } }
    func knowledge(_ uid: String) async throws { order.append("knowledge"); if failStep == "knowledge" { throw RetakeTraceError.failed } }
    func dose(_ uid: String) async throws { order.append("dose"); if failStep == "dose" { throw RetakeTraceError.failed } }
    func notify() async { order.append("notify"); notifications += 1 }
}

/// Writes a valid envelope holding prepared rows directly (conflict fixtures).
func writeEnvelopeRows(_ directory: URL, rows: [(uid: String, epoch: Int, createdAt: String)]) throws {
    let records: [[String: Any]] = rows.map { row in
        ["uid": row.uid, "suggestedOperationId": "rsa1_" + UUID().uuidString.lowercased(), "expectedTaskGenerationEpoch": row.epoch,
         "phase": "prepared", "createdAt": row.createdAt, "updatedAt": row.createdAt]
    }
    let bytes = try #require(DurableEnvelopeCodec.encode(
        fileKind: .taskPlanResetV2, generationId: UUID().uuidString.lowercased(),
        payload: ["records": records, "legacyMigrations": []]
    ))
    try bytes.write(to: directory.appendingPathComponent(ResetOperationRegistry.fileName))
}


// MARK: - S3 helpers: frozen wires, scripted remote, drive trace

struct FrozenResetWires {
    let root: [String: Any]
    func map(_ key: String) -> [String: Any] { root[key] as? [String: Any] ?? [:] }
    func string(_ key: String) -> String { root[key] as? String ?? "" }
}

/// functions/tests/fixtures/resetWiresV1.json, frozen by the Node suite through the real handler.
func frozenResetWires() throws -> FrozenResetWires {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<2 { url.deleteLastPathComponent() }
    url.appendPathComponent("functions/tests/fixtures/resetWiresV1.json")
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DriveTraceError.failed }
    return FrozenResetWires(root: object)
}

/// The fixture marker with its ISO instants turned back into Firestore Timestamps.
func markerFixture(_ wires: FrozenResetWires) -> [String: Any] {
    var marker = wires.map("marker")
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    for key in ["createdAt", "updatedAt", "awaitingLocalResetAt"] {
        if let iso = marker[key] as? String, let date = formatter.date(from: iso) { marker[key] = Timestamp(date: date) }
    }
    return marker
}

/// A registry holding one prepared row for uid A at epoch 1 (the fixture's expected epoch).
func preparedRegistry() async throws -> (ResetOperationRegistry, ResetOperationHandle) {
    let directory = try temporaryDirectory()
    let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: SignedAuthStub(.signedIn(tupleA)), epochAuthority: EpochStub(epoch: 1))
    guard case let .binding(reservation) = try await registry.reserve(gestureId: "rsg1_11111111-1111-4111-8111-111111111111") else { throw DriveTraceError.failed }
    let handle = try await registry.bind(reservation: reservation)
    return (registry, handle)
}

enum DriveTraceError: Error { case failed }

/// Scripts the server from the frozen wires for uid A: resetAllTasks → progress
/// (awaiting, or deleting first), inspections → pending unless scripted committed/absent
/// at an ordinal, finalize → final. Records the row phase the registry held at each dispatch.
actor ScriptedResetRemote: ResetRemoteProviding {
    private let wires: FrozenResetWires
    private var deletingFirst = false
    private var committedAt: Int?
    private var absentAt: Int?
    private var inspections = 0
    private(set) var finalizeCalls = 0
    private(set) var dispatchPhases: [ResetRowPhase] = []
    var registry: ResetOperationRegistry?
    var handle: ResetOperationHandle?
    var recorder: DriveTrace?

    init(wires: FrozenResetWires) { self.wires = wires }
    func setDeletingFirst() { deletingFirst = true }
    func setCommittedAtInspection(_ ordinal: Int) { committedAt = ordinal }
    func setAbsentAtInspection(_ ordinal: Int) { absentAt = ordinal }
    func attach(_ recorder: DriveTrace, registry: ResetOperationRegistry, handle: ResetOperationHandle) { self.recorder = recorder; self.registry = registry; self.handle = handle }

    private func rebased(_ map: [String: Any], replayed: Bool? = nil) -> [String: Any] {
        var out = map
        out["accountUid"] = "A"
        if let replayed { out["replayed"] = replayed }
        return out
    }

    func reset(_ action: ResetRemoteAction, alias: String, expectedTaskGenerationEpoch: Int) async throws -> ResetReceiptV1 {
        if let registry, let handle, let row = await registry.snapshot().records.first(where: { $0.handleId == handle.handleId }) { dispatchPhases.append(row.phase) }
        switch action {
        case .resetAllTasks:
            await recorder?.record("resetDispatch")
            if deletingFirst { deletingFirst = false; return try ResetReceiptV1.decode(rebased(wires.map("progressDeleting"))) }
            return try ResetReceiptV1.decode(rebased(wires.map("progressAwaiting")))
        case .finalizeTaskReset:
            await recorder?.record("finalize")
            finalizeCalls += 1
            return try ResetReceiptV1.decode(rebased(wires.map("final")))
        }
    }

    func inspectReset(uid: String, canonicalOperationId: String, expectedTaskGenerationEpoch: Int) async throws -> ResetInspectionV1 {
        inspections += 1
        await recorder?.record("inspect")
        let inspection = wires.map("inspection")
        var pending = inspection["pending"] as? [String: Any] ?? [:]
        pending["accountUid"] = uid
        pending["identityDigest"] = TaskPlanService.ResetTransport.identityDigest(uid: uid, expectedTaskGenerationEpoch: expectedTaskGenerationEpoch)
        if inspections == absentAt { pending["outcome"] = "absent" }
        if inspections == committedAt {
            pending["outcome"] = "committed"
            pending["receipt"] = rebased(wires.map("final"), replayed: true)
        }
        return try ResetInspectionV1.decode(pending)
    }

    func reconcileLegacyReset(legacyOperationId: String, migrationAlias: String) async throws -> LegacyResetReconciliationV1 {
        throw DriveTraceError.failed
    }
}

/// Records the drive's call order and the authorities the callbacks received.
actor DriveTrace {
    private(set) var order: [String] = []
    private(set) var authorities: [ResetLocalCleanupAuthorityV1] = []
    private var failing: String?

    init() {}

    func record(_ step: String) { order.append(step) }
    func setFailing(_ step: String?) { failing = step }
    func clear() { order = []; authorities = [] }

    private func run(_ step: String, _ authority: ResetLocalCleanupAuthorityV1) throws {
        order.append(step)
        authorities.append(authority)
        if failing == step { throw DriveTraceError.failed }
    }

    func callbacks() -> ResetCleanupCallbacks {
        ResetCleanupCallbacks(
            deleteAssessments: { [self] authority in try await self.run("deleteAssessments", authority) },
            deleteUserKnowledge: { [self] authority in try await self.run("deleteUserKnowledge", authority) },
            resetDose: { [self] authority in try await self.run("resetDose", authority) }
        )
    }
}

/// Recursively turns non-boolean NSNumbers into Swift Ints so the REST seeder writes integerValue.
func restIntegers(_ map: [String: Any]) -> [String: Any] {
    map.mapValues { value in
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.intValue }
        if let nested = value as? [String: Any] { return restIntegers(nested) }
        return value
    }
}
