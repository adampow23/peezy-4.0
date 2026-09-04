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
        // RetakeAssessmentCoordinator.swift joins this list in I6, when its pinned
        // closure slice is replaced whole per §6.6 (the two acquisitions live inside it).
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
