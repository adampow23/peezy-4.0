//
//  SetupInternetFlow.swift
//  Peezy 4.0
//
//  Curated KC-area internet comparison with an attributed-link-ready handoff.
//  Address-level serviceability remains a v1.1 provider/API responsibility.
//

import SwiftUI
import SafariServices
import OSLog

struct SetupInternetFlow: View {
    let taskTitle = "Set up my internet"
    let workflowId = "setup_internet"

    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var currentIndex = 0
    @State private var plans: [ISPPlan] = []
    @State private var addressLabel = "Kansas City"
    @State private var openedPlanID: String?
    @State private var safariDestination: ISPPlanSafariDestination?
    @State private var showsOtherProviders = false
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var submissionError: String?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Peezy",
        category: "ISPPlans"
    )
    private let totalCards = 2
    private let curatedPlanLimit = 3

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: totalCards - currentIndex, currentIndex: currentIndex) {
                cardContent
            }
        }
        .task(id: userId) {
            await loadPlansAndAddress()
        }
        .sheet(item: $safariDestination) { destination in
            ISPPlanSafariView(url: destination.url)
                .ignoresSafeArea()
        }
        .confirmationDialog(
            "Other internet providers",
            isPresented: $showsOtherProviders,
            titleVisibility: .visible
        ) {
            ForEach(otherPlans) { plan in
                Button("\(plan.provider) — \(plan.tier)") {
                    open(plan)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .resumableFlowProgress(
            path: ["card.\(currentIndex)"],
            answers: openedPlanID.map { ["isp_plan": [$0]] } ?? [:]
        ) { restored in
            currentIndex = min(max(FlowProgressCoding.cardIndex(from: restored.path), 0), totalCards - 1)
            openedPlanID = restored.answers["isp_plan"]?.first
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch currentIndex {
        case 0:
            TaskFlowTitleCard(
                taskTitle: taskTitle,
                icon: "wifi",
                onContinue: { currentIndex = 1 }
            )

        case 1:
            comparisonCard

        default:
            EmptyView()
        }
    }

    private var comparisonCard: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(
                taskTitle: taskTitle,
                showBack: true,
                onBack: { currentIndex = 0 }
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                    Text("Plans for \(addressLabel)")
                        .font(.title3.bold())
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("internet.address")

                    Text("Curated Kansas City-area options. Each provider confirms availability and final terms for your exact address.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("internet.coverage_note")

                    if isLoading {
                        ProgressView("Loading plans…")
                            .frame(maxWidth: .infinity, minHeight: 88)
                            .tint(PeezyTheme.Colors.deepInk)
                            .accessibilityIdentifier("internet.loading")
                    } else if let errorMessage {
                        internetError(message: errorMessage)
                    } else {
                        ForEach(curatedPlans) { plan in
                            ComparisonCardView(
                                model: plan.comparisonModel,
                                isSelected: openedPlanID == plan.id,
                                labels: .internet,
                                presentation: .compact,
                                onSelect: { open(plan) }
                            )
                        }

                        if !otherPlans.isEmpty {
                            Button("See other providers") {
                                showsOtherProviders = true
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("internet.other_providers")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, PeezyTheme.Layout.verticalSpacing)
            }
            .scrollIndicators(.hidden)

            if !plans.isEmpty {
                if let submissionError {
                    Text(submissionError)
                        .font(.footnote)
                        .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                        .accessibilityIdentifier("internet.submission_error")
                }

                PeezyAssessmentButton(
                    isSubmitting ? "Saving…" : (submissionError == nil ? "I checked availability" : "Try again"),
                    disabled: openedPlanID == nil || isSubmitting,
                    action: submitAndComplete
                )
                .accessibilityHint("Available after opening a provider plan")
                .accessibilityIdentifier("internet.complete")
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .accessibilityIdentifier("internet.comparison")
    }

    private func internetError(message: String) -> some View {
        VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .accessibilityHidden(true)

            Text(message)
                .font(.body)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("internet.error_message")

            Button("Try again") {
                Task { await loadPlansAndAddress() }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(.bordered)
            .tint(PeezyTheme.Colors.deepInk)
            .accessibilityIdentifier("internet.retry")
        }
        .padding(PeezyTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.62), in: .rect(cornerRadius: PeezyTheme.Layout.cornerRadius))
        .accessibilityIdentifier("internet.error")
    }

    @MainActor
    private func loadPlansAndAddress() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetchedPlans = try await ISPPlanService().fetchPlans()
            guard fetchedPlans.count >= curatedPlanLimit else {
                plans = []
                errorMessage = "We couldn't load internet plans. Check your connection and try again."
                isLoading = false
                return
            }
            plans = fetchedPlans
            if let address = await IdentityService.shared.loadOrMigrate(userId: userId)?.newAddress {
                addressLabel = Self.cityAndZIP(from: address)
            } else {
                addressLabel = "Kansas City"
            }
            isLoading = false
        } catch {
            plans = []
            errorMessage = "We couldn't load internet plans. Check your connection and try again."
            isLoading = false
        }
    }

    private var curatedPlans: [ISPPlan] {
        Array(plans.prefix(curatedPlanLimit))
    }

    private var otherPlans: [ISPPlan] {
        Array(plans.dropFirst(curatedPlanLimit))
    }

    private func open(_ plan: ISPPlan) {
        openedPlanID = plan.id
        if plan.affiliateURL == ISPPlan.affiliatePending {
            logger.notice("Open item: affiliate URL pending for \(plan.id, privacy: .public); using provider URL")
        }
        safariDestination = ISPPlanSafariDestination(url: plan.preferredURL)
    }

    private func submitAndComplete() {
        guard !isSubmitting,
              let openedPlanID,
              let selectedPlan = plans.first(where: { $0.id == openedPlanID }) else { return }
        isSubmitting = true
        submissionError = nil

        var workflowAnswers = WorkflowAnswers(workflowId: workflowId)
        workflowAnswers.answers = [
            "isp_plan": [selectedPlan.id],
            "isp_provider": [selectedPlan.provider]
        ]

        Task {
            do {
                let response = try await WorkflowService().submitAnswers(
                    workflowId: workflowId,
                    answers: workflowAnswers,
                    userId: userId
                )
                await MainActor.run {
                    isSubmitting = false
                    if response.success {
                        onComplete()
                    } else {
                        submissionError = "Couldn't save your choice. Check your connection, then try again."
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submissionError = "Couldn't save your choice. Check your connection, then try again."
                }
            }
        }
    }

    static func cityAndZIP(from address: PeezyAddress) -> String {
        let locality = [address.city, address.state]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ", ")
        return [locality, address.zip]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "Kansas City"
    }
}

private struct ISPPlanSafariDestination: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ISPPlanSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#if DEBUG
#Preview("Setup Internet Flow") {
    SetupInternetFlow(
        userId: "preview-user",
        taskId: "SETUP_INTERNET",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismiss") },
        onStatusAction: { action in print("📋 Status: \(action)") }
    )
}
#endif
