import FirebaseAuth
import FirebaseFirestore
import Foundation
import Security
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
        installSharedRuntimeIfNeeded() // S4-CD2: the registry holds an owner before any acquisition
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

    // MARK: - S4 I1 — recovery types (C9.7.12, C9.7.14), the dose member (S4-CD1), file kinds and the byte rule (C9.7.1)

    @Test func fileKindsCarryTheC971CapsAndTheByteRuleReservesTheReceipt() throws {
        #expect(DurableFileKind.taskRouteInboxV1.storeCap == 131_072)
        #expect(DurableFileKind.handoffAuthorityV1.storeCap == 524_288)
        #expect(DurableFileKind.taskPlanResetV2.storeCap == 131_072)
        #expect(DurableFileKind.workflowRequestsV2.storeCap == 16_777_216)
        #expect(DurableFileKind.expandedHandoffStoreCap == 128 * 524_288 + 2 * 524_288)
        #expect(DurableEnvelopeCodec.recoveryReceiptReserve == 190)
        let receipt: [String: Any] = ["schemaVersion": 1, "quarantineSHA256": String(repeating: "a", count: 64), "recoveredCount": 9_007_199_254_740_991, "droppedCount": 9_007_199_254_740_991]
        // 190 is exactly the byte length of `,"recoveryReceipt":{...}` with the largest members.
        let memberObject = TaskCanonicalV1.data(["recoveryReceipt": receipt])!.count
        #expect(memberObject - 2 + 1 == 190, "the reserve equals the largest receipt member text")
        // base + 190 == cap admits; base + 191 refuses; the receipt then fits inside the same cap.
        let generation = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let base = DurableEnvelopeCodec.encode(fileKind: .taskRouteInboxV1, generationId: generation, payload: ["records": [], "pad": ""], storeCap: 1_000_000)!.count
        let room = 131_072 - 190 - base
        let exact = DurableEnvelopeCodec.encode(fileKind: .taskRouteInboxV1, generationId: generation, payload: ["records": [], "pad": String(repeating: "x", count: room)])
        #expect(exact != nil && exact!.count + 190 == 131_072, "base + 190 == cap is admitted")
        let over = DurableEnvelopeCodec.encode(fileKind: .taskRouteInboxV1, generationId: generation, payload: ["records": [], "pad": String(repeating: "x", count: room + 1)])
        #expect(over == nil, "base + 191 is refused")
        let receipted = try #require(DurableEnvelopeCodec.encode(fileKind: .taskRouteInboxV1, generationId: generation, payload: ["records": [], "pad": String(repeating: "x", count: room)], recoveryReceipt: receipt))
        #expect(receipted.count <= 131_072)
        let decoded = try #require(DurableEnvelopeCodec.decode(receipted, fileKind: .taskRouteInboxV1))
        #expect(TaskCanonicalV1.data(decoded.recoveryReceipt!) == TaskCanonicalV1.data(receipt), "the receipt survives byte-identically")
        #expect(DurableEnvelopeCodec.decode(receipted, fileKind: .workflowRequestsV2) == nil, "fileKind must match")
        for kind in DurableFileKind.allCases {
            let bytes = try #require(DurableEnvelopeCodec.encode(fileKind: kind, generationId: generation, payload: ["records": []]))
            #expect(DurableEnvelopeCodec.decode(bytes, fileKind: kind)?.generationId == generation, Comment(rawValue: kind.rawValue))
        }
    }

    @Test func doseMalformedSnapshotCarriesTheDoseStoreItsSingleActionAndItsDigest() {
        let snapshot = BlockedSnapshot.doseMalformed(recoveryStateDigest: "d", bytesSHA256: String(repeating: "b", count: 64), byteLength: 12)
        #expect(snapshot.store == .dose)
        #expect(snapshot.state == "malformed")
        #expect(snapshot.availableActions == ["quarantine_dose_bytes"])
        #expect(snapshot.recoveryStateDigest == "d")
        #expect(RecoveryStore(.reset) == .reset && RecoveryStore.reset.durable == .reset && RecoveryStore.dose.durable == nil)
        #expect(RecoveryStore.allCases.map(\.rawValue) == ["route", "handoff", "reset", "workflow", "dose"])
        #expect(RecoveryResult.busy(store: .dose) != .busy(store: .reset))
        #expect(BlockedSnapshot.storageIOUnavailable(store: .route, errorCode: .fileOpenFailed).store == .route)
    }

    @Test func recoveryObservedStateDigestIsTheCanonicalSHA256AndTheDoseAlternativeCarriesItsMembers() {
        let target = FileObservationV1.valid(byteLength: 10, bytesSHA256: String(repeating: "1", count: 64), generationId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", envelopeSHA256: String(repeating: "2", count: 64))
        let files = RecoveryObservedStateV1.files(store: .route, baseState: "quarantined", target: target, quarantine: .absent, availableActions: ["recover", "discard_quarantine"])
        #expect(Set(files.canonical.keys) == ["schemaVersion", "store", "baseState", "target", "quarantine", "availableActions"])
        #expect(files.recoveryStateDigest == TaskCanonicalV1.sha256Hex(files.canonical))
        #expect(files.store == .route && files.availableActions == ["recover", "discard_quarantine"])
        let handoff = RecoveryObservedStateV1.files(store: .handoff, baseState: "foreign_installation", target: .overCap(byteLength: 9, fileIdentityDigest: "f"), quarantine: .malformed(byteLength: 3, bytesSHA256: "m"), availableActions: ["reconcile"], keychainInstallationId: "install", firebase: .signedIn(uid: "A"))
        #expect((handoff.canonical["keychain"] as? [String: String]) == ["state": "valid", "installationId": "install"])
        #expect((handoff.canonical["firebase"] as? [String: String]) == ["state": "signed_in", "uid": "A"])
        let dose = RecoveryObservedStateV1.dose(bytesSHA256: String(repeating: "b", count: 64), byteLength: 12, quarantineCount: 1)
        #expect(TaskCanonicalV1.data(dose.canonical) == TaskCanonicalV1.data(["schemaVersion": 1, "store": "dose", "baseState": "malformed", "bytesSHA256": String(repeating: "b", count: 64), "byteLength": 12, "quarantineCount": 1, "availableActions": ["quarantine_dose_bytes"]]))
        #expect(dose.store == .dose)
        let again = RecoveryObservedStateV1.dose(bytesSHA256: String(repeating: "b", count: 64), byteLength: 12, quarantineCount: 2)
        #expect(dose.recoveryStateDigest != again.recoveryStateDigest, "a second quarantined blob changes the observed state")
        #expect(FileObservationV1.absent.canonical.count == 1)
        #expect(FileObservationV1.fileIdentityDigest(device: 1, inode: 2, size: 3, mtimeSeconds: 4, mtimeNanoseconds: 5, ctimeSeconds: 6, ctimeNanoseconds: 7) == TaskCanonicalV1.sha256Hex(["deviceDecimal": "1", "inodeDecimal": "2", "sizeDecimal": "3", "mtimeSecondsDecimal": "4", "mtimeNanosecondsDecimal": "5", "ctimeSecondsDecimal": "6", "ctimeNanosecondsDecimal": "7"]))
    }

    @Test func recoveryAttemptKeysMapOneToOneOntoTheActions() {
        let digest = RecoveryExpectation.digest("d")
        let token = UnavailableToken(store: .route, state: "storage_io_unavailable", errorCode: "FILE_OPEN_FAILED")
        #expect(RecoveryAction.recover.attemptKey(expecting: digest) == .recover(recoveryStateDigest: "d"))
        #expect(RecoveryAction.merge.attemptKey(expecting: digest) == .merge(recoveryStateDigest: "d"))
        #expect(RecoveryAction.discardQuarantine.attemptKey(expecting: digest) == .discard(recoveryStateDigest: "d"))
        #expect(RecoveryAction.retryCleanup.attemptKey(expecting: digest) == .cleanup(recoveryStateDigest: "d"))
        #expect(RecoveryAction.reconcile(mismatchIdentityDigest: "m").attemptKey(expecting: digest) == .receiptReconcile(recoveryStateDigest: "d", mismatchIdentityDigest: "m"))
        #expect(RecoveryAction.foreignReconcile.attemptKey(expecting: digest) == .foreignReconcile(recoveryStateDigest: "d"))
        #expect(RecoveryAction.resolve(resolutionDigest: "r", choices: ["b", "a"]).attemptKey(expecting: digest) == .resolveForeign(recoveryStateDigest: "d", resolutionDigest: "r", choicesSHA256: TaskCanonicalV1.sha256Hex(data: Data("[b,a]".utf8))))
        #expect(RecoveryAction.quarantineDoseBytes.attemptKey(expecting: digest) == .doseQuarantine(recoveryStateDigest: "d"))
        #expect(RecoveryAction.retry(errorCode: "FILE_OPEN_FAILED").attemptKey(expecting: .unavailable(token)) == .unavailable(store: .route, state: "storage_io_unavailable", errorCode: "FILE_OPEN_FAILED", action: "retry"))
        #expect(RecoveryAction.repairInstallationIdentity.attemptKey(expecting: .unavailable(token)) == .unavailable(store: .route, state: "storage_io_unavailable", errorCode: "FILE_OPEN_FAILED", action: "repair"))
        #expect(RecoveryAction.retry(errorCode: "FILE_READ_FAILED").attemptKey(expecting: .unavailable(token)) == nil, "a retry carries the exact unavailable error code")
        #expect(RecoveryAction.recover.attemptKey(expecting: .unavailable(token)) == nil, "a digest-bearing action needs the displayed digest")
        #expect(RecoveryAction.retry(errorCode: "FILE_OPEN_FAILED").attemptKey(expecting: digest) == nil, "Retry carries no state digest")
        let kinds = [RecoveryAttemptKey.recover(recoveryStateDigest: "d"), .merge(recoveryStateDigest: "d"), .discard(recoveryStateDigest: "d"), .cleanup(recoveryStateDigest: "d"), .receiptReconcile(recoveryStateDigest: "d", mismatchIdentityDigest: "m"), .foreignReconcile(recoveryStateDigest: "d"), .resolveForeign(recoveryStateDigest: "d", resolutionDigest: "r", choicesSHA256: "c"), .recoverEpoch(recoveryStateDigest: "d", expectedTaskGenerationEpoch: 1, expectedPhase: .prepared, action: .retryReset), .unavailable(store: .handoff, state: "installation_authority_invalid", errorCode: "KEYCHAIN_VALUE_INVALID", action: "repair"), .doseQuarantine(recoveryStateDigest: "d")].map(\.kind)
        #expect(kinds == ["recover", "merge", "discard", "cleanup", "receipt_reconcile", "foreign_reconcile", "resolve_foreign", "recover_epoch", "unavailable", "dose_quarantine"])
        #expect(TaskCanonicalV1.data(RecoveryAttemptKey.recoverEpoch(recoveryStateDigest: "d", expectedTaskGenerationEpoch: 1, expectedPhase: .prepared, action: .retryReset).canonical) == TaskCanonicalV1.data(["kind": "recover_epoch", "recoveryStateDigest": "d", "expectedTaskGenerationEpoch": 1, "expectedPhase": "prepared", "action": "retry_reset"]))
        #expect([RecoveryAction.recover, .discardQuarantine, .retryCleanup, .merge, .reconcile(mismatchIdentityDigest: "m"), .resolve(resolutionDigest: "r", choices: []), .retry(errorCode: "x"), .repairInstallationIdentity, .quarantineDoseBytes].map(\.name) == ["recover", "discard_quarantine", "retry_cleanup", "merge", "reconcile", "resolve", "retry", "repair_installation_identity", "quarantine_dose_bytes"])
    }

    @Test func durableStoreRecoveringProtocolIsExactAndOwnerShaped() async {
        actor Stub: DurableStoreRecovering {
            var performed: [RecoveryAttemptKey] = []
            func observe() async -> RecoveryObservation { .unavailable(UnavailableToken(store: .route, state: "storage_io_unavailable", errorCode: "FILE_OPEN_FAILED")) }
            nonisolated func classify(_ observation: RecoveryObservation) -> RecoveryClassification {
                switch observation {
                case let .unavailable(token): return .blocked(.storageIOUnavailable(store: token.store.durable!, errorCode: StorageIOErrorCode(rawValue: token.errorCode)!))
                case let .observed(state): return state.availableActions.isEmpty ? .ready : .blocked(.quarantined(store: state.store.durable!, recoveryStateDigest: state.recoveryStateDigest, quarantineEnumerable: true, pendingRecordCount: nil))
                }
            }
            func perform(_ action: RecoveryAction, expecting expectation: RecoveryExpectation) async -> RecoveryResult {
                guard let key = action.attemptKey(expecting: expectation) else { return .unavailable(store: .route) }
                performed.append(key)
                return .busy(store: .route)
            }
        }
        let stub = Stub()
        let observation = await stub.observe()
        #expect(stub.classify(observation) == .blocked(.storageIOUnavailable(store: .route, errorCode: .fileOpenFailed)))
        let ready = RecoveryObservedStateV1.files(store: .route, baseState: "ready", target: .absent, quarantine: .absent, availableActions: [])
        #expect(stub.classify(.observed(ready)) == .ready)
        #expect(await stub.perform(.retry(errorCode: "FILE_OPEN_FAILED"), expecting: .unavailable(UnavailableToken(store: .route, state: "storage_io_unavailable", errorCode: "FILE_OPEN_FAILED"))) == .busy(store: .route))
        #expect(await stub.perform(.recover, expecting: .unavailable(UnavailableToken(store: .route, state: "storage_io_unavailable", errorCode: "FILE_OPEN_FAILED"))) == .unavailable(store: .route))
        #expect(await stub.performed == [.unavailable(store: .route, state: "storage_io_unavailable", errorCode: "FILE_OPEN_FAILED", action: "retry")])
        let recovering: any DurableStoreRecovering = stub
        _ = recovering
    }

    @Test func narrationLeaseAndTransferHandleAreExactValues() {
        let lease = NarrationLease(leaseId: "11111111-1111-4111-8111-111111111111", uid: "A", gateGeneration: GateGeneration(rawValue: 3), sessionId: "s1")
        #expect(lease == NarrationLease(leaseId: "11111111-1111-4111-8111-111111111111", uid: "A", gateGeneration: GateGeneration(rawValue: 3), sessionId: "s1"))
        #expect(lease != NarrationLease(leaseId: "11111111-1111-4111-8111-111111111111", uid: "A", gateGeneration: GateGeneration(rawValue: 4), sessionId: "s1"), "a lease is bound to one gate generation")
        let handle = TransferHandle(handleId: "h1", lease: lease)
        #expect(Set([handle, TransferHandle(handleId: "h1", lease: lease)]).count == 1)
    }

    // MARK: - S4 I2a — Firestore runtime owner and installation (S4-CD2), telemetry authority (C2.2), room-capture owner (S4-CD7)

    @Test(.enabled(if: FirebaseEmulator.isConfigured))
    func firestoreRuntimeInstallsOnceAndRefusesBeforeInstallation() async throws {
        _ = try FirebaseEmulator.firestore()
        let registry = FirestoreRuntime.Registry()
        #expect(registry.isInstalled == false)
        await #expect(throws: FirestoreRuntimeError.notInstalled) { _ = try await registry.provider.acquire() }
        #expect(registry.provider.isCurrent(FirestoreRuntimeGeneration(rawValue: 1)) == false)
        let owner = FirestoreRuntimeOwner(controller: RecordingInstanceController())
        #expect(registry.install(owner) == .installed)
        #expect(registry.isInstalled)
        #expect(registry.install(FirestoreRuntimeOwner(controller: RecordingInstanceController())) == .alreadyInstalled, "a second install changes nothing")
        let lease = try await registry.provider.acquire()
        #expect(lease.generation == FirestoreRuntimeGeneration(rawValue: 1) && registry.provider.isCurrent(lease.generation))
        #expect(registry.provider.published().generation == lease.generation)
        installSharedRuntimeIfNeeded()
        #expect(FirestoreRuntime.shared.isInstalled && FirestoreRuntime.install(owner) == .alreadyInstalled, "the process registry is installed exactly once")
    }

    @Test(.enabled(if: FirebaseEmulator.isConfigured))
    func firestoreRuntimeOwnerPurgesInTheExactOrderAndPublishesAFreshGeneration() async throws {
        _ = try FirebaseEmulator.firestore()
        let controller = RecordingInstanceController()
        let owner = FirestoreRuntimeOwner(controller: controller)
        let stale = try await owner.acquire()
        #expect(await owner.purgeForAccountDeletion(scope: .uid("A")) == .acknowledged)
        #expect(controller.order == ["terminateAndClearPersistence", "fresh", "probe"], "terminate without waitForPendingWrites → clearPersistence → fresh instance → probe")
        #expect(owner.isCurrent(stale.generation) == false, "the stale lease's results are discarded")
        let fresh = try await owner.acquire()
        #expect(fresh.generation.rawValue == stale.generation.rawValue + 1 && owner.isCurrent(fresh.generation))
        // a failed probe: no new generation, the old one dead, acquisition refused until a later purge acks
        let failing = RecordingInstanceController()
        failing.failProbe = true
        let broken = FirestoreRuntimeOwner(controller: failing)
        let before = try await broken.acquire()
        #expect(await broken.purgeForAccountDeletion(scope: .all) == .failed)
        #expect(broken.isCurrent(before.generation) == false)
        await #expect(throws: FirestoreRuntimeError.purging) { _ = try await broken.acquire() }
        failing.failProbe = false
        // a later purge (Retry, the next auth transition) may run and ack; only then does acquisition resume on the fresh generation
        #expect(await broken.purgeForAccountDeletion(scope: .all) == .acknowledged)
        let recovered = try await broken.acquire()
        #expect(recovered.generation.rawValue == before.generation.rawValue + 1 && broken.isCurrent(recovered.generation))
    }

    @Test func telemetryBarrierRunsTheFiveCallsThenOneCheckAndSettlesStickyOutcomes() async {
        // callback false → cleared, sticky with no further SDK call
        let cleared = RecordingTelemetrySDK()
        let authority = ClientTelemetryPrivacyAuthority(sdk: cleared, lifetime: TelemetryPrivacyLifetime())
        async let first = authority.purgeAll()
        while !cleared.hasPendingCallback { await Task.yield() }
        cleared.complete(false)
        cleared.complete(false) // a duplicate callback loses the CAS
        #expect(await first == .cleared)
        #expect(cleared.calls == ["setAnalyticsCollectionEnabled(false)", "setUserID(nil)", "setUserProperty(nil,has_subscription)", "resetAnalyticsData", "checkForUnsentReports"])
        #expect(await authority.purgeAll() == .cleared)
        #expect(cleared.calls.count == 5, "after cleared every same-process call returns cleared with no SDK check")
        // callback true → deleteUnsentReports once → relaunchRequired, sticky
        let unsent = RecordingTelemetrySDK()
        let relaunch = ClientTelemetryPrivacyAuthority(sdk: unsent, lifetime: TelemetryPrivacyLifetime())
        async let second = relaunch.purgeAll()
        while !unsent.hasPendingCallback { await Task.yield() }
        unsent.complete(true)
        #expect(await second == .relaunchRequired)
        #expect(unsent.calls.last == "deleteUnsentReports")
        #expect(await relaunch.purgeAll() == .relaunchRequired)
        #expect(unsent.calls.filter { $0 == "deleteUnsentReports" }.count == 1 && unsent.calls.filter { $0 == "checkForUnsentReports" }.count == 1)
        // cancellation before the callback → failed, not sticky: a later call checks again
        let silent = RecordingTelemetrySDK()
        let lifetime = TelemetryPrivacyLifetime()
        let cancelled = ClientTelemetryPrivacyAuthority(sdk: silent, lifetime: lifetime)
        let task = Task { await cancelled.purgeAll() }
        while !silent.hasPendingCallback { await Task.yield() }
        task.cancel()
        #expect(await task.value == .failed)
        #expect(ClientTelemetryPrivacyAuthority.timeoutSeconds == 10)
        async let again = ClientTelemetryPrivacyAuthority(sdk: silent, lifetime: lifetime).purgeAll()
        while silent.calls.filter({ $0 == "checkForUnsentReports" }).count < 2 { await Task.yield() }
        silent.complete(false)
        #expect(await again == .cleared)
    }

    @Test func roomCaptureOwnerIssuesLeasesOnlyUnderAClearGateAndRevokesBeforeItsAck() async throws {
        let gate = GateSnapshotStub()
        let owner = RoomCaptureArtifactOwner(gateSnapshot: gate.snapshot)
        let lease = try #require(await owner.acquire(uid: "A", sessionId: "s1"))
        #expect(lease.uid == "A" && lease.gateGeneration == GateGeneration(rawValue: 1))
        #expect(await owner.revalidate(lease))
        gate.set(gate: .active(uid: "A"))
        #expect(await owner.acquire(uid: "A", sessionId: "s2") == nil, "no lease under a nonclear gate")
        #expect(await owner.revalidate(lease) == false)
        gate.set(gate: .clear)
        #expect(await owner.revalidate(lease))
        gate.set(generation: 2)
        #expect(await owner.revalidate(lease) == false, "a lease is bound to one gate generation")
        #expect(await owner.deposit("hello", for: lease) == false)
        #expect(await owner.materialize(for: lease) == nil)
        // a fresh lease under the current generation carries a transcript once
        let live = try #require(await owner.acquire(uid: "A", sessionId: "s3"))
        #expect(await owner.deposit("hello", for: live))
        #expect(await owner.materialize(for: live) == "hello")
        #expect(await owner.materialize(for: live) == nil, "materialize clears")
        // artifacts and an in-flight transfer; revokeAll cancels and awaits settlement before returning
        let directory = try temporaryDirectory()
        let artifact = directory.appendingPathComponent("peezy_room_test.mp4")
        try Data("frame".utf8).write(to: artifact)
        #expect(await owner.registerArtifact(artifact, lease: live))
        let cancelled = NotificationCounter()
        let handle = await owner.register(transfer: live, cancel: { Task { await cancelled.bump() } })
        let settled = NotificationCounter()
        let revocation = Task { await owner.revokeAll(); await settled.bump() }
        while await cancelled.count == 0 { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        #expect(await settled.count == 0, "revokeAll waits for the registered transfer to settle")
        await owner.settle(handle)
        await revocation.value
        #expect(await settled.count == 1)
        #expect(await owner.revalidate(live) == false)
        #expect(await owner.acquire(uid: "A", sessionId: "s4") == nil, "no lease after revocation until reopen")
        #expect(await owner.purgeForAccountDeletion(scope: .uid("A")) == .acknowledged)
        #expect(FileManager.default.fileExists(atPath: artifact.path) == false, "registered artifacts are removed")
        await owner.reopen()
        #expect(await owner.acquire(uid: "A", sessionId: "s5") != nil)
    }

    // MARK: - S4 I2b — completion presentation (C2.5), preference barrier (C2.2/C6.6), purge journal (C3), local privacy purge

    @Test func completionFileDerivesReplaysBlocksAndPresentsTheExactC25Maps() async throws {
        let directory = try temporaryDirectory()
        let consumed = NotificationCounter()
        let opened = OpenedURLs()
        let presentation = AccountDeletionCompletionPresentation(directory: directory, clock: ResetClockStub(), consume: { _ in await consumed.bump(); return true }, opener: { url in await opened.record(url); return true })
        #expect(await presentation.observe() == .absent)
        #expect(await presentation.current() == nil)
        let result = CompletionResultV1.completed(appleRevocation: .manualRequired, googleRevocation: .notRequired)
        guard case let .written(snapshot) = await presentation.derive(result) else { Issue.record("derive"); return }
        let url = directory.appendingPathComponent(AccountDeletionCompletionPresentation.fileName)
        let bytes = try Data(contentsOf: url)
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(object["fileKind"] as? String == "ACCOUNT_DELETION_COMPLETION_V1")
        let payload = try #require(object["payload"] as? [String: Any])
        #expect(Set(payload.keys) == ["schemaVersion", "result", "createdAt"])
        #expect(TaskCanonicalV1.data(try #require(payload["result"] as? [String: Any])) == TaskCanonicalV1.data(["schemaVersion": 1, "kind": "ACCOUNT_DELETION_COMPLETED", "appleRevocation": "manual_required", "googleRevocation": "not_required"]))
        #expect(bytes.count <= 4_096 && snapshot.createdAt == "2026-09-06T12:00:00.000Z" && snapshot.result == result)
        #expect(await presentation.current() == snapshot)
        // exact replay preserves bytes; a different pending snapshot blocks
        #expect(await presentation.derive(result) == .replayed(snapshot))
        #expect(try Data(contentsOf: url) == bytes)
        #expect(await presentation.derive(.localCleared) == .blocked)
        // open: offered only for the matching manual-required provider and its frozen URL; never consumes
        #expect(await presentation.open(expectedGenerationId: snapshot.generationId, expectedSHA256: snapshot.sha256, provider: .apple) == .opened)
        #expect(await opened.urls == [AccountDeletionCompletionCopy.appleURL])
        #expect(await presentation.open(expectedGenerationId: snapshot.generationId, expectedSHA256: snapshot.sha256, provider: .google) == .notOffered)
        #expect(await presentation.open(expectedGenerationId: snapshot.generationId, expectedSHA256: "0", provider: .apple) == .stale)
        #expect(await presentation.current() == snapshot, "open never consumes")
        // acknowledge: the sole consuming action; drift is stale; exact runs the consumption then unlinks
        #expect(await presentation.acknowledge(expectedGenerationId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", expectedSHA256: snapshot.sha256) == .stale)
        #expect(await consumed.count == 0)
        #expect(await presentation.acknowledge(expectedGenerationId: snapshot.generationId, expectedSHA256: snapshot.sha256) == .acknowledged)
        #expect(await consumed.count == 1)
        #expect(await presentation.observe() == .absent)
        #expect(await presentation.acknowledge(expectedGenerationId: snapshot.generationId, expectedSHA256: snapshot.sha256) == .stale)
        // a malformed file is observed, never read as absence
        try Data("{".utf8).write(to: url)
        #expect(await presentation.observe() == .malformed)
        #expect(await presentation.derive(.localCleared) == .blocked)
        // the local-cleared and remote-unconfirmed maps and the exact copy
        #expect(TaskCanonicalV1.data(CompletionResultV1.localCleared.presentation) == TaskCanonicalV1.data(["schemaVersion": 1, "kind": "ACCOUNT_DELETION_LOCAL_CLEARED"]))
        #expect(TaskCanonicalV1.data(CompletionResultV1.remoteUnconfirmed.presentation) == TaskCanonicalV1.data(["schemaVersion": 1, "kind": "ACCOUNT_DELETION_REMOTE_UNCONFIRMED"]))
        #expect(CompletionResultV1.decode(["schemaVersion": 1, "kind": "ACCOUNT_DELETION_COMPLETED", "appleRevocation": "manual_required"]) == nil)
        #expect(AccountDeletionCompletionCopy.title == "Account deleted" && AccountDeletionCompletionCopy.body == "Your Peezy account was deleted." && AccountDeletionCompletionCopy.button == "Done")
        #expect(AccountDeletionCompletionCopy.appleURL.absoluteString == "https://support.apple.com/102571")
        #expect(AccountDeletionCompletionCopy.googleURL.absoluteString == "https://support.google.com/accounts/answer/13533235?hl=en")
        #expect(AccountDeletionCompletionCopy.localCleared == "This account was deleted from another device. This device has been cleared.")
        #expect(AccountDeletionCompletionCopy.remoteUnconfirmedTitle == "Deletion not verified")
        #expect(AccountDeletionCompletionCopy.remoteUnconfirmed == "Local data for this account was removed, but remote account deletion could not be verified. Sign in again to retry if the account still exists.")
        #expect(AccountDeletionCompletionCopy.telemetryRelaunch == "Close and reopen Peezy to finish clearing local diagnostics.")
    }

    @Test func preferenceBarrierRemovesTheElevenKeysAndTheConditionalGlobalFirstName() throws {
        #expect(PreferenceBarrier.uidScopedTemplates.count == 11)
        let defaults = try isolatedDefaults()
        for uid in ["A", "B"] { for key in PreferenceBarrier.keys(for: uid) { defaults.set("v", forKey: key) } }
        defaults.set("Adam", forKey: PreferenceBarrier.globalFirstNameKey)
        defaults.set("keep", forKey: "peezy.unscoped.setting")
        // UID scope with a different current UID: A's keys go, B's and the global first name stay
        #expect(PreferenceBarrier.run(scope: .uid("A"), defaults: defaults, currentFirebaseUID: "B") == .acknowledged)
        #expect(PreferenceBarrier.keys(for: "A").allSatisfy { defaults.object(forKey: $0) == nil })
        #expect(PreferenceBarrier.keys(for: "B").allSatisfy { defaults.object(forKey: $0) != nil })
        #expect(defaults.string(forKey: PreferenceBarrier.globalFirstNameKey) == "Adam", "a different current UID keeps the global first name")
        // UID scope while Firebase still names that UID (or no different UID is established): the global first name goes too
        for key in PreferenceBarrier.keys(for: "A") { defaults.set("v", forKey: key) }
        #expect(PreferenceBarrier.run(scope: .uid("A"), defaults: defaults, currentFirebaseUID: nil) == .acknowledged)
        #expect(defaults.object(forKey: PreferenceBarrier.globalFirstNameKey) == nil)
        // all scope: every UID's keys and the global first name; unscoped settings untouched
        defaults.set("Adam", forKey: PreferenceBarrier.globalFirstNameKey)
        defaults.set("v", forKey: "peezy.C.dailyDose.v2.quarantine")
        #expect(PreferenceBarrier.uidScopedKeys(in: defaults).contains("peezy.C.dailyDose.v2.quarantine"))
        #expect(PreferenceBarrier.run(scope: .all, defaults: defaults, currentFirebaseUID: "B") == .acknowledged)
        #expect(PreferenceBarrier.uidScopedKeys(in: defaults).isEmpty && defaults.object(forKey: PreferenceBarrier.globalFirstNameKey) == nil)
        #expect(defaults.string(forKey: "peezy.unscoped.setting") == "keep")
    }

    @Test func purgeJournalEnvelopeIsExactAndValidated() throws {
        let context = PurgeProviderContextV1(deletionOperationId: "adel1_11111111-1111-4111-8111-111111111111", deletionProofSHA256: String(repeating: "a", count: 64), googleRevocation: .sdkDisconnectRequired, googleProviderUid: "g1")
        let journal = LocalPrivacyPurgeJournalV1(scope: .uid("A"), providerContext: context, terminalDeletionLink: nil, acks: [.route, .handoff], createdAt: "2026-09-06T12:00:00.000Z", updatedAt: "2026-09-06T12:00:01.000Z")
        #expect(journal.isValid)
        #expect(LocalPrivacyPurgeJournalV1.decode(journal.canonical) == journal)
        #expect(TaskCanonicalV1.data(journal.canonical)!.count <= 4_096)
        let bytes = try #require(DurableEnvelopeCodec.encode(fileKind: .localPrivacyPurgeV1, generationId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", payload: journal.canonical))
        #expect(DurableEnvelopeCodec.decode(bytes, fileKind: .localPrivacyPurgeV1) != nil)
        #expect(LocalPrivacyPurgeJournalV1(scope: .uid("A"), providerContext: nil, terminalDeletionLink: nil, acks: [], createdAt: journal.createdAt, updatedAt: journal.updatedAt).isValid == false, "providerContext required for UID scope")
        #expect(LocalPrivacyPurgeJournalV1(scope: .all, providerContext: context, terminalDeletionLink: nil, acks: [], createdAt: journal.createdAt, updatedAt: journal.updatedAt).isValid == false, "no providerContext for all scope")
        let link = TerminalDeletionLinkV1(deletionOperationId: context.deletionOperationId, deletionProofSHA256: context.deletionProofSHA256)
        #expect(LocalPrivacyPurgeJournalV1(scope: .uid("A"), providerContext: context, terminalDeletionLink: link, acks: [], createdAt: journal.createdAt, updatedAt: journal.updatedAt).isValid == false, "terminalDeletionLink only for the all-scope handoff")
        #expect(LocalPrivacyPurgeJournalV1(scope: .all, providerContext: nil, terminalDeletionLink: link, acks: PurgeOwner.order, createdAt: journal.createdAt, updatedAt: journal.updatedAt).isValid)
        #expect(LocalPrivacyPurgeJournalV1(scope: .all, providerContext: nil, terminalDeletionLink: nil, acks: [.handoff], createdAt: journal.createdAt, updatedAt: journal.updatedAt).isValid == false, "acks are a displayed-order prefix")
        #expect(PurgeOwner.order.map(\.rawValue) == ["route", "handoff", "reset", "workflow", "room_capture", "firestore_cache", "notifications", "google"])
        var surplus = journal.canonical; surplus["extra"] = 1
        #expect(LocalPrivacyPurgeJournalV1.decode(surplus) == nil)
        #expect(PurgeProviderContextV1.decode(["deletionOperationId": context.deletionOperationId, "deletionProofSHA256": context.deletionProofSHA256, "googleRevocation": "sdk_disconnect_required"]) == nil, "sdk_disconnect_required needs the provider UID")
    }

    @Test func localPrivacyPurgeRunsTheEightOwnersInOrderJournalsEachAckAndResumesAfterAFailure() async throws {
        let directory = try temporaryDirectory()
        let owners = RecordingPurgeOwners()
        let defaults = try isolatedDefaults()
        let telemetry = TelemetryStub()
        let coordinator = LocalPrivacyPurgeCoordinator(directory: directory, clock: ResetClockStub(), owners: owners.owners, defaults: defaults, currentUID: UIDProbe(nil), telemetry: telemetry)
        // all scope: the eight owners in the C2.2 order, google via signOutAll, both barriers, journal unlinked
        defaults.set("Adam", forKey: PreferenceBarrier.globalFirstNameKey)
        #expect(await coordinator.purge(scope: .all) == .cleared)
        #expect(owners.calls == ["route(all)", "handoff(all)", "reset(all)", "workflow(all)", "room_capture(all)", "firestore_cache(all)", "notifications(all)", "google.signOutAll"])
        #expect(telemetry.calls == 1 && defaults.object(forKey: PreferenceBarrier.globalFirstNameKey) == nil)
        #expect(await coordinator.observeJournal() == .absent, "a non-terminal all-scope purge unlinks its own journal")
        // UID scope needs the intent's provider context; a failure at notifications blocks with the journal retained at six acks
        let context = PurgeProviderContextV1(deletionOperationId: "adel1_11111111-1111-4111-8111-111111111111", deletionProofSHA256: String(repeating: "a", count: 64), googleRevocation: .sdkDisconnectRequired, googleProviderUid: "g1")
        #expect(await coordinator.purge(scope: .uid("A")) == .blocked(.localPrivacyPurgeFailed), "a UID purge without its provider context is refused")
        owners.fail("notifications")
        let request = LocalPrivacyPurgeCoordinator.Request(scope: .uid("A"), providerContext: context, terminalDeletionLink: nil)
        #expect(await coordinator.purge(request) == .blocked(.localPrivacyPurgeFailed))
        guard case let .present(journal) = await coordinator.observeJournal() else { Issue.record("journal"); return }
        #expect(journal.scope == .uid("A") && journal.acks == [.route, .handoff, .reset, .workflow, .roomCapture, .firestoreCache] && journal.providerContext == context)
        // resume: the six acknowledged owners are not run again; google disconnects the exact provider UID; the journal is retained for the caller
        let before = owners.calls.count
        owners.fail("notifications", false)
        #expect(await coordinator.purge(request) == .cleared)
        #expect(Array(owners.calls.dropFirst(before)) == ["notifications(A)", "google.disconnect(g1)"])
        guard case let .present(complete) = await coordinator.observeJournal() else { Issue.record("journal retained"); return }
        #expect(complete.acks == PurgeOwner.order)
        #expect(await coordinator.unlinkJournal())
        // manual-required google acks with no SDK mutation; a telemetry relaunch blocks with the journal retained
        let manual = PurgeProviderContextV1(deletionOperationId: context.deletionOperationId, deletionProofSHA256: context.deletionProofSHA256, googleRevocation: .manualRequired, googleProviderUid: nil)
        telemetry.set(.relaunchRequired)
        let count = owners.calls.count
        #expect(await coordinator.purge(LocalPrivacyPurgeCoordinator.Request(scope: .uid("B"), providerContext: manual, terminalDeletionLink: nil)) == .blocked(.localPrivacyPurgeFailed))
        #expect(owners.calls.dropFirst(count).contains(where: { $0.hasPrefix("google.") }) == false, "manual-required acks without an SDK call")
        guard case let .present(retained) = await coordinator.observeJournal() else { Issue.record("journal retained after telemetry"); return }
        #expect(retained.acks == PurgeOwner.order && retained.scope == .uid("B"))
        #expect(await coordinator.purge(LocalPrivacyPurgeCoordinator.Request(scope: .uid("B"), providerContext: manual, terminalDeletionLink: link(context))) == .blocked(.localPrivacyPurgeFailed), "a UID request never carries the terminal link")
    }

    @Test func localPrivacyPurgeGivesAnIntentLinkedUIDPurgeAbsolutePriority() async throws {
        let directory = try temporaryDirectory()
        let owners = RecordingPurgeOwners()
        let coordinator = LocalPrivacyPurgeCoordinator(directory: directory, clock: ResetClockStub(), owners: owners.owners, defaults: try isolatedDefaults(), currentUID: UIDProbe(nil), telemetry: TelemetryStub())
        owners.setHoldRoute()
        let first = Task { await coordinator.purge(scope: .all) }
        while !owners.isHoldingRoute { await Task.yield() }
        let context = PurgeProviderContextV1(deletionOperationId: "adel1_11111111-1111-4111-8111-111111111111", deletionProofSHA256: String(repeating: "a", count: 64), googleRevocation: .notRequired, googleProviderUid: nil)
        let secondAll = Task { await coordinator.purge(scope: .all) }
        for _ in 0..<20 { await Task.yield() }
        let intentLinked = Task { await coordinator.purge(LocalPrivacyPurgeCoordinator.Request(scope: .uid("A"), providerContext: context, terminalDeletionLink: nil)) }
        for _ in 0..<20 { await Task.yield() }
        owners.releaseRoute()
        #expect(await first.value == .cleared)
        #expect(await intentLinked.value == .cleared)
        #expect(await secondAll.value == .cleared)
        let order = owners.calls.filter { $0.hasPrefix("route(") }
        #expect(order == ["route(all)", "route(A)", "route(all)"], "the intent-linked UID purge runs before the earlier-queued all-scope request")
        _ = await coordinator.unlinkJournal()
    }

    // MARK: - S4 I3 — account-deletion intent (C2.1), phase machine (C2.2), transport handling (C2.3), gate (C2.4), presentations (C2.5), capability-invalid exit (C2.6)

    @Test func intentPhaseMemberCrossProductRejectsEveryMissingSurplusUnknownAndCrossBranchMember() throws {
        let variants: [(AccountDeletionPhase, AccountDeletionStagedRoot?, AccountDeletionDetachReason?)] = [
            (.prepared, nil, nil), (.dataConfirmed, nil, nil), (.purging, nil, nil), (.localDetaching, .dataDeleted, nil), (.localDetaching, .authGuarding, nil),
            (.localDetaching, nil, .authDeleted), (.localDetaching, nil, .remoteUnverified), (.localDetaching, nil, .capabilityInvalid),
            (.authFinalizeDispatched, nil, nil), (.guarding, nil, nil), (.completed, nil, nil), (.localCleared, nil, nil)
        ]
        let optionalMembers = ["purpose", "authorityKind", "detachReason", "stagedRoot", "startedAt", "dataDeletedAt", "authGuardAfter"]
        let required = ["schemaVersion", "uid", "authEpochUUID", "credentialRevision", "operationId", "proofNonce", "appleRevocation", "googleRevocation", "phase", "acks", "createdAt", "updatedAt"]
        let fill: [String: Any] = ["purpose": "confirmed_begin", "authorityKind": "member", "detachReason": "auth_deleted", "stagedRoot": "DATA_DELETED", "startedAt": DeletionWires.startedAt, "dataDeletedAt": DeletionWires.dataDeletedAt, "authGuardAfter": DeletionWires.authGuardAfter]
        for (phase, staged, detach) in variants {
            let intent = exactIntent(phase: phase, staged: staged, detach: detach)
            let map = intent.canonical
            #expect(intent.isValid, Comment(rawValue: "\(phase) \(String(describing: staged)) \(String(describing: detach)) exact"))
            #expect(AccountDeletionIntentV1.decode(map) == intent, Comment(rawValue: "\(phase) round-trip"))
            for key in required { var missing = map; missing[key] = nil; #expect(AccountDeletionIntentV1.decode(missing) == nil, Comment(rawValue: "\(phase) missing \(key)")) }
            for key in optionalMembers {
                var mutated = map
                if map[key] == nil { mutated[key] = fill[key] } else { mutated[key] = nil }
                #expect(AccountDeletionIntentV1.decode(mutated) == nil, Comment(rawValue: "\(phase) toggling \(key)"))
            }
            var surplus = map; surplus["extra"] = 1
            #expect(AccountDeletionIntentV1.decode(surplus) == nil)
            var unknownPhase = map; unknownPhase["phase"] = "deleting"
            #expect(AccountDeletionIntentV1.decode(unknownPhase) == nil)
            var badAcks = map; badAcks["acks"] = ["handoff"]
            #expect(AccountDeletionIntentV1.decode(badAcks) == nil, "acks must be a displayed-order prefix")
            var wrongType = map; wrongType["credentialRevision"] = "3"
            #expect(AccountDeletionIntentV1.decode(wrongType) == nil)
        }
        // cross-branch: both stagedRoot and detachReason, or neither, in local_detaching; authGuardAfter iff AUTH_GUARDING
        var both = exactIntent(phase: .localDetaching, staged: .dataDeleted).canonical; both["detachReason"] = "auth_deleted"
        #expect(AccountDeletionIntentV1.decode(both) == nil)
        var neither = exactIntent(phase: .localDetaching, staged: .dataDeleted).canonical; neither["stagedRoot"] = nil
        #expect(AccountDeletionIntentV1.decode(neither) == nil)
        var deadlineOnDataDeleted = exactIntent(phase: .localDetaching, staged: .dataDeleted).canonical; deadlineOnDataDeleted["authGuardAfter"] = DeletionWires.authGuardAfter
        #expect(AccountDeletionIntentV1.decode(deadlineOnDataDeleted) == nil)
        var noDeadline = exactIntent(phase: .localDetaching, staged: .authGuarding).canonical; noDeadline["authGuardAfter"] = nil
        #expect(AccountDeletionIntentV1.decode(noDeadline) == nil)
        var unknownPurpose = exactIntent(phase: .prepared).canonical; unknownPurpose["purpose"] = "startup"
        #expect(AccountDeletionIntentV1.decode(unknownPurpose) == nil)
        var unknownReason = exactIntent(phase: .localDetaching, detach: .authDeleted).canonical; unknownReason["detachReason"] = "signed_out"
        #expect(AccountDeletionIntentV1.decode(unknownReason) == nil)
        var partialAcks = exactIntent(phase: .purging).canonical; partialAcks["acks"] = ["route", "handoff"]
        #expect(AccountDeletionIntentV1.decode(partialAcks) != nil, "purging carries an ack prefix")
        var incompleteGuarding = exactIntent(phase: .guarding).canonical; incompleteGuarding["acks"] = ["route"]
        #expect(AccountDeletionIntentV1.decode(incompleteGuarding) == nil, "guarding requires all eight acks")
        var missingProviderUid = exactIntent(phase: .prepared).canonical; missingProviderUid["googleProviderUid"] = nil
        #expect(AccountDeletionIntentV1.decode(missingProviderUid) == nil, "sdk_disconnect_required requires the provider UID")
        var noncanonicalTime = exactIntent(phase: .guarding).canonical; noncanonicalTime["authGuardAfter"] = "2026-09-13T11:59:30Z"
        #expect(AccountDeletionIntentV1.decode(noncanonicalTime) == nil)
        // the envelope: exact fileKind and cap 16,384
        let bytes = try #require(DurableEnvelopeCodec.encode(fileKind: .accountDeletionIntentV1, generationId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", payload: exactIntent(phase: .guarding).canonical))
        #expect(DurableEnvelopeCodec.decode(bytes, fileKind: .accountDeletionIntentV1) != nil && bytes.count <= 16_384)
        #expect(DurableEnvelopeCodec.decode(bytes, fileKind: .accountDeletionCompletionV1) == nil)
    }

    @Test func capabilityIsAdel1UUIDWithA32ByteNonceAndTheC21ProofDigest() {
        let operationId = AccountDeletionCapability.newOperationId()
        #expect(operationId.range(of: AccountDeletionIntentV1.operationIdPattern, options: .regularExpression) != nil)
        let nonce = AccountDeletionCapability.newProofNonce()
        #expect(nonce?.range(of: AccountDeletionIntentV1.proofNoncePattern, options: .regularExpression) != nil)
        let decoded = Data(base64Encoded: (nonce ?? "").replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "=")
        #expect(decoded?.count == 32)
        #expect(AccountDeletionCapability.newProofNonce() != nonce)
        let expected = TaskCanonicalV1.sha256Hex(data: Data("{\"operation_id\":\"\(operationId)\",\"proof_nonce\":\"\(nonce ?? "")\",\"uid\":\"A\"}".utf8))
        #expect(AccountDeletionCapability.proofSHA256(uid: "A", operationId: operationId, proofNonce: nonce ?? "") == expected)
    }

    @Test func confirmedBeginRoutesDataFinalThroughPurgingDetachAndFinalizeToGuardingThenCompleted() async throws {
        let h = try makeDeletionHarness(auth: signedInA)
        h.remote.always("begin", .success(DeletionWires.dataFinal("x")))
        h.remote.script("finalize", .success(DeletionWires.guarding("x")), .success(DeletionWires.deleted("x")))
        #expect(await h.coordinator.startDeletion(uid: "A") == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        let intent = try #require(await h.coordinator.currentIntent())
        #expect(intent.phase == .guarding && intent.acks == PurgeOwner.order && intent.authorityKind == .member && intent.purpose == nil && intent.stagedRoot == nil)
        #expect(intent.startedAt == DeletionWires.startedAt && intent.dataDeletedAt == DeletionWires.dataDeletedAt && intent.authGuardAfter == DeletionWires.authGuardAfter)
        #expect(h.remote.actions == ["begin", "finalize"])
        #expect(h.remote.requests.first == .begin(uid: "A", operationId: intent.operationId, proofNonce: intent.proofNonce))
        #expect(h.owners.calls == ["route(A)", "handoff(A)", "reset(A)", "workflow(A)", "room_capture(A)", "firestore_cache(A)", "notifications(A)", "google.disconnect(g1)"])
        let trace = await h.coordinator.trace
        let phases = trace.filter { $0.hasPrefix("phase:") }
        #expect(phases == ["phase:prepared:confirmed_begin", "phase:data_confirmed", "phase:purging", "phase:local_detaching:DATA_DELETED", "phase:auth_finalize_dispatched", "phase:guarding"])
        #expect(trace.filter { $0.hasPrefix("ack:") } == PurgeOwner.order.map { "ack:\($0.rawValue)" }, "every owner ack is mirrored into the intent before the next owner")
        #expect(h.telemetry.calls == 2, "purging proves the barriers; the staged detach proves them again")
        #expect(h.gate.gates.last == .guarding(uid: "A", authGuardAfter: DeletionWires.authGuardAfter) && h.gate.gates.first == .active(uid: "A"))
        guard case let .present(journal) = await h.purge.observeJournal() else { Issue.record("journal"); return }
        #expect(journal.acks == PurgeOwner.order && journal.providerContext == intent.providerContext)
        #expect(await h.coordinator.currentPresentation() == .guarding(authGuardAfter: DeletionWires.authGuardAfter))
        // Retry in guarding: finalize returns the deleted wire → nonstaged auth_deleted detach → completed, presentation from the completion file
        let count = h.owners.calls.count
        let result = await h.coordinator.retry()
        guard case let .settled(.completion(snapshot)) = result else { Issue.record("completion expected, got \(result)"); return }
        #expect(snapshot.result == .completed(appleRevocation: .notRequired, googleRevocation: .revoked))
        #expect(await h.completion.current() == snapshot)
        let terminal = try #require(await h.coordinator.currentIntent())
        #expect(terminal.phase == .completed && terminal.acks == PurgeOwner.order && terminal.authorityKind == nil && terminal.startedAt == nil && terminal.authGuardAfter == nil && terminal.detachReason == nil)
        #expect(h.remote.actions == ["begin", "finalize", "finalize"])
        #expect(h.owners.calls.count == count, "acknowledged owners are not run again; the barriers are re-proved")
        #expect(h.telemetry.calls == 3)
        #expect(h.gate.terminals.last == .completed && h.gate.gates.last == .active(uid: "A"), "the gate stays nonclear until the presentation is consumed")
        let terminalTrace = await h.coordinator.trace
        #expect(terminalTrace.filter { $0.hasPrefix("phase:") }.suffix(2) == ["phase:local_detaching:auth_deleted", "phase:completed"])
    }

    @Test func startupDiscoverAtEveryServerRootSkipsFinalizeAndAbsentWritesNothing() async throws {
        // absent: zero write, clear
        let absent = try makeDeletionHarness(auth: signedInA)
        absent.remote.always("discover", .success(.absent(operationId: "x")))
        #expect(await absent.coordinator.discoverAtStartup() == .clear)
        #expect(absent.intentBytes() == nil && absent.remote.actions == ["discover"] && absent.gate.gates == [.clear])
        // signed out: no discovery, clear
        let signedOut = try makeDeletionHarness(auth: .signedOut)
        #expect(await signedOut.coordinator.discoverAtStartup() == .clear && signedOut.remote.actions.isEmpty)
        // AUTH_GUARDING root: prepared(startup_discover) → data_confirmed → purging → staged AUTH_GUARDING detach → guarding, no finalize
        let guarding = try makeDeletionHarness(auth: signedInA)
        guarding.remote.always("discover", .success(DeletionWires.guarding("x")))
        #expect(await guarding.coordinator.discoverAtStartup() == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        #expect(guarding.remote.actions == ["discover"])
        let guardingTrace = await guarding.coordinator.trace
        #expect(guardingTrace.filter { $0.hasPrefix("phase:") } == ["phase:prepared:startup_discover", "phase:data_confirmed", "phase:purging", "phase:local_detaching:AUTH_GUARDING", "phase:guarding"])
        #expect(guarding.owners.calls.count == 8)
        // ACCOUNT_DELETED root: → nonstaged auth_deleted detach → completed, no finalize
        let deleted = try makeDeletionHarness(auth: signedInA)
        deleted.remote.always("discover", .success(DeletionWires.deleted("x")))
        guard case .settled(.completion(let snapshot)) = await deleted.coordinator.discoverAtStartup() else { Issue.record("completion"); return }
        #expect(snapshot.result == .completed(appleRevocation: .notRequired, googleRevocation: .revoked) && deleted.remote.actions == ["discover"])
        let deletedTrace = await deleted.coordinator.trace
        #expect(deletedTrace.filter { $0.hasPrefix("phase:") } == ["phase:prepared:startup_discover", "phase:data_confirmed", "phase:purging", "phase:local_detaching:auth_deleted", "phase:completed"])
        // DATA_DELETED root: the finalize path
        let dataFinal = try makeDeletionHarness(auth: signedInA)
        dataFinal.remote.always("discover", .success(DeletionWires.dataFinal("x", replayed: true)))
        dataFinal.remote.always("finalize", .success(DeletionWires.guarding("x")))
        #expect(await dataFinal.coordinator.discoverAtStartup() == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        #expect(dataFinal.remote.actions == ["discover", "finalize"])
        // DELETING-guarding at discovery: the capability is kept in a prepared intent projecting queued
        let queued = try makeDeletionHarness(auth: signedInA)
        queued.remote.always("discover", .failure(.retryRequired))
        #expect(await queued.coordinator.discoverAtStartup() == .settled(.queued))
        let kept = try #require(await queued.coordinator.currentIntent())
        #expect(kept.phase == .prepared && kept.purpose == .startupDiscover && queued.gate.gates.last == .active(uid: "A"))
        // relaunch with that intent: discovery reuses the same capability
        queued.remote.always("discover", .success(DeletionWires.guarding("x")))
        #expect(await queued.coordinator.discoverAtStartup() == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        #expect(queued.remote.requests.last == .discover(uid: "A", operationId: kept.operationId, proofNonce: kept.proofNonce))
    }

    @Test func transportOutcomesKeepPreparedQueuedOrBlockWithRetainedBytesAndReplayReusesTheCapability() async throws {
        let h = try makeDeletionHarness(auth: signedInA)
        // Build A retry: stays prepared, queued
        h.remote.script("begin", .failure(.retryRequired))
        #expect(await h.coordinator.startDeletion(uid: "A") == .settled(.queued))
        let prepared = try #require(await h.coordinator.currentIntent())
        #expect(prepared.phase == .prepared && prepared.purpose == .confirmedBegin && h.gate.gates.last == .active(uid: "A"))
        let bytes = try #require(h.intentBytes())
        // transport: REMOTE_UNAVAILABLE with retained bytes
        h.remote.script("begin", .failure(.transport))
        #expect(await h.coordinator.retry() == .settled(.blocked(.remoteUnavailable)))
        #expect(h.intentBytes() == bytes)
        // protocol ambiguity and REQUEST_INVALID: REMOTE_MALFORMED with retained bytes
        h.remote.script("begin", .failure(.protocolAmbiguity))
        #expect(await h.coordinator.retry() == .settled(.blocked(.remoteMalformed)))
        h.remote.script("begin", .failure(.requestInvalid(field: "uid")))
        #expect(await h.coordinator.retry() == .settled(.blocked(.remoteMalformed)))
        h.remote.script("begin", .failure(.authRequired))
        #expect(await h.coordinator.retry() == .settled(.blocked(.remoteUnavailable)))
        #expect(h.intentBytes() == bytes && h.owners.calls.isEmpty)
        // a begin whose response was lost is replayed by the next begin with the same capability
        h.remote.script("begin", .success(DeletionWires.dataFinal(prepared.operationId, replayed: true)))
        h.remote.always("finalize", .failure(.transport))
        #expect(await h.coordinator.retry() == .settled(.blocked(.remoteUnavailable)))
        #expect(h.remote.requests.allSatisfy { $0 == .begin(uid: "A", operationId: prepared.operationId, proofNonce: prepared.proofNonce) || $0.action == "finalize" })
        let dispatched = try #require(await h.coordinator.currentIntent())
        #expect(dispatched.phase == .authFinalizeDispatched && dispatched.operationId == prepared.operationId && dispatched.acks == PurgeOwner.order)
        // finalize DELETING-guarding keeps the phase; the queued presentation
        h.remote.always("finalize", .failure(.retryRequired))
        #expect(await h.coordinator.retry() == .settled(.queued))
        #expect(await h.coordinator.currentIntent()?.phase == .authFinalizeDispatched)
        // a data-final wire from finalize is protocol ambiguity
        h.remote.always("finalize", .success(DeletionWires.dataFinal(prepared.operationId)))
        #expect(await h.coordinator.retry() == .settled(.blocked(.remoteMalformed)))
        // signed out (the Auth user is deleted at DATA_DELETED): finalize continues on the capability alone
        h.auth.set(.signedOut)
        h.remote.always("finalize", .success(DeletionWires.guarding(prepared.operationId)))
        #expect(await h.coordinator.retry() == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        let fresh = try makeDeletionHarness(auth: .signedOut)
        try Data(contentsOf: h.intentURL).write(to: fresh.intentURL)
        fresh.remote.always("finalize", .success(DeletionWires.guarding(prepared.operationId)))
        #expect(await fresh.coordinator.retry() == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        // a signed-out relaunch in `prepared` dispatches resume for the exact member and never begins
        let preparedOut = try makeDeletionHarness(auth: .signedOut)
        guard case .success = AccountDeletionIntentStore(directory: preparedOut.directory).write(exactIntent(phase: .prepared), expecting: nil) else { Issue.record("seed"); return }
        preparedOut.remote.always("resume", .success(DeletionWires.guarding("adel1_11111111-1111-4111-8111-111111111111")))
        #expect(await preparedOut.coordinator.retry() == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        #expect(preparedOut.remote.actions == ["resume"])
        // a begin returning the absent wire is protocol ambiguity
        let absent = try makeDeletionHarness(auth: signedInA)
        absent.remote.always("begin", .success(.absent(operationId: "x")))
        #expect(await absent.coordinator.startDeletion(uid: "A") == .settled(.blocked(.remoteMalformed)))
        #expect(await absent.coordinator.currentIntent()?.phase == .prepared)
    }

    @Test func capabilityInvalidExitRequiresDefinitivelyDeletedAndNeverFinalizes() async throws {
        let h = try makeDeletionHarness(auth: signedInA)
        h.remote.always("begin", .failure(.capabilityInvalid))
        // the Auth user is still present: not the exit; bytes retained, no purge
        #expect(await h.coordinator.startDeletion(uid: "A") == .settled(.blocked(.remoteMalformed)))
        let prepared = try #require(await h.coordinator.currentIntent())
        #expect(prepared.phase == .prepared && h.owners.calls.isEmpty && h.auth.deletionChecks == [AuthIdentity(uid: "A", authEpochUUID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")])
        // definitively deleted: nonstaged capability_invalid detach persisted before any purge work → full purge → local_cleared
        h.auth.setDeletionObservation(.definitivelyDeleted)
        let result = await h.coordinator.retry()
        guard case let .settled(.completion(snapshot)) = result else { Issue.record("local_cleared expected, got \(result)"); return }
        #expect(snapshot.result == .localCleared)
        let cleared = try #require(await h.coordinator.currentIntent())
        #expect(cleared.phase == .localCleared && cleared.acks == PurgeOwner.order && cleared.detachReason == nil && cleared.authorityKind == nil)
        #expect(h.remote.actions == ["begin", "begin"], "no finalize call")
        #expect(h.owners.calls.count == 8 && h.gate.terminals.last == .localCleared)
        let phases = await h.coordinator.trace.filter { $0.hasPrefix("phase:") }
        #expect(phases == ["phase:prepared:confirmed_begin", "phase:local_detaching:capability_invalid", "phase:local_cleared"])
        #expect(TaskCanonicalV1.data(snapshot.result.presentation) == TaskCanonicalV1.data(["schemaVersion": 1, "kind": "ACCOUNT_DELETION_LOCAL_CLEARED"]))
        // capability-invalid after the data authority is known is not the exit either
        let late = try makeDeletionHarness(auth: signedInA)
        late.auth.setDeletionObservation(.definitivelyDeleted)
        late.remote.always("begin", .success(DeletionWires.dataFinal("x")))
        late.remote.always("finalize", .failure(.capabilityInvalid))
        #expect(await late.coordinator.startDeletion(uid: "A") == .settled(.blocked(.remoteMalformed)))
        #expect(await late.coordinator.currentIntent()?.phase == .authFinalizeDispatched)
    }

    @Test func differentUIDStartDeletionIsBusyAndTheSameUIDJoinsWithoutReplacingTheCapability() async throws {
        let h = try makeDeletionHarness(auth: signedInA)
        h.remote.hold("begin")
        h.remote.always("begin", .failure(.retryRequired))
        let first = Task { await h.coordinator.startDeletion(uid: "A") }
        while !h.remote.isHolding { await Task.yield() }
        #expect(await h.coordinator.startDeletion(uid: "B") == .busy)
        let joiner = Task { await h.coordinator.startDeletion(uid: "A") }
        for _ in 0..<20 { await Task.yield() }
        h.remote.release()
        #expect(await first.value == .settled(.queued))
        #expect(await joiner.value == .settled(.queued))
        #expect(h.remote.actions == ["begin"], "the joiner never dispatches or replaces the capability")
        let intent = try #require(await h.coordinator.currentIntent())
        // at rest in a nonguarding phase: still busy for another UID; the same UID resumes the same capability
        #expect(await h.coordinator.startDeletion(uid: "B") == .busy)
        h.remote.always("begin", .failure(.retryRequired))
        #expect(await h.coordinator.startDeletion(uid: "A") == .settled(.queued))
        #expect(h.remote.requests.last == .begin(uid: "A", operationId: intent.operationId, proofNonce: intent.proofNonce))
        #expect(TaskCanonicalV1.data(AccountDeletionBusy.map) == Data("{\"reason\":\"ACCOUNT_DELETION_BUSY\",\"schemaVersion\":1}".utf8))
    }

    @Test func intentFileCASClocksAndMalformedBytesAreExact() async throws {
        // malformed and over-cap intent files block the gate with retained bytes, never read as absence
        let malformed = try makeDeletionHarness(auth: signedInA)
        try Data("{".utf8).write(to: malformed.intentURL)
        #expect(await malformed.coordinator.discoverAtStartup() == .settled(.blocked(.fileIO)))
        #expect(malformed.gate.gates == [.blocked] && malformed.remote.actions.isEmpty && malformed.intentBytes() == Data("{".utf8))
        #expect(await malformed.coordinator.startDeletion(uid: "A") == .settled(.blocked(.fileIO)))
        let overCap = try makeDeletionHarness(auth: signedInA)
        try Data(repeating: 0x20, count: 16_385).write(to: overCap.intentURL)
        #expect(await overCap.coordinator.retry() == .settled(.blocked(.fileIO)))
        #expect(overCap.intentBytes()?.count == 16_385)
        // stale CAS: the file is replaced under a running purge; the next mirrored ack refuses and the foreign bytes survive
        let stale = try makeDeletionHarness(auth: signedInA)
        stale.remote.always("begin", .success(DeletionWires.dataFinal("x")))
        stale.owners.setHoldRoute()
        let running = Task { await stale.coordinator.startDeletion(uid: "A") }
        while !stale.owners.isHoldingRoute { await Task.yield() }
        let foreign = try #require(DurableEnvelopeCodec.encode(fileKind: .accountDeletionIntentV1, generationId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", payload: exactIntent(phase: .prepared).canonical))
        try foreign.write(to: stale.intentURL)
        stale.owners.releaseRoute()
        #expect(await running.value == .settled(.blocked(.fileIO)))
        #expect(stale.intentBytes() == foreign)
        let staleTrace = await stale.coordinator.trace
        #expect(staleTrace.contains("ack:route:write_failed"))
        // clocks: forward advances updatedAt, equal repeats it, backward never regresses it, noncanonical writes nothing
        let clocks = try makeDeletionHarness(auth: signedInA)
        clocks.remote.always("begin", .failure(.retryRequired))
        #expect(await clocks.coordinator.startDeletion(uid: "A") == .settled(.queued))
        #expect(await clocks.coordinator.currentIntent()?.updatedAt == "2026-09-06T12:00:00.000Z")
        clocks.remote.always("begin", .success(DeletionWires.dataFinal("x")))
        clocks.remote.always("finalize", .failure(.retryRequired))
        clocks.clock.set("2026-09-06T11:00:00.000Z")
        #expect(await clocks.coordinator.retry() == .settled(.queued))
        let backward = try #require(await clocks.coordinator.currentIntent())
        #expect(backward.phase == .authFinalizeDispatched && backward.updatedAt == "2026-09-06T12:00:00.000Z" && backward.createdAt == "2026-09-06T12:00:00.000Z")
        clocks.clock.set("2026-09-06T13:00:00.000Z")
        clocks.remote.always("finalize", .success(DeletionWires.guarding("x")))
        #expect(await clocks.coordinator.retry() == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        #expect(await clocks.coordinator.currentIntent()?.updatedAt == "2026-09-06T13:00:00.000Z")
        let guardingBytes = clocks.intentBytes()
        clocks.clock.set("not-a-time")
        clocks.remote.always("finalize", .success(DeletionWires.deleted("x")))
        #expect(await clocks.coordinator.retry() == .settled(.blocked(.fileIO)))
        let clockTrace = await clocks.coordinator.trace
        #expect(clocks.intentBytes() == guardingBytes && clockTrace.contains("clock:nonrepresentable"))
        // the store's own CAS: create requires absence; replace requires the observed identity; unlink likewise
        let store = AccountDeletionIntentStore(directory: try temporaryDirectory())
        guard case let .success(identity) = store.write(exactIntent(phase: .prepared), expecting: nil) else { Issue.record("create"); return }
        #expect(store.write(exactIntent(phase: .prepared), expecting: nil) == .failure(.stale))
        let drifted = AccountDeletionIntentIdentity(generationId: identity.generationId, sha256: "0", device: identity.device, inode: identity.inode)
        #expect(store.write(exactIntent(phase: .dataConfirmed), expecting: drifted) == .failure(.stale))
        var invalid = exactIntent(phase: .prepared); invalid.acks = [.route]
        #expect(store.write(invalid, expecting: identity) == .failure(.encodeFailed))
        guard case .success = store.write(exactIntent(phase: .dataConfirmed), expecting: identity) else { Issue.record("replace"); return }
        guard case .failure(.stale) = store.unlink(expecting: identity) else { Issue.record("stale unlink"); return }
        guard case let .present(_, current) = store.observe(), case .success = store.unlink(expecting: current) else { Issue.record("unlink"); return }
        #expect(store.observe() == .absent)
    }

    @Test func queuedBlockedAndGuardingPresentationMapsAreExact() throws {
        #expect(TaskCanonicalV1.data(AccountDeletionPresentationV1.queued.map) == TaskCanonicalV1.data(["schemaVersion": 1, "state": "account_deletion_queued", "copy": "Deletion is queued while Peezy finishes clearing protected copies. You can close the app and try again later.", "availableActions": ["retry"]]))
        for reason in LocalPrivacyPurgeBlockedReason.allCases {
            #expect(TaskCanonicalV1.data(AccountDeletionPresentationV1.blocked(reason).map) == TaskCanonicalV1.data(["schemaVersion": 1, "state": "account_deletion_recovery_unavailable", "reason": reason.rawValue, "availableActions": ["retry"]]))
        }
        #expect(LocalPrivacyPurgeBlockedReason.allCases.map(\.rawValue) == ["FILE_IO", "REMOTE_UNAVAILABLE", "REMOTE_MALFORMED", "LOCAL_PRIVACY_PURGE_FAILED"])
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = TimeZone.autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let date = formatter.string(from: Date(timeIntervalSince1970: 1_789_300_770.0))
        #expect(AccountDeletionDateFormatter.string(from: DeletionWires.authGuardAfter) == date)
        #expect(TaskCanonicalV1.data(AccountDeletionPresentationV1.guarding(authGuardAfter: DeletionWires.authGuardAfter).map) == TaskCanonicalV1.data(["schemaVersion": 1, "kind": "ACCOUNT_DELETION_GUARDING", "authGuardAfter": DeletionWires.authGuardAfter, "copy": "Deletion is in progress. Protected copies clear by \(date)."]))
        #expect(AccountDeletionDateFormatter.string(from: "2026-09-13") == nil)
    }

    // MARK: - S4 I4 — terminal consumption (C2.2), crash/relaunch boundaries, Option B (C2.4), auth transitions, remote_unverified (C2.6)

    /// Runs confirmed-begin A through `completed` (begin → data-final, finalize → guarding, Retry finalize → deleted).
    func runToCompleted(_ h: DeletionHarness) async throws -> CompletionSnapshotV1 {
        h.remote.always("begin", .success(DeletionWires.dataFinal("x")))
        h.remote.script("finalize", .success(DeletionWires.guarding("x")), .success(DeletionWires.deleted("x")))
        #expect(await h.coordinator.startDeletion(uid: "A") == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        guard case let .settled(.completion(snapshot)) = await h.coordinator.retry() else { throw DriveTraceError.failed }
        return snapshot
    }

    @Test func terminalConsumptionSignsOutThenRunsTheLinkedAllScopeJournalUnlinksIntentThenJournalThenClears() async throws {
        let h = try makeDeletionHarness(auth: signedInA)
        let snapshot = try await runToCompleted(h)
        let intent = try #require(await h.coordinator.currentIntent())
        let before = h.owners.calls.count
        // open never consumes; a drifted acknowledge is stale and consumes nothing
        #expect(await h.completion.open(expectedGenerationId: snapshot.generationId, expectedSHA256: snapshot.sha256, provider: .google) == .notOffered)
        #expect(await h.completion.acknowledge(expectedGenerationId: snapshot.generationId, expectedSHA256: "0") == .stale)
        let stillPresent = await h.coordinator.currentIntent()
        #expect(h.signOut.calls.isEmpty && stillPresent != nil)
        // the exact-snapshot acknowledge: sign-out → linked all-scope journal → eight owners + barriers → intent unlink → journal unlink → clear
        #expect(await h.completion.acknowledge(expectedGenerationId: snapshot.generationId, expectedSHA256: snapshot.sha256) == .acknowledged)
        #expect(h.signOut.calls == ["A"])
        #expect(Array(h.owners.calls.dropFirst(before)) == ["route(all)", "handoff(all)", "reset(all)", "workflow(all)", "room_capture(all)", "firestore_cache(all)", "notifications(all)", "google.signOutAll"])
        #expect(await h.coordinator.currentIntent() == nil && h.intentBytes() == nil)
        #expect(await h.purge.observeJournal() == .absent)
        #expect(await h.completion.current() == nil)
        #expect(h.gate.gates.last == .clear && h.gate.terminals.last! == nil)
        let trace = await h.coordinator.trace
        let consumption = trace.filter { $0.hasPrefix("consume:") }
        #expect(consumption.count == 5 && consumption.first == "consume:sign_out" && consumption[1].hasPrefix("consume:keychain_scrub:") && Array(consumption.suffix(3)) == ["consume:purge:cleared", "consume:intent_unlinked", "consume:journal_unlinked"])
        h.auth.set(.signedOut)
        #expect(await h.coordinator.discoverAtStartup() == .clear)
        // a sign-out that leaves a matching user blocks the consumption with everything retained
        let refused = try makeDeletionHarness(auth: signedInA)
        let kept = try await runToCompleted(refused)
        refused.signOut.set(false)
        #expect(await refused.completion.acknowledge(expectedGenerationId: kept.generationId, expectedSHA256: kept.sha256) == .failed)
        #expect(await refused.coordinator.currentIntent()?.phase == .completed && refused.gate.gates.last == .blocked)
        #expect(await refused.completion.current() == kept)
        // a linked journal that does not byte-match the surviving intent is LOCAL_PRIVACY_PURGE_FAILED with retained bytes
        let mismatch = try makeDeletionHarness(auth: signedInA)
        _ = try await runToCompleted(mismatch)
        let foreignLink = TerminalDeletionLinkV1(deletionOperationId: "adel1_22222222-2222-4222-8222-222222222222", deletionProofSHA256: String(repeating: "b", count: 64))
        let journal = LocalPrivacyPurgeJournalV1(scope: .all, providerContext: nil, terminalDeletionLink: foreignLink, acks: [.route], createdAt: "2026-09-06T12:00:00.000Z", updatedAt: "2026-09-06T12:00:00.000Z")
        try #require(DurableEnvelopeCodec.encode(fileKind: .localPrivacyPurgeV1, generationId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", payload: journal.canonical)).write(to: mismatch.directory.appendingPathComponent(LocalPrivacyPurgeCoordinator.journalFileName))
        let relaunch = try makeDeletionHarness(auth: .signedOut, directory: mismatch.directory)
        #expect(await relaunch.coordinator.discoverAtStartup() == .settled(.blocked(.localPrivacyPurgeFailed)))
        let retainedIntent = await relaunch.coordinator.currentIntent()
        #expect(retainedIntent?.phase == .completed, "the terminal intent is retained")
        _ = intent
        guard case .present = await relaunch.purge.observeJournal() else { Issue.record("journal retained"); return }
    }

    @Test func relaunchAtEveryPhaseAckBarrierDetachFinalizeGuardingTerminalAndConsumptionBoundaryResolvesFromBytesAlone() async throws {
        // crash mid-purge at every owner: the failing owner blocks; a fresh process resumes past the acknowledged ones
        for (index, failing) in ["route", "handoff", "reset", "workflow", "room_capture", "firestore_cache", "notifications", "google"].enumerated() {
            let first = try makeDeletionHarness(auth: signedInA)
            first.remote.always("begin", .success(DeletionWires.dataFinal("x")))
            first.owners.fail(failing)
            #expect(await first.coordinator.startDeletion(uid: "A") == .settled(.blocked(.localPrivacyPurgeFailed)), Comment(rawValue: "owner \(failing) fails"))
            let crashed = try #require(await first.coordinator.currentIntent())
            #expect(crashed.phase == .purging && crashed.acks.count == index, Comment(rawValue: "\(failing): \(crashed.acks.count) acks mirrored"))
            let second = try makeDeletionHarness(auth: .signedOut, directory: first.directory)
            second.remote.always("resume", .success(DeletionWires.dataFinal("x", replayed: true)))
            second.remote.always("finalize", .success(DeletionWires.guarding("x")))
            #expect(await second.coordinator.discoverAtStartup() == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)), Comment(rawValue: "relaunch after \(failing)"))
            let ownerCalls = second.owners.calls.filter { !$0.hasPrefix("google.") }.count + (second.owners.calls.contains("google.disconnect(g1)") ? 1 : 0)
            #expect(ownerCalls == 8 - index, Comment(rawValue: "\(failing): resumed owners \(ownerCalls)"))
            #expect(second.remote.actions == ["resume", "finalize"], "the root is re-learned by resume, then finalize is dispatched once")
            let resumed = try #require(await second.coordinator.currentIntent())
            #expect(resumed.phase == .guarding && resumed.acks == PurgeOwner.order && resumed.operationId == crashed.operationId)
        }
        // relaunch at each persisted phase (seeded bytes, matching journal where the phase carries acks)
        struct Seed { let intent: AccountDeletionIntentV1; let journalAcks: [PurgeOwner]?; let expectedOwners: Int; let actions: [String] }
        let op = "adel1_11111111-1111-4111-8111-111111111111"
        var staged = exactIntent(phase: .localDetaching, staged: .dataDeleted); staged.acks = [.route, .handoff, .reset]
        var stagedGuarding = exactIntent(phase: .localDetaching, staged: .authGuarding); stagedGuarding.acks = PurgeOwner.order
        var nonstaged = exactIntent(phase: .localDetaching, detach: .authDeleted); nonstaged.acks = [.route]
        let seeds: [Seed] = [
            Seed(intent: exactIntent(phase: .dataConfirmed), journalAcks: nil, expectedOwners: 8, actions: ["resume", "finalize"]),
            Seed(intent: exactIntent(phase: .purging), journalAcks: nil, expectedOwners: 8, actions: ["resume", "finalize"]),
            Seed(intent: staged, journalAcks: [.route, .handoff, .reset], expectedOwners: 5, actions: ["finalize"]),
            Seed(intent: stagedGuarding, journalAcks: PurgeOwner.order, expectedOwners: 0, actions: []),
            Seed(intent: nonstaged, journalAcks: [.route], expectedOwners: 7, actions: []),
            Seed(intent: exactIntent(phase: .authFinalizeDispatched), journalAcks: PurgeOwner.order, expectedOwners: 0, actions: ["finalize"])
        ]
        for seed in seeds {
            let h = try makeDeletionHarness(auth: .signedOut)
            let context = seed.intent.providerContext
            guard case .success = AccountDeletionIntentStore(directory: h.directory).write(seed.intent, expecting: nil) else { Issue.record("seed"); return }
            if let acks = seed.journalAcks {
                let journal = LocalPrivacyPurgeJournalV1(scope: .uid("A"), providerContext: context, terminalDeletionLink: nil, acks: acks, createdAt: "2026-09-06T12:00:00.000Z", updatedAt: "2026-09-06T12:00:00.000Z")
                try #require(DurableEnvelopeCodec.encode(fileKind: .localPrivacyPurgeV1, generationId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", payload: journal.canonical)).write(to: h.directory.appendingPathComponent(LocalPrivacyPurgeCoordinator.journalFileName))
            }
            h.remote.always("resume", .success(DeletionWires.dataFinal(op, replayed: true)))
            h.remote.always("finalize", .success(DeletionWires.guarding(op)))
            let result = await h.coordinator.discoverAtStartup()
            let phase = seed.intent.phase.rawValue + (seed.intent.stagedRoot.map { ":\($0.rawValue)" } ?? "") + (seed.intent.detachReason.map { ":\($0.rawValue)" } ?? "")
            let ownerCalls = h.owners.calls.filter { !$0.hasPrefix("google.") }.count + (h.owners.calls.contains("google.disconnect(g1)") ? 1 : 0)
            #expect(ownerCalls == seed.expectedOwners, Comment(rawValue: "\(phase): owners \(ownerCalls)"))
            #expect(h.remote.actions == seed.actions, Comment(rawValue: "\(phase): actions \(h.remote.actions)"))
            if seed.intent.detachReason == .authDeleted {
                guard case .settled(.completion(let snapshot)) = result, snapshot.result == .completed(appleRevocation: .notRequired, googleRevocation: .revoked) else { Issue.record("\(phase): completed expected, got \(result)"); continue }
                #expect(await h.coordinator.currentIntent()?.phase == .completed && h.gate.terminals.last == .completed)
            } else {
                #expect(result == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)), Comment(rawValue: "\(phase): \(result)"))
                #expect(await h.coordinator.currentIntent()?.phase == .guarding)
            }
            let expectedBarriers: Int
            switch seed.intent.phase {
            case .authFinalizeDispatched: expectedBarriers = 0   // finalize alone never re-proves the barriers
            case .dataConfirmed, .purging: expectedBarriers = 2   // the purging pass and the detach pass
            default: expectedBarriers = 1                         // the detach pass
            }
            #expect(h.telemetry.calls == expectedBarriers, Comment(rawValue: "\(phase): barriers proved \(h.telemetry.calls) times"))
        }
        // guarding relaunch: the deleted UID stays forbidden; a terminal intent with no journal recreates its presentation
        let guarding = try makeDeletionHarness(auth: .signedOut)
        guard case .success = AccountDeletionIntentStore(directory: guarding.directory).write(exactIntent(phase: .guarding), expecting: nil) else { Issue.record("seed"); return }
        guarding.remote.always("finalize", .failure(.retryRequired))
        #expect(await guarding.coordinator.discoverAtStartup() == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        #expect(guarding.gate.gates.last == .guarding(uid: "A", authGuardAfter: DeletionWires.authGuardAfter))
        let terminal = try makeDeletionHarness(auth: .signedOut)
        guard case .success = AccountDeletionIntentStore(directory: terminal.directory).write(exactIntent(phase: .completed), expecting: nil) else { Issue.record("seed"); return }
        guard case .settled(.completion(let recreated)) = await terminal.coordinator.discoverAtStartup() else { Issue.record("recreated"); return }
        #expect(recreated.result == .completed(appleRevocation: .notRequired, googleRevocation: .revoked) && terminal.remote.actions.isEmpty && terminal.owners.calls.isEmpty)
        #expect(terminal.gate.gates.last == .active(uid: "A") && terminal.gate.terminals.last == .completed)
        let bytes = try Data(contentsOf: terminal.directory.appendingPathComponent(AccountDeletionCompletionPresentation.fileName))
        let again = try makeDeletionHarness(auth: .signedOut, directory: terminal.directory)
        guard case .settled(.completion(let replayed)) = await again.coordinator.discoverAtStartup() else { Issue.record("replayed"); return }
        let replayedBytes = try Data(contentsOf: terminal.directory.appendingPathComponent(AccountDeletionCompletionPresentation.fileName))
        #expect(replayed == recreated && replayedBytes == bytes, "exact replay preserves bytes")
        // crash after the acknowledge at every consumption boundary: linked journal partial → intent present; intent unlinked → journal present; both gone → stray completion file
        let partial = try makeDeletionHarness(auth: signedInA)
        let snapshot = try await runToCompleted(partial)
        let intent = try #require(await partial.coordinator.currentIntent())
        let link = TerminalDeletionLinkV1(deletionOperationId: intent.operationId, deletionProofSHA256: intent.proofSHA256)
        let linked = LocalPrivacyPurgeJournalV1(scope: .all, providerContext: nil, terminalDeletionLink: link, acks: [.route, .handoff, .reset, .workflow, .roomCapture], createdAt: "2026-09-06T12:00:00.000Z", updatedAt: "2026-09-06T12:00:00.000Z")
        try #require(DurableEnvelopeCodec.encode(fileKind: .localPrivacyPurgeV1, generationId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", payload: linked.canonical)).write(to: partial.directory.appendingPathComponent(LocalPrivacyPurgeCoordinator.journalFileName))
        let resumed = try makeDeletionHarness(auth: .signedOut, directory: partial.directory)
        #expect(await resumed.coordinator.discoverAtStartup() == .clear)
        #expect(resumed.owners.calls == ["firestore_cache(all)", "notifications(all)", "google.signOutAll"] && resumed.remote.actions.isEmpty)
        let resumedJournal = await resumed.purge.observeJournal()
        #expect(resumed.intentBytes() == nil && resumedJournal == .absent)
        // the completion file survived that crash: its acknowledge finds nothing left to consume and unlinks it
        #expect(await resumed.completion.current() == snapshot)
        #expect(await resumed.completion.acknowledge(expectedGenerationId: snapshot.generationId, expectedSHA256: snapshot.sha256) == .acknowledged)
        #expect(await resumed.completion.current() == nil)
        let orphanJournal = try makeDeletionHarness(auth: .signedOut)
        try #require(DurableEnvelopeCodec.encode(fileKind: .localPrivacyPurgeV1, generationId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", payload: linked.canonical)).write(to: orphanJournal.directory.appendingPathComponent(LocalPrivacyPurgeCoordinator.journalFileName))
        #expect(await orphanJournal.coordinator.discoverAtStartup() == .clear && orphanJournal.owners.calls.count == 3)
        #expect(await orphanJournal.purge.observeJournal() == .absent)
        let stray = try makeDeletionHarness(auth: .signedOut)
        guard case .written(let strayShot) = await stray.completion.derive(.localCleared) else { Issue.record("stray"); return }
        #expect(await stray.coordinator.discoverAtStartup() == .settled(.completion(strayShot)))
        #expect(stray.gate.terminals.last == .localCleared)
        #expect(await stray.completion.acknowledge(expectedGenerationId: strayShot.generationId, expectedSHA256: strayShot.sha256) == .acknowledged)
        #expect(stray.gate.gates.last == .clear)
        // authenticatedOverflow authority is carried unchanged
        let overflow = try makeDeletionHarness(auth: signedInA)
        overflow.remote.always("begin", .success(.dataFinal(AccountDeletionDataFinalWireV1(operationId: "x", authorityKind: .authenticatedOverflow, startedAt: DeletionWires.startedAt, dataDeletedAt: DeletionWires.dataDeletedAt, replayed: false))))
        overflow.remote.always("finalize", .failure(.retryRequired))
        #expect(await overflow.coordinator.startDeletion(uid: "A") == .settled(.queued))
        #expect(await overflow.coordinator.currentIntent()?.authorityKind == .authenticatedOverflow)
    }

    @Test func optionBHandsTheGuardingSlotToASecondUIDBeforeItsFirstAwaitAndRefusesOnAnyDrift() async throws {
        let h = try makeDeletionHarness(auth: signedInA)
        h.remote.always("begin", .success(DeletionWires.dataFinal("x")))
        h.remote.always("finalize", .success(DeletionWires.guarding("x")))
        #expect(await h.coordinator.startDeletion(uid: "A") == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        let guarding = try #require(await h.coordinator.currentIntent())
        let guardingBytes = try #require(h.intentBytes())
        let signedInB = SignedAuthAuthority.signedIn(SignedAuthTuple(uid: "B", authEpochUUID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", credentialRevision: 1))
        // refusals with retained bytes: a deleted root, a mismatched deadline, a data-final root, auth drift, an incomplete journal
        h.auth.set(signedInB)
        h.remote.script("resume", .success(DeletionWires.deleted("x")))
        #expect(await h.coordinator.startDeletion(uid: "B") == .busy && h.intentBytes() == guardingBytes)
        var drifted = AccountDeletionAuthGuardingWireV1(operationId: "x", authorityKind: .member, startedAt: DeletionWires.startedAt, dataDeletedAt: DeletionWires.dataDeletedAt, authAbsenceObservedAt: DeletionWires.dataDeletedAt, authGuardAfter: "2026-09-14T00:00:00.000Z", replayed: true)
        h.remote.script("resume", .success(.authGuarding(drifted)))
        #expect(await h.coordinator.startDeletion(uid: "B") == .busy && h.intentBytes() == guardingBytes)
        h.remote.script("resume", .success(DeletionWires.dataFinal("x", replayed: true)))
        #expect(await h.coordinator.startDeletion(uid: "B") == .busy)
        h.remote.script("resume", .failure(.transport))
        #expect(await h.coordinator.startDeletion(uid: "B") == .busy)
        h.auth.set(.signedIn(SignedAuthTuple(uid: "C", authEpochUUID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc", credentialRevision: 1)))
        #expect(await h.coordinator.startDeletion(uid: "B") == .busy && h.remote.actions.filter { $0 == "resume" }.count == 4, "auth drift refuses before any dispatch")
        h.auth.set(signedInB)
        drifted = AccountDeletionAuthGuardingWireV1(operationId: "x", authorityKind: .member, startedAt: DeletionWires.startedAt, dataDeletedAt: DeletionWires.dataDeletedAt, authAbsenceObservedAt: DeletionWires.dataDeletedAt, authGuardAfter: DeletionWires.authGuardAfter, replayed: true)
        let incomplete = LocalPrivacyPurgeJournalV1(scope: .uid("A"), providerContext: guarding.providerContext, terminalDeletionLink: nil, acks: [.route], createdAt: "2026-09-06T12:00:00.000Z", updatedAt: "2026-09-06T12:00:00.000Z")
        let journalURL = h.directory.appendingPathComponent(LocalPrivacyPurgeCoordinator.journalFileName)
        let completeJournal = try Data(contentsOf: journalURL)
        try #require(DurableEnvelopeCodec.encode(fileKind: .localPrivacyPurgeV1, generationId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", payload: incomplete.canonical)).write(to: journalURL)
        h.remote.script("resume", .success(.authGuarding(drifted)))
        #expect(await h.coordinator.startDeletion(uid: "B") == .busy && h.intentBytes() == guardingBytes)
        try completeJournal.write(to: journalURL)
        #expect(await h.coordinator.currentIntent() == guarding)
        // the handoff: byte-matching authority, complete postconditions, CAS unlink then B's prepared intent with no await between
        h.remote.always("resume", .success(.authGuarding(drifted)))
        h.remote.always("begin", .failure(.retryRequired))
        #expect(await h.coordinator.startDeletion(uid: "B") == .settled(.queued))
        let prepared = try #require(await h.coordinator.currentIntent())
        #expect(prepared.uid == "B" && prepared.phase == .prepared && prepared.purpose == .confirmedBegin && prepared.operationId != guarding.operationId)
        #expect(h.remote.requests.last == .begin(uid: "B", operationId: prepared.operationId, proofNonce: prepared.proofNonce))
        let trace = await h.coordinator.trace
        let handoff = trace.drop(while: { $0 != "optionB:unlinked" })
        #expect(Array(handoff.prefix(2)) == ["optionB:unlinked", "phase:prepared:confirmed_begin"])
        #expect(h.gate.gates.last == .active(uid: "B"))
        // the empty slot: a crash between unlink and persist leaves no intent; relaunch publishes clear and the next startDeletion restarts cleanly
        let empty = try makeDeletionHarness(auth: signedInB)
        empty.remote.always("discover", .success(.absent(operationId: "x")))
        #expect(await empty.coordinator.discoverAtStartup() == .clear)
        empty.remote.always("begin", .failure(.retryRequired))
        #expect(await empty.coordinator.startDeletion(uid: "B") == .settled(.queued))
        #expect(await empty.coordinator.currentIntent()?.uid == "B")
    }

    @Test func signedOutTransitionRunsTheIntentThenTheAllScopePurgeThenDiscoveryAndUserNotFoundTakesOnlyTheNamedExit() async throws {
        // manual sign-out with no named deletion: loading → all-scope purge → discovery → clear; never an intent, never local_cleared
        let manual = try makeDeletionHarness(auth: .signedOut)
        #expect(await manual.coordinator.authTransition() == .clear)
        #expect(manual.gate.gates == [.loading, .clear] && manual.remote.actions.isEmpty && manual.intentBytes() == nil)
        #expect(manual.owners.calls == ["route(all)", "handoff(all)", "reset(all)", "workflow(all)", "room_capture(all)", "firestore_cache(all)", "notifications(all)", "google.signOutAll"])
        let manualJournal = await manual.purge.observeJournal()
        let manualCompletion = await manual.completion.current()
        #expect(manualJournal == .absent && manualCompletion == nil)
        // A→B with A guarding: A's reducer first, then the all-scope purge, then A's guarding stands (B may dispatch under it)
        let switching = try makeDeletionHarness(auth: signedInA)
        switching.remote.always("begin", .success(DeletionWires.dataFinal("x")))
        switching.remote.always("finalize", .success(DeletionWires.guarding("x")))
        #expect(await switching.coordinator.startDeletion(uid: "A") == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        switching.auth.set(.signedIn(SignedAuthTuple(uid: "B", authEpochUUID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", credentialRevision: 1)))
        let before = switching.owners.calls.count
        #expect(await switching.coordinator.authTransition() == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        #expect(Array(switching.owners.calls.dropFirst(before)) == ["route(all)", "handoff(all)", "reset(all)", "workflow(all)", "room_capture(all)", "firestore_cache(all)", "notifications(all)", "google.signOutAll"])
        #expect(switching.gate.gates.suffix(2).first == .loading && switching.gate.gates.last == .guarding(uid: "A", authGuardAfter: DeletionWires.authGuardAfter))
        #expect(await switching.coordinator.currentIntent()?.uid == "A")
        // an all-scope owner failure is blocked with Retry
        let failing = try makeDeletionHarness(auth: .signedOut)
        failing.owners.fail("reset")
        #expect(await failing.coordinator.authTransition() == .settled(.blocked(.localPrivacyPurgeFailed)) && failing.gate.gates.last == .blocked)
        failing.owners.fail("reset", false)
        #expect(await failing.coordinator.authTransition() == .clear)
        // mid-purge precedence: an all-scope transition queued behind the intent-linked purge waits for it
        let mid = try makeDeletionHarness(auth: signedInA)
        mid.remote.always("begin", .success(DeletionWires.dataFinal("x")))
        mid.remote.always("finalize", .failure(.retryRequired))
        mid.owners.setHoldRoute()
        let deletion = Task { await mid.coordinator.startDeletion(uid: "A") }
        while !mid.owners.isHoldingRoute { await Task.yield() }
        let transition = Task { await mid.purge.purge(scope: .all) }
        for _ in 0..<20 { await Task.yield() }
        mid.owners.releaseRoute()
        #expect(await deletion.value == .settled(.queued))
        #expect(await transition.value == .cleared)
        let routeCalls = mid.owners.calls.filter { $0.hasPrefix("route(") }
        #expect(Array(routeCalls.prefix(2)) == ["route(A)", "route(all)"], "the UID purge pass completes before the queued all-scope purge starts; the detach pass then repeats the complete eight-owner work because the all-scope purge retired the UID journal")
        #expect(await mid.coordinator.currentIntent()?.acks == PurgeOwner.order, "an all-scope ack is never mirrored into the UID intent; the UID prefix is its own")
    }

    @Test func remoteUnverifiedBranchPresentsRemoteUnconfirmedTakesTheLinkedHandoffAndEntersNeitherTerminalPhase() async throws {
        let h = try makeDeletionHarness(auth: signedInA)
        h.remote.script("begin", .failure(.retryRequired))
        #expect(await h.coordinator.startDeletion(uid: "A") == .settled(.queued))
        let prepared = try #require(await h.coordinator.currentIntent())
        // signed out, capability invalid, deletion not proven: the honest branch
        h.auth.set(.signedOut)
        h.remote.always("resume", .failure(.capabilityInvalid))
        let result = await h.coordinator.retry()
        guard case let .settled(.completion(snapshot)) = result else { Issue.record("remote-unconfirmed expected, got \(result)"); return }
        #expect(snapshot.result == .remoteUnconfirmed && h.gate.terminals.last == .remoteUnconfirmed)
        let intent = try #require(await h.coordinator.currentIntent())
        #expect(intent.phase == .localDetaching && intent.detachReason == .remoteUnverified && intent.acks == PurgeOwner.order && intent.operationId == prepared.operationId)
        #expect(h.remote.actions == ["begin", "resume"] && h.owners.calls.count == 8)
        #expect(TaskCanonicalV1.data(snapshot.result.presentation) == TaskCanonicalV1.data(["schemaVersion": 1, "kind": "ACCOUNT_DELETION_REMOTE_UNCONFIRMED"]))
        // relaunch resolves the same terminal from bytes alone (no finalize, no completion claim)
        let relaunch = try makeDeletionHarness(auth: .signedOut, directory: h.directory)
        #expect(await relaunch.coordinator.discoverAtStartup() == .settled(.completion(snapshot)) && relaunch.remote.actions.isEmpty)
        // the acknowledge takes the linked all-scope handoff and clears
        #expect(await relaunch.completion.acknowledge(expectedGenerationId: snapshot.generationId, expectedSHA256: snapshot.sha256) == .acknowledged)
        #expect(relaunch.intentBytes() == nil && relaunch.gate.gates.last == .clear && relaunch.signOut.calls == ["A"])
        #expect(relaunch.owners.calls.contains("google.signOutAll"))
    }

    // MARK: - S4 I5 — blocked-store recovery: the dose store (S4-CD1), the reset store through `DurableStoreRecovering` (S4-CD5), the driver

    @Test func doseStoreClassifiesMalformedBytesAndQuarantineDoseBytesCopiesThemBeforeRemoval() async throws {
        let defaults = try isolatedDefaults()
        let store = DailyDoseLocalStore(defaults: defaults)
        let key = DailyDoseLocalStore.key(uid: "A")
        let quarantineKey = DailyDoseLocalStore.quarantineKey(uid: "A")
        #expect(quarantineKey == "peezy.A.dailyDose.v2.quarantine")
        #expect(await store.observeMalformed(uid: "A") == nil)
        _ = await store.ensure(uid: "A", taskGenerationEpoch: 1)
        #expect(await store.observeMalformed(uid: "A") == nil, "a valid store is never malformed")
        let malformed = Data("{\"schemaVersion\":1,\"completedCount\":-1}".utf8)
        defaults.set(malformed, forKey: key)
        for legacy in DailyDoseLocalStore.legacyKeys(uid: "A") { defaults.set("keep", forKey: legacy) }
        let observed = try #require(await store.observeMalformed(uid: "A"))
        let sha = TaskCanonicalV1.sha256Hex(data: malformed)
        #expect(observed == .dose(bytesSHA256: sha, byteLength: malformed.count, quarantineCount: 0))
        let digest = observed.recoveryStateDigest
        #expect(await store.classification(uid: "A") == .blocked(.doseMalformed(recoveryStateDigest: digest, bytesSHA256: sha, byteLength: malformed.count)))
        // a stale token returns the refreshed snapshot with zero writes
        #expect(await store.performQuarantine(uid: "A", expecting: "stale") == .blocked(.doseMalformed(recoveryStateDigest: digest, bytesSHA256: sha, byteLength: malformed.count)))
        #expect(defaults.data(forKey: key) == malformed && defaults.array(forKey: quarantineKey) == nil)
        // drift on the bytes themselves
        #expect(await store.quarantineMalformed(uid: "A", expectedBytesSHA256: "0") == .drifted)
        // the action: copy aside, verify, only then remove; legacy keys untouched; identical concurrent keys coalesce
        async let first = store.performQuarantine(uid: "A", expecting: digest)
        async let second = store.performQuarantine(uid: "A", expecting: digest)
        let results = await [first, second]
        #expect(results == [.ready, .ready])
        #expect(defaults.data(forKey: key) == nil)
        #expect((defaults.array(forKey: quarantineKey) as? [Data]) == [malformed])
        #expect(DailyDoseLocalStore.legacyKeys(uid: "A").allSatisfy { defaults.string(forKey: $0) == "keep" })
        #expect(await store.load(uid: "A") == .absent)
        // crash between (1) and (4): the same bytes with a quarantine copy already held reclassify with a fresh digest; the old token is stale
        defaults.set(malformed, forKey: key)
        let again = try #require(await store.observeMalformed(uid: "A"))
        #expect(again == .dose(bytesSHA256: sha, byteLength: malformed.count, quarantineCount: 1) && again.recoveryStateDigest != digest)
        #expect(await store.performQuarantine(uid: "A", expecting: digest) == .blocked(.doseMalformed(recoveryStateDigest: again.recoveryStateDigest, bytesSHA256: sha, byteLength: malformed.count)))
        #expect(await store.performQuarantine(uid: "A", expecting: again.recoveryStateDigest) == .ready)
        #expect((defaults.array(forKey: quarantineKey) as? [Data]) == [malformed, malformed], "a second append of the same bytes is harmless")
        // a verification read that fails at step (3) leaves the v2 key untouched: the last copy is never removed before its copy is verified
        let suite = "peezy.tests.\(UUID().uuidString)"
        let failing = try #require(VerificationFailingDefaults(suiteName: suite))
        defer { failing.removePersistentDomain(forName: suite) }
        let failingStore = DailyDoseLocalStore(defaults: failing)
        failing.set(malformed, forKey: key)
        failing.failQuarantineReads = true
        #expect(await failingStore.quarantineMalformed(uid: "A", expectedBytesSHA256: sha) == .ioFailed)
        #expect(failing.data(forKey: key) == malformed, "the v2 bytes survive a failed verification")
        failing.failQuarantineReads = false
        #expect(await failingStore.quarantineMalformed(uid: "A", expectedBytesSHA256: sha) == .quarantined && failing.data(forKey: key) == nil)
        // the eleven-key registry holds the quarantine key and the barrier removes it
        #expect(PreferenceBarrier.uidScopedTemplates.contains("peezy.{uid}.dailyDose.v2.quarantine"))
        #expect(PreferenceBarrier.run(scope: .uid("A"), defaults: defaults, currentFirebaseUID: "B") == .acknowledged && defaults.array(forKey: quarantineKey) == nil)
    }

    @Test func resetStoreClassificationSweepsTheDiskCombinationsInTheC973Order() async throws {
        let directory = try temporaryDirectory()
        let target = ResetFixtures.target(directory)
        let quarantine = ResetFixtures.quarantine(directory)
        let (registry, auth) = await ResetFixtures.registry(directory, auth: signedInA)
        func classify() async -> (RecoveryObservation, RecoveryClassification) { let o = await registry.observe(); return (o, registry.classify(o)) }
        // absent / absent → ready
        var (observation, classification) = await classify()
        #expect(classification == .ready)
        guard case let .observed(readyState) = observation else { Issue.record("observed"); return }
        #expect(TaskCanonicalV1.data(readyState.canonical) == TaskCanonicalV1.data(["schemaVersion": 1, "store": "reset", "baseState": "ready", "target": ["present": false], "quarantine": ["present": false], "availableActions": []]))
        // malformed target / absent quarantine → renamed to the fixed sibling at once → quarantined, unenumerable (non-JSON): Discard only
        try Data("not json".utf8).write(to: target)
        (observation, classification) = await classify()
        #expect(!FileManager.default.fileExists(atPath: target.path) && FileManager.default.fileExists(atPath: quarantine.path))
        guard case let .observed(state) = observation, case let .files(_, base, targetObs, quarantineObs, actions, _, _, _, _, enumerable, count, _) = state else { Issue.record("files"); return }
        #expect(base == "quarantined" && targetObs == .absent && actions == ["discard_quarantine"] && enumerable == false && count == nil)
        #expect(quarantineObs == .malformed(byteLength: 8, bytesSHA256: TaskCanonicalV1.sha256Hex(data: Data("not json".utf8))))
        #expect(classification == .blocked(.quarantined(store: .reset, recoveryStateDigest: state.recoveryStateDigest, quarantineEnumerable: false, pendingRecordCount: nil)))
        // absent / two valid rows → quarantined with Recover, count 2
        let rows = [ResetFixtures.row(uid: "A", epoch: 1), ResetFixtures.row(uid: "B", epoch: 2, createdAt: "2026-09-06T12:00:01.000Z", suggested: "rsa1_22222222-2222-4222-8222-222222222222")]
        try ResetFixtures.envelope(records: rows).write(to: quarantine)
        (observation, classification) = await classify()
        guard case let .observed(recoverable) = observation else { Issue.record("recoverable"); return }
        #expect(recoverable.availableActions == ["recover", "discard_quarantine"])
        #expect(classification == .blocked(.quarantined(store: .reset, recoveryStateDigest: recoverable.recoveryStateDigest, quarantineEnumerable: true, pendingRecordCount: 2)))
        // a duplicate member on a candidate path is unenumerable; an invalid candidate is enumerable but unrecoverable (count still reported by the observation, Discard only)
        try Data("{\"payload\":{\"records\":[],\"legacyMigrations\":[]},\"payload\":{}}".utf8).write(to: quarantine)
        (observation, classification) = await classify()
        guard case let .observed(duplicate) = observation, case let .files(_, _, _, _, dupActions, _, _, _, _, dupEnumerable, _, _) = duplicate else { Issue.record("dup"); return }
        #expect(dupActions == ["discard_quarantine"] && dupEnumerable == false)
        try Data("{\"payload\":{\"records\":[{\"uid\":\"A\"}],\"legacyMigrations\":[]}}".utf8).write(to: quarantine)
        (observation, classification) = await classify()
        guard case let .observed(invalid) = observation, case let .files(_, _, _, _, invActions, _, _, _, _, invEnumerable, invCount, _) = invalid else { Issue.record("invalid"); return }
        #expect(invActions == ["discard_quarantine"] && invEnumerable == true && invCount == 1)
        #expect(classification == .blocked(.quarantined(store: .reset, recoveryStateDigest: invalid.recoveryStateDigest, quarantineEnumerable: false, pendingRecordCount: nil)), "S1's snapshot derives its actions from the enumerable flag, so the fallback reports false")
        // malformed target / present quarantine → collision; Recover only for an enumerable zero-candidate target without a singleton
        try ResetFixtures.envelope(records: rows).write(to: quarantine)
        try Data("garbage".utf8).write(to: target)
        (observation, classification) = await classify()
        guard case let .observed(collision) = observation else { Issue.record("collision"); return }
        #expect(collision.availableActions == ["discard_quarantine"])
        #expect(classification == .blocked(.collision(store: .reset, recoveryStateDigest: collision.recoveryStateDigest, quarantineEnumerable: false, pendingRecordCount: nil)))
        try Data("{\"payload\":{\"records\":[],\"legacyMigrations\":[]}}".utf8).write(to: target)
        (observation, classification) = await classify()
        guard case let .observed(emptyCollision) = observation else { Issue.record("empty collision"); return }
        #expect(emptyCollision.availableActions == ["recover", "discard_quarantine"])
        // valid target / present quarantine without a matching receipt → quarantine_conflict; Merge only when shared keys agree
        try ResetFixtures.envelope(records: [rows[0]]).write(to: target)
        (observation, classification) = await classify()
        guard case let .observed(conflict) = observation else { Issue.record("conflict"); return }
        #expect(conflict.availableActions == ["merge", "discard_quarantine"])
        #expect(classification == .blocked(.quarantineConflict(store: .reset, recoveryStateDigest: conflict.recoveryStateDigest, quarantineEnumerable: true, pendingRecordCount: 2)))
        var unequal = rows[0]; unequal["phase"] = "reset_dispatched"
        try ResetFixtures.envelope(records: [unequal, rows[1]]).write(to: quarantine)
        (observation, classification) = await classify()
        guard case let .observed(unequalConflict) = observation else { Issue.record("unequal"); return }
        #expect(unequalConflict.availableActions == ["discard_quarantine"], "same-key unequal rows are unresolved: Merge absent")
        // a valid target whose receipt names the quarantine's digest and counts → recovered_pending_cleanup; a count disagreement stays a conflict
        let quarantineBytes = ResetFixtures.envelope(records: rows)
        try quarantineBytes.write(to: quarantine)
        try ResetFixtures.envelope(records: rows, receipt: ["schemaVersion": 1, "quarantineSHA256": TaskCanonicalV1.sha256Hex(data: quarantineBytes), "recoveredCount": 2, "droppedCount": 0]).write(to: target)
        (observation, classification) = await classify()
        guard case let .observed(cleanup) = observation else { Issue.record("cleanup"); return }
        #expect(cleanup.availableActions == ["retry_cleanup"] && classification == .blocked(.recoveredPendingCleanup(store: .reset, recoveryStateDigest: cleanup.recoveryStateDigest)))
        try ResetFixtures.envelope(records: rows, receipt: ["schemaVersion": 1, "quarantineSHA256": TaskCanonicalV1.sha256Hex(data: quarantineBytes), "recoveredCount": 1, "droppedCount": 0]).write(to: target)
        (observation, classification) = await classify()
        guard case let .observed(disagree) = observation else { Issue.record("disagree"); return }
        #expect(disagree.availableActions == ["merge", "discard_quarantine"])
        // an over-cap quarantine is present, unenumerable, identified by descriptor identity: Discard only
        try Data(repeating: 0x20, count: DurableFileKind.taskPlanResetV2.storeCap + 1).write(to: quarantine)
        (observation, classification) = await classify()
        guard case let .observed(overCap) = observation, case let .files(_, _, _, overQuarantine, overActions, _, _, _, _, _, _, _) = overCap else { Issue.record("overcap"); return }
        guard case let .overCap(length, identity) = overQuarantine else { Issue.record("overCap observation: \(overQuarantine)"); return }
        #expect(length == DurableFileKind.taskPlanResetV2.storeCap + 1 && identity.count == 64 && overActions == ["discard_quarantine"])
        try FileManager.default.removeItem(at: quarantine)
        // I/O failure is storage_io_unavailable, never Discard: the target path is a directory
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        (observation, classification) = await classify()
        #expect(observation == .unavailable(UnavailableToken(store: .reset, state: "storage_io_unavailable", errorCode: "FILE_READ_FAILED")))
        #expect(classification == .blocked(.storageIOUnavailable(store: .reset, errorCode: .fileReadFailed)))
        try FileManager.default.removeItem(at: target)
        // the current UID's epoch conflict through the protocol carries the same digest `recoverEpoch` CASes; signed out it is ready
        try ResetFixtures.envelope(records: [ResetFixtures.row(uid: "A", epoch: 1), ResetFixtures.row(uid: "A", epoch: 2, createdAt: "2026-09-06T12:00:01.000Z", suggested: "rsa1_33333333-3333-4333-8333-333333333333")]).write(to: target)
        (observation, classification) = await classify()
        guard case let .blocked(.resetEpochConflict(digest, actionable, occupants)) = classification else { Issue.record("epoch conflict: \(classification)"); return }
        #expect(actionable == 1 && occupants.count == 2)
        #expect(await registry.classification() == .blocked(.resetEpochConflict(recoveryStateDigest: digest, actionableExpectedTaskGenerationEpoch: 1, occupants: occupants)))
        auth.set(.signedOut)
        (observation, classification) = await classify()
        #expect(classification == .ready, "foreign-UID multiplicity never blocks")
    }

    @Test func resetRecoveryActionsHonorWholeStateCASAndTheReplacementSequences() async throws {
        let directory = try temporaryDirectory()
        let target = ResetFixtures.target(directory)
        let quarantine = ResetFixtures.quarantine(directory)
        let (registry, _) = await ResetFixtures.registry(directory, auth: signedInA)
        func digest() async -> String { guard case let .observed(state) = await registry.observe() else { return "" }; return state.recoveryStateDigest }
        let rows = [ResetFixtures.row(uid: "A", epoch: 1), ResetFixtures.row(uid: "B", epoch: 2, createdAt: "2026-09-06T12:00:01.000Z", suggested: "rsa1_22222222-2222-4222-8222-222222222222")]
        // recover from `quarantined`: stale digest → the refreshed snapshot with zero writes; exact digest → fresh generation with the receipt, quarantine unlinked
        let quarantineBytes = ResetFixtures.envelope(records: rows)
        try quarantineBytes.write(to: quarantine)
        let current = await digest()
        #expect(await registry.perform(.recover, expecting: .digest("stale")) == .blocked(.quarantined(store: .reset, recoveryStateDigest: current, quarantineEnumerable: true, pendingRecordCount: 2)))
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(await registry.perform(.repairInstallationIdentity, expecting: .unavailable(UnavailableToken(store: .reset, state: "x", errorCode: "y"))) == .unavailable(store: .reset))
        #expect(await registry.perform(.recover, expecting: .digest(current)) == .ready)
        let recovered = try #require(DurableEnvelopeCodec.decode(try Data(contentsOf: target), fileKind: .taskPlanResetV2))
        #expect(TaskCanonicalV1.data(recovered.recoveryReceipt ?? [:]) == TaskCanonicalV1.data(["schemaVersion": 1, "quarantineSHA256": TaskCanonicalV1.sha256Hex(data: quarantineBytes), "recoveredCount": 2, "droppedCount": 0]))
        let recoveredRows = await registry.snapshot().records.count
        #expect(!FileManager.default.fileExists(atPath: quarantine.path) && recoveredRows == 2)
        let recoveredBytes = try Data(contentsOf: target)
        let readyObservation = await registry.observe()
        #expect(readyObservation == .observed(.files(store: .reset, baseState: "ready", target: .valid(byteLength: recoveredBytes.count, bytesSHA256: TaskCanonicalV1.sha256Hex(data: recoveredBytes), generationId: recovered.generationId, envelopeSHA256: recovered.sha256), quarantine: .absent, availableActions: [])))
        // crash after rename before unlink → recovered_pending_cleanup → retry_cleanup unlinks only the quarantine
        try quarantineBytes.write(to: quarantine)
        let targetBytes = try Data(contentsOf: target)
        let cleanupDigest = await digest()
        #expect(await registry.perform(.retryCleanup, expecting: .digest(cleanupDigest)) == .ready)
        let afterCleanup = try Data(contentsOf: target)
        #expect(!FileManager.default.fileExists(atPath: quarantine.path) && afterCleanup == targetBytes)
        // discard: the quarantine only; a two-step collision discard exposes the malformed target as the next quarantine
        try Data("garbage".utf8).write(to: target)
        try quarantineBytes.write(to: quarantine)
        let collisionDigest = await digest()
        let afterFirstDiscard = await registry.perform(.discardQuarantine, expecting: .digest(collisionDigest))
        let renamedDigest = await digest()
        #expect(afterFirstDiscard == .blocked(.quarantined(store: .reset, recoveryStateDigest: renamedDigest, quarantineEnumerable: false, pendingRecordCount: nil)))
        let renamedBytes = try Data(contentsOf: quarantine)
        #expect(renamedBytes == Data("garbage".utf8) && !FileManager.default.fileExists(atPath: target.path))
        #expect(await registry.perform(.discardQuarantine, expecting: .digest(renamedDigest)) == .ready)
        #expect(!FileManager.default.fileExists(atPath: quarantine.path))
        // merge: live rows kept, same-key byte-equal rows not inserted, new rows added; the receipt counts every candidate
        try ResetFixtures.envelope(records: [rows[0]]).write(to: target)
        try quarantineBytes.write(to: quarantine)
        #expect(await registry.perform(.merge, expecting: .digest(await digest())) == .ready)
        let merged = try #require(DurableEnvelopeCodec.decode(try Data(contentsOf: target), fileKind: .taskPlanResetV2))
        let mergedUIDs = await registry.snapshot().records.map(\.uid)
        #expect(mergedUIDs == ["A", "B"] && (merged.recoveryReceipt?["recoveredCount"] as? Int) == 2)
        // a different key while one attempt is in flight is RECOVERY_BUSY (the merged target's receipt now names this quarantine: cleanup)
        try quarantineBytes.write(to: quarantine)
        let cleanupAgain = await digest()
        #expect(registry.classify(await registry.observe()) == .blocked(.recoveredPendingCleanup(store: .reset, recoveryStateDigest: cleanupAgain)))
        async let winner = registry.perform(.retryCleanup, expecting: .digest(cleanupAgain))
        async let loser = registry.perform(.discardQuarantine, expecting: .digest(cleanupAgain))
        let outcomes = await [winner, loser]
        #expect(outcomes == [.ready, .busy(store: .reset)])
        #expect(!FileManager.default.fileExists(atPath: quarantine.path))
        // unavailable retry: the token must match; a directory in the target's place fails the read, removing it and retrying classifies ready
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let token = UnavailableToken(store: .reset, state: "storage_io_unavailable", errorCode: "FILE_READ_FAILED")
        #expect(await registry.perform(.retry(errorCode: "FILE_OPEN_FAILED"), expecting: .unavailable(token)) == .unavailable(store: .reset), "the action and token disagree")
        #expect(await registry.perform(.retry(errorCode: "FILE_READ_FAILED"), expecting: .unavailable(token)) == .blocked(.storageIOUnavailable(store: .reset, errorCode: .fileReadFailed)))
        try FileManager.default.removeItem(at: target)
        #expect(await registry.perform(.retry(errorCode: "FILE_READ_FAILED"), expecting: .unavailable(token)) == .ready)
    }

    @Test func resetReceiptMismatchReconcilesThroughInspectionOnlyAndInstallsProvenance() async throws {
        let directory = try temporaryDirectory()
        let target = ResetFixtures.target(directory)
        let remote = InspectionRemote()
        let (registry, auth) = await ResetFixtures.registry(directory, auth: signedInA, remote: remote)
        let receipt = ResetFixtures.finalReceipt(uid: "A", epoch: 1)
        try ResetFixtures.envelope(records: [ResetFixtures.row(uid: "A", epoch: 1, phase: "final_receipt", finalReceipt: receipt)]).write(to: target)
        let identity = ResetOperationRegistry.identityDigest(uid: "A", expectedTaskGenerationEpoch: 1)
        #expect(identity == TaskCanonicalV1.sha256Hex(["kind": "reset", "uid": "A", "expectedTaskGenerationEpoch": 1]))
        // a loaded receipt-bearing row of the current UID is receipt_mismatch; signed out it is inert
        var observation = await registry.observe()
        guard case let .observed(state) = observation, case let .files(_, base, _, _, actions, _, _, authTuple, mismatch, _, _, _) = state else { Issue.record("observed"); return }
        #expect(base == "receipt_mismatch" && actions == ["reconcile"] && mismatch == identity && authTuple?.uid == "A")
        #expect(state.canonical["auth"] != nil)
        let digest = state.recoveryStateDigest
        #expect(registry.classify(observation) == .blocked(.receiptMismatch(store: .reset, recoveryStateDigest: digest, mismatchIdentityDigest: identity)))
        auth.set(.signedOut)
        #expect(registry.classify(await registry.observe()) == .ready)
        auth.set(signedInA)
        let bytes = try Data(contentsOf: target)
        // stale digest and a transport failure: zero write, the same classification
        #expect(await registry.perform(.reconcile(mismatchIdentityDigest: identity), expecting: .digest("stale")) == .blocked(.receiptMismatch(store: .reset, recoveryStateDigest: digest, mismatchIdentityDigest: identity)))
        #expect(remote.calls.isEmpty)
        remote.script(.transport)
        #expect(await registry.perform(.reconcile(mismatchIdentityDigest: identity), expecting: .digest(digest)) == .blocked(.receiptMismatch(store: .reset, recoveryStateDigest: digest, mismatchIdentityDigest: identity)))
        let untouched = try Data(contentsOf: target)
        #expect(remote.calls == ["A|\(ResetFixtures.operationId)|1"] && untouched == bytes)
        // committed: the exact receipt is installed as provenance and the store is ready until the auth tuple changes
        remote.script(.committed(receipt))
        #expect(await registry.perform(.reconcile(mismatchIdentityDigest: identity), expecting: .digest(digest)) == .ready)
        #expect(registry.classify(await registry.observe()) == .ready)
        auth.set(.signedIn(SignedAuthTuple(uid: "A", authEpochUUID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", credentialRevision: 4)))
        observation = await registry.observe()
        guard case let .observed(afterAuth) = observation else { Issue.record("after auth"); return }
        #expect(registry.classify(observation) == .blocked(.receiptMismatch(store: .reset, recoveryStateDigest: afterAuth.recoveryStateDigest, mismatchIdentityDigest: identity)), "any signed-auth change clears the provenance")
        // absent: the row returns to its pre-replay phase with every receipt member cleared, then the store is ready
        remote.script(.absent)
        #expect(await registry.perform(.reconcile(mismatchIdentityDigest: identity), expecting: .digest(afterAuth.recoveryStateDigest)) == .ready)
        let row = try #require(await registry.snapshot().records.first)
        #expect(row.phase == .resetDispatched && row.finalReceipt == nil && row.progressReceipt == nil && row.canonicalOperationId == nil && row.applicationId == nil)
        // step 6 precedes step 7: two receipt-bearing rows of one UID are reconciled first-in-frozen-order, then the epoch conflict surfaces
        try ResetFixtures.envelope(records: [
            ResetFixtures.row(uid: "A", epoch: 1, phase: "final_receipt", finalReceipt: receipt),
            ResetFixtures.row(uid: "A", epoch: 2, createdAt: "2026-09-06T12:00:01.000Z", phase: "final_receipt", finalReceipt: ResetFixtures.finalReceipt(uid: "A", epoch: 2, operationId: "rso1_" + String(repeating: "c", count: 40)), suggested: "rsa1_33333333-3333-4333-8333-333333333333")
        ]).write(to: target)
        guard case let .observed(first) = await registry.observe(), case let .files(_, _, _, _, _, _, _, _, firstMismatch, _, _, _) = first else { Issue.record("first"); return }
        #expect(firstMismatch == identity)
        remote.script(.committed(receipt))
        let afterFirst = await registry.perform(.reconcile(mismatchIdentityDigest: identity), expecting: .digest(first.recoveryStateDigest))
        guard case let .blocked(.receiptMismatch(_, _, secondMismatch)) = afterFirst else { Issue.record("second mismatch, got \(afterFirst)"); return }
        #expect(secondMismatch == ResetOperationRegistry.identityDigest(uid: "A", expectedTaskGenerationEpoch: 2))
        guard case let .observed(second) = await registry.observe() else { Issue.record("second"); return }
        remote.script(.committed(ResetFixtures.finalReceipt(uid: "A", epoch: 2, operationId: "rso1_" + String(repeating: "c", count: 40))))
        let afterSecond = await registry.perform(.reconcile(mismatchIdentityDigest: secondMismatch), expecting: .digest(second.recoveryStateDigest))
        guard case .blocked(.resetEpochConflict) = afterSecond else { Issue.record("epoch conflict expected, got \(afterSecond)"); return }
        #expect(remote.calls.count == 5, "transport, committed, absent, and the two ordered commits")
    }

    @Test func recoveryDriverClassifiesEveryStoreThroughTheProtocolPublishesReadinessAndRoutesActions() async throws {
        let directory = try temporaryDirectory()
        let defaults = try isolatedDefaults()
        let dose = DailyDoseLocalStore(defaults: defaults)
        defaults.set(Data("{".utf8), forKey: DailyDoseLocalStore.key(uid: "A"))
        let route = ScriptedStoreOwner(store: .route)
        let identity = InstallationIdentityStub(.error)
        let handoff = KeychainHandoffOwner(identity: identity)
        let workflow = ScriptedStoreOwner(store: .workflow, observation: .observed(.files(store: .workflow, baseState: "quarantined", target: .absent, quarantine: .malformed(byteLength: 3, bytesSHA256: String(repeating: "e", count: 64)), availableActions: ["discard_quarantine"])))
        let (reset, _) = await ResetFixtures.registry(directory, auth: signedInA)
        let published = NotificationCounter()
        let log = OpenedURLs()
        let driver = DurableStoreRecoveryDriver(owners: DurableStoreOwners(route: route, handoff: handoff, reset: reset, workflow: workflow), dose: dose, currentUID: UIDProbe("A")) { store, readiness in
            await published.bump()
            let state: String
            switch readiness { case .loading: state = "loading"; case .ready: state = "ready"; case let .blocked(snapshot): state = snapshot.state }
            await log.record(URL(string: "peezy://\(store.rawValue)/\(state)")!)
        }
        let classifications = await driver.classifyAll()
        #expect(await log.urls.map(\.absoluteString) == ["peezy://route/ready", "peezy://handoff/installation_authority_unavailable", "peezy://reset/ready", "peezy://workflow/quarantined"], "frozen order; each result published as it settles")
        #expect(classifications[.route] == .ready && classifications[.reset] == .ready)
        #expect(classifications[.handoff] == .blocked(.installationAuthorityUnavailable(errorCode: KeychainUnavailableCode.allCases.first { $0.rawValue == "KEYCHAIN_LOAD_FAILED" }!)))
        guard case .blocked(.doseMalformed(let doseDigest, _, 1)) = classifications[.dose] else { Issue.record("dose: \(String(describing: classifications[.dose]))"); return }
        // keychain Retry repeats the exact authority operation; Repair runs `repairInvalid` with a fresh UUID
        let token = UnavailableToken(store: .handoff, state: "installation_authority_unavailable", errorCode: "KEYCHAIN_LOAD_FAILED")
        identity.set(.invalid)
        #expect(await driver.perform(store: .handoff, action: .retry(errorCode: "KEYCHAIN_LOAD_FAILED"), expecting: .unavailable(token)) == .blocked(.installationAuthorityInvalid))
        #expect(await log.urls.last?.absoluteString == "peezy://handoff/installation_authority_invalid")
        let invalidToken = UnavailableToken(store: .handoff, state: "installation_authority_invalid", errorCode: "KEYCHAIN_VALUE_INVALID")
        #expect(await driver.perform(store: .handoff, action: .repairInstallationIdentity, expecting: .unavailable(invalidToken)) == .ready)
        #expect(identity.repairs.count == 1 && identity.repairs[0].range(of: DurableEnvelopeCodec.uuidPattern, options: .regularExpression) != nil)
        #expect(await log.urls.last?.absoluteString == "peezy://handoff/ready")
        // routed actions reach only their owner and reclassify that store; the dose store is driven through `DailyDoseLocalStore`
        workflow.setResult(.ready)
        workflow.set(.observed(.files(store: .workflow, baseState: "ready", target: .absent, quarantine: .absent, availableActions: [])))
        #expect(await driver.perform(store: .workflow, action: .discardQuarantine, expecting: .digest("d")) == .ready)
        #expect(workflow.performedActions == ["discard_quarantine"] && route.performedActions.isEmpty)
        #expect(await log.urls.last?.absoluteString == "peezy://workflow/ready")
        #expect(await driver.perform(store: .dose, action: .quarantineDoseBytes, expecting: .digest(doseDigest)) == .ready)
        let doseAfter = await driver.classifications[.dose]
        #expect(defaults.data(forKey: DailyDoseLocalStore.key(uid: "A")) == nil && doseAfter == .ready)
        #expect(await driver.perform(store: .dose, action: .recover, expecting: .digest(doseDigest)) == .unavailable(store: .dose))
        #expect(await published.count == 7)
    }

    @Test func foreignResolutionChoicesAreCollectedLocallyInDisplayedOrderWithOrdinals() {
        let groups = [ForeignDecisionGroup(decisionDigest: String(repeating: "1", count: 64), actionLabel: "Continue on iPad"),
                      ForeignDecisionGroup(decisionDigest: String(repeating: "2", count: 64), actionLabel: "Continue on iPad"),
                      ForeignDecisionGroup(decisionDigest: String(repeating: "3", count: 64), actionLabel: "Restart here")]
        #expect(ForeignResolutionChoices.displayLabels(groups) == ["Continue on iPad (1)", "Continue on iPad (2)", "Restart here"])
        let selections = [groups[0].decisionDigest: "continue", groups[1].decisionDigest: "restart", groups[2].decisionDigest: "continue"]
        let choices = ForeignResolutionChoices.choices(groups: groups, selections: selections)
        #expect(choices == [["decisionDigest": groups[0].decisionDigest, "choice": "continue"], ["decisionDigest": groups[1].decisionDigest, "choice": "restart"], ["decisionDigest": groups[2].decisionDigest, "choice": "continue"]])
        #expect(ForeignResolutionChoices.choices(groups: groups, selections: [groups[0].decisionDigest: "continue"]) == nil, "missing")
        #expect(ForeignResolutionChoices.choices(groups: groups, selections: selections.merging([String(repeating: "9", count: 64): "continue"]) { a, _ in a }) == nil, "surplus")
        #expect(ForeignResolutionChoices.choices(groups: groups, selections: selections.merging([groups[2].decisionDigest: "later"]) { _, b in b }) == nil, "unknown value")
        let elements = ForeignResolutionChoices.elements(choices ?? [])
        #expect(elements[0] == "{\"choice\":\"continue\",\"decisionDigest\":\"\(groups[0].decisionDigest)\"}")
        let expected = TaskCanonicalV1.sha256Hex(data: Data(("[" + elements.joined(separator: ",") + "]").utf8))
        #expect(ForeignResolutionChoices.choicesSHA256(elements: elements) == expected)
        #expect(RecoveryAction.resolve(resolutionDigest: "r", choices: elements).attemptKey(expecting: .digest("d")) == .resolveForeign(recoveryStateDigest: "d", resolutionDigest: "r", choicesSHA256: expected))
        #expect(ForeignResolutionChoices.resolutionDigest(recoveryStateDigest: "d", groups: groups) == TaskCanonicalV1.sha256Hex(["recovery_state_digest": "d", "decision_groups": groups.map { ["decisionDigest": $0.decisionDigest, "actionLabel": $0.actionLabel] }]))
        #expect(JSONObjectScanner.hasNoDuplicateKeys(Data("{\"a\":{\"b\":1,\"b\":2}}".utf8)) == false)
        #expect(JSONObjectScanner.hasNoDuplicateKeys(Data("{\"a\":[{\"b\":1},{\"b\":2}],\"c\":\"}{\"}".utf8)) == true)
        #expect(JSONObjectScanner.object(Data("[1]".utf8)) == nil)
    }

    // MARK: - S4 I6 — C9.4.5 client legacy migration rows (`LegacyResetMigrationV1`, alias candidates, receipt→applying, invalid-alias inspection)

    @Test func legacyMigrationRowGrammarAcceptsEveryMemberCrossProductAndRejectsTheRest() throws {
        let uid = "A", legacy = LegacyFixtures.legacyA, alias = "rsa1_22222222-2222-4222-8222-222222222222"
        let upgraded = LegacyFixtures.upgraded(uid: uid, legacy: legacy, alias: alias, epoch: 1)
        let notDispatched = LegacyFixtures.notDispatched(uid: uid, legacy: legacy, alias: alias)
        let migrationId = LegacyResetReconciliationV1.migrationId(uid: uid, legacyOperationId: legacy)
        let rla = LegacyResetMigrationV1.applicationId(uid: uid, migrationId: migrationId, outcome: "not_dispatched")
        let rows: [LegacyResetMigrationV1] = [
            LegacyFixtures.exactRow(phase: .prepared), LegacyFixtures.exactRow(phase: .dispatched), LegacyFixtures.exactRow(phase: .receipt, receipt: upgraded),
            LegacyFixtures.exactRow(phase: .applying, receipt: upgraded, authority: nil), LegacyFixtures.exactRow(phase: .applying, receipt: notDispatched, applicationId: rla, authority: nil),
            LegacyFixtures.exactRow(phase: .blocked, errorCode: .legacyResetCorrupt), LegacyFixtures.exactRow(phase: .blocked, errorCode: .operationReused), LegacyFixtures.exactRow(phase: .blocked, errorCode: .aliasCollisionExhausted),
            LegacyFixtures.exactRow(phase: .prepared, authority: .resetDispatched(expectedTaskGenerationEpoch: 1, suggestedOperationId: alias)), LegacyFixtures.exactRow(phase: .prepared, authority: nil),
            LegacyFixtures.invalidRow(.nonString), LegacyFixtures.invalidRow(.invalidString, authority: .reservedGesture(gestureId: "rsg1_11111111-1111-4111-8111-111111111111", gestureGeneration: "g1", alias: alias))
        ]
        for row in rows {
            let map = row.map()
            #expect(row.isValid, Comment(rawValue: "\(row.phase) \(String(describing: row.errorCode)) exact"))
            #expect(LegacyResetMigrationV1.from(map) == row, Comment(rawValue: "\(row.phase) round-trip"))
            var surplus = map; surplus["extra"] = 1
            #expect(LegacyResetMigrationV1.from(surplus) == nil)
            var wrongPhase = map; wrongPhase["phase"] = "done"
            #expect(LegacyResetMigrationV1.from(wrongPhase) == nil)
            for key in ["uid", "authEpochUUID", "credentialRevision", "phase", "createdAt", "updatedAt"] { var missing = map; missing[key] = nil; #expect(LegacyResetMigrationV1.from(missing) == nil, Comment(rawValue: "missing \(key)")) }
            if !row.isInvalidAliasMember {
                #expect(map["requestFingerprint"] as? String == "rlmreq1_" + TaskCanonicalV1.sha256Hex(["account_uid": uid, "legacy_operation_id": legacy]))
                #expect(map["requestCanonicalJSON"] as? String == "{\"action\":\"reconcileLegacyTaskReset\",\"legacyOperationId\":\"\(legacy)\",\"migrationAlias\":\"\(alias)\"}")
                #expect(map["requestSHA256"] as? String == TaskCanonicalV1.sha256Hex(data: Data((map["requestCanonicalJSON"] as? String ?? "").utf8)))
                var drifted = map; drifted["requestSHA256"] = String(repeating: "0", count: 64)
                #expect(LegacyResetMigrationV1.from(drifted) == nil, "derived members must match")
                for key in ["legacyOperationId", "migrationAlias", "aliasCandidateOrdinal", "legacyKeyGuard"] { var missing = map; missing[key] = nil; #expect(LegacyResetMigrationV1.from(missing) == nil, Comment(rawValue: "missing \(key)")) }
                var ordinal = map; ordinal["aliasCandidateOrdinal"] = 5
                #expect(LegacyResetMigrationV1.from(ordinal) == nil)
            }
        }
        #expect(migrationId == "rlm1_" + String(TaskCanonicalV1.sha256Hex(["account_uid": uid, "legacy_operation_id": legacy]).prefix(40)))
        #expect(rla == "rla1_" + String(TaskCanonicalV1.sha256Hex(["uid": uid, "migration_id": migrationId, "outcome": "not_dispatched"]).prefix(40)))
        #expect(LegacyResetMigrationV1.clearApplicationId(uid: uid, legacyValueClass: .nonString, utf8Length: nil, sha256: nil, outcome: "none") == "rlic1_" + String(TaskCanonicalV1.sha256Hex(["uid": uid, "legacy_value_class": "non_string", "outcome": "none"]).prefix(40)))
        // forbidden cross-member combinations
        var receiptInPrepared = LegacyFixtures.exactRow(phase: .prepared); receiptInPrepared.receipt = TaskCanonicalV1.data(upgraded.map())
        #expect(!receiptInPrepared.isValid)
        var applicationForUpgraded = LegacyFixtures.exactRow(phase: .applying, receipt: upgraded, authority: nil); applicationForUpgraded.applicationId = rla
        #expect(!applicationForUpgraded.isValid)
        #expect(!LegacyFixtures.exactRow(phase: .applying, receipt: notDispatched, authority: nil).isValid, "not_dispatched requires the application ID")
        #expect(!LegacyFixtures.exactRow(phase: .applying, receipt: upgraded).isValid, "APPLYING forbids the initiating authority")
        #expect(!LegacyFixtures.exactRow(phase: .receipt).isValid && !LegacyFixtures.exactRow(phase: .blocked).isValid)
        var blockedWithReceipt = LegacyFixtures.exactRow(phase: .blocked, errorCode: .operationReused); blockedWithReceipt.receipt = TaskCanonicalV1.data(upgraded.map())
        #expect(!blockedWithReceipt.isValid)
        #expect(!LegacyFixtures.invalidRow(.nonString, authority: .resetDispatched(expectedTaskGenerationEpoch: 1, suggestedOperationId: alias)).isValid, "the invalid-alias member permits only a reserved-gesture authority")
        var nonStringWithMetadata = LegacyFixtures.invalidRow(.nonString); nonStringWithMetadata.legacyValueUtf8Length = 3
        #expect(!nonStringWithMetadata.isValid)
        var invalidWithoutDigest = LegacyFixtures.invalidRow(.invalidString); invalidWithoutDigest.legacyValueSHA256 = nil
        #expect(!invalidWithoutDigest.isValid)
        var invalidWithLegacyId = LegacyFixtures.invalidRow(.nonString); invalidWithLegacyId.legacyOperationId = legacy
        #expect(!invalidWithLegacyId.isValid)
        var foreignReceipt = LegacyFixtures.exactRow(phase: .receipt, receipt: LegacyFixtures.upgraded(uid: "B", legacy: legacy, alias: alias, epoch: 1))
        #expect(!foreignReceipt.isValid)
        foreignReceipt = LegacyFixtures.exactRow(phase: .receipt, receipt: LegacyFixtures.upgraded(uid: uid, legacy: LegacyFixtures.legacyB, alias: alias, epoch: 1))
        #expect(!foreignReceipt.isValid, "the receipt names the row's legacy ID")
        #expect(!LegacyResetMigrationV1.isValidLegacyOperationId(" \(legacy)") && !LegacyResetMigrationV1.isValidLegacyOperationId("a/b") && !LegacyResetMigrationV1.isValidLegacyOperationId(""))
        #expect(LegacyKeyGuard.from(["kind": "valid_string", "value": "a/b"]) == nil && LegacyKeyGuard.from(["kind": "invalid_value", "valueClass": "non_string", "utf8Length": 1]) == nil)
        // the inspection wire and the local-only surfaces
        #expect(try LegacyResetInspectionV1.decode(["schemaVersion": 1, "kind": "legacy_reset_inspection", "outcome": "none", "accountUid": uid]) == .none(accountUid: uid))
        #expect(try LegacyResetInspectionV1.decode(["schemaVersion": 1, "kind": "legacy_reset_inspection", "outcome": "legacy_active", "accountUid": uid, "legacyOperationId": legacy]) == .legacyActive(accountUid: uid, legacyOperationId: legacy))
        #expect(try LegacyResetInspectionV1.decode(["schemaVersion": 1, "kind": "legacy_reset_inspection", "outcome": "phase2_active", "accountUid": uid, "canonicalOperationId": ResetFixtures.operationId, "expectedTaskGenerationEpoch": 3]) == .phase2Active(accountUid: uid, canonicalOperationId: ResetFixtures.operationId, expectedTaskGenerationEpoch: 3))
        #expect(throws: ResetRemoteError.self) { try LegacyResetInspectionV1.decode(["schemaVersion": 1, "kind": "legacy_reset_inspection", "outcome": "none", "accountUid": uid, "legacyOperationId": legacy]) }
        #expect(throws: ResetRemoteError.self) { try LegacyResetInspectionV1.decode(["schemaVersion": 1, "kind": "legacy_reset_inspection", "outcome": "phase2_active", "accountUid": uid, "canonicalOperationId": "x", "expectedTaskGenerationEpoch": 3]) }
        #expect(TaskCanonicalV1.data(LegacyMigrationSurface.pending(uid: uid, phase: .dispatched).map) == TaskCanonicalV1.data(["schemaVersion": 1, "kind": "RESET_MIGRATION_PENDING", "uid": uid, "phase": "dispatched"]))
        #expect(TaskCanonicalV1.data(LegacyMigrationSurface.blocked(uid: uid, errorCode: .aliasInvalid).map) == TaskCanonicalV1.data(["schemaVersion": 1, "reason": "RESET_MIGRATION_BLOCKED", "uid": uid, "errorCode": "LEGACY_ALIAS_INVALID"]))
        #expect(TaskCanonicalV1.data(LegacyMigrationSurface.retryRequired(uid: uid, applicationId: rla).map) == TaskCanonicalV1.data(["schemaVersion": 1, "kind": "LEGACY_RESET_RETRY_REQUIRED", "uid": uid, "applicationId": rla]))
        #expect(TaskCanonicalV1.data(LegacyMigrationSurface.completed(uid: uid, applicationId: rla).map) == TaskCanonicalV1.data(["schemaVersion": 1, "kind": "LEGACY_RESET_COMPLETED", "uid": uid, "applicationId": rla]))
    }

    @Test func legacyMigrationAliasCandidatesAdvanceOnOccupiedRedirectOnRequiredAndBlockOnExhaustedReusedAndCorrupt() async throws {
        let directory = try temporaryDirectory()
        let defaults = try isolatedDefaults()
        defaults.set(LegacyFixtures.legacyA, forKey: LegacyResetMigrationV1.legacyKey(uid: "A"))
        let (registry, _) = await LegacyFixtures.registry(directory, defaults: defaults)
        let remote = LegacyRemote()
        // a confirmed reserve with a valid key adopts a durable reserved gesture and creates PREPARED at ordinal 1 with the valid_string guard
        #expect(try await registry.reserve(gestureId: LegacyFixtures.gestureId()) == .migrationPending(ResetMigrationPending(uid: "A", phase: .prepared)))
        var row = try #require(await registry.legacyMigration(uid: "A"))
        let gesture = try #require(await registry.snapshot().gesture)
        #expect(row.phase == .prepared && row.aliasCandidateOrdinal == 1 && row.legacyOperationId == LegacyFixtures.legacyA && row.legacyKeyGuard == .validString(value: LegacyFixtures.legacyA))
        #expect(row.initiatingAuthority == .reservedGesture(gestureId: gesture.gestureId, gestureGeneration: gesture.gestureGeneration, alias: gesture.alias) && gesture.phase == .reserved)
        #expect(await registry.classification() == .ready, "a migration row never blocks the reset store")
        // a reserve during every transient phase joins the pending surface; bind is stale while a migration exists
        #expect(try await registry.reserve(gestureId: LegacyFixtures.gestureId()) == .migrationPending(ResetMigrationPending(uid: "A", phase: .prepared)))
        await #expect(throws: ResetOperationRegistry.RegistryError.self) { try await registry.bind(reservation: ResetReservation(gestureId: gesture.gestureId, gestureGeneration: gesture.gestureGeneration)) }
        // occupied candidates 1–3 advance the ordinal with a fresh alias, each committed before the next dispatch; transport ambiguity retains the candidate
        var aliases: [String] = [row.migrationAlias ?? ""]
        for ordinal in 1...3 {
            remote.reconcile(.failure(.legacyResetAliasOccupied(legacyOperationId: LegacyFixtures.legacyA, migrationAlias: aliases.last ?? "")))
            remote.reconcile(.failure(.transport))
            await #expect(throws: ResetRemoteError.self) { try await registry.driveLegacyMigration(remote: remote) }
            row = try #require(await registry.legacyMigration(uid: "A"))
            #expect(row.phase == .dispatched && row.aliasCandidateOrdinal == ordinal + 1 && row.migrationAlias != aliases.last, Comment(rawValue: "ordinal \(ordinal) occupied → \(ordinal + 1)"))
            aliases.append(row.migrationAlias ?? "")
        }
        #expect(remote.calls.count == 6, "each candidate dispatched once, each transport retry once")
        #expect(Set(aliases).count == 4, "every draw consumes its ordinal with a fresh UUID")
        // a collision detail that names another request is a protocol failure: the row is untouched
        remote.reconcile(.failure(.legacyResetAliasOccupied(legacyOperationId: LegacyFixtures.legacyB, migrationAlias: aliases.last ?? "")))
        await #expect(throws: ResetRemoteError.self) { try await registry.driveLegacyMigration(remote: remote) }
        let untouched = await registry.legacyMigration(uid: "A")
        #expect(untouched == row)
        // ordinal 4 occupied → LEGACY_ALIAS_COLLISION_EXHAUSTED; a confirmed reserve draws ordinal 1 again; the drive never resets it
        remote.reconcile(.failure(.legacyResetAliasOccupied(legacyOperationId: LegacyFixtures.legacyA, migrationAlias: aliases.last ?? "")))
        await #expect(throws: ResetOperationRegistry.RegistryError.migrationBlocked(uid: "A", errorCode: "LEGACY_ALIAS_COLLISION_EXHAUSTED")) { try await registry.driveLegacyMigration(remote: remote) }
        row = try #require(await registry.legacyMigration(uid: "A"))
        #expect(row.phase == .blocked && row.errorCode == .aliasCollisionExhausted && row.aliasCandidateOrdinal == 4)
        await #expect(throws: ResetOperationRegistry.RegistryError.migrationBlocked(uid: "A", errorCode: "LEGACY_ALIAS_COLLISION_EXHAUSTED")) { try await registry.driveLegacyMigration(remote: remote) }
        #expect(try await registry.reserve(gestureId: LegacyFixtures.gestureId()) == .migrationPending(ResetMigrationPending(uid: "A", phase: .prepared)))
        row = try #require(await registry.legacyMigration(uid: "A"))
        #expect(row.aliasCandidateOrdinal == 1 && !aliases.contains(row.migrationAlias ?? "") && row.initiatingAuthority == .reservedGesture(gestureId: gesture.gestureId, gestureGeneration: gesture.gestureGeneration, alias: gesture.alias))
        // MIGRATION_REQUIRED(B) redirects to PREPARED(B) at ordinal 1 preserving guard, authority, and createdAt; B == A is a protocol failure
        let createdAt = row.createdAt
        remote.reconcile(.failure(.legacyResetMigrationRequired(legacyOperationId: LegacyFixtures.legacyA)))
        await #expect(throws: ResetRemoteError.self) { try await registry.driveLegacyMigration(remote: remote) }
        #expect(await registry.legacyMigration(uid: "A")?.legacyOperationId == LegacyFixtures.legacyA)
        remote.reconcile(.failure(.legacyResetMigrationRequired(legacyOperationId: LegacyFixtures.legacyB)))
        remote.reconcile(.failure(.transport))
        await #expect(throws: ResetRemoteError.self) { try await registry.driveLegacyMigration(remote: remote) }
        row = try #require(await registry.legacyMigration(uid: "A"))
        #expect(row.legacyOperationId == LegacyFixtures.legacyB && row.aliasCandidateOrdinal == 1 && row.legacyKeyGuard == .validString(value: LegacyFixtures.legacyA) && row.createdAt == createdAt && row.phase == .dispatched)
        #expect(row.map()["requestFingerprint"] as? String == LegacyResetReconciliationV1.requestFingerprint(uid: "A", legacyOperationId: LegacyFixtures.legacyB))
        // LEGACY_RESET_CORRUPT blocks; the confirmed reserve is the frozen same-request Retry to PREPARED (alias and ordinal kept)
        let keptAlias = row.migrationAlias
        remote.reconcile(.failure(.legacyResetCorrupt(context: "reconcile", legacyOperationId: LegacyFixtures.legacyB, recordClass: "deleting", markerClass: "absent")))
        await #expect(throws: ResetOperationRegistry.RegistryError.migrationBlocked(uid: "A", errorCode: "LEGACY_RESET_CORRUPT")) { try await registry.driveLegacyMigration(remote: remote) }
        #expect(try await registry.reserve(gestureId: LegacyFixtures.gestureId()) == .migrationPending(ResetMigrationPending(uid: "A", phase: .prepared)))
        row = try #require(await registry.legacyMigration(uid: "A"))
        #expect(row.errorCode == nil && row.migrationAlias == keptAlias && row.aliasCandidateOrdinal == 1)
        // REQUEST_INVALID after local validation is LEGACY_RESET_CORRUPT; OPERATION_REUSED never transitions, even on reserve
        remote.reconcile(.failure(.requestInvalid(field: "migrationAlias")))
        await #expect(throws: ResetOperationRegistry.RegistryError.migrationBlocked(uid: "A", errorCode: "LEGACY_RESET_CORRUPT")) { try await registry.driveLegacyMigration(remote: remote) }
        _ = try await registry.reserve(gestureId: LegacyFixtures.gestureId())
        remote.reconcile(.failure(.operationReused(operationId: ResetFixtures.operationId)))
        await #expect(throws: ResetOperationRegistry.RegistryError.migrationBlocked(uid: "A", errorCode: "OPERATION_REUSED")) { try await registry.driveLegacyMigration(remote: remote) }
        await #expect(throws: ResetOperationRegistry.RegistryError.migrationBlocked(uid: "A", errorCode: "OPERATION_REUSED")) { try await registry.reserve(gestureId: LegacyFixtures.gestureId()) }
        #expect(await registry.legacyMigration(uid: "A")?.errorCode == .operationReused)
        #expect(defaults.string(forKey: LegacyResetMigrationV1.legacyKey(uid: "A")) == LegacyFixtures.legacyA, "the key is compare/remove authority only in APPLYING")
    }

    @Test func legacyMigrationReceiptToApplyingMaterializesUpgradedRetiresNotDispatchedAndComparesTheKey() async throws {
        // upgraded under a reserved gesture: the progress receipt materializes the row under the bound alias, the gesture goes, the key is removed
        let upgradedDirectory = try temporaryDirectory()
        let defaults = try isolatedDefaults()
        defaults.set(LegacyFixtures.legacyA, forKey: LegacyResetMigrationV1.legacyKey(uid: "A"))
        let (registry, _) = await LegacyFixtures.registry(upgradedDirectory, defaults: defaults)
        let remote = LegacyRemote()
        _ = try await registry.reserve(gestureId: LegacyFixtures.gestureId())
        let gesture = try #require(await registry.snapshot().gesture)
        let prepared = try #require(await registry.legacyMigration(uid: "A"))
        remote.reconcile(.success(LegacyFixtures.upgraded(uid: "A", legacy: LegacyFixtures.legacyA, alias: prepared.migrationAlias ?? "", epoch: 4)))
        let outcome = try await registry.driveLegacyMigration(remote: remote)
        let snapshot = await registry.snapshot()
        let materialized = try #require(snapshot.records.first)
        #expect(outcome == .operation(ResetOperationHandle(uid: "A", handleId: materialized.handleId)))
        #expect(materialized.suggestedOperationId == gesture.alias && materialized.createdAt == gesture.reservedAt && materialized.expectedTaskGenerationEpoch == 4 && materialized.phase == .resetReceiptDeleting)
        #expect(materialized.canonicalOperationId == "rso1_" + String(repeating: "d", count: 40) && materialized.progressReceipt != nil)
        let migrationAfterUpgrade = await registry.legacyMigration(uid: "A")
        #expect(snapshot.gesture == nil && migrationAfterUpgrade == nil)
        #expect(defaults.object(forKey: LegacyResetMigrationV1.legacyKey(uid: "A")) == nil, "the exact valid_string value is removed in APPLYING")
        #expect(try await registry.reserve(gestureId: LegacyFixtures.gestureId()) == .operation(ResetOperationHandle(uid: "A", handleId: materialized.handleId)), "a later reserve derives the same handle")
        #expect(remote.calls == ["reconcile:\(LegacyFixtures.legacyA)|\(prepared.migrationAlias ?? "")"])
        // a replayed response must not name a different alias only when it is not replayed
        // not_dispatched: the gesture is retired, no reset row, the rla1_ application ID, LEGACY_RESET_RETRY_REQUIRED; a whitespace-changed key is not removed
        let notDispatchedDirectory = try temporaryDirectory()
        let defaults2 = try isolatedDefaults()
        defaults2.set(LegacyFixtures.legacyA, forKey: LegacyResetMigrationV1.legacyKey(uid: "A"))
        let (registry2, _) = await LegacyFixtures.registry(notDispatchedDirectory, defaults: defaults2)
        _ = try await registry2.reserve(gestureId: LegacyFixtures.gestureId())
        let prepared2 = try #require(await registry2.legacyMigration(uid: "A"))
        defaults2.set(LegacyFixtures.legacyA + " ", forKey: LegacyResetMigrationV1.legacyKey(uid: "A"))
        let remote2 = LegacyRemote()
        remote2.reconcile(.success(LegacyFixtures.notDispatched(uid: "A", legacy: LegacyFixtures.legacyA, alias: prepared2.migrationAlias ?? "")))
        let migrationId = LegacyResetReconciliationV1.migrationId(uid: "A", legacyOperationId: LegacyFixtures.legacyA)
        #expect(try await registry2.driveLegacyMigration(remote: remote2) == .legacyRetryRequired(LegacyResetRetryRequired(uid: "A", applicationId: LegacyResetMigrationV1.applicationId(uid: "A", migrationId: migrationId, outcome: "not_dispatched"))))
        let snapshot2 = await registry2.snapshot()
        let migrationAfterNotDispatched = await registry2.legacyMigration(uid: "A")
        #expect(snapshot2.records.isEmpty && snapshot2.gesture == nil && migrationAfterNotDispatched == nil)
        #expect(defaults2.string(forKey: LegacyResetMigrationV1.legacyKey(uid: "A")) == LegacyFixtures.legacyA + " ", "a different value remains")
        // finalized_compat: LEGACY_RESET_COMPLETED
        let compatDirectory = try temporaryDirectory()
        let defaults3 = try isolatedDefaults()
        defaults3.set(LegacyFixtures.legacyA, forKey: LegacyResetMigrationV1.legacyKey(uid: "A"))
        let (registry3, _) = await LegacyFixtures.registry(compatDirectory, defaults: defaults3)
        _ = try await registry3.reserve(gestureId: LegacyFixtures.gestureId())
        let prepared3 = try #require(await registry3.legacyMigration(uid: "A"))
        let remote3 = LegacyRemote()
        remote3.reconcile(.success(LegacyFixtures.finalizedCompat(uid: "A", legacy: LegacyFixtures.legacyA, alias: prepared3.migrationAlias ?? "")))
        #expect(try await registry3.driveLegacyMigration(remote: remote3) == .legacyCompleted(LegacyResetCompleted(uid: "A", applicationId: LegacyResetMigrationV1.applicationId(uid: "A", migrationId: migrationId, outcome: "finalized_compat"))))
        #expect(defaults3.object(forKey: LegacyResetMigrationV1.legacyKey(uid: "A")) == nil)
        // phase2_active under a reset_dispatched authority (discovery without a local key): the durable row is transformed in place, handle stable
        let dispatchedDirectory = try temporaryDirectory()
        let defaults4 = try isolatedDefaults()
        let (registry4, _) = await LegacyFixtures.registry(dispatchedDirectory, defaults: defaults4)
        try ResetFixtures.envelope(records: [ResetFixtures.row(uid: "A", epoch: 1, phase: "reset_dispatched")]).write(to: ResetFixtures.target(dispatchedDirectory))
        let dispatched = try #require(await registry4.snapshot().records.first)
        let handle = ResetOperationHandle(uid: "A", handleId: dispatched.handleId)
        #expect(try await registry4.noteMigrationRequired(handle: handle, legacyOperationId: LegacyFixtures.legacyB) == ResetMigrationPending(uid: "A", phase: .prepared))
        let background = try #require(await registry4.legacyMigration(uid: "A"))
        #expect(background.initiatingAuthority == .resetDispatched(expectedTaskGenerationEpoch: 1, suggestedOperationId: dispatched.suggestedOperationId) && background.legacyKeyGuard == .absent)
        #expect(try await registry4.reserve(gestureId: LegacyFixtures.gestureId()) == .migrationPending(ResetMigrationPending(uid: "A", phase: .prepared)), "the migration precedes the reset row")
        let remote4 = LegacyRemote()
        remote4.reconcile(.success(LegacyFixtures.phase2Active(uid: "A", legacy: LegacyFixtures.legacyB, alias: "rsa1_99999999-9999-4999-8999-999999999999", epoch: 2)))
        #expect(try await registry4.driveLegacyMigration(remote: remote4) == .operation(handle), "the handle survives the in-place transformation")
        let transformed = try #require(await registry4.snapshot().records.first)
        #expect(transformed.phase == .resetReceiptAwaitingLocalReset && transformed.expectedTaskGenerationEpoch == 2 && transformed.canonicalOperationId != nil && transformed.suggestedOperationId == dispatched.suggestedOperationId)
        #expect(await registry4.legacyMigration(uid: "A") == nil)
        await #expect(throws: ResetOperationRegistry.RegistryError.self) { try await registry4.noteMigrationRequired(handle: handle, legacyOperationId: LegacyFixtures.legacyB) }
        // a present-authority mismatch at receipt→applying blocks with zero write
        let mismatchDirectory = try temporaryDirectory()
        let (registry5, _) = await LegacyFixtures.registry(mismatchDirectory, defaults: try isolatedDefaults())
        var receiptRow = LegacyFixtures.exactRow(phase: .receipt, receipt: LegacyFixtures.upgraded(uid: "A", legacy: LegacyFixtures.legacyA, alias: "rsa1_22222222-2222-4222-8222-222222222222", epoch: 1), authority: .resetDispatched(expectedTaskGenerationEpoch: 1, suggestedOperationId: "rsa1_22222222-2222-4222-8222-222222222222"))
        receiptRow.legacyKeyGuard = .absent
        try LegacyFixtures.seed(mismatchDirectory, migration: receiptRow, records: [ResetFixtures.row(uid: "A", epoch: 1, phase: "final_receipt", finalReceipt: ResetFixtures.finalReceipt(uid: "A", epoch: 1), suggested: "rsa1_22222222-2222-4222-8222-222222222222")])
        let before = try Data(contentsOf: ResetFixtures.target(mismatchDirectory))
        await #expect(throws: ResetOperationRegistry.RegistryError.envelopeCorrupt) { try await registry5.driveLegacyMigration(remote: LegacyRemote()) }
        let after = try Data(contentsOf: ResetFixtures.target(mismatchDirectory))
        #expect(after == before)
    }

    @Test func legacyAliasInvalidRowsInspectUnderReservedConsentAndClearOrRedirect() async throws {
        // a non-string key: the invalid-alias member with the reserved-gesture consent; without an inspection wire it stays byte-identical
        let directory = try temporaryDirectory()
        let defaults = try isolatedDefaults()
        defaults.set(5, forKey: LegacyResetMigrationV1.legacyKey(uid: "A"))
        let (registry, _) = await LegacyFixtures.registry(directory, defaults: defaults)
        #expect(try await registry.reserve(gestureId: LegacyFixtures.gestureId()) == .migrationPending(ResetMigrationPending(uid: "A", phase: .blocked)))
        let row = try #require(await registry.legacyMigration(uid: "A"))
        #expect(row.isInvalidAliasMember && row.legacyValueClass == .nonString && row.legacyValueUtf8Length == nil && row.legacyOperationId == nil)
        guard case .reservedGesture = row.initiatingAuthority else { Issue.record("consent attached"); return }
        let bytes = try Data(contentsOf: ResetFixtures.target(directory))
        let remote = LegacyRemote()
        await #expect(throws: ResetOperationRegistry.RegistryError.migrationBlocked(uid: "A", errorCode: "LEGACY_ALIAS_INVALID")) { try await registry.driveLegacyMigration(remote: remote) }
        remote.inspect(.failure(.legacyResetCorrupt(context: "inspect", legacyOperationId: nil, recordClass: "phase2", markerClass: "malformed")))
        await #expect(throws: ResetOperationRegistry.RegistryError.migrationBlocked(uid: "A", errorCode: "LEGACY_ALIAS_INVALID")) { try await registry.driveLegacyMigration(remote: remote) }
        let retained = try Data(contentsOf: ResetFixtures.target(directory))
        #expect(retained == bytes && remote.calls == ["inspect", "inspect"], "a transport failure and a corrupt inspection each call once and write nothing")
        // none with a non_string guard: the key is never auto-removed; migration and gesture retire; LEGACY_RESET_RETRY_REQUIRED with the rlic1_/none ID
        remote.inspect(.success(.none(accountUid: "A")))
        #expect(try await registry.driveLegacyMigration(remote: remote) == .legacyRetryRequired(LegacyResetRetryRequired(uid: "A", applicationId: LegacyResetMigrationV1.clearApplicationId(uid: "A", legacyValueClass: .nonString, utf8Length: nil, sha256: nil, outcome: "none"))))
        let afterNone = await registry.legacyMigration(uid: "A")
        let afterNoneGesture = await registry.snapshot().gesture
        #expect(defaults.integer(forKey: LegacyResetMigrationV1.legacyKey(uid: "A")) == 5 && afterNone == nil && afterNoneGesture == nil)
        // an invalid string: legacy_active(B) redirects to PREPARED(B) at ordinal 1 with the carried invalid guard; APPLYING then compare-removes by length and digest
        let redirectDirectory = try temporaryDirectory()
        let defaults2 = try isolatedDefaults()
        defaults2.set("bad/id", forKey: LegacyResetMigrationV1.legacyKey(uid: "A"))
        let (registry2, _) = await LegacyFixtures.registry(redirectDirectory, defaults: defaults2)
        #expect(try await registry2.reserve(gestureId: LegacyFixtures.gestureId()) == .migrationPending(ResetMigrationPending(uid: "A", phase: .blocked)))
        let invalid = try #require(await registry2.legacyMigration(uid: "A"))
        #expect(invalid.legacyValueClass == .invalidString && invalid.legacyValueUtf8Length == 6 && invalid.legacyValueSHA256 == TaskCanonicalV1.sha256Hex(data: Data("bad/id".utf8)))
        let remote2 = LegacyRemote()
        remote2.inspect(.success(.legacyActive(accountUid: "A", legacyOperationId: LegacyFixtures.legacyB)))
        #expect(try await registry2.driveLegacyMigration(remote: remote2) == .migrationPending(ResetMigrationPending(uid: "A", phase: .prepared)))
        let redirected = try #require(await registry2.legacyMigration(uid: "A"))
        #expect(redirected.legacyOperationId == LegacyFixtures.legacyB && redirected.aliasCandidateOrdinal == 1 && redirected.legacyKeyGuard == .invalidValue(valueClass: .invalidString, utf8Length: 6, sha256: TaskCanonicalV1.sha256Hex(data: Data("bad/id".utf8))) && redirected.initiatingAuthority == invalid.initiatingAuthority && redirected.legacyValueClass == nil)
        remote2.reconcile(.success(LegacyFixtures.notDispatched(uid: "A", legacy: LegacyFixtures.legacyB, alias: redirected.migrationAlias ?? "")))
        guard case .legacyRetryRequired = try await registry2.driveLegacyMigration(remote: remote2) else { Issue.record("not dispatched"); return }
        #expect(defaults2.object(forKey: LegacyResetMigrationV1.legacyKey(uid: "A")) == nil, "the invalid string matching length and digest is removed")
        // phase2_active(C) with the guard matching adopts a no-receipt reset_dispatched row under the stored reserved alias and clears the key
        let adoptDirectory = try temporaryDirectory()
        let defaults3 = try isolatedDefaults()
        defaults3.set("bad/id", forKey: LegacyResetMigrationV1.legacyKey(uid: "A"))
        let (registry3, _) = await LegacyFixtures.registry(adoptDirectory, defaults: defaults3)
        _ = try await registry3.reserve(gestureId: LegacyFixtures.gestureId())
        let reserved = try #require(await registry3.snapshot().gesture)
        let remote3 = LegacyRemote()
        remote3.inspect(.success(.phase2Active(accountUid: "A", canonicalOperationId: ResetFixtures.operationId, expectedTaskGenerationEpoch: 3)))
        let adopted = try await registry3.driveLegacyMigration(remote: remote3)
        let adoptedRow = try #require(await registry3.snapshot().records.first)
        #expect(adopted == .operation(ResetOperationHandle(uid: "A", handleId: adoptedRow.handleId)))
        #expect(adoptedRow.phase == .resetDispatched && adoptedRow.canonicalOperationId == nil && adoptedRow.progressReceipt == nil && adoptedRow.expectedTaskGenerationEpoch == 3 && adoptedRow.suggestedOperationId == reserved.alias && adoptedRow.createdAt == reserved.reservedAt)
        let afterAdopt = await registry3.legacyMigration(uid: "A")
        let afterAdoptGesture = await registry3.snapshot().gesture
        #expect(defaults3.object(forKey: LegacyResetMigrationV1.legacyKey(uid: "A")) == nil && afterAdopt == nil && afterAdoptGesture == nil)
        // a drifted guard retires everything, leaves the key untouched, and returns the rlic1_/legacy_value_changed ID
        let driftDirectory = try temporaryDirectory()
        let defaults4 = try isolatedDefaults()
        defaults4.set("bad/id", forKey: LegacyResetMigrationV1.legacyKey(uid: "A"))
        let (registry4, _) = await LegacyFixtures.registry(driftDirectory, defaults: defaults4)
        _ = try await registry4.reserve(gestureId: LegacyFixtures.gestureId())
        defaults4.set("worse/id", forKey: LegacyResetMigrationV1.legacyKey(uid: "A"))
        let remote4 = LegacyRemote()
        remote4.inspect(.success(.phase2Active(accountUid: "A", canonicalOperationId: ResetFixtures.operationId, expectedTaskGenerationEpoch: 3)))
        let sha = TaskCanonicalV1.sha256Hex(data: Data("bad/id".utf8))
        #expect(try await registry4.driveLegacyMigration(remote: remote4) == .legacyRetryRequired(LegacyResetRetryRequired(uid: "A", applicationId: LegacyResetMigrationV1.clearApplicationId(uid: "A", legacyValueClass: .invalidString, utf8Length: 6, sha256: sha, outcome: "legacy_value_changed"))))
        let afterDriftRecords = await registry4.snapshot().records
        let afterDrift = await registry4.legacyMigration(uid: "A")
        #expect(defaults4.string(forKey: LegacyResetMigrationV1.legacyKey(uid: "A")) == "worse/id" && afterDriftRecords.isEmpty && afterDrift == nil)
        // a background invalid-alias row (no consent) never inspects; a confirmed reserve attaches the consent
        let backgroundDirectory = try temporaryDirectory()
        let (registry5, _) = await LegacyFixtures.registry(backgroundDirectory, defaults: try isolatedDefaults())
        try LegacyFixtures.seed(backgroundDirectory, migration: LegacyFixtures.invalidRow(.nonString))
        let remote5 = LegacyRemote()
        remote5.inspect(.success(.none(accountUid: "A")))
        await #expect(throws: ResetOperationRegistry.RegistryError.migrationBlocked(uid: "A", errorCode: "LEGACY_ALIAS_INVALID")) { try await registry5.driveLegacyMigration(remote: remote5) }
        #expect(remote5.calls.isEmpty)
        #expect(try await registry5.reserve(gestureId: LegacyFixtures.gestureId()) == .migrationPending(ResetMigrationPending(uid: "A", phase: .blocked)))
        guard case .reservedGesture = try #require(await registry5.legacyMigration(uid: "A")).initiatingAuthority else { Issue.record("consent"); return }
        #expect(await registry5.snapshot().gesture?.phase == .reserved)
    }


    // MARK: - S4 I7 — the recovery surface (`DurableStoreRecoveryView.swift`): presentation, C2.5 content, action wiring

    @Test func recoverySurfacePresentsEverySnapshotMemberWithExactActionsAndEnablesOnlyTheActionableEpoch() {
        let digest = String(repeating: "1", count: 64)
        let occupants = [ResetEpochOccupant(expectedTaskGenerationEpoch: 1, phase: .resetReceiptDeleting, recoveryAction: .resumeServerDeletion), ResetEpochOccupant(expectedTaskGenerationEpoch: 2, phase: .prepared, recoveryAction: .retryReset)]
        let foreign = ForeignInstallationObservation(targetPresent: true, targetEnumerable: true, targetPendingRecordCount: 2, quarantinePresent: false, quarantineEnumerable: false, quarantinePendingRecordCount: nil)
        let groups = [ForeignDecisionGroup(decisionDigest: String(repeating: "2", count: 64), actionLabel: "Continue on iPad"), ForeignDecisionGroup(decisionDigest: String(repeating: "3", count: 64), actionLabel: "Continue on iPad")]
        let snapshots: [BlockedSnapshot] = [
            .quarantined(store: .route, recoveryStateDigest: digest, quarantineEnumerable: true, pendingRecordCount: 3),
            .quarantined(store: .route, recoveryStateDigest: digest, quarantineEnumerable: false, pendingRecordCount: nil),
            .collision(store: .workflow, recoveryStateDigest: digest, quarantineEnumerable: true, pendingRecordCount: 1),
            .recoveredPendingCleanup(store: .reset, recoveryStateDigest: digest),
            .quarantineConflict(store: .handoff, recoveryStateDigest: digest, quarantineEnumerable: true, pendingRecordCount: 4),
            .receiptMismatch(store: .reset, recoveryStateDigest: digest, mismatchIdentityDigest: String(repeating: "9", count: 64)),
            .resetEpochConflict(recoveryStateDigest: digest, actionableExpectedTaskGenerationEpoch: 1, occupants: occupants),
            .foreignInstallation(recoveryStateDigest: digest, observation: foreign),
            .foreignResolutionRequired(recoveryStateDigest: digest, resolutionDigest: String(repeating: "4", count: 64), observation: foreign, decisionGroups: groups),
            .storageIOUnavailable(store: .workflow, errorCode: .fileFsyncFailed),
            .installationAuthorityUnavailable(errorCode: KeychainUnavailableCode.allCases.first { $0.rawValue == "KEYCHAIN_ADD_FAILED" }!),
            .installationAuthorityInvalid,
            .doseMalformed(recoveryStateDigest: digest, bytesSHA256: String(repeating: "5", count: 64), byteLength: 12)
        ]
        for snapshot in snapshots {
            let controls = RecoverySurfacePresentation.actions(for: snapshot)
            let expectedNames = snapshot.availableActions.filter { $0 != "recover_epoch" }
            #expect(controls.map(\.action.name) == expectedNames, Comment(rawValue: "\(snapshot.state): \(controls.map(\.action.name))"))
            #expect(controls.allSatisfy { $0.store == snapshot.store }, Comment(rawValue: "\(snapshot.state) store"))
            for control in controls {
                switch control.expectation {
                case let .digest(d): #expect(d == digest && snapshot.recoveryStateDigest == digest)
                case let .unavailable(token): #expect(token.store == snapshot.store && token.state == snapshot.state && snapshot.recoveryStateDigest == nil)
                }
                #expect(control.action.attemptKey(expecting: control.expectation) != nil, Comment(rawValue: "\(snapshot.state)/\(control.action.name) derives its key"))
            }
        }
        #expect(RecoverySurfacePresentation.actions(for: snapshots[0]).map(\.title) == ["Recover", "Discard quarantine"])
        #expect(RecoverySurfacePresentation.actions(for: snapshots[4]).map(\.title) == ["Merge", "Discard quarantine"])
        #expect(RecoverySurfacePresentation.actions(for: snapshots[5]).first?.action == .reconcile(mismatchIdentityDigest: String(repeating: "9", count: 64)))
        #expect(RecoverySurfacePresentation.actions(for: snapshots[7]).first?.action == .foreignReconcile)
        #expect(RecoverySurfacePresentation.actions(for: snapshots[9]).first?.expectation == .unavailable(UnavailableToken(store: .workflow, state: "storage_io_unavailable", errorCode: "FILE_FSYNC_FAILED")))
        #expect(RecoverySurfacePresentation.actions(for: snapshots[11]).first?.title == "Repair installation identity")
        #expect(RecoverySurfacePresentation.actions(for: snapshots[12]).first?.title == "Quarantine dose bytes")
        // resolve is disabled until every group has a choice; then the choices ride in displayed order
        let pending = RecoverySurfacePresentation.actions(for: snapshots[8])
        #expect(pending.count == 1 && pending[0].enabled == false && pending[0].title == "Resolve")
        let chosen = RecoverySurfacePresentation.actions(for: snapshots[8], foreignChoices: [groups[0].decisionDigest: "continue", groups[1].decisionDigest: "restart"])
        guard case let .resolve(resolution, choices) = chosen[0].action else { Issue.record("resolve"); return }
        #expect(chosen[0].enabled && resolution == String(repeating: "4", count: 64) && choices.count == 2 && choices[0].contains("\"choice\":\"continue\""))
        // epoch options: only the actionable epoch is enabled; every occupant is displayed
        let options = RecoverySurfacePresentation.epochOptions(for: snapshots[6])
        #expect(options.map(\.expectedTaskGenerationEpoch) == [1, 2] && options.map(\.enabled) == [true, false] && options[0].recoveryAction == .resumeServerDeletion && options[0].recoveryStateDigest == digest)
        #expect(RecoverySurfacePresentation.epochOptions(for: snapshots[0]).isEmpty)
        #expect(RecoverySurfacePresentation.stateCopy(snapshots[6]) == "Reset store: reset epoch conflict" && RecoverySurfacePresentation.stateCopy(snapshots[12]) == "Daily dose store: malformed")
        #expect(RecoverySurfacePresentation.deletionCopy(.queued) == (AccountDeletionCompletionCopy.queued, true))
        #expect(RecoverySurfacePresentation.deletionCopy(.blocked(.localPrivacyPurgeFailed)) == (AccountDeletionCompletionCopy.telemetryRelaunch, true))
        #expect(RecoverySurfacePresentation.deletionCopy(.guarding(authGuardAfter: DeletionWires.authGuardAfter)).retry == false)
    }

    @Test func completionSurfaceContentIsExactForEveryResultInAppleThenGoogleOrder() {
        let none = CompletionSurfaceContent.content(for: .completed(appleRevocation: .notRequired, googleRevocation: .revoked))
        #expect(none == CompletionSurfaceContent(title: "Account deleted", body: "Your Peezy account was deleted.", button: "Done", sections: []))
        let both = CompletionSurfaceContent.content(for: .completed(appleRevocation: .manualRequired, googleRevocation: .manualRequired))
        #expect(both.sections.map(\.provider) == [.apple, .google])
        #expect(both.sections[0] == CompletionSurfaceContent.Section(provider: .apple, paragraph: AccountDeletionCompletionCopy.appleManual, linkTitle: "Apple instructions", url: URL(string: "https://support.apple.com/102571")!))
        #expect(both.sections[1] == CompletionSurfaceContent.Section(provider: .google, paragraph: AccountDeletionCompletionCopy.googleManual, linkTitle: "Google instructions", url: URL(string: "https://support.google.com/accounts/answer/13533235?hl=en")!))
        #expect(CompletionSurfaceContent.content(for: .completed(appleRevocation: .notRequired, googleRevocation: .manualRequired)).sections.map(\.provider) == [.google])
        #expect(CompletionSurfaceContent.content(for: .localCleared) == CompletionSurfaceContent(title: "Account deleted", body: "This account was deleted from another device. This device has been cleared.", button: "Done", sections: []))
        #expect(CompletionSurfaceContent.content(for: .remoteUnconfirmed) == CompletionSurfaceContent(title: "Deletion not verified", body: "Local data for this account was removed, but remote account deletion could not be verified. Sign in again to retry if the account still exists.", button: "Done", sections: []))
    }

    @MainActor @Test func recoveryModelWiresActionsThroughTheDriverCoordinatorAndPresenter() async throws {
        let h = try makeDeletionHarness(auth: signedInA, dispositions: AccountDeletionProviderDispositions(appleRevocation: .manualRequired, googleRevocation: .notRequired, googleProviderUid: nil))
        let defaults = try isolatedDefaults()
        let dose = DailyDoseLocalStore(defaults: defaults)
        defaults.set(Data("{".utf8), forKey: DailyDoseLocalStore.key(uid: "A"))
        let workflow = ScriptedStoreOwner(store: .workflow, observation: .observed(.files(store: .workflow, baseState: "quarantined", target: .absent, quarantine: .malformed(byteLength: 3, bytesSHA256: String(repeating: "e", count: 64)), availableActions: ["discard_quarantine"])))
        let (reset, _) = await ResetFixtures.registry(h.directory, auth: signedInA)
        try ResetFixtures.envelope(records: [ResetFixtures.row(uid: "A", epoch: 1), ResetFixtures.row(uid: "A", epoch: 2, createdAt: "2026-09-06T12:00:01.000Z", suggested: "rsa1_33333333-3333-4333-8333-333333333333")]).write(to: ResetFixtures.target(h.directory))
        let driver = DurableStoreRecoveryDriver(owners: DurableStoreOwners(route: ScriptedStoreOwner(store: .route), handoff: ScriptedStoreOwner(store: .handoff), reset: reset, workflow: workflow), dose: dose, currentUID: UIDProbe("A")) { _, _ in }
        let model = DurableStoreRecoveryModel(driver: driver, epochRecovery: reset, coordinator: h.coordinator, presenter: h.completion)
        h.remote.script("begin", .failure(.retryRequired))
        #expect(await h.coordinator.startDeletion(uid: "A") == .settled(.queued))
        await model.refresh()
        #expect(model.deletion == .queued && model.completion == nil)
        #expect(model.blocked.map(\.store) == [.reset, .workflow, .dose], "frozen order; the surface mounts with stores blocked")
        // a blocked-store action reaches only its owner and reclassifies
        let control = try #require(RecoverySurfacePresentation.actions(for: model.blocked[1].snapshot).first)
        workflow.set(.observed(.files(store: .workflow, baseState: "ready", target: .absent, quarantine: .absent, availableActions: [])))
        #expect(await model.perform(control) == .ready && workflow.performedActions == ["discard_quarantine"])
        #expect(model.blocked.map(\.store) == [.reset, .dose] && model.lastResult == .ready)
        // the dose action through DailyDoseLocalStore
        let doseControl = try #require(RecoverySurfacePresentation.actions(for: model.blocked[1].snapshot).first)
        #expect(await model.perform(doseControl) == .ready && defaults.data(forKey: DailyDoseLocalStore.key(uid: "A")) == nil)
        // the epoch option: only the actionable epoch runs its own reducer branch; without S7's bundle the registry answers unavailable
        let options = RecoverySurfacePresentation.epochOptions(for: model.blocked[0].snapshot)
        #expect(options.map(\.enabled) == [true, false])
        #expect(await model.recover(options[1]) == .unavailable(store: .reset), "a later epoch is displayed but disabled")
        #expect(await model.recover(options[0]) == .unavailable(store: .reset) && model.lastResult == .unavailable(store: .reset))
        // the deletion Retry through the coordinator, then the completion surface through the presenter: links never consume, Done consumes
        h.remote.always("begin", .success(DeletionWires.dataFinal("x")))
        h.remote.script("finalize", .success(DeletionWires.guarding("x")), .success(DeletionWires.deleted("x")))
        #expect(await model.retryDeletion() == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        #expect(model.deletion == .guarding(authGuardAfter: DeletionWires.authGuardAfter) && RecoverySurfacePresentation.deletionCopy(model.deletion!).retry == false)
        guard case .settled(.completion(let snapshot))? = await model.retryDeletion() else { Issue.record("completed"); return }
        #expect(model.completion == snapshot && CompletionSurfaceContent.content(for: snapshot.result).sections.map(\.provider) == [.apple])
        let appleOpen = await model.open(.apple)
        let googleOpen = await model.open(.google)
        #expect(appleOpen == .opened && googleOpen == .notOffered)
        #expect(model.completion == snapshot && h.signOut.calls.isEmpty, "links never consume")
        #expect(await model.acknowledgeCompletion() == .acknowledged)
        #expect(model.completion == nil && model.deletion == nil && h.signOut.calls == ["A"] && h.gate.gates.last == .clear)
        #expect(await model.acknowledgeCompletion() == nil)
    }

    // MARK: - S4 I8 — the analytics collection gate (C2.2 telemetry barrier) and the fixed-parameter sink rule

    @Test func analyticsCollectionGateClosesOnTheTelemetryBarrierAndOnlyFixedScalarParametersReachTheSDK() async {
        #expect(AnalyticsEvents.sanitized(nil) == nil)
        let cleaned = AnalyticsEvents.sanitized(["dayNumber": 3, "uid": "A", "path": "users/A", "trigger": "book", "flagged": true, "cubicFeet": 1.5, "itemCount": ["nested": 1], "error": NSError(domain: "x", code: 1)])
        #expect(Set(cleaned.map { Array($0.keys) } ?? []) == ["dayNumber", "trigger", "flagged", "cubicFeet"], "no UID, path, nested value, or error object leaves the process")
        let gate = AnalyticsEvents.CollectionGate()
        #expect(!gate.isSuspended)
        gate.suspend()
        #expect(gate.isSuspended)
        // the client telemetry barrier closes the process-wide gate before its first SDK call
        let sdk = RecordingTelemetrySDK()
        let authority = ClientTelemetryPrivacyAuthority(sdk: sdk, lifetime: TelemetryPrivacyLifetime())
        let purge = Task { await authority.purgeAll() }
        while !sdk.calls.contains("checkForUnsentReports") { await Task.yield() }
        #expect(AnalyticsEvents.isSuspended, "the gate closes before the first SDK call completes")
        // the double stores its continuation right after recording the call; a duplicate callback loses the CAS harmlessly
        for _ in 0..<3 { for _ in 0..<20 { await Task.yield() }; sdk.complete(false) }
        #expect(await purge.value == .cleared)
    }

    // MARK: - S4 I10 — inventory scope: §8.9.3 admission at the InventoryAPIClient call sites (S4-CD6), narration and media leases (S4-CD7)

    @MainActor @Test func inventoryAdmissionRequiresTheCurrentUIDAndAClearGateAndDiscardsAHeldResponseAfterTheGateChanges() async throws {
        // the pure admission over every gate member and a UID mismatch
        for gate in [AccountDeletionGate.loading, .blocked, .active(uid: "A"), .active(uid: "B"), .guarding(uid: "A", authGuardAfter: DeletionWires.authGuardAfter), .guarding(uid: "B", authGuardAfter: DeletionWires.authGuardAfter)] {
            #expect(!InventorySessionManager.admits(currentUID: "A", requestUID: "A", gate: gate), Comment(rawValue: "\(gate)"))
        }
        #expect(InventorySessionManager.admits(currentUID: "A", requestUID: "A", gate: .clear))
        #expect(!InventorySessionManager.admits(currentUID: "B", requestUID: "A", gate: .clear) && !InventorySessionManager.admits(currentUID: nil, requestUID: "A", gate: .clear))
        // the pinned three-argument initializer, the owner attached by the mount seam
        let gate = GateSnapshotStub()
        let owner = RoomCaptureArtifactOwner(gateSnapshot: gate.snapshot)
        let client = HoldableInventoryClient()
        let uid = UIDProbe("A")
        let manager = InventorySessionManager(coverageConfirmationStore: NoopCoverageStore(), userIDProvider: { uid.uid }, apiClient: client)
        manager.attachArtifactOwner(owner)
        let request = InventoryProcessingRequest(userId: "A", sessionId: "s1", roomName: "Kitchen", frameCount: 3, narration: nil)
        // a nonclear gate before the call: refused with zero calls
        gate.set(gate: .active(uid: "A"))
        await manager.processUploadedSession(request)
        #expect(client.requests.isEmpty && manager.error == "Scanning is paused while your account is being cleared." && !manager.movePassRequired)
        // a different current UID: refused with zero calls
        gate.set(gate: .clear)
        uid.uid = "B"
        await manager.processUploadedSession(request)
        #expect(client.requests.isEmpty)
        uid.uid = "A"
        // admitted: the entitlement denial is applied when nothing changed during the call
        client.setDenying(true)
        await manager.processUploadedSession(request)
        #expect(client.requests == ["A/s1"] && manager.movePassRequired)
        manager.discardRetainedProcessingRequest()
        #expect(!manager.movePassRequired)
        // a held response across a gate change is discarded, never applied
        client.setHold()
        let held = Task { await manager.processUploadedSession(request) }
        while !client.isHolding { await Task.yield() }
        gate.set(gate: .active(uid: "A"))
        client.release()
        await held.value
        #expect(client.requests.count == 2 && !manager.movePassRequired, "the denial that arrived after the gate closed was not applied")
        // a held response across an account change is discarded too
        gate.set(gate: .clear)
        client.setHold()
        let switched = Task { await manager.processUploadedSession(request) }
        while !client.isHolding { await Task.yield() }
        uid.uid = "B"
        client.release()
        await switched.value
        #expect(client.requests.count == 3 && !manager.movePassRequired)
    }

    @MainActor @Test func narrationStartsOnlyUnderALeaseAndTheOwnerResolvesLeasesByIdForTheSessionManager() async {
        let gate = GateSnapshotStub()
        let owner = RoomCaptureArtifactOwner(gateSnapshot: gate.snapshot)
        let lease = await owner.acquire(uid: "A", sessionId: "Kitchen")
        let issued = lease!
        let resolved = await owner.lease(withId: issued.leaseId)
        let missing = await owner.lease(withId: "missing")
        #expect(resolved == issued && missing == nil)
        let gateNow = await owner.currentGate()
        #expect(gateNow.gate == .clear && gateNow.generation == issued.gateGeneration)
        let narration = NarrationService()
        #expect(narration.activeLease == nil)
        narration.start(lease: issued)
        #expect(narration.activeLease == issued, "the recording runs under the actor-issued lease (listening itself needs the microphone authorization)")
        await owner.revokeAll()
        let afterRevoke = await owner.lease(withId: issued.leaseId)
        let reissued = await owner.acquire(uid: "A", sessionId: "Kitchen")
        #expect(afterRevoke == nil && reissued == nil, "after revocation no lease resolves or is issued")
    }

    // MARK: - S4 I11 — the named static tests (C10 D29), the Open 3 fixture, the S4 Firestore gate

    @Test("UID-interpolated preference keys are registry-complete") func uidInterpolatedPreferenceKeysAreRegistryComplete() throws {
        let registry = PreferenceBarrier.uidScopedTemplates
        #expect(registry == ["phase1.pendingRetakeOperation.{uid}", "peezy.{uid}.dailyDose.completedCount", "peezy.{uid}.dailyDose.lastDate", "peezy.{uid}.dailyDose.firstLaunchDate", "peezy.{uid}.dailyDose.v2", "peezy.{uid}.hasSeenFirstTimeWelcome", "peezy.{uid}.lastGreetingDate", "peezy.{uid}.totalCompletedCount", "inventory.scanCoaching.seen.{uid}", "inventory.narrationOffer.seen.{uid}", "peezy.{uid}.dailyDose.v2.quarantine"])
        // every string literal in the app source that interpolates a UID-like expression and names a preference prefix must be a registry key
        let literal = try NSRegularExpression(pattern: #""([^"\n]*\\\([^)]*\)[^"\n]*)""#)
        let uidLike = try NSRegularExpression(pattern: #"\\\((?:[^)]*)(uid|userId|userID|accountID|resolvedUserId)"#, options: [.caseInsensitive])
        var offenders: [String] = []
        var found: Set<String> = []
        for file in try appSourceFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in literal.matches(in: source, range: range) {
                guard let inner = Range(match.range(at: 1), in: source) else { continue }
                let text = String(source[inner])
                guard uidLike.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil,
                      text.hasPrefix("peezy.") || text.hasPrefix("phase1.") || text.hasPrefix("inventory.") else { continue }
                // normalize the UID-like interpolation; any other interpolation parameterizes the tail
                var normalized = ""
                var rest = Substring(text)
                while let open = rest.range(of: "\\(") {
                    normalized += rest[..<open.lowerBound]
                    guard let close = rest[open.upperBound...].firstIndex(of: ")") else { break }
                    let expression = rest[open.upperBound..<close]
                    normalized += uidLike.firstMatch(in: "\\(" + expression, range: NSRange(location: 0, length: expression.utf16.count + 2)) != nil ? "{uid}" : "{param}"
                    rest = rest[rest.index(after: close)...]
                }
                normalized += rest
                found.insert(normalized)
                if normalized.contains("{param}") {
                    let prefix = String(normalized[..<normalized.range(of: "{param}")!.lowerBound])
                    if !registry.contains(where: { $0.hasPrefix(prefix) }) { offenders.append("\(file.lastPathComponent): \(text)") }
                } else if !registry.contains(normalized) {
                    offenders.append("\(file.lastPathComponent): \(text)")
                }
            }
        }
        #expect(offenders.isEmpty, Comment(rawValue: "UID-interpolated keys outside the eleven-key registry: \(offenders)"))
        #expect(found.contains("peezy.{uid}.dailyDose.v2") && found.contains("inventory.narrationOffer.seen.{uid}"), "the scan sees the app's keys")
        // Open 3 fixture: the global first name goes with a UID deletion only while Firebase still names that UID or no different UID is established
        let defaults = try isolatedDefaults()
        defaults.set("Adam", forKey: PreferenceBarrier.globalFirstNameKey)
        #expect(PreferenceBarrier.run(scope: .uid("A"), defaults: defaults, currentFirebaseUID: "B") == .acknowledged && defaults.string(forKey: PreferenceBarrier.globalFirstNameKey) == "Adam")
        #expect(PreferenceBarrier.run(scope: .uid("A"), defaults: defaults, currentFirebaseUID: "A") == .acknowledged && defaults.string(forKey: PreferenceBarrier.globalFirstNameKey) == nil)
        defaults.set("Adam", forKey: PreferenceBarrier.globalFirstNameKey)
        #expect(PreferenceBarrier.run(scope: .uid("A"), defaults: defaults, currentFirebaseUID: nil) == .acknowledged && defaults.string(forKey: PreferenceBarrier.globalFirstNameKey) == nil)
    }

    @Test("Release call graph and adversarial NSError are sink-free") func releaseCallGraphAndAdversarialNSErrorAreSinkFree() async throws {
        // the Release product of every S4-owned file has no unguarded print/debugPrint/dump/NSLog/os_log with a dynamic argument
        let sink = try NSRegularExpression(pattern: #"\b(print|debugPrint|dump|NSLog|os_log)\("#)
        var offenders: [String] = []
        for relative in s4OwnedProductionFiles {
            let source = try String(contentsOf: repositoryRoot().appendingPathComponent(relative), encoding: .utf8)
            var debugDepth = 0
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#if DEBUG") { debugDepth += 1; continue }
                if trimmed.hasPrefix("#endif"), debugDepth > 0 { debugDepth -= 1; continue }
                guard debugDepth == 0, !trimmed.hasPrefix("//"), sink.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil, line.contains("\\(") else { continue }
                offenders.append("\(relative):\(index + 1)")
            }
        }
        #expect(offenders.isEmpty, Comment(rawValue: "Release sinks with dynamic arguments: \(offenders)"))
        // an adversarial NSError (UID and path in its domain and description) never reaches a trace, a log, or an analytics parameter
        let directory = try temporaryDirectory()
        let owners = RecordingPurgeOwners()
        let purge = LocalPrivacyPurgeCoordinator(directory: directory, clock: ResetClockStub(), owners: owners.owners, defaults: try isolatedDefaults(), currentUID: UIDProbe(nil), telemetry: TelemetryStub())
        let completion = AccountDeletionCompletionPresentation(directory: directory, clock: ResetClockStub(), consume: { _ in true }, opener: { _ in true })
        let coordinator = DurableStoreRecoveryCoordinator(DurableStoreRecoveryCoordinator.Dependencies(directory: directory, clock: ResetClockStub(), auth: SignedAuthStub(signedInA), remote: AdversarialDeletionRemote(), providerContext: DispositionsStub(value: AccountDeletionProviderDispositions(appleRevocation: .notRequired, googleRevocation: .notRequired, googleProviderUid: nil)), purge: purge, completion: completion, gate: GateSpy(), signOutMatchingUser: { _ in true }))
        #expect(await coordinator.startDeletion(uid: "A") == .settled(.blocked(.remoteUnavailable)))
        let trace = await coordinator.trace
        #expect(trace.contains("error:unknown") && !trace.joined().contains(AdversarialDeletionRemote.secret) && !trace.joined().contains("users/"))
        let purgeLog = await purge.log
        #expect(!purgeLog.joined().contains(AdversarialDeletionRemote.secret))
        let adversarial = NSError(domain: "users/\(AdversarialDeletionRemote.secret)", code: 1)
        #expect(AnalyticsEvents.sanitized(["dayNumber": 1, "error": adversarial, "uid": AdversarialDeletionRemote.secret])?.keys.sorted() == ["dayNumber"])
        // every trace entry of the deletion coordinator is a fixed code path: no path separators, no UUIDs beyond the fixed grammar
        #expect(trace.allSatisfy { !$0.contains("/") })
    }

    @Test("Firebase Auth keychain item is absent after terminal detach", .enabled(if: FirebaseEmulator.isConfigured))
    func firebaseAuthKeychainItemIsAbsentAfterTerminalDetach() async throws {
        _ = try FirebaseEmulator.firestore()
        let signedIn = try await Auth.auth().signInAnonymously()
        let uid = signedIn.user.uid
        // a user item persisted by an earlier app configuration (a different Firebase app name) must not outlive the account either
        let stale: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "firebase_auth_1:stale:ios:test", kSecAttrAccount as String: "firebase_auth_stale_firebase_user", kSecValueData as String: Data("stale-user".utf8)]
        SecItemDelete(stale as CFDictionary)
        #expect(SecItemAdd(stale as CFDictionary, nil) == errSecSuccess)
        #expect(Auth.auth().currentUser?.uid == uid && firebaseAuthKeychainServices().count >= 2, "the emulator user and the stale item are persisted in the keychain")
        // the coordinator's terminal consumption signs out only a matching Firebase user through the S7-wired closure
        let directory = try temporaryDirectory()
        let owners = RecordingPurgeOwners()
        let purge = LocalPrivacyPurgeCoordinator(directory: directory, clock: ResetClockStub(), owners: owners.owners, defaults: try isolatedDefaults(), currentUID: UIDProbe(uid), telemetry: TelemetryStub())
        let box = ConsumeBox()
        let completion = AccountDeletionCompletionPresentation(directory: directory, clock: ResetClockStub(), consume: { snapshot in await box.coordinator?.consumeTerminal(snapshot) ?? false }, opener: { _ in true })
        let remote = ScriptedDeletionRemote()
        remote.always("begin", .success(DeletionWires.dataFinal("x")))
        remote.script("finalize", .success(DeletionWires.guarding("x")), .success(DeletionWires.deleted("x")))
        let auth = SignedAuthStub(.signedIn(SignedAuthTuple(uid: uid, authEpochUUID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", credentialRevision: 1)))
        let coordinator = DurableStoreRecoveryCoordinator(DurableStoreRecoveryCoordinator.Dependencies(directory: directory, clock: ResetClockStub(), auth: auth, remote: remote, providerContext: DispositionsStub(value: AccountDeletionProviderDispositions(appleRevocation: .notRequired, googleRevocation: .notRequired, googleProviderUid: nil)), purge: purge, completion: completion, gate: GateSpy(), signOutMatchingUser: { expected in
            guard Auth.auth().currentUser?.uid == expected else { return Auth.auth().currentUser == nil }
            try? Auth.auth().signOut()
            return Auth.auth().currentUser == nil
        }))
        box.coordinator = coordinator
        #expect(await coordinator.startDeletion(uid: uid) == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        guard case .settled(.completion(let snapshot)) = await coordinator.retry() else { Issue.record("completed"); return }
        #expect(await completion.acknowledge(expectedGenerationId: snapshot.generationId, expectedSHA256: snapshot.sha256) == .acknowledged)
        let survivors = firebaseAuthKeychainServices()
        #expect(Auth.auth().currentUser == nil && survivors.isEmpty, Comment(rawValue: "no Firebase Auth keychain item survives the terminal detach: \(survivors)"))
    }

    @Test func s4OwnedFilesAcquireFirestoreOnlyThroughTheRuntimeSeam() throws {
        var hits: [String] = []
        for relative in s4OwnedProductionFiles where !relative.hasSuffix("LocalPrivacyPurgeCoordinator.swift") {
            let source = try String(contentsOf: repositoryRoot().appendingPathComponent(relative), encoding: .utf8)
            for (index, line) in source.components(separatedBy: "\n").enumerated() where line.contains("Firestore.firestore()") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                hits.append("\(relative):\(index + 1)")
            }
        }
        #expect(hits.isEmpty, Comment(rawValue: "production Firestore.firestore() in S4-owned files: \(hits)"))
    }

    // MARK: - S4 close-out review fixes (Swift concurrency pass)

    @Test func everyCoordinatorEntryReservesTheSingleflightSlotBeforeItsFirstSuspension() async throws {
        let h = try makeDeletionHarness(auth: signedInA)
        h.remote.always("begin", .success(DeletionWires.dataFinal("x")))
        h.remote.always("finalize", .failure(.retryRequired))
        h.owners.setHoldRoute()
        // an auth transition parks on its first await (the gate hop, then the held route owner); a concurrent startDeletion joins the slot
        let transition = Task { await h.coordinator.authTransition() }
        for _ in 0..<20 { await Task.yield() }
        let deletion = Task { await h.coordinator.startDeletion(uid: "A") }
        for _ in 0..<20 { await Task.yield() }
        h.owners.releaseRoute()
        let transitionResult = await transition.value
        let deletionResult = await deletion.value
        #expect(h.remote.actions.filter { $0 == "begin" }.count <= 1, "one reducer at most dispatched begin; the joiner never installed a second task over the slot")
        #expect(transitionResult == deletionResult || deletionResult == .busy || transitionResult == .clear)
        let intent = await h.coordinator.currentIntent()
        #expect(intent == nil || intent?.uid == "A")
        // consumption reserves the slot before the sign-out await: a concurrent retry joins it and the intent is consumed exactly once
        let c = try makeDeletionHarness(auth: signedInA)
        c.remote.always("begin", .success(DeletionWires.dataFinal("x")))
        c.remote.script("finalize", .success(DeletionWires.guarding("x")), .success(DeletionWires.deleted("x")))
        _ = await c.coordinator.startDeletion(uid: "A")
        guard case .settled(.completion(let snapshot)) = await c.coordinator.retry() else { Issue.record("completed"); return }
        c.owners.setHoldRoute()
        let acknowledge = Task { await c.completion.acknowledge(expectedGenerationId: snapshot.generationId, expectedSHA256: snapshot.sha256) }
        while !c.owners.isHoldingRoute { await Task.yield() }
        let retry = Task { await c.coordinator.retry() }
        for _ in 0..<20 { await Task.yield() }
        c.owners.releaseRoute()
        #expect(await acknowledge.value == .acknowledged)
        #expect(await retry.value == .clear, "the retry joined the consumption and saw its result")
        #expect(c.signOut.calls == ["A"] && c.gate.gates.last == .clear && c.gate.terminals.last! == nil)
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

    // MARK: - Coordinator (D30; S3 replaces the S1 interim cases, Decision 10). The three
    // properties the interim cases proved hold under the drive path: callback order, the server
    // seeing one operation identity, and a failed finalize resuming with that identity.

    @Test func retakeReservesFirstThenDrivesTheExactTraceAndPostsOnce() async throws {
        let wires = try frozenResetWires()
        let (registry, _) = try await preparedRegistry()
        let remote = ScriptedResetRemote(wires: wires)
        let trace = DriveTrace()
        let notifications = NotificationCounter()
        let coordinator = RetakeAssessmentCoordinator(
            currentUser: { "A" }, remote: remote, registry: registry,
            gestureId: { "rsg1_11111111-1111-4111-8111-111111111111" },
            cleanup: await trace.callbacks(), postNotification: { await notifications.bump(); await trace.record("notification") }
        )
        let handle = try #require(await registry.snapshot().records.first).handleId
        await remote.attach(trace, registry: registry, handle: ResetOperationHandle(uid: "A", handleId: handle))
        try await coordinator.retake()
        #expect(await trace.order == ["resetDispatch", "inspect", "deleteAssessments", "inspect", "deleteUserKnowledge", "inspect", "resetDose", "inspect", "finalize", "notification"])
        let aliases = await remote.aliases
        #expect(aliases.count == 2 && Set(aliases).count == 1 && aliases[0].hasPrefix("rsa1_"), "the server sees one operation identity: the row's alias")
        #expect(await notifications.count == 1)
        #expect(await registry.snapshot().records.isEmpty)
    }

    @Test func retakeFailureLeavesARowAndTheNextRetakeResumesWithTheSameAlias() async throws {
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
        let row = try #require(await registry.snapshot().records.first)
        #expect(row.phase == .finalizeDispatched && row.recoveryAction == .retryFinalize)
        #expect(await notifications.count == 0)
        await trace.clear()
        try await coordinator.retake()
        #expect(await trace.order == ["finalize", "notification"], "the resumed retake replays only finalize from the durable phase")
        let aliases = await remote.aliases
        #expect(aliases.count == 3 && Set(aliases).count == 1, "reset, failed finalize, and the resumed finalize carry one alias")
        #expect(await notifications.count == 1)
        #expect(await registry.snapshot().records.isEmpty)
    }

    @Test func retakePostsNoNotificationWhenAnotherDeviceFinalized() async throws {
        let wires = try frozenResetWires()
        let (registry, handle) = try await preparedRegistry()
        let remote = ScriptedResetRemote(wires: wires)
        await remote.setCommittedAtInspection(1)
        let trace = DriveTrace()
        await remote.attach(trace, registry: registry, handle: handle)
        let notifications = NotificationCounter()
        let coordinator = RetakeAssessmentCoordinator(
            currentUser: { "A" }, remote: remote, registry: registry,
            gestureId: { "rsg1_11111111-1111-4111-8111-111111111111" },
            cleanup: await trace.callbacks(), postNotification: { await notifications.bump(); await trace.record("notification") }
        )
        try await coordinator.retake()
        #expect(await trace.order == ["resetDispatch", "inspect"], "committed inspection short-circuits the trace suffix")
        #expect(await notifications.count == 0, "a replayed final receipt never posts")
        #expect(await registry.snapshot().records.isEmpty)
    }

    @Test func retakeNeverSendsALegacyOperationIdAndHoldsNoIdentityOfItsOwn() async throws {
        let wires = try frozenResetWires()
        let (registry, handle) = try await preparedRegistry()
        let remote = ScriptedResetRemote(wires: wires)
        let trace = DriveTrace()
        await remote.attach(trace, registry: registry, handle: handle)
        let coordinator = RetakeAssessmentCoordinator(
            currentUser: { "A" }, remote: remote, registry: registry,
            gestureId: { "rsg1_11111111-1111-4111-8111-111111111111" },
            cleanup: await trace.callbacks(), postNotification: {}
        )
        let alias = try #require(await registry.snapshot().records.first).suggestedOperationId
        try await coordinator.retake()
        let aliases = await remote.aliases
        #expect(aliases.allSatisfy { $0 == alias && ResetOperationRegistry.isAlias($0) }, "only the actor-owned alias reaches the server; no UserDefaults identity exists")
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Peezy 4.0/MainInterface/Models/RetakeAssessmentCoordinator.swift"), encoding: .utf8)
        #expect(source.contains("operationStore") == false && source.contains("UserDefaults") == false)
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
        #expect(authority.requestFingerprint == wires.string("requestFingerprint") && authority.deletedCount == awaiting.deletedCount && authority.deletedCounts == awaiting.deletedCounts)
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
        #expect(outcome.replayed == false && outcome.notify == true && outcome.finalReceipt.kind == .final)
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
        #expect(outcome.replayed == true && outcome.notify == false && outcome.finalReceipt.replayed == true)
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
        #expect(resumed.replayed == false && resumed.notify == true)
        // Resume after the other device finalized: the first inspection is committed, no callback runs.
        let (registry2, handle2) = try await preparedRegistry()
        let remote2 = ScriptedResetRemote(wires: wires)
        let trace2 = DriveTrace()
        await remote2.attach(trace2, registry: registry2, handle: handle2)
        await trace2.setFailing("deleteAssessments")
        await #expect(throws: DriveTraceError.failed) { _ = try await registry2.drive(handle: handle2, remote: remote2, cleanup: trace2.callbacks()) }
        await remote2.setCommittedAtInspection(3) // the failed first drive consumed inspection 1 and its post-error re-inspection 2
        await trace2.setFailing(nil)
        await trace2.clear()
        let adopted = try await registry2.drive(handle: handle2, remote: remote2, cleanup: trace2.callbacks())
        #expect(await trace2.order == ["inspect"] && adopted.replayed == true && adopted.notify == false)
        #expect(await registry2.snapshot().records.isEmpty)
    }

    /// C9.5.14 "after callback error": the same invocation re-inspects; committed → adopt the final receipt and skip forever.
    @Test func driveAdoptsACommittedRecordInTheSameInvocationAfterACallbackError() async throws {
        let (registry, handle) = try await preparedRegistry()
        let remote = ScriptedResetRemote(wires: try frozenResetWires())
        let trace = DriveTrace()
        await remote.attach(trace, registry: registry, handle: handle)
        await trace.setFailing("deleteAssessments")
        await remote.setCommittedAtInspection(2) // the post-error re-inspection observes the other device's commit
        let outcome = try await registry.drive(handle: handle, remote: remote, cleanup: trace.callbacks())
        #expect(await trace.order == ["resetDispatch", "inspect", "deleteAssessments", "inspect"], "one post-error inspection, no further callback")
        #expect(outcome.replayed == true && outcome.notify == false)
        #expect(await registry.snapshot().records.isEmpty)
    }

    /// C9.5.12: the winner revalidates signed auth after every suspension (drift → frozen auth branch, phase preserved,
    /// no later call or callback); a second call on the same handle joins the winner's outcome and never invokes its own callbacks.
    @Test func driveFreezesOnAuthDriftAfterASuspensionAndASecondCallJoinsWithoutItsOwnCallbacks() async throws {
        let wires = try frozenResetWires()
        let directory = try temporaryDirectory()
        let auth = SignedAuthStub(.signedIn(tupleA))
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: auth, epochAuthority: EpochStub(epoch: 1))
        guard case let .binding(reservation) = try await registry.reserve(gestureId: "rsg1_11111111-1111-4111-8111-111111111111") else { Issue.record("reserve"); return }
        let handle = try await registry.bind(reservation: reservation)
        let remote = ScriptedResetRemote(wires: wires)
        let trace = DriveTrace()
        await remote.attach(trace, registry: registry, handle: handle)
        // auth drift while the dispatch is in flight
        await remote.setHoldDispatch()
        let winner = Task { try await registry.drive(handle: handle, remote: remote, cleanup: await trace.callbacks()) }
        while await remote.heldCount == 0 { await Task.yield() }
        auth.set(.signedIn(tupleB))
        await remote.releaseHeld()
        await #expect(throws: ResetOperationRegistry.RegistryError.authRequired) { _ = try await winner.value }
        #expect(await trace.order == ["resetDispatch"], "no call or callback after auth drift")
        let row = try #require(await registry.snapshot().records.first)
        #expect(row.phase == .resetDispatched, "durable phase preserved")
        // join: the same auth again; a second call on the handle joins the in-flight drive
        auth.set(.signedIn(tupleA))
        await trace.clear()
        await remote.setHoldDispatch()
        let first = Task { try await registry.drive(handle: handle, remote: remote, cleanup: await trace.callbacks()) }
        while await remote.heldCount == 0 { await Task.yield() }
        let readsBefore = auth.reads
        let joinerTrace = DriveTrace()
        let joiner = Task { try await registry.drive(handle: handle, remote: remote, cleanup: await joinerTrace.callbacks()) }
        while auth.reads == readsBefore { await Task.yield() }
        await remote.releaseHeld()
        let outcome = try await first.value
        let joined = try await joiner.value
        #expect(joined.finalReceipt == outcome.finalReceipt && joined.replayed == outcome.replayed, "the joiner receives the winner's outcome")
        #expect(outcome.notify == true && joined.notify == false, "C9.5.17: only the winner notifies; a joiner never does")
        #expect(await joinerTrace.order.isEmpty, "the joiner never invokes its own callbacks")
        #expect(await trace.order == ["resetDispatch", "inspect", "deleteAssessments", "inspect", "deleteUserKnowledge", "inspect", "resetDose", "inspect", "finalize"], "exactly one callback bundle ran")
        #expect(await remote.finalizeCalls == 1)
        #expect(await registry.snapshot().records.isEmpty)
    }

    /// C9.5.8 foreign caller: while A's drive is in flight and the account is B, a call on A's handle waits for the slot,
    /// discards A's result, rereads auth, and restarts (then A's handle is stale for B) instead of rejecting immediately.
    @Test(arguments: [SignedAuthAuthority.signedIn(tupleB), SignedAuthAuthority.signedOut])
    func foreignCallerWaitsForTheInFlightSlotBeforeItsHandleIsJudged(foreignAuth: SignedAuthAuthority) async throws {
        let directory = try temporaryDirectory()
        let auth = SignedAuthStub(.signedIn(tupleA))
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: auth, epochAuthority: EpochStub(epoch: 1))
        guard case let .binding(reservation) = try await registry.reserve(gestureId: "rsg1_11111111-1111-4111-8111-111111111111") else { Issue.record("reserve"); return }
        let handle = try await registry.bind(reservation: reservation)
        let remote = ScriptedResetRemote(wires: try frozenResetWires())
        let trace = DriveTrace()
        await remote.attach(trace, registry: registry, handle: handle)
        await remote.setHoldDispatch()
        let winner = Task { try await registry.drive(handle: handle, remote: remote, cleanup: await trace.callbacks()) }
        while await remote.heldCount == 0 { await Task.yield() }
        auth.set(foreignAuth)
        let readsBefore = auth.reads
        let settled = NotificationCounter()
        let foreign = Task { defer { Task { await settled.bump() } }; return try await registry.drive(handle: handle, remote: remote, cleanup: await DriveTrace().callbacks()) }
        while auth.reads == readsBefore { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        // the foreign caller is still waiting for the slot to retire; it is not answered while the slot is occupied
        #expect(await settled.count == 0, "a foreign caller waits for slot retirement instead of being rejected immediately")
        await remote.releaseHeld()
        let winnerResult = await winner.result
        let foreignResult = await foreign.result
        guard case .failure = winnerResult else { Issue.record("the winner drifted to B and must return the auth branch"); return }
        let expected: ResetOperationRegistry.RegistryError = foreignAuth == .signedOut ? .authRequired : .operationStale(uid: "A", handleId: handle.handleId)
        guard case let .failure(foreignError) = foreignResult, let registryError = foreignError as? ResetOperationRegistry.RegistryError, registryError == expected else {
            Issue.record("after the slot retires, the foreign caller restarts: signed out → the auth branch; another account → A's handle is stale"); return
        }
        #expect(await trace.order == ["resetDispatch"], "no call or callback ran for either caller after the switch")
    }

    /// C9.5.8 post-task reread: a joiner rereads signed auth after the winner's task settles, even when the task threw;
    /// an account switch in that window returns the frozen auth branch instead of the winner's error.
    @Test func joinerRereadsAuthAfterAThrowingWinnerAndReturnsTheAuthBranchOnDrift() async throws {
        // calibration run: the same schedule with a steady auth; the last read is the joiner's post-task reread
        func scenario(_ auth: SignedAuthStub) async throws -> (winner: Result<ResetDriveOutcome, Error>, joiner: Result<ResetDriveOutcome, Error>) {
            let directory = try temporaryDirectory()
            let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: auth, epochAuthority: EpochStub(epoch: 1))
            guard case let .binding(reservation) = try await registry.reserve(gestureId: "rsg1_11111111-1111-4111-8111-111111111111") else { throw DriveTraceError.failed }
            let handle = try await registry.bind(reservation: reservation)
            let remote = ScriptedResetRemote(wires: try frozenResetWires())
            let trace = DriveTrace()
            await remote.attach(trace, registry: registry, handle: handle)
            await trace.setFailing("deleteAssessments")
            await remote.setHoldDispatch()
            let winner = Task { try await registry.drive(handle: handle, remote: remote, cleanup: await trace.callbacks()) }
            while await remote.heldCount == 0 { await Task.yield() }
            let readsBefore = auth.reads
            let joiner = Task { try await registry.drive(handle: handle, remote: remote, cleanup: await DriveTrace().callbacks()) }
            while auth.reads == readsBefore { await Task.yield() }
            await remote.releaseHeld()
            return (await winner.result, await joiner.result)
        }
        let steady = SignedAuthStub(.signedIn(tupleA))
        let calibration = try await scenario(steady)
        #expect((try? calibration.winner.get()) == nil && (try? calibration.joiner.get()) == nil, "both callers see the callback failure under steady auth")
        let lastRead = steady.reads
        let switching = SignedAuthStub(.signedIn(tupleA))
        switching.switchOnRead(lastRead, to: .signedIn(tupleB))
        let drifted = try await scenario(switching)
        guard case let .failure(winnerError) = drifted.winner, winnerError is DriveTraceError else { Issue.record("the winner propagates the callback error"); return }
        guard case let .failure(joinerError) = drifted.joiner, let registryError = joinerError as? ResetOperationRegistry.RegistryError, registryError == .authRequired else {
            Issue.record("the joiner must reread auth after the winner's task and return the auth branch, not the winner's error"); return
        }
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
        // No attached bundle: the action is unavailable and no byte changes.
        #expect(await registry.recoverEpoch(recoveryStateDigest: digest, expectedTaskGenerationEpoch: 1, expectedPhase: .prepared, action: .retryReset) == .unavailable(store: .reset))
        #expect(await registry.snapshot().records.count == 3)
        // The actionable row's own reducer branch runs; the other occupants are untouched; completion reclassifies.
        let wires = try frozenResetWires()
        let remote = ScriptedResetRemote(wires: wires)
        let trace = DriveTrace()
        let actionableRow = try #require(await registry.snapshot().records.first { $0.uid == "A" && $0.expectedTaskGenerationEpoch == 1 })
        await remote.attach(trace, registry: registry, handle: ResetOperationHandle(uid: "A", handleId: actionableRow.handleId))
        await registry.attachRecovery(ResetRecoveryBundle(remote: remote, cleanup: await trace.callbacks()))
        #expect(await registry.recoverEpoch(recoveryStateDigest: digest, expectedTaskGenerationEpoch: 1, expectedPhase: .prepared, action: .retryReset) == .ready)
        let remaining = await registry.snapshot().records
        #expect(remaining.map { "\($0.uid)|\($0.expectedTaskGenerationEpoch)" }.sorted() == ["A|3", "B|0"], "the driven row is retired; the other occupants are untouched")
        #expect(await trace.order == ["resetDispatch", "inspect", "deleteAssessments", "inspect", "deleteUserKnowledge", "inspect", "resetDose", "inspect", "finalize"])
        #expect(await registry.classification() == .ready)
        #expect(await registry.recoverEpoch(recoveryStateDigest: digest, expectedTaskGenerationEpoch: 1, expectedPhase: .prepared, action: .retryReset) == .ready)
    }

    /// Contract single slot: one shared `(key, Task)` per store owner; exact key equality coalesces;
    /// a different key is `busy` before any callback, call, or write.
    @Test func recoverEpochCoalescesAnIdenticalInFlightCallAndAnswersADifferentKeyBusyBeforeAnyCall() async throws {
        let directory = try temporaryDirectory()
        try writeEnvelopeRows(directory, rows: [(uid: "B", epoch: 0, createdAt: "2026-09-06T09:00:00.000Z"), (uid: "A", epoch: 3, createdAt: "2026-09-06T10:00:00.000Z"), (uid: "A", epoch: 1, createdAt: "2026-09-06T11:00:00.000Z")])
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: SignedAuthStub(.signedIn(tupleA)), epochAuthority: EpochStub(epoch: 0))
        guard case let .blocked(.resetEpochConflict(digest, actionable, _)) = await registry.classification() else { Issue.record("expected conflict"); return }
        let wires = try frozenResetWires()
        let remote = ScriptedResetRemote(wires: wires)
        let trace = DriveTrace()
        let actionableRow = try #require(await registry.snapshot().records.first { $0.uid == "A" && $0.expectedTaskGenerationEpoch == actionable })
        await remote.attach(trace, registry: registry, handle: ResetOperationHandle(uid: "A", handleId: actionableRow.handleId))
        await registry.attachRecovery(ResetRecoveryBundle(remote: remote, cleanup: await trace.callbacks()))
        await remote.setHoldDispatch()
        let first = Task { await registry.recoverEpoch(recoveryStateDigest: digest, expectedTaskGenerationEpoch: actionable, expectedPhase: .prepared, action: .retryReset) }
        while await remote.heldCount == 0 { await Task.yield() }
        let same = Task { await registry.recoverEpoch(recoveryStateDigest: digest, expectedTaskGenerationEpoch: actionable, expectedPhase: .prepared, action: .retryReset) }
        #expect(await registry.recoverEpoch(recoveryStateDigest: digest, expectedTaskGenerationEpoch: actionable, expectedPhase: .prepared, action: .applyFinal) == .busy(store: .reset), "a different key is busy while the slot is occupied")
        #expect(await trace.order == ["resetDispatch"], "the busy answer performs no callback or call")
        await remote.releaseHeld()
        #expect(await first.value == .ready)
        #expect(await same.value == .ready, "an identical call coalesces onto the in-flight attempt")
        #expect(await trace.order == ["resetDispatch", "inspect", "deleteAssessments", "inspect", "deleteUserKnowledge", "inspect", "resetDose", "inspect", "finalize"], "exactly one drive ran")
        #expect(await remote.finalizeCalls == 1)
        #expect(await registry.classification() == .ready)
    }

    @Test func dailyDoseCleanupWritesTheEmptyFloorAtTheResultEpochAndStaleWritersDrift() async throws {
        let defaults = try isolatedDefaults()
        let store = DailyDoseLocalStore(defaults: defaults)
        _ = await store.ensure(uid: "A", taskGenerationEpoch: 1)
        guard case .committed = await store.mutate(uid: "A", expectedTaskGenerationEpoch: 1, expectedRevision: 0, { $0.completedCount = 4; $0.lastDate = "2026-09-05" }) else { Issue.record("seed"); return }
        let cleaned = await store.cleanup(uid: "A", taskGenerationEpoch: 2)
        let floor = DailyDoseLocalStateV1(taskGenerationEpoch: 2, revision: 2, completedCount: 0, lastDate: nil, firstLaunchDate: nil)
        #expect(cleaned == .cleaned(floor), "older epoch → exact empty epoch-r state with revision + 1")
        #expect(await store.load(uid: "A") == .present(floor))
        guard case .drift = await store.mutate(uid: "A", expectedTaskGenerationEpoch: 1, expectedRevision: 1, { $0.completedCount = 9 }) else { Issue.record("stale writer must drift"); return }
        #expect(await store.load(uid: "A") == .present(floor))
        #expect(await store.cleanup(uid: "A", taskGenerationEpoch: 2) == .preserved(floor), "equal epoch → preserve")
        #expect(await store.cleanup(uid: "A", taskGenerationEpoch: 1) == .drift(current: floor), "newer epoch → preserve and report drift")
        let absentFloor = DailyDoseLocalStateV1(taskGenerationEpoch: 3, revision: 0, completedCount: 0, lastDate: nil, firstLaunchDate: nil)
        #expect(await store.cleanup(uid: "Z", taskGenerationEpoch: 3) == .cleaned(absentFloor), "absent → empty epoch-r floor")
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
        installSharedRuntimeIfNeeded() // S4-CD2
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
        try await FirebaseEmulator.adminSet("users/\(uid)/user_assessments/a1", ["task_generation_epoch": 1, "name": "one"])
        try await FirebaseEmulator.adminSet("users/\(uid)/user_assessments/a2", ["task_generation_epoch": 0, "name": "two"])
        try await FirebaseEmulator.adminSet("users/\(uid)/user_assessments/kept", ["task_generation_epoch": 2, "name": "already at r"])
        try await FirebaseEmulator.adminSet("users/\(uid)/user_assessments/unstamped", ["name": "no stamp"])
        try await FirebaseEmulator.adminSet("userKnowledge/\(uid)", ["task_generation_epoch": 1, "entries": [:]])

        // A wrong authority (another operation) writes nothing.
        var foreign = progress; foreign["operationId"] = "rso1_" + String(repeating: "0", count: 40)
        var foreignPending = pending; foreignPending["authority"] = ["operationId": "rso1_" + String(repeating: "0", count: 40)]
        let foreignPendingDecoded = try ResetInspectionV1.decode(foreignPending)
        let foreignDecoded = try ResetReceiptV1.decode(foreign)
        let wrong = try #require(ResetLocalCleanupAuthorityV1(inspection: foreignPendingDecoded, progress: foreignDecoded))
        await #expect(throws: ResetCleanupError.markerMismatch) { try await ResetLocalCleanupV1.deleteAssessments(authority: wrong) }
        await #expect(throws: ResetCleanupError.markerMismatch) { try await ResetLocalCleanupV1.deleteUserKnowledge(authority: wrong) }
        await #expect(throws: ResetCleanupError.markerMismatch) { try await DailyDoseEngine().resetForRetake(authority: wrong, localStore: DailyDoseLocalStore(defaults: try isolatedDefaults())) }
        #expect(try await firestore.collection("users").document(uid).collection("user_assessments").getDocuments().documents.count == 4)
        #expect(try await firestore.collection("userKnowledge").document(uid).getDocument().exists)

        // The exact authority deletes stamps below r in their own marker-checked transactions, preserves the stamp at r,
        // and an unstamped document outside the 0→1 bridge is preserved and blocks finalization.
        await #expect(throws: ResetCleanupError.localGenerationInvalid(path: "users/\(uid)/user_assessments/unstamped")) { try await ResetLocalCleanupV1.deleteAssessments(authority: authority) }
        let afterAssessments = try await firestore.collection("users").document(uid).collection("user_assessments").getDocuments().documents.map(\.documentID).sorted()
        #expect(afterAssessments == ["kept", "unstamped"])
        try await FirebaseEmulator.adminSet("users/\(uid)/user_assessments/unstamped", ["task_generation_epoch": 1, "name": "now stamped"])
        try await ResetLocalCleanupV1.deleteAssessments(authority: authority)
        try await ResetLocalCleanupV1.deleteUserKnowledge(authority: authority)
        let defaults = try isolatedDefaults()
        defaults.set(5, forKey: "peezy.\(uid).dailyDose.completedCount")
        let localStore = DailyDoseLocalStore(defaults: defaults)
        _ = await localStore.ensure(uid: uid, taskGenerationEpoch: 1)
        try await DailyDoseEngine().resetForRetake(authority: authority, localStore: localStore)
        #expect(try await firestore.collection("users").document(uid).collection("user_assessments").getDocuments().documents.map(\.documentID) == ["kept"])
        #expect(try await firestore.collection("userKnowledge").document(uid).getDocument().exists == false)
        let root = try await firestore.collection("users").document(uid).getDocument().data()
        #expect(root?["dailyDose"] == nil && root?["taskReset"] != nil)
        #expect(await localStore.load(uid: uid) == .present(DailyDoseLocalStateV1(taskGenerationEpoch: 2, revision: 1, completedCount: 0, lastDate: nil, firstLaunchDate: nil)))
        #expect(defaults.object(forKey: "peezy.\(uid).dailyDose.completedCount") == nil)
        // C9.5.16: malformed v2 bytes block (preserved, legacy keys untouched); a newer epoch is preserved and reported as drift
        let malformedDefaults = try isolatedDefaults()
        malformedDefaults.set(Data("{".utf8), forKey: DailyDoseLocalStore.key(uid: uid))
        malformedDefaults.set(5, forKey: "peezy.\(uid).dailyDose.completedCount")
        let malformedStore = DailyDoseLocalStore(defaults: malformedDefaults)
        await #expect(throws: ResetCleanupError.localDoseMalformed) { try await DailyDoseEngine().resetForRetake(authority: authority, localStore: malformedStore) }
        #expect(malformedDefaults.integer(forKey: "peezy.\(uid).dailyDose.completedCount") == 5, "legacy keys preserved under malformed v2")
        #expect(await malformedStore.load(uid: uid) == .malformed)
        let driftDefaults = try isolatedDefaults()
        let driftStore = DailyDoseLocalStore(defaults: driftDefaults)
        _ = await driftStore.ensure(uid: uid, taskGenerationEpoch: 3)
        await #expect(throws: ResetCleanupError.localDoseDrift(currentEpoch: 3)) { try await DailyDoseEngine().resetForRetake(authority: authority, localStore: driftStore) }
        #expect(await driftStore.load(uid: uid) == .present(DailyDoseLocalStateV1(taskGenerationEpoch: 3, revision: 0, completedCount: 0, lastDate: nil, firstLaunchDate: nil)), "newer epoch preserved")
    }

}

/// S4-CD2: the shared registry must hold an owner before any acquisition; installs the production owner over the
/// emulator once per test process (`alreadyInstalled` tolerated).
func installSharedRuntimeIfNeeded() {
    guard !FirestoreRuntime.shared.isInstalled else { return }
    _ = FirestoreRuntime.install(FirestoreRuntimeOwner(controller: FirebaseFirestoreInstanceController()))
}

/// Records the owner's purge order over the real (emulator) instance without terminating it.
final class RecordingInstanceController: FirestoreInstanceControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var failProbe = false
    var failTerminate = false
    var order: [String] { lock.withLock { recorded } }
    private func record(_ step: String) { lock.withLock { recorded.append(step) } }
    func initial() -> Firestore { Firestore.firestore() }
    func terminateAndClearPersistence(_ firestore: Firestore) async throws {
        record("terminateAndClearPersistence")
        if failTerminate { throw DriveTraceError.failed }
    }
    func fresh() -> Firestore { record("fresh"); return Firestore.firestore() }
    func probe(_ firestore: Firestore) async throws {
        record("probe")
        if failProbe { throw DriveTraceError.failed }
    }
}

/// Records the telemetry barrier's SDK calls; the completion is driven by the test.
final class RecordingTelemetrySDK: TelemetryPrivacySDK, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var pending: (@Sendable (Bool) -> Void)?
    var calls: [String] { lock.withLock { recorded } }
    private func record(_ call: String) { lock.withLock { recorded.append(call) } }
    func setAnalyticsCollectionEnabled(_ enabled: Bool) { record("setAnalyticsCollectionEnabled(\(enabled))") }
    func setUserID(_ userID: String?) { record("setUserID(\(userID ?? "nil"))") }
    func setUserProperty(_ value: String?, forName name: String) { record("setUserProperty(\(value ?? "nil"),\(name))") }
    func resetAnalyticsData() { record("resetAnalyticsData") }
    func checkForUnsentReports(_ completion: @escaping @Sendable (Bool) -> Void) { record("checkForUnsentReports"); lock.withLock { pending = completion } }
    func deleteUnsentReports() { record("deleteUnsentReports") }
    /// Delivers the callback (possibly more than once) from the test.
    func complete(_ hasUnsent: Bool) { let completion: (@Sendable (Bool) -> Void)? = lock.withLock { pending }; completion?(hasUnsent) }
    var hasPendingCallback: Bool { lock.withLock { pending != nil } }
}

/// A mutable gate snapshot for the room-capture owner.
final class GateSnapshotStub: @unchecked Sendable {
    private let lock = NSLock()
    private var gate: AccountDeletionGate
    private var generation: GateGeneration
    init(gate: AccountDeletionGate = .clear, generation: UInt64 = 1) { self.gate = gate; self.generation = GateGeneration(rawValue: generation) }
    func set(gate: AccountDeletionGate? = nil, generation: UInt64? = nil) {
        lock.withLock { if let gate { self.gate = gate }; if let generation { self.generation = GateGeneration(rawValue: generation) } }
    }
    var snapshot: RoomCaptureArtifactOwner.GateSnapshot { { [self] in self.lock.withLock { (self.gate, self.generation) } } }
}

/// Records the eight purge owners' calls in order; one owner can be made to fail or to wait on a gate.
final class RecordingPurgeOwners: RouteAccountDeletionPurging, HandoffAccountDeletionPurging, ResetAccountDeletionPurging, WorkflowAccountDeletionPurging, RoomCaptureArtifactPurging, FirestoreLocalCachePurging, NotificationIdentityPurging, GoogleIdentityControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var failing: Set<String> = []
    private var holdRoute: CheckedContinuation<Void, Never>?
    private var routeHeld = false
    var calls: [String] { lock.withLock { recorded } }
    func fail(_ owner: String, _ on: Bool = true) { lock.withLock { if on { failing.insert(owner) } else { failing.remove(owner) } } }
    func setHoldRoute() { lock.withLock { routeHeld = true } }
    var isHoldingRoute: Bool { lock.withLock { holdRoute != nil } }
    func releaseRoute() { let held: CheckedContinuation<Void, Never>? = lock.withLock { defer { holdRoute = nil; routeHeld = false }; return holdRoute }; held?.resume() }
    private func ack(_ owner: String, scope: LocalPurgeScope) -> LocalPurgeAck {
        let scopeText: String
        switch scope { case .all: scopeText = "all"; case let .uid(uid): scopeText = uid }
        return lock.withLock { recorded.append("\(owner)(\(scopeText))"); return failing.contains(owner) ? .failed : .acknowledged }
    }
    func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck {
        // the route conformance: the first owner, optionally held so a second request can queue behind it
        let shouldHold: Bool = lock.withLock { routeHeld }
        if shouldHold { await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in lock.withLock { holdRoute = continuation } } }
        return ack("route", scope: scope)
    }
    var handoff: any HandoffAccountDeletionPurging { Delegate(self, "handoff") }
    var reset: any ResetAccountDeletionPurging { Delegate(self, "reset") }
    var workflow: any WorkflowAccountDeletionPurging { Delegate(self, "workflow") }
    var roomCapture: any RoomCaptureArtifactPurging { Delegate(self, "room_capture") }
    var firestoreCache: any FirestoreLocalCachePurging { Delegate(self, "firestore_cache") }
    var notifications: any NotificationIdentityPurging { Delegate(self, "notifications") }
    struct Delegate: HandoffAccountDeletionPurging, ResetAccountDeletionPurging, WorkflowAccountDeletionPurging, RoomCaptureArtifactPurging, FirestoreLocalCachePurging, NotificationIdentityPurging, @unchecked Sendable {
        let owners: RecordingPurgeOwners
        let name: String
        init(_ owners: RecordingPurgeOwners, _ name: String) { self.owners = owners; self.name = name }
        func purgeForAccountDeletion(scope: LocalPurgeScope) async -> LocalPurgeAck { owners.ack(name, scope: scope) }
    }
    // GoogleIdentityControlling
    func currentProviderUID() async -> String? { nil }
    func handle(_ url: URL) async -> GoogleURLHandleOutcomeV1 { .notHandled }
    func signIn() async -> GoogleFirebaseSignInOutcomeV1 { .cancelled }
    func disconnect(expectedProviderUID: String) async -> GoogleCredentialOutcomeV1 {
        lock.withLock { recorded.append("google.disconnect(\(expectedProviderUID))"); return failing.contains("google") ? .failed : .disconnected }
    }
    func signOutAll() async -> GoogleCredentialOutcomeV1 {
        lock.withLock { recorded.append("google.signOutAll"); return failing.contains("google") ? .failed : .signedOut }
    }
    var owners: LocalPurgeOwners { LocalPurgeOwners(route: self, handoff: handoff, reset: reset, workflow: workflow, roomCapture: roomCapture, firestoreCache: firestoreCache, notifications: notifications, google: self) }
}

final class TelemetryStub: ClientTelemetryPrivacyPurging, @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: ClientTelemetryPurgeOutcomeV1
    private(set) var calls = 0
    init(_ outcome: ClientTelemetryPurgeOutcomeV1 = .cleared) { self.outcome = outcome }
    func set(_ value: ClientTelemetryPurgeOutcomeV1) { lock.withLock { outcome = value } }
    func purgeAll() async -> ClientTelemetryPurgeOutcomeV1 { lock.withLock { calls += 1; return outcome } }
}

actor OpenedURLs {
    private(set) var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
}

func link(_ context: PurgeProviderContextV1) -> TerminalDeletionLinkV1 {
    TerminalDeletionLinkV1(deletionOperationId: context.deletionOperationId, deletionProofSHA256: context.deletionProofSHA256)
}

/// Scripted `AccountDeletionRemoteProviding`: per-action outcome queues, a per-action fallback, one holdable action.
final class ScriptedDeletionRemote: AccountDeletionRemoteProviding, @unchecked Sendable {
    typealias Outcome = Result<AccountDeletionRemoteResultV1, AccountDeletionRemoteError>
    private let lock = NSLock()
    private var queues: [String: [Outcome]] = [:]
    private var fallbacks: [String: Outcome] = [:]
    private var recorded: [AccountDeletionRequestV1] = []
    private var heldAction: String?
    private var continuation: CheckedContinuation<Void, Never>?
    var requests: [AccountDeletionRequestV1] { lock.withLock { recorded } }
    var actions: [String] { requests.map(\.action) }
    func script(_ action: String, _ outcomes: Outcome...) { lock.withLock { queues[action, default: []].append(contentsOf: outcomes) } }
    func always(_ action: String, _ outcome: Outcome) { lock.withLock { fallbacks[action] = outcome } }
    func hold(_ action: String) { lock.withLock { heldAction = action } }
    var isHolding: Bool { lock.withLock { continuation != nil } }
    func release() {
        let held: CheckedContinuation<Void, Never>? = lock.withLock { defer { continuation = nil; heldAction = nil }; return continuation }
        held?.resume()
    }
    func perform(_ request: AccountDeletionRequestV1) async throws -> AccountDeletionRemoteResultV1 {
        let shouldHold: Bool = lock.withLock { recorded.append(request); return heldAction == request.action }
        if shouldHold { await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in lock.withLock { continuation = c } } }
        let outcome: Outcome? = lock.withLock {
            if var queue = queues[request.action], !queue.isEmpty { let next = queue.removeFirst(); queues[request.action] = queue; return next }
            return fallbacks[request.action]
        }
        switch outcome {
        case let .success(value)?: return value
        case let .failure(error)?: throw error
        case nil: throw AccountDeletionRemoteError.protocolAmbiguity
        }
    }
}

enum DeletionWires {
    static let startedAt = "2026-09-06T11:59:00.000Z"
    static let dataDeletedAt = "2026-09-06T11:59:30.000Z"
    static let authGuardAfter = "2026-09-13T11:59:30.000Z"
    static func dataFinal(_ operationId: String, replayed: Bool = false) -> AccountDeletionRemoteResultV1 {
        .dataFinal(AccountDeletionDataFinalWireV1(operationId: operationId, authorityKind: .member, startedAt: startedAt, dataDeletedAt: dataDeletedAt, replayed: replayed))
    }
    static func guarding(_ operationId: String) -> AccountDeletionRemoteResultV1 {
        .authGuarding(AccountDeletionAuthGuardingWireV1(operationId: operationId, authorityKind: .member, startedAt: startedAt, dataDeletedAt: dataDeletedAt, authAbsenceObservedAt: dataDeletedAt, authGuardAfter: authGuardAfter, replayed: false))
    }
    static func deleted(_ operationId: String) -> AccountDeletionRemoteResultV1 {
        .accountDeleted(AccountDeletionAccountDeletedWireV1(operationId: operationId, authorityKind: .member, startedAt: startedAt, dataDeletedAt: dataDeletedAt, authAbsenceObservedAt: dataDeletedAt, authGuardAfter: authGuardAfter, authGuardCompletedAt: authGuardAfter, accountDeletedAt: authGuardAfter, replayed: true))
    }
}

final class GateSpy: AccountDeletionGateControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var gateLog: [AccountDeletionGate] = []
    private var terminalLog: [TerminalPresentationKind?] = []
    var gates: [AccountDeletionGate] { lock.withLock { gateLog } }
    var terminals: [TerminalPresentationKind?] { lock.withLock { terminalLog } }
    func setGate(_ gate: AccountDeletionGate) async { lock.withLock { gateLog.append(gate) } }
    func setPendingTerminalPresentation(_ kind: TerminalPresentationKind?) async { lock.withLock { terminalLog.append(kind) } }
}

struct DispositionsStub: AccountDeletionProviderContextProviding {
    let value: AccountDeletionProviderDispositions
    func dispositions(expectedUID: String) async -> AccountDeletionProviderDispositions { value }
}

/// Lets the completion presenter's `consume` reach the coordinator constructed after it (S7 wires production the same way).
final class ConsumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var target: DurableStoreRecoveryCoordinator?
    var coordinator: DurableStoreRecoveryCoordinator? {
        get { lock.withLock { target } }
        set { lock.withLock { target = newValue } }
    }
}

final class SignOutRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var outcome = true
    var calls: [String] { lock.withLock { recorded } }
    func set(_ value: Bool) { lock.withLock { outcome = value } }
    func signOut(_ uid: String) -> Bool { lock.withLock { recorded.append(uid); return outcome } }
}

/// One coordinator over seam fakes: scripted remote, recording owners, gate spy, isolated defaults, temp directory.
struct DeletionHarness {
    let coordinator: DurableStoreRecoveryCoordinator
    let signOut: SignOutRecorder
    let remote: ScriptedDeletionRemote
    let gate: GateSpy
    let owners: RecordingPurgeOwners
    let auth: SignedAuthStub
    let clock: ResetClockStub
    let telemetry: TelemetryStub
    let purge: LocalPrivacyPurgeCoordinator
    let completion: AccountDeletionCompletionPresentation
    let directory: URL
    var intentURL: URL { directory.appendingPathComponent(AccountDeletionIntentStore.fileName) }
    func intentBytes() -> Data? { try? Data(contentsOf: intentURL) }
}

func makeDeletionHarness(auth: SignedAuthAuthority, dispositions: AccountDeletionProviderDispositions = AccountDeletionProviderDispositions(appleRevocation: .notRequired, googleRevocation: .sdkDisconnectRequired, googleProviderUid: "g1"), directory: URL? = nil) throws -> DeletionHarness {
    let directory = try directory ?? temporaryDirectory()
    let remote = ScriptedDeletionRemote()
    let box = ConsumeBox()
    let signOut = SignOutRecorder()
    let gate = GateSpy()
    let owners = RecordingPurgeOwners()
    let authStub = SignedAuthStub(auth)
    let clock = ResetClockStub()
    let telemetry = TelemetryStub()
    let purge = LocalPrivacyPurgeCoordinator(directory: directory, clock: clock, owners: owners.owners, defaults: try isolatedDefaults(), currentUID: UIDProbe(nil), telemetry: telemetry)
    let completion = AccountDeletionCompletionPresentation(directory: directory, clock: clock, consume: { snapshot in await box.coordinator?.consumeTerminal(snapshot) ?? false }, opener: { _ in true })
    let coordinator = DurableStoreRecoveryCoordinator(DurableStoreRecoveryCoordinator.Dependencies(directory: directory, clock: clock, auth: authStub, remote: remote, providerContext: DispositionsStub(value: dispositions), purge: purge, completion: completion, gate: gate, signOutMatchingUser: { uid in signOut.signOut(uid) }))
    box.coordinator = coordinator
    return DeletionHarness(coordinator: coordinator, signOut: signOut, remote: remote, gate: gate, owners: owners, auth: authStub, clock: clock, telemetry: telemetry, purge: purge, completion: completion, directory: directory)
}

let signedInA = SignedAuthAuthority.signedIn(SignedAuthTuple(uid: "A", authEpochUUID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", credentialRevision: 3))

func exactIntent(phase: AccountDeletionPhase, staged: AccountDeletionStagedRoot? = nil, detach: AccountDeletionDetachReason? = nil) -> AccountDeletionIntentV1 {
    let authority = [AccountDeletionPhase.dataConfirmed, .purging, .authFinalizeDispatched, .guarding].contains(phase) || (phase == .localDetaching && staged != nil)
    let allAcks = [AccountDeletionPhase.authFinalizeDispatched, .guarding, .completed, .localCleared].contains(phase)
    return AccountDeletionIntentV1(
        uid: "A", authEpochUUID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", credentialRevision: 3,
        operationId: "adel1_11111111-1111-4111-8111-111111111111", proofNonce: String(repeating: "x", count: 43),
        dispositions: AccountDeletionProviderDispositions(appleRevocation: .notRequired, googleRevocation: .sdkDisconnectRequired, googleProviderUid: "g1"),
        phase: phase, purpose: phase == .prepared ? .confirmedBegin : nil, authorityKind: authority ? .member : nil, detachReason: detach, stagedRoot: staged,
        startedAt: authority ? DeletionWires.startedAt : nil, dataDeletedAt: authority ? DeletionWires.dataDeletedAt : nil,
        authGuardAfter: phase == .guarding || staged == .authGuarding ? DeletionWires.authGuardAfter : nil,
        acks: allAcks ? PurgeOwner.order : [], createdAt: "2026-09-06T12:00:00.000Z", updatedAt: "2026-09-06T12:00:00.000Z")
}

/// A scripted `DurableStoreRecovering` owner for the stores S5/S7 conform (route, handoff, workflow).
final class ScriptedStoreOwner: DurableStoreRecovering, @unchecked Sendable {
    let store: DurableStore
    private let lock = NSLock()
    private var observation: RecoveryObservation
    private var result: RecoveryResult = .ready
    private var performed: [String] = []
    init(store: DurableStore, observation: RecoveryObservation? = nil) {
        self.store = store
        self.observation = observation ?? .observed(.files(store: store, baseState: "ready", target: .absent, quarantine: .absent, availableActions: []))
    }
    func set(_ value: RecoveryObservation) { lock.withLock { observation = value } }
    func setResult(_ value: RecoveryResult) { lock.withLock { result = value } }
    var performedActions: [String] { lock.withLock { performed } }
    func observe() async -> RecoveryObservation { lock.withLock { observation } }
    func classify(_ observation: RecoveryObservation) -> RecoveryClassification {
        switch observation {
        case let .unavailable(token):
            return .blocked(.storageIOUnavailable(store: store, errorCode: StorageIOErrorCode(rawValue: token.errorCode) ?? .fileReadFailed))
        case let .observed(state):
            guard case let .files(_, base, _, _, _, _, _, _, _, enumerable, count, _) = state, base != "ready" else { return .ready }
            return .blocked(.quarantined(store: store, recoveryStateDigest: state.recoveryStateDigest, quarantineEnumerable: enumerable, pendingRecordCount: count))
        }
    }
    func perform(_ action: RecoveryAction, expecting expectation: RecoveryExpectation) async -> RecoveryResult {
        lock.withLock { performed.append(action.name); return result }
    }
}

final class InstallationIdentityStub: InstallationIdentityProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var loadResult: InstallationIdentityLoadResult
    private var repaired: [String] = []
    init(_ loadResult: InstallationIdentityLoadResult) { self.loadResult = loadResult }
    func set(_ value: InstallationIdentityLoadResult) { lock.withLock { loadResult = value } }
    var repairs: [String] { lock.withLock { repaired } }
    func load() async -> InstallationIdentityLoadResult { lock.withLock { loadResult } }
    func addIfAbsent(_ candidate: String) async -> InstallationIdentityAddResult { .inserted(candidate) }
    func rekeyEmptyContainer(_ candidate: String) async -> InstallationIdentityRekeyResult { .rekeyed(candidate) }
    func repairInvalid(_ candidate: String) async -> InstallationIdentityRepairResult {
        lock.withLock { repaired.append(candidate); loadResult = .present(candidate); return .repaired(candidate) }
    }
}

/// A handoff owner fake whose only authority is the Keychain seam: Retry repeats the load, Repair runs `repairInvalid`.
final class KeychainHandoffOwner: DurableStoreRecovering, @unchecked Sendable {
    let identity: InstallationIdentityStub
    init(identity: InstallationIdentityStub) { self.identity = identity }
    func observe() async -> RecoveryObservation {
        switch await identity.load() {
        case .error: return .unavailable(UnavailableToken(store: .handoff, state: "installation_authority_unavailable", errorCode: "KEYCHAIN_LOAD_FAILED"))
        case .invalid: return .unavailable(UnavailableToken(store: .handoff, state: "installation_authority_invalid", errorCode: "KEYCHAIN_VALUE_INVALID"))
        case .absent, .present: return .observed(.files(store: .handoff, baseState: "ready", target: .absent, quarantine: .absent, availableActions: []))
        }
    }
    func classify(_ observation: RecoveryObservation) -> RecoveryClassification {
        switch observation {
        case let .unavailable(token) where token.state == "installation_authority_invalid": return .blocked(.installationAuthorityInvalid)
        case let .unavailable(token): return .blocked(.installationAuthorityUnavailable(errorCode: KeychainUnavailableCode.allCases.first { $0.rawValue == token.errorCode }!))
        case .observed: return .ready
        }
    }
    func perform(_ action: RecoveryAction, expecting expectation: RecoveryExpectation) async -> RecoveryResult {
        guard action.attemptKey(expecting: expectation) != nil else { return .unavailable(store: .handoff) }
        if case .repairInstallationIdentity = action { _ = await identity.repairInvalid(UUID().uuidString.lowercased()) }
        switch classify(await observe()) {
        case .ready: return .ready
        case let .blocked(snapshot): return .blocked(snapshot)
        }
    }
}

/// Inspection-only reset remote: scripted `inspectReset` outcomes, everything else refused.
final class InspectionRemote: ResetRemoteProviding, @unchecked Sendable {
    enum Script { case committed(ResetReceiptV1), absent, pending, transport }
    private let lock = NSLock()
    private var scripts: [Script] = []
    private var recorded: [String] = []
    var calls: [String] { lock.withLock { recorded } }
    func script(_ next: Script) { lock.withLock { scripts.append(next) } }
    func reset(_ action: ResetRemoteAction, alias: String, expectedTaskGenerationEpoch: Int) async throws -> ResetReceiptV1 { throw ResetRemoteError.protocolAmbiguity }
    func reconcileLegacyReset(legacyOperationId: String, migrationAlias: String) async throws -> LegacyResetReconciliationV1 { throw ResetRemoteError.protocolAmbiguity }
    func inspectReset(uid: String, canonicalOperationId: String, expectedTaskGenerationEpoch: Int) async throws -> ResetInspectionV1 {
        let next: Script? = lock.withLock { recorded.append("\(uid)|\(canonicalOperationId)|\(expectedTaskGenerationEpoch)"); return scripts.isEmpty ? nil : scripts.removeFirst() }
        let fingerprint = "reset1_" + String(repeating: "f", count: 64)
        let identity = ResetOperationRegistry.identityDigest(uid: uid, expectedTaskGenerationEpoch: expectedTaskGenerationEpoch)
        switch next {
        case let .committed(receipt)?: return ResetInspectionV1(accountUid: uid, operationId: canonicalOperationId, requestFingerprint: fingerprint, identityDigest: identity, outcome: .committed, receipt: receipt)
        case .absent?: return ResetInspectionV1(accountUid: uid, operationId: canonicalOperationId, requestFingerprint: fingerprint, identityDigest: identity, outcome: .absent, receipt: nil)
        case .pending?: return ResetInspectionV1(accountUid: uid, operationId: canonicalOperationId, requestFingerprint: fingerprint, identityDigest: identity, outcome: .pending, receipt: nil)
        case .transport?, nil: throw ResetRemoteError.transport
        }
    }
}

enum ResetFixtures {
    static let operationId = "rso1_" + String(repeating: "a", count: 40)
    static func finalReceipt(uid: String, epoch: Int, operationId: String = operationId) -> ResetReceiptV1 {
        ResetReceiptV1(kind: .final, operationId: operationId, replayed: true, accountUid: uid, expectedTaskGenerationEpoch: epoch, taskGenerationEpoch: epoch + 1,
                       activeMoveEventId: "me1_" + String(repeating: "b", count: 40), deletedCount: 0,
                       deletedCounts: ResetDeletedCountsV1(tasks: 0, notificationIntents: 0, taskDeadlineEvidence: 0, confirmationSnapshots: 0), state: .finalized)
    }
    static func row(uid: String, epoch: Int, createdAt: String = "2026-09-06T12:00:00.000Z", phase: String = "prepared", finalReceipt: ResetReceiptV1? = nil, suggested: String = "rsa1_11111111-1111-4111-8111-111111111111") -> [String: Any] {
        var map: [String: Any] = ["uid": uid, "suggestedOperationId": suggested, "expectedTaskGenerationEpoch": epoch, "phase": phase, "createdAt": createdAt, "updatedAt": createdAt]
        if let finalReceipt { map["canonicalOperationId"] = finalReceipt.operationId; map["finalReceipt"] = finalReceipt.map() }
        return map
    }
    static func envelope(records: [[String: Any]], migrations: [[String: Any]] = [], gesture: [String: Any]? = nil, receipt: [String: Any]? = nil) -> Data {
        var payload: [String: Any] = ["records": records, "legacyMigrations": migrations]
        if let gesture { payload["gesture"] = gesture }
        return DurableEnvelopeCodec.encode(fileKind: .taskPlanResetV2, generationId: UUID().uuidString.lowercased(), payload: payload, recoveryReceipt: receipt)!
    }
    static func registry(_ directory: URL, auth: SignedAuthAuthority, remote: (any ResetRemoteProviding)? = nil) async -> (ResetOperationRegistry, SignedAuthStub) {
        let stub = SignedAuthStub(auth)
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: stub, epochAuthority: EpochStub(epoch: 1))
        if let remote { await registry.attachRecovery(ResetRecoveryBundle(remote: remote, cleanup: ResetCleanupCallbacks(deleteAssessments: { _ in }, deleteUserKnowledge: { _ in }, resetDose: { _ in }))) }
        return (registry, stub)
    }
    static func target(_ directory: URL) -> URL { directory.appendingPathComponent(ResetOperationRegistry.fileName) }
    static func quarantine(_ directory: URL) -> URL { directory.appendingPathComponent(ResetOperationRegistry.quarantineFileName) }
}

/// A `UserDefaults` whose quarantine-array reads can be made to fail: proves the dose copy is verified before the v2 key goes.
final class VerificationFailingDefaults: UserDefaults, @unchecked Sendable {
    var failQuarantineReads = false
    override func array(forKey defaultName: String) -> [Any]? {
        if failQuarantineReads, defaultName.hasSuffix(".dailyDose.v2.quarantine") { return nil }
        return super.array(forKey: defaultName)
    }
}

/// Scripted legacy reconciliation/inspection remote for the C9.4.5 families; the reset messages are refused.
final class LegacyRemote: ResetRemoteProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var reconciles: [Result<LegacyResetReconciliationV1, ResetRemoteError>] = []
    private var inspections: [Result<LegacyResetInspectionV1, ResetRemoteError>] = []
    private var recorded: [String] = []
    var calls: [String] { lock.withLock { recorded } }
    func reconcile(_ outcome: Result<LegacyResetReconciliationV1, ResetRemoteError>) { lock.withLock { reconciles.append(outcome) } }
    func inspect(_ outcome: Result<LegacyResetInspectionV1, ResetRemoteError>) { lock.withLock { inspections.append(outcome) } }
    func reset(_ action: ResetRemoteAction, alias: String, expectedTaskGenerationEpoch: Int) async throws -> ResetReceiptV1 { throw ResetRemoteError.protocolAmbiguity }
    func inspectReset(uid: String, canonicalOperationId: String, expectedTaskGenerationEpoch: Int) async throws -> ResetInspectionV1 { throw ResetRemoteError.protocolAmbiguity }
    func reconcileLegacyReset(legacyOperationId: String, migrationAlias: String) async throws -> LegacyResetReconciliationV1 {
        let next: Result<LegacyResetReconciliationV1, ResetRemoteError>? = lock.withLock { recorded.append("reconcile:\(legacyOperationId)|\(migrationAlias)"); return reconciles.isEmpty ? nil : reconciles.removeFirst() }
        guard let next else { throw ResetRemoteError.transport }
        return try next.get()
    }
    func inspectLegacyReset() async throws -> LegacyResetInspectionV1 {
        let next: Result<LegacyResetInspectionV1, ResetRemoteError>? = lock.withLock { recorded.append("inspect"); return inspections.isEmpty ? nil : inspections.removeFirst() }
        guard let next else { throw ResetRemoteError.transport }
        return try next.get()
    }
}

enum LegacyFixtures {
    static let legacyA = "20000000-0000-4000-8000-000000000001"
    static let legacyB = "20000000-0000-4000-8000-000000000002"
    static func base(uid: String, legacy: String, alias: String, replayed: Bool = false) -> LegacyResetReconciliationV1.Base {
        LegacyResetReconciliationV1.Base(migrationId: LegacyResetReconciliationV1.migrationId(uid: uid, legacyOperationId: legacy), legacyOperationId: legacy, migrationAlias: alias, accountUid: uid, replayed: replayed)
    }
    static func progress(uid: String, epoch: Int, state: ResetReceiptState, replayed: Bool) -> ResetReceiptV1 {
        ResetReceiptV1(kind: .progress, operationId: "rso1_" + String(repeating: "d", count: 40), replayed: replayed, accountUid: uid, expectedTaskGenerationEpoch: epoch, taskGenerationEpoch: epoch + 1,
                       activeMoveEventId: "me1_" + String(repeating: "e", count: 40), deletedCount: 0,
                       deletedCounts: ResetDeletedCountsV1(tasks: 0, notificationIntents: 0, taskDeadlineEvidence: 0, confirmationSnapshots: 0), state: state)
    }
    static func upgraded(uid: String, legacy: String, alias: String, epoch: Int) -> LegacyResetReconciliationV1 {
        .upgraded(base(uid: uid, legacy: legacy, alias: alias), sourceState: "deleting", progress: progress(uid: uid, epoch: epoch, state: .deleting, replayed: false))
    }
    static func phase2Active(uid: String, legacy: String, alias: String, epoch: Int) -> LegacyResetReconciliationV1 {
        .phase2Active(base(uid: uid, legacy: legacy, alias: alias, replayed: true), progress: progress(uid: uid, epoch: epoch, state: .awaitingLocalReset, replayed: true))
    }
    static func notDispatched(uid: String, legacy: String, alias: String) -> LegacyResetReconciliationV1 { .notDispatched(base(uid: uid, legacy: legacy, alias: alias)) }
    static func finalizedCompat(uid: String, legacy: String, alias: String) -> LegacyResetReconciliationV1 {
        .finalizedCompat(base(uid: uid, legacy: legacy, alias: alias), legacyFinal: LegacyResetFinalReceiptV1(operationId: legacy, accountUid: uid, deletedCount: 2))
    }
    static func gestureId() -> String { "rsg1_" + UUID().uuidString.lowercased() }
    static func exactRow(phase: LegacyMigrationPhase, errorCode: LegacyMigrationErrorCode? = nil, receipt: LegacyResetReconciliationV1? = nil, applicationId: String? = nil, authority: LegacyInitiatingAuthority? = .reservedGesture(gestureId: "rsg1_11111111-1111-4111-8111-111111111111", gestureGeneration: "g1", alias: "rsa1_22222222-2222-4222-8222-222222222222")) -> LegacyResetMigrationV1 {
        LegacyResetMigrationV1(uid: "A", authEpochUUID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", credentialRevision: 3, initiatingAuthority: authority, phase: phase,
                               createdAt: "2026-09-06T12:00:00.000Z", updatedAt: "2026-09-06T12:00:00.000Z", legacyOperationId: legacyA, migrationAlias: "rsa1_22222222-2222-4222-8222-222222222222",
                               aliasCandidateOrdinal: 1, legacyKeyGuard: .validString(value: legacyA), receipt: receipt.flatMap { TaskCanonicalV1.data($0.map()) }, applicationId: applicationId, errorCode: errorCode,
                               legacyValueClass: nil, legacyValueUtf8Length: nil, legacyValueSHA256: nil)
    }
    static func invalidRow(_ valueClass: LegacyValueClass, authority: LegacyInitiatingAuthority? = nil) -> LegacyResetMigrationV1 {
        LegacyResetMigrationV1(uid: "A", authEpochUUID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", credentialRevision: 3, initiatingAuthority: authority, phase: .blocked,
                               createdAt: "2026-09-06T12:00:00.000Z", updatedAt: "2026-09-06T12:00:00.000Z", legacyOperationId: nil, migrationAlias: nil, aliasCandidateOrdinal: nil, legacyKeyGuard: nil,
                               receipt: nil, applicationId: nil, errorCode: .aliasInvalid, legacyValueClass: valueClass,
                               legacyValueUtf8Length: valueClass == .invalidString ? 6 : nil, legacyValueSHA256: valueClass == .invalidString ? TaskCanonicalV1.sha256Hex(data: Data("bad/id".utf8)) : nil)
    }
    static func registry(_ directory: URL, defaults: UserDefaults) async -> (ResetOperationRegistry, SignedAuthStub) {
        let stub = SignedAuthStub(signedInA)
        let registry = ResetOperationRegistry(directory: directory, clock: ResetClockStub(), auth: stub, epochAuthority: EpochStub(epoch: 1))
        await registry.attachLegacyKeyStore(defaults)
        return (registry, stub)
    }
    static func seed(_ directory: URL, migration: LegacyResetMigrationV1, records: [[String: Any]] = [], gesture: ResetGestureV1? = nil) throws {
        try ResetFixtures.envelope(records: records, migrations: [migration.map()], gesture: gesture?.map()).write(to: ResetFixtures.target(directory))
    }
}

/// The coverage store the pinned three-argument initializer needs; nothing is persisted.
struct NoopCoverageStore: CoverageConfirmationPersisting {
    func insertConfirmedRoomID(_ roomID: String, userID: String) async throws -> Set<String> { [roomID] }
}

/// A holdable `InventoryProcessingCalling`: records requests, parks the call until released, and can throw the entitlement denial.
final class HoldableInventoryClient: InventoryProcessingCalling, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var holding = false
    private var held: CheckedContinuation<Void, Never>?
    private var denies = false
    var requests: [String] { lock.withLock { recorded } }
    func setHold() { lock.withLock { holding = true } }
    var isHolding: Bool { lock.withLock { held != nil } }
    func release() { let c: CheckedContinuation<Void, Never>? = lock.withLock { defer { held = nil; holding = false }; return held }; c?.resume() }
    func setDenying(_ value: Bool) { lock.withLock { denies = value } }
    func processInventory(_ request: InventoryProcessingRequest) async throws {
        let shouldHold: Bool = lock.withLock { recorded.append("\(request.userId)/\(request.sessionId)"); return holding }
        if shouldHold { await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in lock.withLock { held = c } } }
        if lock.withLock({ denies }) { throw InventoryError.movePassRequired }
    }
}

