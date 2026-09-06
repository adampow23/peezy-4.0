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
        #expect(RecoveryAction.resolve(resolutionDigest: "r", choices: ["b", "a"]).attemptKey(expecting: digest) == .resolveForeign(recoveryStateDigest: "d", resolutionDigest: "r", choicesSHA256: TaskCanonicalV1.sha256Hex(["choices": ["b", "a"]])))
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
        #expect(await broken.purgeForAccountDeletion(scope: .all) == .failed, "a purge already in flight or unacknowledged is not restarted concurrently")
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
