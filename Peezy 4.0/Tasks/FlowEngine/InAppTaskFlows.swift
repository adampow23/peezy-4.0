//
//  InAppTaskFlows.swift
//  Peezy 4.0
//
//  The four catalog-v2 in-app tasks (Spec 04 Phase B):
//  - AddNewAddressFlow    (ADD_NEW_ADDRESS: newAddressPending escape hatch;
//                          reuses the Settings EditAddressSheet, clears the
//                          flag, recomputes distance via IdentityService)
//  - ConfirmMoveDateFlow  (CONFIRM_MOVE_DATE: moveDatePending escape hatch;
//                          kit ConfirmDateCard, clears the flag)
//  - DeclutterIntentFlow  (DECLUTTER_INTENT tier-2 dose card: one tap sets
//                          hasDeclutter/wantToSell, then add-only generation
//                          surfaces SELL_ITEMS or REMOVE_ITEMS)
//  - StorageNeedFlow      (STORAGE_NEED tier-2 dose card: one tap sets
//                          storageNeeded; STORAGE_UNIT conditions on it)
//
//  All four are routed by the explicit in-app map (Phase C), complete via
//  onComplete → PeezyHomeViewModel.completeTaskFlow (selfServiceOnly →
//  Completed). Assessment-key writes update users/{uid}/user_assessments first,
//  then best-effort mirror into the entries-shaped userKnowledge document.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Shared write plumbing

enum InAppTaskWrites {

    /// Updates the assessment doc (first doc — Settings' saveMoveDetailField
    /// pattern) and mirrors to userKnowledge best-effort.
    /// Returns the merged assessment data for downstream generation.
    @discardableResult
    static func updateAssessmentKeys(_ keys: [String: Any], userId: String) async throws -> [String: Any] {
        let db = Firestore.firestore()
        let snapshot = try await db.collection("users").document(userId)
            .collection("user_assessments")
            .limit(to: 1)
            .getDocuments()

        var merged: [String: Any] = [:]
        if let doc = snapshot.documents.first {
            try await doc.reference.updateData(keys)
            merged = doc.data()
        }
        try? await UserKnowledgeService.merge(
            keys,
            source: .assessment,
            userId: userId
        )

        for (key, value) in keys { merged[key] = value }
        return merged
    }

    /// Add-only generation pass after a dose card writes new keys — creates
    /// tasks that now match (never touches existing docs).
    static func generateNewMatches(assessment: [String: Any], userId: String) async {
        let moveDate = (assessment["moveDate"] as? Timestamp)?.dateValue() ?? Date()
        do {
            let count = try await TaskGenerationService().generateNewlyMatchingTasks(
                userId: userId, assessment: assessment, moveDate: moveDate
            )
            #if DEBUG
            print("🌱 Incremental generation: \(count) new task(s)")
            #endif
        } catch {
            print("⚠️ Incremental generation failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Saving overlay (shared chrome)

private struct InAppFlowSaving: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(PeezyTheme.Colors.deepInk)
            Text("Saving...")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("inapp.saving")
    }
}

// MARK: - Add New Address

struct AddNewAddressFlow: View {
    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    @State private var showSheet = false
    @State private var isSaving = false
    @State private var addressDraft = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: 1, currentIndex: 0) {
                Group {
                    if isSaving {
                        InAppFlowSaving()
                    } else {
                        TaskFlowTitleCard(
                            taskTitle: "Add your new address",
                            icon: "mappin.and.ellipse",
                            primaryLabel: "Add address",
                            onContinue: { showSheet = true }
                        )
                    }
                }
                .accessibilityIdentifier("inapp.add_new_address")
            }

        }
        .sheet(isPresented: $showSheet) {
            EditAddressSheet(
                title: "New Address",
                currentValue: addressDraft,
                onDraftChange: { addressDraft = $0 }
            ) { newValue in
                save(raw: newValue)
            }
        }
        .resumableFlowProgress(
            path: ["add_address"],
            answers: addressDraft.isEmpty ? [:] : ["address_draft": [addressDraft]]
        ) { restored in
            addressDraft = restored.answers["address_draft"]?.first ?? ""
        }
    }

    private func save(raw: String) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                // Identity is the authority: address + pending flag + distance
                // (Settings' saveAddressEdit pattern).
                var identity = await IdentityService.shared.loadOrMigrate(userId: userId)
                    ?? PeezyIdentity(name: "", email: Auth.auth().currentUser?.email ?? "")
                identity.newAddress = PeezyAddress.parse(addressString: raw)
                identity.newAddressPending = false

                var assessmentKeys: [String: Any] = [
                    "newAddress": raw,
                    "newAddressPending": false
                ]

                if let current = identity.currentAddress?.raw,
                   let result = await IdentityService.shared.geocodedDistance(from: current, to: raw) {
                    identity.moveDistanceMiles = result.miles
                    identity.isInterstate = result.isInterstate
                    assessmentKeys["moveDistance"] = result.miles >= 50 ? "Long Distance" : "Local"
                    assessmentKeys["isInterstate"] = result.isInterstate ? "Yes" : "No"
                }

                try await IdentityService.shared.save(identity, userId: userId)
                try await InAppTaskWrites.updateAssessmentKeys(assessmentKeys, userId: userId)

                await MainActor.run { onComplete() }
            } catch {
                print("⚠️ Add-address save failed: \(error.localizedDescription)")
                await MainActor.run {
                    isSaving = false
                    ToastManager.shared.show("Couldn't save the address — please try again", style: .error)
                }
            }
        }
    }
}