/// A remote whose failure is an arbitrary `NSError` carrying a UID and a path in its description (the adversarial sink case).
struct AdversarialDeletionRemote: AccountDeletionRemoteProviding {
    static let secret = "UID-SECRET-7f3a"
    func perform(_ request: AccountDeletionRequestV1) async throws -> AccountDeletionRemoteResultV1 {
        throw NSError(domain: "users/\(Self.secret)/tasks", code: 7, userInfo: [NSLocalizedDescriptionKey: "failed for users/\(Self.secret)/tasks/t1 with payload {\"uid\":\"\(Self.secret)\"}"])
    }
}

/// The S4-owned production files (the C10.2 rows S4 writes), relative to the repository root.
let s4OwnedProductionFiles = [
    "Peezy 4.0/Tasks/Durable/DurableStoreRecoveryCoordinator.swift", "Peezy 4.0/Tasks/Durable/DurableStoreRecoveryView.swift",
    "Peezy 4.0/Tasks/Durable/LocalPrivacyPurgeCoordinator.swift", "Peezy 4.0/Tasks/Disposition/TaskDispositionSurface.swift",
    "Peezy 4.0/Tasks/Store/TasksStore.swift", "Peezy 4.0/MainInterface/Views/AppRootView.swift", "Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift",
    "Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift", "Peezy 4.0/MainInterface/Views/PeezyHomeView.swift", "Peezy 4.0/MainInterface/Models/AnalyticsEvents.swift",
    "Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift", "Peezy 4.0/Tasks/Views/TasksTabView.swift", "Peezy 4.0/Tasks/Views/TasksList.swift",
    "Peezy 4.0/Tasks/Views/TaskRow.swift", "Peezy 4.0/Tasks/Views/TaskRowButtons.swift", "Peezy 4.0/Inventory/Models/InventorySessionManager.swift",
    "Peezy 4.0/Inventory/Views/InventoryCameraView.swift", "Peezy 4.0/Inventory/Services/NarrationService.swift", "Peezy 4.0/Inventory/Views/InventoryItemConfirmView.swift",
    "Peezy 4.0/Inventory/ViewModels/RoomCaptureViewModel.swift"
]

