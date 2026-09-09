import Foundation
import Testing
@testable import Peezy_4_0

/// S5 (briefs/S5_BRIEF.md). I1: the C9.7.18 record grammar, the two C9.7.6 recovery keys,
/// and the event × source-phase transition tables.
///
/// This file carries every S5 durable-store case, workflow included: C10.4 L4284 forbids a
/// fourth new Swift test file, so its name is narrower than its contents by contract.
struct HandoffSessionTests {

    // MARK: - Fixtures

    private static let instant = "2026-09-08T12:00:00.000Z"
    private static let sha = String(repeating: "a", count: 64)

    private static func ordinary(phase: HandoffSessionPhase,
                                 action: HandoffAction? = .beginHandoff) -> HandoffSessionRecordV1 {
        let required = phase.requiredMembers
        return HandoffSessionRecordV1(
            uid: "u1", installationId: "i1", authEpochUUID: "e1",
            taskDocumentId: "d1", taskInstanceId: "t1", sessionId: "s1",
            action: phase.carriesAction ? action : nil,
            phase: phase, createdAt: instant, updatedAt: instant,
            operationId: required.contains(.operationId) ? "op1" : nil,
            requestCanonicalJSON: required.contains(.requestCanonicalJSON) ? "{}" : nil,
            requestSHA256: required.contains(.requestSHA256) ? sha : nil,
            receipt: required.contains(.receipt) ? "{}" : nil,
            applicationId: required.contains(.applicationId)
                ? HandoffApplicationIdentity.ordinary(uid: "u1", identityDigest: sha, receiptSHA256: sha) : nil,
            serverSnapshot: required.contains(.serverSnapshot) ? "{}" : nil)
    }

    private static func cancel(phase: ReconciliationCancelPhase,
                               reason: HandoffCancelReason = .authEpochChanged) -> ReconciliationCancelV1 {
        let required = phase.requiredMembers
        let stored = HandoffNamespace(installationId: "i1", authEpochUUID: "e1")
        let requester = reason == .authEpochChanged
            ? HandoffNamespace(installationId: "i1", authEpochUUID: "e2")
            : HandoffNamespace(installationId: "i2", authEpochUUID: "e1")
        return ReconciliationCancelV1(
            uid: "u1", taskDocumentId: "d1", taskInstanceId: "t1", sessionId: "s1",
            reasonCode: reason, storedNamespace: stored, requesterNamespace: requester,
            phase: phase, createdAt: instant, updatedAt: instant,
            operationId: required.contains(.operationId) ? "op1" : nil,
            requestCanonicalJSON: required.contains(.requestCanonicalJSON) ? "{}" : nil,
            requestSHA256: required.contains(.requestSHA256) ? sha : nil,
            receipt: required.contains(.receipt) ? "{}" : nil,
            applicationId: required.contains(.applicationId)
                ? HandoffApplicationIdentity.ordinary(uid: "u1", identityDigest: sha, receiptSHA256: sha) : nil)
    }

    // MARK: - Grammar cross-product (C9.7.18 per-phase required/forbidden)

