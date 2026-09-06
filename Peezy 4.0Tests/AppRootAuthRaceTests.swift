import Foundation
import Testing
@testable import Peezy_4_0

/// S4 (briefs/S4_BRIEF.md; S4-CD4): the auth-race families against the C9.7.14 seams. S5 contributes the Google
/// callback-slot fixtures and the two call-site scans, S7 the eleven runtime identities and the mount cases; S4 performs
/// the final full-class review. Every case runs on fakes; nothing here touches a Firebase SDK.
struct AppRootAuthRaceTests {

    @Test func consumerProjectionCoversAllNineGateStates() async {
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
        await barrier.setGate(.guarding(uid: "A", authGuardAfter: "2026-09-13T11:59:30.000Z"))
        probe.uid = "A"
        #expect(await barrier.projection() == .guardingSameUID)
        probe.uid = "B"
        #expect(await barrier.projection() == .guardingOtherUID)
        await barrier.setGate(.active(uid: "A"))
        await barrier.setPendingTerminalPresentation(.localCleared)
        #expect(await barrier.projection() == .localCleared)
        await barrier.setGate(.clear)
        #expect(await barrier.projection() == .clear, "clear drops the pending terminal")
        #expect(AccountDeletionGateProjection.allCases.count == 9)
    }

    @Test func sameUIDGuardingRefusalWhileASecondUIDSignsInAndDispatches() async {
        let barrier = StartupBarrier(currentUID: UIDProbe("B"))
        for store in DurableStore.allCases { await barrier.publish(store, .ready) }
        await barrier.setGate(.guarding(uid: "A", authGuardAfter: "2026-09-13T11:59:30.000Z"))
        for operation in GatedOperation.allCases {
            #expect(await barrier.admission(of: operation, uid: "A") == .refused(.guardingSameUID))
            guard case .admitted = await barrier.admission(of: operation, uid: "B") else { Issue.record("B is admitted under A's guarding: \(operation)"); continue }
        }
        // the non-UID barriers: a loading store defers B's dependent operations, a blocked store blocks them
        await barrier.publish(.handoff, .loading)
        #expect(await barrier.admission(of: .routeClaim, uid: "B") == .deferred(storesLoading: [.handoff]))
        guard case .admitted = await barrier.admission(of: .directTaskCallable, uid: "B") else { Issue.record("empty required set never waits on a store"); return }
        // active for A refuses every UID, including nil, and never admits an empty required set
        await barrier.setGate(.active(uid: "A"))
        #expect(await barrier.admission(of: .directTaskCallable, uid: "B") == .refused(.activeOtherUID))
        #expect(await barrier.admission(of: .directTaskCallable, uid: nil) == .refused(.activeOtherUID))
        await barrier.setGate(.clear)
        await barrier.setPendingTerminalPresentation(.localCleared)
        guard case .admitted = await barrier.admission(of: .directTaskCallable, uid: "B") else { Issue.record("clear admits"); return }
    }

    @Test func authCallbackAndRouteDispatchObeyTheSameUIDScopeAndStaleABCallbacksLoseTheGeneration() async {
        let barrier = StartupBarrier(currentUID: UIDProbe("A"))
        for store in DurableStore.allCases { await barrier.publish(store, .ready) }
        await barrier.setGate(.clear)
        guard case let .admitted(generation) = await barrier.admission(of: .routeClaim, uid: "A") else { Issue.record("admitted"); return }
        #expect(await barrier.gateGeneration() == generation)
        // A→B: every gate change advances the generation; a callback admitted under the old generation is discarded by its holder
        await barrier.setGate(.loading)
        #expect(await barrier.gateGeneration() != generation)
        await barrier.setGate(.clear)
        guard case let .admitted(next) = await barrier.admission(of: .routeClaim, uid: "B") else { Issue.record("B admitted"); return }
        #expect(next != generation && next.rawValue > generation.rawValue)
        // the same gate value twice does not advance (no spurious discards)
        await barrier.setGate(.clear)
        #expect(await barrier.gateGeneration() == next)
        // guarding A: A's callback/route dispatch refused, B's admitted; the deleted UID keeps only its Retry reducer
        await barrier.setGate(.guarding(uid: "A", authGuardAfter: "2026-09-13T11:59:30.000Z"))
        #expect(await barrier.admission(of: .routeClaim, uid: "A") == .refused(.guardingSameUID))
        #expect(await barrier.admission(of: .directTaskCallable, uid: "A") == .refused(.guardingSameUID))
        guard case .admitted = await barrier.admission(of: .routeClaim, uid: "B") else { Issue.record("B route"); return }
    }

