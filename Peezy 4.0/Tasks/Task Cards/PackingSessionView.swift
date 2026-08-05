import FirebaseFirestore
import SwiftUI

struct PackingSessionView: View {
    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var session: PackingSession?
    @State private var consequenceLine: String?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var packingV2Plan: PackingV2SessionPlan?

    private let actionService = TaskActionService()

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: 1, currentIndex: 0) {
                content
            }
        }
        .task { await loadSession() }
        .accessibilityIdentifier("packing.session.flow")
        .resumableFlowProgress(
            path: [consequenceLine == nil ? "session" : "completed"],
            answers: consequenceLine.map { ["packed": [$0]] } ?? [:]
        ) { restored in
            consequenceLine = restored.answers["packed"]?.first
        }
        .flowAnswerProbe {
            isSaving || consequenceLine != nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if let consequenceLine {
            consequence(consequenceLine)
        } else if let session {
            sessionCard(session)
        } else if let errorMessage {
            errorCard(errorMessage)
        } else {
            ProgressView("Loading today's session…")
                .tint(PeezyTheme.Colors.deepInk)
                .accessibilityIdentifier("packing.session.loading")
        }
    }

    @ViewBuilder
    private func sessionCard(_ session: PackingSession) -> some View {
        if let packingV2Plan {
            packingV2SessionCard(session, plan: packingV2Plan)
        } else {
            legacySessionCard(session)
        }
    }

    private func legacySessionCard(_ session: PackingSession) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Packing plan")

            Spacer()

            VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                Image(systemName: "shippingbox.fill")
                    .font(.largeTitle)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityHidden(true)

                Text("Today: \(session.roomLabel). About \(session.estMinutes) minutes.")
                    .font(.title)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("packing.session.title")

                Text("Here's what's in it")
                    .font(.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityIdentifier("packing.session.summary_heading")

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(session.itemSummary.enumerated()), id: \.offset) { index, item in
                        Label(item, systemImage: "checklist")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("packing.session.item.\(index)")
                    }
                }
                .accessibilityIdentifier("packing.session.summary")

                if session.isBehindPace {
                    // Copy LOCKED (Spec 06 Phase C).
                    Text("You're behind pace — movers charge by the hour, and unpacked homes run long. Today's session matters.")
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("packing.session.behind_pace")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                PeezyAssessmentButton(
                    isSaving ? "Saving…" : "I packed this",
                    disabled: isSaving,
                    action: complete
                )
                .accessibilityIdentifier("packing.session.complete")

                SecondaryActionButton(title: "Do this later") {
                    onStatusAction(.later)
                }
                .disabled(isSaving)
                .accessibilityIdentifier("packing.session.snooze")

                Button("Close", action: onDismiss)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .disabled(isSaving)
                    .accessibilityIdentifier("packing.session.close")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("packing.session.card")
    }

    private func packingV2SessionCard(
        _ session: PackingSession,
        plan: PackingV2SessionPlan
    ) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Packing plan")

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "shippingbox.fill")
                        .font(.largeTitle)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .accessibilityHidden(true)

                    Text("Today: \(session.roomLabel). \(plan.timeRange.label(centralMinutes: Double(session.estMinutes))).")
                        .font(.title)
                        .bold()
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("packing.session.title")

                    betaLabel
                    evidenceCard(plan.evidence)

                    if !plan.restricted.isEmpty {
                        restrictedSection(plan)
                    }

                    if !plan.boxes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Box plan")
                                .font(.headline)
                                .foregroundStyle(PeezyTheme.Colors.deepInk)

                            ForEach(plan.boxes) { displayBox in
                                boxCard(
                                    displayBox,
                                    timeRange: plan.timeRange,
                                    showsRoom: session.rooms.count > 1
                                )
                            }
                        }
                        .accessibilityIdentifier("packing.session.boxes")
                    }

                    if !plan.leftovers.isEmpty {
                        leftoversSection(plan.leftovers)
                    }

                    if plan.boxes.isEmpty,
                       plan.leftovers.isEmpty,
                       plan.restricted.isEmpty {
                        legacyChecklist(session.itemSummary)
                    }

                    if session.isBehindPace {
                        Text("You're behind pace — movers charge by the hour, and unpacked homes run long. Today's session matters.")
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("packing.session.behind_pace")
                    }

                    if !plan.openFirst.isEmpty {
                        keepOutStrip(plan.openFirst)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }

            sessionActions
        }
        .accessibilityIdentifier("packing.session.card.v2")
    }

    private var betaLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Packing engine · beta")
                .font(.caption.bold())
                .foregroundStyle(PeezyTheme.Colors.deepInk)
            Text("Estimates improve as movers like you use it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("packing.session.beta")
    }

    private func evidenceCard(_ evidence: PackingV2Evidence) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("What this plan is based on.")
                    .font(.headline)
                Spacer()
                Text(evidence.coverageGrade)
                    .font(.caption.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(PeezyTheme.Colors.infoBlue.opacity(0.45))
                    .clipShape(Capsule())
            }

            Text("\(evidence.assignedCount) assigned + \(evidence.reserveCount) reserve")
                .font(.subheadline.bold())

            Text(evidence.basedOn)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !evidence.couldNotVerify.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Could not verify")
                        .font(.subheadline.bold())
                    ForEach(evidence.couldNotVerify) { item in
                        Text("• \(quantityPrefix(item.qty))\(item.name): \(item.reason)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !evidence.mostUncertain.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Most uncertain")
                        .font(.subheadline.bold())
                    ForEach(evidence.mostUncertain) { item in
                        Text("• \(item.name): \(uncertaintyReasons(item.reasons))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(evidence.notIncluded)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(PeezyTheme.Colors.deepInk)
        .accessibilityIdentifier("packing.session.evidence")
    }

    private func restrictedSection(_ plan: PackingV2SessionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Set aside before packing", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(PeezyTheme.Colors.emotionalRed)

            ForEach(plan.restricted) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.subheadline.bold())
                    if let guidance = plan.transportGuidance[item.policy] {
                        Text(guidance)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PeezyTheme.Colors.emotionalRed.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("packing.session.restricted")
    }

    private func boxCard(
        _ displayBox: PackingV2DisplayBox,
        timeRange: PackingV2TimeRange,
        showsRoom: Bool
    ) -> some View {
        let box = displayBox.box
        return VStack(alignment: .leading, spacing: 8) {
            if showsRoom {
                Text(displayBox.roomName)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Text("Box \(box.n) · \(boxSizeLabel(box.size))")
                .font(.headline)
            Text(boxItemSummary(box.items))
                .font(.body)
            Text(timeRange.label(centralMinutes: box.estMinutes))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !box.layers.isEmpty {
                Text("Layer order, bottom to top: \(box.layers.joined(separator: " → "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(PeezyTheme.Colors.deepInk)
        .accessibilityIdentifier("packing.session.box.\(box.roomID).\(box.n)")
    }

    private func leftoversSection(_ leftovers: [PackingV2Leftover]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Handle separately")
                .font(.headline)
            ForEach(leftovers) { item in
                Label {
                    Text("\(item.name) — \(item.handlingNote)")
                } icon: {
                    Image(systemName: "hand.raised.fill")
                }
                .font(.subheadline)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(PeezyTheme.Colors.deepInk)
        .accessibilityIdentifier("packing.session.leftovers")
    }

    private func legacyChecklist(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session checklist")
                .font(.headline)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Label(item, systemImage: "checklist")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("packing.session.v2_checklist")
    }

    private func keepOutStrip(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Keep these out", systemImage: "handbag.fill")
                .font(.headline)
            Text(items.joined(separator: ", "))
                .font(.subheadline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PeezyTheme.Colors.infoBlue.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(PeezyTheme.Colors.deepInk)
        .accessibilityIdentifier("packing.session.keep_out")
    }

    private var sessionActions: some View {
        VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
            PeezyAssessmentButton(
                isSaving ? "Saving…" : "I packed this",
                disabled: isSaving,
                action: complete
            )
            .accessibilityIdentifier("packing.session.complete")

            SecondaryActionButton(title: "Do this later") {
                onStatusAction(.later)
            }
            .disabled(isSaving)
            .accessibilityIdentifier("packing.session.snooze")

            Button("Close", action: onDismiss)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .disabled(isSaving)
                .accessibilityIdentifier("packing.session.close")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func consequence(_ line: String) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Packing plan")

            Spacer()

            VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(PeezyTheme.Colors.successGreen)
                    .accessibilityHidden(true)

                Text(line)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("packing.session.consequence")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer()

            PeezyAssessmentButton("Done", action: onComplete)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .accessibilityIdentifier("packing.session.done")
        }
        .accessibilityIdentifier("packing.session.completed")
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Packing plan")
            Spacer()
            ContentUnavailableView {
                Label("Couldn't load this session", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(message)
                    .accessibilityIdentifier("packing.session.error_message")
            }
            Spacer()
            VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                PeezyAssessmentButton("Try again") { Task { await loadSession() } }
                    .accessibilityIdentifier("packing.session.retry")
                Button("Close", action: onDismiss)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("packing.session.error_close")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("packing.session.error")
    }

    private func boxItemSummary(_ items: [PackingV2BoxItem]) -> String {
        items.map { item in
            "\(spelledOut(item.qty)) \(sentenceCase(item.name))"
        }.joined(separator: ", ")
    }

    private func spelledOut(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func sentenceCase(_ value: String) -> String {
        guard let first = value.first,
              first.isUppercase,
              value.dropFirst().first?.isLowercase == true
        else { return value }
        return first.lowercased() + value.dropFirst()
    }

    private func quantityPrefix(_ quantity: Int) -> String {
        quantity > 1 ? "\(spelledOut(quantity)) × " : ""
    }

    private func boxSizeLabel(_ size: String) -> String {
        switch size.lowercased() {
        case "xl": "Extra Large"
        default: size.capitalized
        }
    }

    private func uncertaintyReasons(_ reasons: [String]) -> String {
        reasons.map { reason in
            switch reason {
            case "highBand": "size is at the high end of its estimate"
            case "ambiguous": "the item match is ambiguous"
            case "unmappedCubeRow": "the packing profile needs review"
            default: reason
            }
        }.joined(separator: ", ")
    }

    private func loadSession() async {
        errorMessage = nil
        do {
            let loadedSession = try await actionService.loadPackingSession(
                userId: userId,
                taskId: taskId
            )
            session = loadedSession
            packingV2Plan = try? await loadPackingV2Plan(for: loadedSession)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPackingV2Plan(
        for loadedSession: PackingSession
    ) async throws -> PackingV2SessionPlan? {
        guard let legacyPlan = try await actionService.loadPackingPlan(userId: userId)
        else { return nil }

        let db = Firestore.firestore()
        let configurationSnapshot = try await db.collection("appConfig")
            .document("packingSim")
            .getDocument()
        guard let configurationData = configurationSnapshot.data(),
              let configuration = PackingV2RenderConfiguration(
                  firestoreData: configurationData
              )
        else { return nil }

        let inventorySnapshot = try await db.collection("users").document(userId)
            .collection("inventory")
            .getDocuments()
        let roomPlans = inventorySnapshot.documents
            .filter { $0.documentID != "_metadata" }
            .compactMap { document in
                PackingV2RoomPlan(
                    inventoryDocument: PackingV2InventoryDocument(
                        id: document.documentID,
                        data: document.data()
                    ),
                    configuration: configuration
                )
            }
        return PackingV2SessionPlan.make(
            session: loadedSession,
            legacyPlan: legacyPlan,
            roomPlans: roomPlans,
            configuration: configuration
        )
    }

    private func complete() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                let result = try await actionService.completePackingSession(
                    userId: userId,
                    taskId: taskId
                )
                await MainActor.run {
                    consequenceLine = result.consequenceLine
                    isSaving = false
                    PeezyHaptics.taskComplete()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    session = nil
                    isSaving = false
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    PackingSessionView(
        userId: "preview",
        taskId: "PACKING_SESSION_1",
        onComplete: {},
        onDismiss: {},
        onStatusAction: { _ in }
    )
}
#endif
