import FirebaseFirestore
import SwiftUI

struct SuppliesKitView: View {
    let userId: String
    let taskId: String
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var kit: SuppliesKit?
    @State private var draftKit: SuppliesKit?
    @State private var isSaving = false
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var didLogOfferView = false
    @State private var errorMessage: String?
    @State private var hasCustomizedKit = false
    @State private var didEditCustomization = false
    @State private var restoredCustomizationValue: String?
    @State private var packingAllocation: PackingSupplyAllocation?
    @State private var reserveDetails: ReserveDetails?

    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    private let actionService = TaskActionService()

    @ViewBuilder
    var body: some View {
        if PaywallPolicy.requiresMovePass(for: .supplies),
           !subscriptionManager.isSubscribed {
            PaywallGateSheet(surface: .supplies) { subscribed in
                if !subscribed {
                    onDismiss()
                }
            }
        } else {
            kitFlow
        }
    }

    private var kitFlow: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: 1, currentIndex: 0) {
                content
            }
        }
        .task { await loadKit() }
        .sheet(item: $draftKit) { presentedKit in
            SuppliesKitCustomizeSheet(
                kit: Binding(
                    get: { self.draftKit ?? presentedKit },
                    set: {
                        self.draftKit = $0
                        self.didEditCustomization = true
                    }
                ),
                includesExtraLarge: packingAllocation != nil,
                isSaving: isSaving,
                onSave: saveCustomization,
                onCancel: {
                    draftKit = nil
                    didEditCustomization = false
                    if !hasCustomizedKit { restoredCustomizationValue = nil }
                }
            )
        }
        .sheet(item: $reserveDetails) { details in
            ReserveReasonsSheet(details: details)
        }
        .accessibilityIdentifier("kit.flow")
        .resumableFlowProgress(
            path: [submitted ? "submitted" : "kit"],
            answers: customizationProgressAnswers
        ) { restored in
            restoredCustomizationValue = restored.answers["kit_customization"]?.first
            hasCustomizedKit = restoredCustomizationValue != nil
        }
        .flowAnswerProbe {
            isSaving || isSubmitting || hasCustomizedKit || didEditCustomization
        }
    }

    @ViewBuilder
    private var content: some View {
        if submitted {
            submittedCard
        } else if let kit {
            kitCard(kit)
        } else if let errorMessage {
            errorCard(errorMessage)
        } else {
            ProgressView("Building your kit…")
                .tint(PeezyTheme.Colors.deepInk)
                .accessibilityIdentifier("kit.loading")
        }
    }

    private func kitCard(_ kit: SuppliesKit) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Packing supplies")

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "shippingbox.and.arrow.backward.fill")
                        .font(.largeTitle)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .accessibilityHidden(true)

                    Text("Your packing kit")
                        .font(.title)
                        .bold()
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .accessibilityIdentifier("kit.title")

                    if packingAllocation != nil {
                        betaLabel
                    }

                    Text(
                        packingAllocation == nil
                            ? "Sized from your home scan"
                            : "Based on the items visible in your walkthrough and the inventory you confirmed."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        if let packingAllocation {
                            packingQuantityLine(
                                "Small boxes",
                                currentValue: kit.small,
                                breakdown: packingAllocation[.small],
                                size: .small
                            )
                            packingQuantityLine(
                                "Medium boxes",
                                currentValue: kit.medium,
                                breakdown: packingAllocation[.medium],
                                size: .medium
                            )
                            packingQuantityLine(
                                "Large boxes",
                                currentValue: kit.large,
                                breakdown: packingAllocation[.large],
                                size: .large
                            )
                            packingQuantityLine(
                                "Extra-large boxes",
                                currentValue: kit.xl,
                                breakdown: packingAllocation[.xl],
                                size: .xl
                            )
                        } else {
                            quantityLine("Small boxes", kit.small, id: "small")
                            quantityLine("Medium boxes", kit.medium, id: "medium")
                            quantityLine("Large boxes", kit.large, id: "large")
                        }
                        quantityLine("Wardrobe boxes", kit.wardrobe, id: "wardrobe")
                        quantityLine("Dish packs", kit.dishPack, id: "dish_pack")
                        quantityLine("Tape rolls", kit.tape, id: "tape")
                        quantityLine("Packing-paper packs", kit.paper, id: "paper")
                        quantityLine("Protective-wrap rolls", kit.wrap, id: "wrap")
                        quantityLine("Mattress bags", kit.mattressBags, id: "mattress_bags")
                    }
                    .padding(16)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("kit.items")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Estimated total: \(formattedPrice(kit.totalPriceCents))")
                            .font(.title3)
                            .bold()
                            .foregroundStyle(PeezyTheme.Colors.deepInk)

                        Text("Estimated at typical retail — prices vary.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("kit.price")

                    if let deliveryBy = kit.deliveryBy {
                        Text("Have these ready by \(deliveryBy.formatted(date: .abbreviated, time: .omitted)) — before your first packing session.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("kit.delivery")
                    }

                    Text(
                        packingAllocation == nil
                            ? "Includes a few extra — running out mid-pack is worse than spares."
                            : "Reserve boxes cover the specific inventory gaps listed with each size."
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("kit.headroom_copy")

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                            .accessibilityIdentifier("kit.error_message")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }

            VStack(spacing: 12) {
                PeezyAssessmentButton(
                    isSubmitting ? "Sending…" : "Send kit request",
                    disabled: isSubmitting || isSaving,
                    action: orderTapped
                )
                .accessibilityIdentifier("kit.order")

                SecondaryActionButton(title: "Customize") {
                    draftKit = restoredCustomizationValue
                        .flatMap { Self.applyingCustomization($0, to: kit) }
                        ?? kit
                }
                .disabled(isSubmitting || isSaving)
                .accessibilityIdentifier("kit.customize")

                Button("No thanks") {
                    Task { await dismissPermanently() }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .disabled(isSubmitting || isSaving)
                .accessibilityIdentifier("kit.no_thanks")

                Button("Close", action: onDismiss)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("kit.close")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .accessibilityIdentifier("kit.card")
    }

    private var submittedCard: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Packing supplies")
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(PeezyTheme.Colors.successGreen)
                    .accessibilityHidden(true)
                Text("Kit request sent. Keep this list handy so you can confirm the supplies and timing before packing starts.")
                    .font(.title2)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityIdentifier("kit.submitted_message")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            Spacer()
            PeezyAssessmentButton("Done") {
                onStatusAction(.submittedToPeezy)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .accessibilityIdentifier("kit.submitted_done")
        }
        .accessibilityIdentifier("kit.submitted")
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Packing supplies")
            Spacer()
            ContentUnavailableView {
                Label("Couldn't load your kit", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(message)
            }
            Spacer()
            PeezyAssessmentButton("Try again") { Task { await loadKit() } }
                .padding(.horizontal, 24)
                .accessibilityIdentifier("kit.retry")
            Button("Close", action: onDismiss)
                .frame(minHeight: 44)
                .padding(.bottom, 24)
                .accessibilityIdentifier("kit.error_close")
        }
        .accessibilityIdentifier("kit.error")
    }

    private func quantityLine(_ label: String, _ value: Int, id: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .bold()
        }
        .foregroundStyle(PeezyTheme.Colors.deepInk)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("kit.item.\(id)")
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
        .accessibilityIdentifier("kit.packing_beta")
    }

    private func packingQuantityLine(
        _ label: String,
        currentValue: Int,
        breakdown: PackingSupplyBreakdown,
        size: PackingSupplyBoxSize
    ) -> some View {
        let valueMatchesPlan = currentValue == breakdown.purchase
        let content = HStack(spacing: 10) {
            Text(label)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if !valueMatchesPlan {
                    Text("\(currentValue) selected")
                        .bold()
                }
                Text("\(breakdown.assigned) assigned + \(breakdown.reserve) reserve")
                    .font(valueMatchesPlan ? .body.bold() : .caption)
                    .foregroundStyle(valueMatchesPlan ? PeezyTheme.Colors.deepInk : .secondary)
            }
            if !breakdown.reasons.isEmpty {
                Image(systemName: "info.circle")
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityHidden(true)
            }
        }

        return Group {
            if breakdown.reasons.isEmpty {
                content
            } else {
                Button {
                    reserveDetails = ReserveDetails(
                        size: size,
                        label: label,
                        breakdown: breakdown
                    )
                } label: {
                    content
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(PeezyTheme.Colors.deepInk)
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            breakdown.reasons.isEmpty
                ? ""
                : "Shows why reserve boxes were included."
        )
        .accessibilityIdentifier("kit.item.\(size.rawValue)")
    }

    private func loadKit() async {
        errorMessage = nil
        do {
            let loaded = try await actionService.loadSuppliesKitState(userId: userId, taskId: taskId)
            let allocation = try? await loadPackingAllocation()
            var loadedKit = restoredCustomizationValue
                .flatMap { Self.applyingCustomization($0, to: loaded.kit) }
                ?? loaded.kit
            if let allocation,
               !loaded.wasCustomized,
               restoredCustomizationValue == nil {
                loadedKit.apply(allocation)
            }
            kit = loadedKit
            packingAllocation = allocation
            hasCustomizedKit = loaded.wasCustomized || restoredCustomizationValue != nil
            if !didLogOfferView {
                didLogOfferView = true
                AnalyticsEvents.kitOfferViewed(itemTotal: itemTotal(loadedKit))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPackingAllocation() async throws -> PackingSupplyAllocation? {
        let db = Firestore.firestore()
        let aggregateSnapshot = try await db.collection("users").document(userId)
            .collection("packingAggregate").document("current")
            .getDocument()
        guard let aggregateData = aggregateSnapshot.data() else { return nil }

        let inventorySnapshot = try await db.collection("users").document(userId)
            .collection("inventory")
            .getDocuments()
        let inventoryDocuments = inventorySnapshot.documents
            .filter { $0.documentID != "_metadata" }
            .map {
                PackingV2InventoryDocument(id: $0.documentID, data: $0.data())
            }
        return PackingSupplyAllocation(
            aggregateData: aggregateData,
            inventoryDocuments: inventoryDocuments
        )
    }

    private func saveCustomization() {
        guard var draftKit else { return }
        draftKit.clampToNonnegative()
        isSaving = true
        Task {
            do {
                try await actionService.updateSuppliesKit(userId: userId, taskId: taskId, kit: draftKit)
                await MainActor.run {
                    kit = draftKit
                    restoredCustomizationValue = Self.customizationValue(for: draftKit)
                    hasCustomizedKit = true
                    didEditCustomization = false
                    self.draftKit = nil
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    private func orderTapped() {
        errorMessage = nil
        Task { await submitOrder() }
    }

    private func submitOrder() async {
        guard let kit, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            guard let identity = await IdentityService.shared.loadOrMigrate(userId: userId) else {
                throw SuppliesKitSubmissionError.missingIdentity
            }
            let answers = try workflowAnswers(kit: kit, identity: identity)
            let response = try await WorkflowService().submitAnswers(
                workflowId: "supplies_kit",
                answers: answers,
                userId: userId
            )
            guard response.success else {
                throw WorkflowServiceError.submissionFailed(response.message)
            }
            AnalyticsEvents.kitOrdered(itemTotal: itemTotal(kit))
            if let moveDate = identity.moveDate {
                do {
                    _ = try await TaskGenerationService().generateNewlyMatchingTasks(
                        userId: userId,
                        assessment: [:],
                        moveDate: moveDate
                    )
                } catch {
                    print("⚠️ BOX_RETURN generation refresh failed: \(error.localizedDescription)")
                }
            }
            submitted = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dismissPermanently() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await actionService.dismissSuppliesKit(userId: userId, taskId: taskId)
            onStatusAction(.dismissedPermanently)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func workflowAnswers(
        kit: SuppliesKit,
        identity: PeezyIdentity
    ) throws -> WorkflowAnswers {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let kitPayload = SuppliesKitOrderPayload(
            small: kit.small,
            medium: kit.medium,
            large: kit.large,
            xl: kit.xl,
            wardrobe: kit.wardrobe,
            dishPack: kit.dishPack,
            tape: kit.tape,
            paper: kit.paper,
            wrap: kit.wrap,
            mattressBags: kit.mattressBags,
            headroomPercent: KitConstants.headroomPercent,
            totalPriceCents: kit.totalPriceCents,
            deliveryBy: kit.deliveryBy
        )
        var answers = WorkflowAnswers(workflowId: "supplies_kit")
        answers.answers["kit"] = [try jsonString(kitPayload, encoder: encoder)]
        answers.answers["identity"] = [try jsonString(identity, encoder: encoder)]
        return answers
    }

    private func jsonString<T: Encodable>(_ value: T, encoder: JSONEncoder) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func formattedPrice(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100)
    }

    private var customizationProgressAnswers: [String: [String]] {
        guard hasCustomizedKit || didEditCustomization,
              let currentKit = draftKit ?? kit
        else { return [:] }
        let value = Self.customizationValue(for: currentKit)
        return ["kit_customization": [value]]
    }

    private static func customizationValue(for kit: SuppliesKit) -> String {
        [
            kit.small, kit.medium, kit.large, kit.xl, kit.wardrobe, kit.dishPack,
            kit.tape, kit.paper, kit.wrap, kit.mattressBags
        ]
        .map(String.init)
        .joined(separator: ",")
    }

    private static func applyingCustomization(_ value: String, to base: SuppliesKit) -> SuppliesKit? {
        let values = value.split(separator: ",").compactMap { Int($0) }
        guard values.count == 9 || values.count == 10 else { return nil }
        var result = base
        result.small = values[0]
        result.medium = values[1]
        result.large = values[2]
        let offset: Int
        if values.count == 10 {
            result.xl = values[3]
            offset = 1
        } else {
            offset = 0
        }
        result.wardrobe = values[3 + offset]
        result.dishPack = values[4 + offset]
        result.tape = values[5 + offset]
        result.paper = values[6 + offset]
        result.wrap = values[7 + offset]
        result.mattressBags = values[8 + offset]
        return result
    }

    private func itemTotal(_ kit: SuppliesKit) -> Int {
        kit.small + kit.medium + kit.large + kit.xl + kit.wardrobe + kit.dishPack
            + kit.tape + kit.paper + kit.wrap + kit.mattressBags
    }
}

private struct SuppliesKitOrderPayload: Codable {
    let small: Int
    let medium: Int
    let large: Int
    let xl: Int
    let wardrobe: Int
    let dishPack: Int
    let tape: Int
    let paper: Int
    let wrap: Int
    let mattressBags: Int
    let headroomPercent: Int
    let totalPriceCents: Int
    let deliveryBy: Date?
}

private enum SuppliesKitSubmissionError: LocalizedError {
    case missingIdentity

    var errorDescription: String? {
        "Your move profile is missing. Add it in Settings before ordering the kit."
    }
}

private struct ReserveDetails: Identifiable {
    let size: PackingSupplyBoxSize
    let label: String
    let breakdown: PackingSupplyBreakdown

    var id: PackingSupplyBoxSize { size }
}

private struct ReserveReasonsSheet: View {
    let details: ReserveDetails

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Assigned", value: "\(details.breakdown.assigned)")
                    LabeledContent("Reserve", value: "\(details.breakdown.reserve)")
                }

                Section("Why reserve boxes are included") {
                    ForEach(details.breakdown.reasons) { reason in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reason.reason)
                            Text("\(reason.count) reserve")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle(details.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("kit.reserve_reasons.\(details.size.rawValue)")
    }
}

private struct SuppliesKitCustomizeSheet: View {
    @Binding var kit: SuppliesKit
    let includesExtraLarge: Bool
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var questionIndex = 0

    private enum KitField: CaseIterable {
        case small
        case medium
        case large
        case xl
        case wardrobe
        case dishPack
        case tape
        case paper
        case wrap
        case mattressBags

        var label: String {
            switch self {
            case .small: "Small boxes"
            case .medium: "Medium boxes"
            case .large: "Large boxes"
            case .xl: "Extra-large boxes"
            case .wardrobe: "Wardrobe boxes"
            case .dishPack: "Dish packs"
            case .tape: "Tape rolls"
            case .paper: "Paper packs"
            case .wrap: "Wrap rolls"
            case .mattressBags: "Mattress bags"
            }
        }

        var id: String {
            switch self {
            case .small: "small"
            case .medium: "medium"
            case .large: "large"
            case .xl: "xl"
            case .wardrobe: "wardrobe"
            case .dishPack: "dish_pack"
            case .tape: "tape"
            case .paper: "paper"
            case .wrap: "wrap"
            case .mattressBags: "mattress_bags"
            }
        }
    }

    private var fields: [KitField] {
        KitField.allCases.filter { includesExtraLarge || $0 != .xl }
    }

    private var currentField: KitField {
        fields[min(questionIndex, fields.count - 1)]
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Item \(questionIndex + 1) of \(fields.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("kit.customize.progress")

                Text("How many \(currentField.label.lowercased()) do you want?")
                    .font(.title.bold())
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("kit.customize.question.\(currentField.id)")

                quantityStepper(currentField.label, value: binding(for: currentField), id: currentField.id)

                Spacer()

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Estimated total")
                            Spacer()
                            Text(String(format: "$%.2f", Double(kit.totalPriceCents) / 100))
                                .bold()
                        }

                        Text("Estimated at typical retail — prices vary.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("kit.customize.price")

                    PeezyAssessmentButton(
                        questionIndex == fields.count - 1
                            ? (isSaving ? "Saving…" : "Save")
                            : "Continue",
                        disabled: isSaving,
                        action: advance
                    )
                    .accessibilityIdentifier("kit.customize.continue")
                }
            }
            .padding(24)
            .navigationTitle("Customize kit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("kit.customize.cancel")
                }
                if questionIndex > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { questionIndex -= 1 }
                            .disabled(isSaving)
                            .accessibilityIdentifier("kit.customize.back")
                    }
                }
            }
        }
        .accessibilityIdentifier("kit.customize.sheet")
    }

    private func advance() {
        if questionIndex == fields.count - 1 {
            onSave()
        } else {
            questionIndex += 1
        }
    }

    private func binding(for field: KitField) -> Binding<Int> {
        switch field {
        case .small: $kit.small
        case .medium: $kit.medium
        case .large: $kit.large
        case .xl: $kit.xl
        case .wardrobe: $kit.wardrobe
        case .dishPack: $kit.dishPack
        case .tape: $kit.tape
        case .paper: $kit.paper
        case .wrap: $kit.wrap
        case .mattressBags: $kit.mattressBags
        }
    }

    private func quantityStepper(
        _ label: String,
        value: Binding<Int>,
        id: String
    ) -> some View {
        Stepper(value: value, in: 0...250) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.wrappedValue)")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("kit.customize.\(id)")
    }
}

#if DEBUG
#Preview {
    SuppliesKitView(
        userId: "preview",
        taskId: SuppliesKit.taskId,
        onDismiss: {},
        onStatusAction: { _ in }
    )
}
#endif