    @Test func completionAndLocalClearedSurviveAuthRootReplacement() async throws {
        let first = try makeDeletionHarness(auth: signedInA)
        first.remote.always("begin", .success(DeletionWires.dataFinal("x")))
        first.remote.script("finalize", .success(DeletionWires.guarding("x")), .success(DeletionWires.deleted("x")))
        #expect(await first.coordinator.startDeletion(uid: "A") == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        guard case .settled(.completion(let snapshot)) = await first.coordinator.retry() else { Issue.record("completed"); return }
        // a replaced auth root (fresh coordinator, presenter, and barrier seam over the same files) re-presents the same snapshot
        let replaced = try makeDeletionHarness(auth: .signedOut, directory: first.directory)
        #expect(await replaced.coordinator.discoverAtStartup() == .settled(.completion(snapshot)))
        #expect(await replaced.completion.current() == snapshot && replaced.gate.terminals.last == .completed && replaced.gate.gates.last == .active(uid: "A"))
        #expect(replaced.remote.actions.isEmpty, "no server call recreates a terminal presentation")
        // local_cleared likewise
        let cleared = try makeDeletionHarness(auth: signedInA)
        cleared.remote.always("begin", .failure(.capabilityInvalid))
        cleared.auth.setDeletionObservation(.definitivelyDeleted)
        guard case .settled(.completion(let local)) = await cleared.coordinator.startDeletion(uid: "A"), local.result == .localCleared else { Issue.record("local_cleared"); return }
        let replacedLocal = try makeDeletionHarness(auth: .signedOut, directory: cleared.directory)
        #expect(await replacedLocal.coordinator.discoverAtStartup() == .settled(.completion(local)) && replacedLocal.gate.terminals.last == .localCleared)
        let barrier = StartupBarrier(currentUID: UIDProbe(nil))
        await barrier.setGate(.active(uid: "A"))
        await barrier.setPendingTerminalPresentation(.localCleared)
        #expect(await barrier.projection() == .localCleared)
        #expect(await barrier.admission(of: .directTaskCallable, uid: "B") == .refused(.localCleared))
    }

    @Test func bothManualProvidersOfferNonconsumingLinksAppleThenGoogle() async throws {
        let dispositions = AccountDeletionProviderDispositions(appleRevocation: .manualRequired, googleRevocation: .manualRequired, googleProviderUid: nil)
        let h = try makeDeletionHarness(auth: signedInA, dispositions: dispositions)
        h.remote.always("begin", .success(DeletionWires.dataFinal("x")))
        h.remote.script("finalize", .success(DeletionWires.guarding("x")), .success(DeletionWires.deleted("x")))
        #expect(await h.coordinator.startDeletion(uid: "A") == .settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter)))
        guard case .settled(.completion(let snapshot)) = await h.coordinator.retry() else { Issue.record("completed"); return }
        #expect(snapshot.result == .completed(appleRevocation: .manualRequired, googleRevocation: .manualRequired))
        #expect(snapshot.result.manualProviders == [.apple, .google])
        #expect(h.owners.calls.filter { $0.hasPrefix("google.") }.isEmpty, "manual-required acks without an SDK call")
        #expect(await h.completion.open(expectedGenerationId: snapshot.generationId, expectedSHA256: snapshot.sha256, provider: .apple) == .opened)
        #expect(await h.completion.open(expectedGenerationId: snapshot.generationId, expectedSHA256: snapshot.sha256, provider: .google) == .opened)
        let currentAfterLinks = await h.completion.current()
        let intentAfterLinks = await h.coordinator.currentIntent()
        #expect(currentAfterLinks == snapshot && intentAfterLinks?.phase == .completed && h.signOut.calls.isEmpty, "links never consume")
        #expect(CompletionResultV1.completed(appleRevocation: .notRequired, googleRevocation: .manualRequired).manualProviders == [.google])
        #expect(CompletionResultV1.completed(appleRevocation: .manualRequired, googleRevocation: .revoked).manualProviders == [.apple])
        #expect(CompletionResultV1.localCleared.manualProviders.isEmpty && CompletionResultV1.remoteUnconfirmed.manualProviders.isEmpty)
        #expect(await h.completion.acknowledge(expectedGenerationId: snapshot.generationId, expectedSHA256: snapshot.sha256) == .acknowledged)
        #expect(h.signOut.calls == ["A"])
    }

    @Test func appleCredentialStateRevokedOrNotFoundSignsOutAndResumesOnlyANamedDeletion() async throws {
        let h = try makeDeletionHarness(auth: signedInA)
        #expect(await h.coordinator.appleCredentialState(.authorized, uid: "A") == .noOp)
        #expect(await h.coordinator.appleCredentialState(.transferred, uid: "A") == .unresolved("APPLE_CREDENTIAL_STATE_UNRESOLVED"))
        #expect(await h.coordinator.appleCredentialState(.unresolved, uid: "A") == .unresolved("APPLE_CREDENTIAL_STATE_UNRESOLVED"))
        #expect(await h.coordinator.appleCredentialState(.revoked, uid: "B") == .noOp, "authority no longer matching: nothing happens")
        #expect(h.signOut.calls.isEmpty)
        // matching authority, no named deletion: sign out only
        #expect(await h.coordinator.appleCredentialState(.notFound, uid: "A") == .signedOut)
        #expect(h.signOut.calls == ["A"] && h.remote.actions.isEmpty && h.intentBytes() == nil)
        // matching authority with a named deletion: sign out and resume it
        h.remote.script("begin", .failure(.retryRequired))
        #expect(await h.coordinator.startDeletion(uid: "A") == .settled(.queued))
        h.remote.always("begin", .success(DeletionWires.dataFinal("x")))
        h.remote.always("finalize", .success(DeletionWires.guarding("x")))
        #expect(await h.coordinator.appleCredentialState(.revoked, uid: "A") == .resumed(.settled(.guarding(authGuardAfter: DeletionWires.authGuardAfter))))
        #expect(h.signOut.calls == ["A", "A"])
        // manual sign-out versus user-not-found: only `definitivelyDeleted` on a named deletion takes the capability-invalid exit
        let manual = try makeDeletionHarness(auth: .signedOut)
        #expect(await manual.coordinator.authTransition() == .clear && manual.intentBytes() == nil)
        #expect(await manual.completion.current() == nil)
    }
}