    /// Every phase decodes with exactly its own member set, and fails with any other —
    /// the cross-product, not a sample of it.
    @Test func ordinaryGrammarIsExactAcrossEveryPhaseAndMember() {
        for phase in HandoffSessionPhase.allCases {
            let record = Self.ordinary(phase: phase)
            #expect(record.isWellFormed, Comment(rawValue: "\(phase.rawValue) fixture is its own required set"))
            let encoded = record.map()
            #expect(HandoffSessionRecordV1.from(encoded) == record,
                    Comment(rawValue: "\(phase.rawValue) round-trips"))

            for member in HandoffRecordMember.allCases {
                var mutated = encoded
                if phase.requiredMembers.contains(member) {
                    mutated.removeValue(forKey: member.rawValue)
                    #expect(HandoffSessionRecordV1.from(mutated) == nil,
                            Comment(rawValue: "\(phase.rawValue) without required \(member.rawValue) is corrupt"))
                } else {
                    mutated[member.rawValue] = member == .requestSHA256 ? Self.sha : "{}"
                    #expect(HandoffSessionRecordV1.from(mutated) == nil,
                            Comment(rawValue: "\(phase.rawValue) with forbidden \(member.rawValue) is corrupt"))
                }
            }
        }
    }

    /// SERVER_SNAPSHOT is the one phase carrying no `action` (S5-CD10): its own recovery
    /// key is the identity of the row it replaced. Where the resumed action comes from is
    /// a registered open decision — see `theResumeIsNotModelledBecauseTheResumedActionIsUnnameable`.
    @Test func onlyServerSnapshotOmitsTheAction() {
        for phase in HandoffSessionPhase.allCases {
            var encoded = Self.ordinary(phase: phase).map()
            #expect((encoded["action"] != nil) == phase.carriesAction,
                    Comment(rawValue: "\(phase.rawValue) action presence"))
            if phase.carriesAction {
                encoded.removeValue(forKey: "action")
            } else {
                encoded["action"] = HandoffAction.beginHandoff.rawValue
            }
            #expect(HandoffSessionRecordV1.from(encoded) == nil,
                    Comment(rawValue: "\(phase.rawValue) rejects the opposite action presence"))
        }
        #expect(Self.ordinary(phase: .serverSnapshot).identityMap() == nil,
                "a snapshot contributes no ordinary identity digest, having no action")
    }

    @Test func cancelGrammarIsExactAcrossEveryPhaseAndMember() {
        for phase in ReconciliationCancelPhase.allCases {
            let record = Self.cancel(phase: phase)
            #expect(record.isWellFormed, Comment(rawValue: "\(phase.rawValue) cancel fixture"))
            let encoded = record.map()
            #expect(ReconciliationCancelV1.from(encoded) == record,
                    Comment(rawValue: "\(phase.rawValue) cancel round-trips"))

            for member in HandoffRecordMember.allCases {
                var mutated = encoded
                if phase.requiredMembers.contains(member) {
                    mutated.removeValue(forKey: member.rawValue)
                } else {
                    mutated[member.rawValue] = member == .requestSHA256 ? Self.sha : "{}"
                }
                #expect(ReconciliationCancelV1.from(mutated) == nil,
                        Comment(rawValue: "\(phase.rawValue) cancel rejects \(member.rawValue)"))
            }
        }
    }

    /// A cancel row never carries a `serverSnapshot` in any phase (C9.7.7 L3674), so the
    /// member is not merely forbidden by the phase — it is not in the decoder's key set.
    @Test func cancelNeverCarriesAServerSnapshot() {
        for phase in ReconciliationCancelPhase.allCases {
            #expect(phase.forbiddenMembers.contains(.serverSnapshot))
            var encoded = Self.cancel(phase: phase).map()
            encoded["serverSnapshot"] = "{}"
            #expect(ReconciliationCancelV1.from(encoded) == nil)
        }
    }

    /// C9.7.9 L3752: any other pairing is structural corruption, in both directions.
    @Test func reasonPairingIsTotal() {
        let a = HandoffNamespace(installationId: "i1", authEpochUUID: "e1")
        let sameInstallDifferentEpoch = HandoffNamespace(installationId: "i1", authEpochUUID: "e2")
        let differentInstall = HandoffNamespace(installationId: "i2", authEpochUUID: "e1")

        #expect(HandoffNamespacePair.isReasonPaired(reason: .authEpochChanged, stored: a, requester: sameInstallDifferentEpoch))
        #expect(!HandoffNamespacePair.isReasonPaired(reason: .authEpochChanged, stored: a, requester: a),
                "same epoch is not an epoch change")
        #expect(!HandoffNamespacePair.isReasonPaired(reason: .authEpochChanged, stored: a, requester: differentInstall),
                "a different installation is a takeover, not an epoch change")
        #expect(HandoffNamespacePair.isReasonPaired(reason: .takeover, stored: a, requester: differentInstall))
        #expect(!HandoffNamespacePair.isReasonPaired(reason: .takeover, stored: a, requester: sameInstallDifferentEpoch),
                "the same installation is never a takeover")

        var encoded = Self.cancel(phase: .preflight).map()
        encoded["reasonCode"] = HandoffCancelReason.takeover.rawValue
        #expect(ReconciliationCancelV1.from(encoded) == nil, "the decoder rejects an unpaired reason")
    }

    // MARK: - The two C9.7.6 recovery keys

    @Test func ordinaryRecoveryKeyIsItsFiveMembersInKeyOrder() {
        let record = Self.ordinary(phase: .prepared)
        #expect(record.recoveryKey == HandoffOrdinaryKey(uid: "u1", installationId: "i1", authEpochUUID: "e1",
                                                         taskInstanceId: "t1", sessionId: "s1"))
        #expect(record.recoveryKey.sortMembers == ["u1", "i1", "e1", "t1", "s1"])
        // The key carries no action, which is why a C9.7.11 L3793 reconstruction keeps it.
        var snapshot = Self.ordinary(phase: .serverSnapshot)
        #expect(snapshot.recoveryKey == record.recoveryKey)
        snapshot.phase = .serverSnapshot
        #expect(snapshot.action == nil)
    }

    /// S5-CD10. Two lawful ordinary rows differing only in `authEpochUUID` replace per
    /// candidate (C9.7.9 L3749) into two PREFLIGHTs identical on every other member; the
    /// stored namespace is what keeps their keys apart. Drop it and they collide.
    @Test func cancelRecoveryKeySeparatesPerCandidateReplacementsOfDifferentStoredNamespaces() {
        let requester = HandoffNamespace(installationId: "i1", authEpochUUID: "now")
        func preflight(storedEpoch: String) -> ReconciliationCancelV1 {
            ReconciliationCancelV1(uid: "u1", taskDocumentId: "d1", taskInstanceId: "t1", sessionId: "s1",
                                   reasonCode: .authEpochChanged,
                                   storedNamespace: HandoffNamespace(installationId: "i1", authEpochUUID: storedEpoch),
                                   requesterNamespace: requester,
                                   phase: .preflight, createdAt: Self.instant, updatedAt: Self.instant,
                                   operationId: nil, requestCanonicalJSON: nil, requestSHA256: nil,
                                   receipt: nil, applicationId: nil)
        }
        let first = preflight(storedEpoch: "old1")
        let second = preflight(storedEpoch: "old2")
        #expect(first.recoveryKey != second.recoveryKey,
                "two lawful per-candidate replacements must not share one recovery key")
        #expect(first.recoveryKey.sortMembers.count == 8)
        // Everything but the stored namespace is identical, which is the whole point.
        #expect(Array(first.recoveryKey.sortMembers.prefix(6)) == Array(second.recoveryKey.sortMembers.prefix(6)))
        #expect(first.lineage == second.lineage, "and they share one lineage, which is a group")
    }

    /// A lineage is a group: the ordinary key adds two namespace members the lineage
    /// identity does not, so one lineage lawfully holds several ordinary rows.
    @Test func lineageGroupsRowsTheOrdinaryKeySeparates() {
        var a = Self.ordinary(phase: .prepared)
        let b = HandoffSessionRecordV1(
            uid: a.uid, installationId: "i2", authEpochUUID: a.authEpochUUID,
            taskDocumentId: a.taskDocumentId, taskInstanceId: a.taskInstanceId, sessionId: a.sessionId,
            action: a.action, phase: a.phase, createdAt: a.createdAt, updatedAt: a.updatedAt,
            operationId: a.operationId, requestCanonicalJSON: a.requestCanonicalJSON,
            requestSHA256: a.requestSHA256, receipt: nil, applicationId: nil, serverSnapshot: nil)
        #expect(a.recoveryKey != b.recoveryKey)
        #expect(a.lineage == b.lineage)
        a.phase = .prepared
    }

    // MARK: - Transitions (event × source phase)

    /// The edge a phase-indexed table cannot express, and the reason C9.7.18 forbids one:
    /// C9.7.8 L3730 makes a loaded RECEIPT or APPLYING row a `receipt_mismatch`, and on
    /// `absent` it goes **backwards** to DISPATCHED, its pre-replay phase.
    @Test func reconcileAbsentReturnsBothReceiptBearingPhasesToDispatched() {
        for source in [HandoffSessionPhase.receipt, .applying] {
            #expect(HandoffTransitions.ordinary(.reconcileAbsent, from: source) == .moved(to: .dispatched),
                    Comment(rawValue: "\(source.rawValue) → DISPATCHED on absent"))
        }
        for source in [ReconciliationCancelPhase.receipt, .applying] {
            #expect(HandoffTransitions.cancel(.reconcileAbsent, from: source) == .moved(to: .dispatched))
        }
        // DISPATCHED is never a source: C9.7.3 L3540 classifies only a receipt-bearing row.
        #expect(HandoffTransitions.ordinary(.reconcileAbsent, from: .dispatched) == nil)
        #expect(HandoffTransitions.ordinary(.reconcileCommitted(landsInApplying: false), from: .dispatched) == nil)
        #expect(HandoffTransitions.ordinary(.reconcileAbsent, from: .prepared) == nil)
    }

    /// The happy path. Without this edge RECEIPT is unreachable outside recovery,
    /// DISPATCHED is absorbing, and `applicationId` is dead text.
    @Test func aFirstResponseStoresTheReceiptFromDispatched() {
        #expect(HandoffTransitions.ordinary(.firstResponse, from: .dispatched) == .moved(to: .receipt))
        #expect(HandoffTransitions.cancel(.firstResponse, from: .dispatched) == .moved(to: .receipt))
        for source in HandoffSessionPhase.allCases where source != .dispatched {
            #expect(HandoffTransitions.ordinary(.firstResponse, from: source) == nil,
                    Comment(rawValue: "no first response from \(source.rawValue)"))
        }
    }

    @Test func theOrdinaryOperationEdgesAreExactlyTheseAndNoOthers() {
        #expect(HandoffTransitions.ordinary(.prepare, from: nil) == .created(.prepared))
        #expect(HandoffTransitions.ordinary(.dispatch, from: .prepared) == .moved(to: .dispatched))
        #expect(HandoffTransitions.ordinary(.reconcileCommitted(landsInApplying: false), from: .receipt) == .moved(to: .receipt))
        #expect(HandoffTransitions.ordinary(.reconcileCommitted(landsInApplying: true), from: .applying) == .moved(to: .applying))
        #expect(HandoffTransitions.ordinary(.reconstruct, from: nil) == .created(.serverSnapshot))
        for phase in HandoffSessionPhase.allCases {
            #expect(HandoffTransitions.ordinary(.purge, from: phase) == .removed)
            #expect(HandoffTransitions.ordinary(.prepare, from: phase) == nil, "prepare never has a source")
        }
    }

    /// C9.7.9 L3750: retirement is lawful from the two phases that owe no receipt, and
    /// never from RECEIPT or APPLYING, whose bytes C9.7.6 L3638 never drops.
    @Test func cancelRetirementIsLawfulOnlyBeforeAReceiptIsOwed() {
        for source in [ReconciliationCancelPhase.preflight, .prepared] {
            #expect(HandoffTransitions.cancel(.retire, from: source) == .removed)
        }
        for source in [ReconciliationCancelPhase.dispatched, .receipt, .applying] {
            #expect(HandoffTransitions.cancel(.retire, from: source) == nil,
                    Comment(rawValue: "\(source.rawValue) may not be retired"))
        }
        #expect(HandoffTransitions.cancel(.preflight, from: nil) == .created(.preflight))
        #expect(HandoffTransitions.cancel(.prepare, from: .preflight) == .moved(to: .prepared))
    }

    /// Decision 11 moved the application to S6. S5 writes rows into RECEIPT and recovers
    /// rows found in either receipt-bearing phase; it takes neither edge.
    /// The resume is not an edge here, and that is deliberate: C9.7.11 L3796's
    /// `actionLabel` is a safe-label display string (L3811 disambiguates duplicates with
    /// ordinals), so it cannot name one of the five actions. Modelling it would leave two
    /// rows under one recovery key or perform an unauthorized removal.
    @Test func theResumeIsNotModelledBecauseTheResumedActionIsUnnameable() {
        for phase in HandoffSessionPhase.allCases {
            #expect(HandoffTransitions.ordinary(.resume, from: phase) == nil,
                    Comment(rawValue: "no resume edge from \(phase.rawValue)"))
        }
        #expect(HandoffTransitions.ordinary(.resume, from: nil) == nil)
    }

    @Test func theApplicationEdgesAreS6s() {
        #expect(HandoffTransitions.sixthSliceOrdinaryEvents.count == 2)
        #expect(HandoffTransitions.ordinary(.apply, from: .receipt) == .moved(to: .applying))
        #expect(HandoffTransitions.ordinary(.applied, from: .applying) == .removed)
        // They exist in the table because S5 must recover rows S6 leaves in those phases.
        #expect(Self.ordinary(phase: .applying).isWellFormed)
        #expect(HandoffTransitions.ordinary(.applied, from: .receipt) == nil)
    }

    // MARK: - Payload (C9.7.17) and the canonical empty payload (C9.7.5 L3593)

    @Test func canonicalEmptyPayloadIsTheFourMemberSetWithBothCollectionsEmpty() {
        let auth = HandoffSignedAuth.signedIn(uid: "u1", installationId: "i1", epochUUID: "e1", credentialRevision: 0)
        let payload = HandoffPayloadV1.canonicalEmpty(installationId: "i1", auth: auth)
        #expect(payload.isEmpty)
        #expect(payload.pendingRecordCount == 0)
        let map = payload.map()
        #expect(Set(map.keys) == ["installation", "auth", "sessions", "reconciliationCancels"])
        #expect(HandoffPayloadV1.from(map) == payload)
        // The two singletons are excluded from the counted universe (C9.7.6 L3624).
        var populated = payload
        populated.records = [Self.ordinary(phase: .prepared)]
        populated.reconciliationCancels = [Self.cancel(phase: .preflight)]
        #expect(populated.pendingRecordCount == 2)
        #expect(HandoffPayloadV1.from(populated.map()) == populated)
    }

    @Test func payloadRejectsAnyOtherMemberSet() {
        let auth = HandoffSignedAuth.signedOut(installationId: "i1", epochUUID: "e1")
        let base = HandoffPayloadV1.canonicalEmpty(installationId: "i1", auth: auth).map()
        for key in base.keys {
            var mutated = base
            mutated.removeValue(forKey: key)
            #expect(HandoffPayloadV1.from(mutated) == nil, Comment(rawValue: "payload without \(key)"))
        }
        var extra = base
        extra["refreshLease"] = "x"
        #expect(HandoffPayloadV1.from(extra) == nil, "the payload is an exact four-member set")
    }

    /// C9.7.9 L3742: SIGNED_OUT carries no uid and no credential revision, and the row's
    /// revision is always this singleton's rather than a record member.
    @Test func signedAuthSingletonHasTwoExactShapes() {
        let out = HandoffSignedAuth.signedOut(installationId: "i1", epochUUID: "e1")
        #expect(out.credentialRevision == nil)
        #expect(Set(out.map().keys) == ["state", "installationId", "epochUUID"])
        #expect(HandoffSignedAuth.from(out.map()) == out)

        let inAuth = HandoffSignedAuth.signedIn(uid: "u1", installationId: "i1", epochUUID: "e1", credentialRevision: 3)
        #expect(inAuth.credentialRevision == 3)
        #expect(Set(inAuth.map().keys) == ["state", "uid", "installationId", "epochUUID", "credentialRevision"])
        #expect(HandoffSignedAuth.from(inAuth.map()) == inAuth)

        var crossed = out.map()
        crossed["uid"] = "u1"
        #expect(HandoffSignedAuth.from(crossed) == nil, "a signed-out singleton never carries a uid")
        var negative = inAuth.map()
        negative["credentialRevision"] = -1
        #expect(HandoffSignedAuth.from(negative) == nil)
    }

    // MARK: - Application identity

    @Test func applicationIdentityIsThePrefixedFirstForty() {
        let id = HandoffApplicationIdentity.ordinary(uid: "u1", identityDigest: Self.sha, receiptSHA256: Self.sha)
        #expect(id.hasPrefix("hap1_"))
        #expect(id.count == 45)
        #expect(id == HandoffApplicationIdentity.ordinary(uid: "u1", identityDigest: Self.sha, receiptSHA256: Self.sha))
        #expect(id != HandoffApplicationIdentity.ordinary(uid: "u2", identityDigest: Self.sha, receiptSHA256: Self.sha))
    }

    // MARK: - Identity maps (C9.7.8 L3698, L3699)

    @Test func identityMapsAreTheContractsAndCarryNoTaskDocumentId() {
        let ordinaryMap = Self.ordinary(phase: .prepared).identityMap()
        #expect(ordinaryMap.map { Set($0.keys) } == ["kind", "action", "uid", "installationId",
                                                     "authEpochUUID", "taskInstanceId", "sessionId"])
        #expect(ordinaryMap?["kind"] as? String == "handoff")

        let cancelMap = Self.cancel(phase: .preflight).identityMap()
        #expect(Set(cancelMap.keys) == ["kind", "uid", "taskInstanceId", "sessionId", "reasonCode",
                                        "requesterInstallationId", "requesterAuthEpochUUID"])
        #expect(cancelMap["kind"] as? String == "handoff_cancel")
        // The stored namespace is in the recovery key and not in the identity digest.
        #expect(cancelMap["storedInstallationId"] == nil)
    }
}
