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
    @State private var packedBoxIDs: Set<String> = []
    @State private var hasEditedBoxChecks = false
    @State private var isEvidenceExpanded = false

    private let actionService = TaskActionService()
    private let v2PrimaryText = Color.white
    private let v2SecondaryText = Color.white.opacity(0.72)
    private let v2TertiaryText = Color.white.opacity(0.52)
    private let v2InsetFill = Color.white.opacity(0.08)

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
            answers: packingProgressAnswers
        ) { restored in
            consequenceLine = restored.answers["packed"]?.first
            let restoredBoxIDs = Set(restored.answers["packedBoxes"] ?? [])
            if let packingV2Plan {
                packedBoxIDs = restoredBoxIDs.intersection(Set(packingV2Plan.boxes.map(\.id)))
            } else {
                packedBoxIDs = restoredBoxIDs
            }
        }
        .flowAnswerProbe {
            isSaving
                || consequenceLine != nil
                || (packingV2Plan != nil && hasEditedBoxChecks)
        }
    }

    private var packingProgressAnswers: [String: [String]] {
        var answers: [String: [String]] = [:]
        if packingV2Plan != nil {
            answers["packedBoxes"] = packedBoxIDs.sorted()
        }
        if let consequenceLine {
            answers["packed"] = [consequenceLine]
        }
        return answers
    }

    @ViewBuilder
    private var content: some View {
        if let consequenceLine {
            if packingV2Plan != nil {
                packingV2Consequence(consequenceLine)
            } else {
                legacyConsequence(consequenceLine)
            }
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
        let nextBoxID = currentBoxID(in: plan.boxes)
        let displayBoxes = boxesForDisplay(plan.boxes, currentBoxID: nextBoxID)

        return VStack(spacing: 0) {
            packingV2Header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Today: \(session.roomLabel). \(plan.timeRange.label(centralMinutes: Double(session.estMinutes))).")
                        .font(.title)
                        .bold()
                        .foregroundStyle(v2PrimaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("packing.session.title")

                    Text("\(packedBoxCount(in: plan.boxes)) of \(plan.boxes.count) boxes packed")
                        .font(.headline)
                        .foregroundStyle(v2SecondaryText)
                        .accessibilityIdentifier("packingBoxProgress")

                    if session.isBehindPace {
                        Text("You're behind pace — movers charge by the hour, and unpacked homes run long. Today's session matters.")
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("packing.session.behind_pace")
                    }

                    if !plan.restricted.isEmpty {
                        restrictedSection(plan)
                    }

                    if !plan.openFirst.isEmpty {
                        keepOutStrip(plan.openFirst)
                    }

                    if !plan.boxes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Box plan")
                                .font(.headline)
                                .foregroundStyle(v2PrimaryText)

                            ForEach(Array(displayBoxes.enumerated()), id: \.element.id) { index, displayBox in
                                boxRow(
                                    displayBox,
                                    ordinal: index + 1,
                                    timeRange: plan.timeRange,
                                    showsRoom: session.rooms.count > 1,
                                    isCurrent: displayBox.id == nextBoxID
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

                    evidenceDisclosure(plan.evidence)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }

            packingV2SessionActions(plan)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 36)
                .fill(PeezyTheme.Colors.deepInk)
        )
        .clipShape(RoundedRectangle(cornerRadius: 36))
        .accessibilityIdentifier("packing.session.card.v2")
    }

    private var packingV2Header: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox.fill")
                .font(.subheadline)
                .accessibilityHidden(true)

            Spacer()

            Text("PACKING PLAN")
                .font(.caption.bold())
                .tracking(1.5)
                .lineLimit(1)
        }
        .foregroundStyle(v2TertiaryText)
        .padding(.top, 24)
        .padding(.horizontal, 24)
        .accessibilityIdentifier("packing.session.header.v2")
    }

    private var betaLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Packing engine · beta")
                .font(.caption.bold())
                .foregroundStyle(v2PrimaryText)
            Text("Estimates improve as movers like you use it.")
                .font(.caption)
                .foregroundStyle(v2TertiaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("packing.session.beta")
    }

    private func evidenceDisclosure(_ evidence: PackingV2Evidence) -> some View {
        DisclosureGroup(isExpanded: $isEvidenceExpanded) {
            evidenceDetails(evidence)
                .padding(.top, 12)
        } label: {
            betaLabel
        }
        .tint(v2PrimaryText)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(v2InsetFill)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityIdentifier("packing.session.beta_evidence")
    }

    private func evidenceDetails(_ evidence: PackingV2Evidence) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("What this plan is based on.")
                    .font(.headline)
                    .foregroundStyle(v2PrimaryText)
                Spacer()
                Text(evidence.coverageGrade)
                    .font(.caption.bold())
                    .foregroundStyle(v2PrimaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(PeezyTheme.Colors.infoBlue.opacity(0.28))
                    .clipShape(Capsule())
            }

            Text("\(evidence.assignedCount) assigned + \(evidence.reserveCount) reserve")
                .font(.subheadline.bold())
                .foregroundStyle(v2PrimaryText)

            Text(evidence.basedOn)
                .font(.subheadline)
                .foregroundStyle(v2SecondaryText)

            if !evidence.couldNotVerify.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Could not verify")
                        .font(.subheadline.bold())
                        .foregroundStyle(v2PrimaryText)
                    ForEach(evidence.couldNotVerify) { item in
                        Text("• \(quantityPrefix(item.qty))\(item.name): \(item.reason)")
                            .font(.footnote)
                            .foregroundStyle(v2SecondaryText)
                    }
                }
            }

            if !evidence.mostUncertain.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Most uncertain")
                        .font(.subheadline.bold())
                        .foregroundStyle(v2PrimaryText)
                    ForEach(evidence.mostUncertain) { item in
                        Text("• \(item.name): \(uncertaintyReasons(item.reasons))")
                            .font(.footnote)
                            .foregroundStyle(v2SecondaryText)
                    }
                }
            }

            Text(evidence.notIncluded)
                .font(.footnote)
                .foregroundStyle(v2TertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .foregroundStyle(v2PrimaryText)
                    if let guidance = plan.transportGuidance[item.policy] {
                        Text(guidance)
                            .font(.footnote)
                            .foregroundStyle(v2SecondaryText)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(v2InsetFill)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(PeezyTheme.Colors.emotionalRed.opacity(0.45), lineWidth: 1)
        )
        .accessibilityIdentifier("packing.session.restricted")
    }

    private func boxRow(
        _ displayBox: PackingV2DisplayBox,
        ordinal: Int,
        timeRange: PackingV2TimeRange,
        showsRoom: Bool,
        isCurrent: Bool
    ) -> some View {
        let box = displayBox.box
        let isPacked = packedBoxIDs.contains(displayBox.id)
        let primaryText = isCurrent
            ? v2PrimaryText
            : (isPacked ? v2SecondaryText : Color.white.opacity(0.64))
        let secondaryText = isCurrent
            ? v2SecondaryText
            : (isPacked ? v2TertiaryText : Color.white.opacity(0.42))
        let fill = isCurrent
            ? Color.white.opacity(0.14)
            : (isPacked ? Color.white.opacity(0.08) : Color.white.opacity(0.035))
        let border = isCurrent
            ? Color.white.opacity(0.72)
            : (isPacked ? Color.white.opacity(0.18) : Color.white.opacity(0.10))
        let title = showsRoom
            ? "\(displayBox.roomName) · Box \(box.n) · \(boxSizeLabel(box.size))"
            : "Box \(box.n) · \(boxSizeLabel(box.size))"

        return VStack(alignment: .leading, spacing: 6) {
            if isCurrent {
                Text("UP NEXT")
                    .font(.caption.bold())
                    .tracking(1.2)
                    .foregroundStyle(v2PrimaryText)
                    .accessibilityIdentifier("packingBoxUpNext")
            }

            Button {
                togglePackedBox(displayBox.id)
            } label: {
                VStack(alignment: .leading, spacing: isPacked ? 0 : 8) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 5) {
                            Image(systemName: isPacked ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                            if isPacked {
                                Text("Packed")
                                    .font(.subheadline.bold())
                            }
                        }
                        .foregroundStyle(isPacked ? v2PrimaryText : primaryText)
                        .frame(minWidth: 44, minHeight: 44)
                    }

                    if !isPacked {
                        Text(boxItemSummary(box.items))
                            .font(.body)
                            .foregroundStyle(primaryText)
                        Text(timeRange.label(centralMinutes: box.estMinutes))
                            .font(.subheadline)
                            .foregroundStyle(secondaryText)
                        if !box.layers.isEmpty {
                            Text("Layer order, bottom to top: \(box.layers.joined(separator: " → "))")
                                .font(.footnote)
                                .foregroundStyle(secondaryText)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(displayBox.roomName), Box \(box.n), \(boxSizeLabel(box.size))")
            .accessibilityValue(isPacked ? "Packed" : (isCurrent ? "Current" : "Not packed"))
            .accessibilityIdentifier("packingBoxCheck_\(ordinal)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(border, lineWidth: isCurrent ? 1.5 : 1)
        )
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
                .foregroundStyle(v2SecondaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(v2InsetFill)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .foregroundStyle(v2PrimaryText)
        .accessibilityIdentifier("packing.session.leftovers")
    }

    private func legacyChecklist(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session checklist")
                .font(.headline)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Label(item, systemImage: "checklist")
                    .font(.body)
                    .foregroundStyle(v2SecondaryText)
            }
        }
        .foregroundStyle(v2PrimaryText)
        .accessibilityIdentifier("packing.session.v2_checklist")
    }

    private func keepOutStrip(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Keep these out", systemImage: "handbag.fill")
                .font(.headline)
            Text(items.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(v2SecondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(v2InsetFill)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(PeezyTheme.Colors.infoBlue.opacity(0.38), lineWidth: 1)
        )
        .foregroundStyle(v2PrimaryText)
        .accessibilityIdentifier("packing.session.keep_out")
    }

    private func packingV2SessionActions(_ plan: PackingV2SessionPlan) -> some View {
        let allBoxesPacked = allBoxesPacked(in: plan.boxes)

        return VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
            Button(action: complete) {
                HStack(spacing: 8) {
                    if allBoxesPacked {
                        Image(systemName: "checkmark")
                            .accessibilityHidden(true)
                    }
                    Text("Finish this packing session")
                        .font(.headline)
                }
                .foregroundStyle(allBoxesPacked ? PeezyTheme.Colors.deepInk : v2PrimaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule()
                        .fill(allBoxesPacked ? Color.white : Color.clear)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white, lineWidth: 1.5)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("packing.session.complete")

            if allBoxesPacked {
                Text("All planned boxes packed")
                    .font(.caption)
                    .foregroundStyle(v2SecondaryText)
                    .accessibilityIdentifier("packingAllBoxesPacked")
            }

            Button {
                onStatusAction(.later)
            } label: {
                Text("Do this later")
                    .font(.headline)
                    .foregroundStyle(v2PrimaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        Capsule()
                            .stroke(Color.white.opacity(0.78), lineWidth: 1.5)
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .accessibilityIdentifier("packing.session.snooze")

            Button("Close", action: onDismiss)
                .font(.subheadline)
                .foregroundStyle(v2TertiaryText)
                .frame(minHeight: 44)
                .disabled(isSaving)
                .accessibilityIdentifier("packing.session.close")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 12)
    }

    private func packingV2Consequence(_ line: String) -> some View {
        VStack(spacing: 0) {
            packingV2Header

            Spacer()

            VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(PeezyTheme.Colors.successGreen)
                    .accessibilityHidden(true)

                Text(line)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(v2PrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("packing.session.consequence")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer()

            Button(action: onComplete) {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.white, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .accessibilityIdentifier("packing.session.done")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 36)
                .fill(PeezyTheme.Colors.deepInk)
        )
        .clipShape(RoundedRectangle(cornerRadius: 36))
        .accessibilityIdentifier("packing.session.completed.v2")
    }

    private func legacyConsequence(_ line: String) -> some View {
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

    private func currentBoxID(in boxes: [PackingV2DisplayBox]) -> String? {
        boxes.first { !packedBoxIDs.contains($0.id) }?.id
    }

    private func boxesForDisplay(
        _ boxes: [PackingV2DisplayBox],
        currentBoxID: String?
    ) -> [PackingV2DisplayBox] {
        guard let currentBoxID,
              let currentBox = boxes.first(where: { $0.id == currentBoxID })
        else { return boxes }
        return [currentBox] + boxes.filter { $0.id != currentBoxID }
    }

    private func packedBoxCount(in boxes: [PackingV2DisplayBox]) -> Int {
        let currentIDs = Set(boxes.map(\.id))
        return packedBoxIDs.intersection(currentIDs).count
    }

    private func allBoxesPacked(in boxes: [PackingV2DisplayBox]) -> Bool {
        !boxes.isEmpty && packedBoxCount(in: boxes) == boxes.count
    }

    private func togglePackedBox(_ id: String) {
        hasEditedBoxChecks = true
        if packedBoxIDs.contains(id) {
            packedBoxIDs.remove(id)
        } else {
            packedBoxIDs.insert(id)
        }
        PeezyHaptics.selection()
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
            let loadedV2Plan = try? await loadPackingV2Plan(for: loadedSession)
            packingV2Plan = loadedV2Plan
            if let loadedV2Plan {
                packedBoxIDs.formIntersection(Set(loadedV2Plan.boxes.map(\.id)))
            }
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
