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
                isSaving: isSaving,
                onSave: saveCustomization,
                onCancel: {
                    draftKit = nil
                    didEditCustomization = false
                    if !hasCustomizedKit { restoredCustomizationValue = nil }
                }
            )
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

                    Text("Sized from your home scan")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        quantityLine("Small boxes", kit.small, id: "small")
                        quantityLine("Medium boxes", kit.medium, id: "medium")
                        quantityLine("Large boxes", kit.large, id: "large")
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

                    Text("Estimated kit: \(formattedPrice(kit.totalPriceCents))")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .accessibilityIdentifier("kit.price")

                    if let deliveryBy = kit.deliveryBy {
                        Text("Deliver by \(deliveryBy.formatted(date: .abbreviated, time: .omitted)) — before your first packing session.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("kit.delivery")
                    }

                    // Copy LOCKED (Spec 06 Phase B).
                    Text("Includes a few extra — running out mid-pack is worse than spares.")
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
                    isSubmitting ? "Sending…" : "Order my kit",
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
                Text("Kit request sent. Peezy is lining up the supplies before packing starts.")
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

    private func loadKit() async {
        errorMessage = nil
        do {
            let loaded = try await actionService.loadSuppliesKitState(userId: userId, taskId: taskId)
            let loadedKit = restoredCustomizationValue
                .flatMap { Self.applyingCustomization($0, to: loaded.kit) }
                ?? loaded.kit
            kit = loadedKit
            hasCustomizedKit = loaded.wasCustomized || restoredCustomizationValue != nil
            if !didLogOfferView {
                didLogOfferView = true
                AnalyticsEvents.kitOfferViewed(itemTotal: itemTotal(loadedKit))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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
            kit.small, kit.medium, kit.large, kit.wardrobe, kit.dishPack,
            kit.tape, kit.paper, kit.wrap, kit.mattressBags
        ]
        .map(String.init)
        .joined(separator: ",")
    }

    private static func applyingCustomization(_ value: String, to base: SuppliesKit) -> SuppliesKit? {
        let values = value.split(separator: ",").compactMap { Int($0) }
        guard values.count == 9 else { return nil }
        var result = base
        result.small = values[0]
        result.medium = values[1]
        result.large = values[2]
        result.wardrobe = values[3]
        result.dishPack = values[4]
        result.tape = values[5]
        result.paper = values[6]
        result.wrap = values[7]
        result.mattressBags = values[8]
        return result
    }

    private func itemTotal(_ kit: SuppliesKit) -> Int {
        kit.small + kit.medium + kit.large + kit.wardrobe + kit.dishPack
            + kit.tape + kit.paper + kit.wrap + kit.mattressBags
    }
}

private struct SuppliesKitOrderPayload: Codable {
    let small: Int
    let medium: Int
    let large: Int
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

private struct SuppliesKitCustomizeSheet: View {
    @Binding var kit: SuppliesKit
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var questionIndex = 0

    private enum KitField: CaseIterable {
        case small
        case medium
        case large
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
            case .wardrobe: "wardrobe"
            case .dishPack: "dish_pack"
            case .tape: "tape"
            case .paper: "paper"
            case .wrap: "wrap"
            case .mattressBags: "mattress_bags"
            }
        }
    }

    private var currentField: KitField {
        KitField.allCases[min(questionIndex, KitField.allCases.count - 1)]
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Item \(questionIndex + 1) of \(KitField.allCases.count)")
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
                    HStack {
                        Text("Estimated kit")
                        Spacer()
                        Text(String(format: "$%.2f", Double(kit.totalPriceCents) / 100))
                            .bold()
                    }
                    .accessibilityIdentifier("kit.customize.price")

                    PeezyAssessmentButton(
                        questionIndex == KitField.allCases.count - 1
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
        if questionIndex == KitField.allCases.count - 1 {
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