func repositoryRoot() -> URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }

/// Every `.swift` file under the app source tree (never the test target).
func appSourceFiles() throws -> [URL] {
    let app = repositoryRoot().appendingPathComponent("Peezy 4.0")
    var files: [URL] = []
    guard let enumerator = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else { return [] }
    for case let url as URL in enumerator where url.pathExtension == "swift" { files.append(url) }
    return files.sorted { $0.path < $1.path }
}

/// The generic-password keychain items whose service names Firebase Auth (the persisted user).
func firebaseAuthKeychainServices() -> [String] {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecReturnAttributes as String: true, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
    return items.compactMap { item -> String? in
        guard let service = item[kSecAttrService as String] as? String, service.lowercased().contains("firebase_auth") else { return nil }
        let account = item[kSecAttrAccount as String] as? String ?? "-"
        let length = (item[kSecValueData as String] as? Data)?.count ?? 0
        return "\(service)|\(account)|\(length)"
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
    guard case let .binding(reservation) = try await seeded.reserve(gestureId: "rsg1_" + UUID().uuidString.lowercased()) else { throw DriveTraceError.failed }
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
    private var readCount = 0
    init(_ value: SignedAuthAuthority) { self.value = value }
    func set(_ newValue: SignedAuthAuthority) { lock.withLock { value = newValue } }
    private var switchAt: (read: Int, value: SignedAuthAuthority)?
    /// Number of signed-auth reads so far (a test can wait for a caller's entry read).
    var reads: Int { lock.withLock { readCount } }
    /// The `read`-th read (1-based) and every later read return `value`.
    func switchOnRead(_ read: Int, to value: SignedAuthAuthority) { lock.withLock { switchAt = (read, value) } }
    func currentSignedAuth() async -> SignedAuthAuthority {
        lock.withLock {
            readCount += 1
            if let switchAt, readCount >= switchAt.read { value = switchAt.value }
            return value
        }
    }
    func forceRefresh(expected: SignedAuthTuple) async -> AuthRefreshOutcome { .notCommitted }
    private var deletionObservation: AccountDeletionAuthObservation = .notProven
    private(set) var deletionChecks: [AuthIdentity] = []
    /// S4: what `confirmAccountDeleted` answers (default `.notProven`, the S1/S3 behavior).
    func setDeletionObservation(_ value: AccountDeletionAuthObservation) { lock.withLock { deletionObservation = value } }
    func confirmAccountDeleted(expected: AuthIdentity) async -> AccountDeletionAuthObservation {
        lock.withLock { deletionChecks.append(expected); return deletionObservation }
    }
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
    private(set) var aliases: [String] = []
    private var failFinalizeOnce = false
    private(set) var dispatchPhases: [ResetRowPhase] = []
    private var holdDispatch = false
    private var held: [CheckedContinuation<Void, Never>] = []
    /// Number of reset dispatches currently parked by `setHoldDispatch`.
    private(set) var heldCount = 0
    var registry: ResetOperationRegistry?
    var handle: ResetOperationHandle?
    var recorder: DriveTrace?

    init(wires: FrozenResetWires) { self.wires = wires }
    func setDeletingFirst() { deletingFirst = true }
    func setCommittedAtInspection(_ ordinal: Int) { committedAt = ordinal }
    func setAbsentAtInspection(_ ordinal: Int) { absentAt = ordinal }
    func setFailFinalizeOnce() { failFinalizeOnce = true }
    /// The next reset dispatch parks until `releaseHeld()`, keeping one drive in flight.
    func setHoldDispatch() { holdDispatch = true }
    func releaseHeld() { let waiting = held; held = []; heldCount = 0; waiting.forEach { $0.resume() } }
    func attach(_ recorder: DriveTrace, registry: ResetOperationRegistry, handle: ResetOperationHandle) { self.recorder = recorder; self.registry = registry; self.handle = handle }

    private func rebased(_ map: [String: Any], replayed: Bool? = nil) -> [String: Any] {
        var out = map
        out["accountUid"] = "A"
        if let replayed { out["replayed"] = replayed }
        return out
    }

    func reset(_ action: ResetRemoteAction, alias: String, expectedTaskGenerationEpoch: Int) async throws -> ResetReceiptV1 {
        if let registry, let handle, let row = await registry.snapshot().records.first(where: { $0.handleId == handle.handleId }) { dispatchPhases.append(row.phase) }
        aliases.append(alias)
        switch action {
        case .resetAllTasks:
            await recorder?.record("resetDispatch")
            if holdDispatch {
                holdDispatch = false
                heldCount += 1
                await withCheckedContinuation { held.append($0) }
            }
            if deletingFirst { deletingFirst = false; return try ResetReceiptV1.decode(rebased(wires.map("progressDeleting"))) }
            return try ResetReceiptV1.decode(rebased(wires.map("progressAwaiting")))
        case .finalizeTaskReset:
            await recorder?.record("finalize")
            if failFinalizeOnce { failFinalizeOnce = false; throw DriveTraceError.failed }
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

actor NotificationCounter {
    private(set) var count = 0
    func bump() { count += 1 }
}