// MARK: - Confirm Move Date

struct ConfirmMoveDateFlow: View {
    let userId: String
    let taskId: String
    let currentDate: Date
    let onComplete: () -> Void
    let onDismiss: () -> Void

    @State private var isSaving = false
    @State private var restoredDraftDate: Date?

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: 1, currentIndex: 0) {
                Group {
                    if isSaving {
                        InAppFlowSaving()
                    } else {
                        TaskFlowConfirmDateCard(
                            taskTitle: "Lock in your move date",
                            question: "Is this the real date?",
                            currentDate: restoredDraftDate ?? currentDate,
                            confirmLabel: "Lock it in",
                            onDraftChange: { restoredDraftDate = $0 },
                            onConfirm: { date in save(date: date) }
                        )
                    }
                }
                .accessibilityIdentifier("inapp.confirm_move_date")
            }

        }
        .resumableFlowProgress(
            path: ["confirm_date"],
            answers: restoredDraftDate.map {
                ["move_date_draft": [ISO8601DateFormatter().string(from: $0)]]
            } ?? [:]
        ) { restored in
            guard let raw = restored.answers["move_date_draft"]?.first else { return }
            restoredDraftDate = ISO8601DateFormatter().date(from: raw)
        }
    }

    private func save(date: Date) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                try? await IdentityService.shared.update(userId: userId) {
                    $0.moveDate = date
                    $0.moveDatePending = false
                }
                try await InAppTaskWrites.updateAssessmentKeys([
                    "moveDate": Timestamp(date: date),
                    "moveDatePending": false
                ], userId: userId)
                await MainActor.run { onComplete() }
            } catch {
                print("⚠️ Move-date save failed: \(error.localizedDescription)")
                await MainActor.run {
                    isSaving = false
                    ToastManager.shared.show("Couldn't save the date — please try again", style: .error)
                }
            }
        }
    }
}

// MARK: - Declutter Intent (tier-2 dose card)

struct DeclutterIntentFlow: View {
    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    @State private var isSaving = false
    @State private var selected: Set<String> = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: 1, currentIndex: 0) {
                Group {
                    if isSaving {
                        InAppFlowSaving()
                    } else {
                        TaskFlowTilesCard(
                            taskTitle: "Lighten the load?",
                            question: "Lightening the load before the move?",
                            options: [
                                FlowOption(id: "sell", label: "Yes — I'll sell some of it", icon: "dollarsign.circle"),
                                FlowOption(id: "donate", label: "Yes — donate or junk it", icon: "shippingbox"),
                                FlowOption(id: "no", label: "Not this move", icon: "xmark.circle")
                            ],
                            mode: .single,
                            selectedIds: selected,
                            onSelect: { id in
                                selected = [id]
                                save(choice: id)
                            }
                        )
                    }
                }
                .accessibilityIdentifier("inapp.declutter_intent")
            }

        }
        .resumableFlowProgress(
            path: ["declutter_intent"],
            answers: selected.isEmpty ? [:] : ["declutter_intent": selected.sorted()]
        ) { restored in
            selected = Set(restored.answers["declutter_intent"] ?? [])
        }
    }

    private func save(choice: String) {
        guard !isSaving else { return }
        isSaving = true
        let keys: [String: Any] = [
            "hasDeclutter": choice == "no" ? "No" : "Yes",
            "wantToSell": choice == "sell" ? "Yes" : "No"
        ]
        Task {
            do {
                let merged = try await InAppTaskWrites.updateAssessmentKeys(keys, userId: userId)
                await InAppTaskWrites.generateNewMatches(assessment: merged, userId: userId)
                await MainActor.run { onComplete() }
            } catch {
                print("⚠️ Declutter save failed: \(error.localizedDescription)")
                await MainActor.run {
                    isSaving = false
                    ToastManager.shared.show("Couldn't save — please try again", style: .error)
                }
            }
        }
    }
}

// MARK: - Storage Need (tier-2 dose card)

struct StorageNeedFlow: View {
    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    @State private var isSaving = false
    @State private var selected: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: 1, currentIndex: 0) {
                Group {
                    if isSaving {
                        InAppFlowSaving()
                    } else {
                        TaskFlowCompactTilesCard(
                            taskTitle: "Need a storage unit?",
                            question: "Will everything fit — or might you need a unit?",
                            options: [
                                FlowOption(id: "need", label: "I'll need a unit", icon: "archivebox"),
                                FlowOption(id: "fits", label: "It all fits", icon: "checkmark.circle")
                            ],
                            selectedId: selected,
                            onSelect: { id in
                                selected = id
                                save(needsStorage: id == "need")
                            }
                        )
                    }
                }
                .accessibilityIdentifier("inapp.storage_need")
            }

        }
        .resumableFlowProgress(
            path: ["storage_need"],
            answers: selected.map { ["storage_need": [$0]] } ?? [:]
        ) { restored in
            selected = restored.answers["storage_need"]?.first
        }
    }

    private func save(needsStorage: Bool) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                let merged = try await InAppTaskWrites.updateAssessmentKeys(
                    ["storageNeeded": needsStorage ? "Yes" : "No"], userId: userId
                )
                await InAppTaskWrites.generateNewMatches(assessment: merged, userId: userId)
                await MainActor.run { onComplete() }
            } catch {
                print("⚠️ Storage-need save failed: \(error.localizedDescription)")
                await MainActor.run {
                    isSaving = false
                    ToastManager.shared.show("Couldn't save — please try again", style: .error)
                }
            }
        }
    }
}
