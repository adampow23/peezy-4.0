//
//  SetupInternetFlow.swift
//  Peezy 4.0
//
//  Exact-address internet setup guidance until live provider research ships.
//

import SwiftUI

struct SetupInternetFlow: View {
    let taskTitle = "Set up my internet"
    let workflowId = "setup_internet"

    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var currentIndex = 0
    @State private var addressLabel = "Kansas City"
    @State private var isSubmitting = false
    @State private var submissionError: String?

    private let totalCards = 2

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: totalCards - currentIndex, currentIndex: currentIndex) {
                cardContent
            }
        }
        .task(id: userId) {
            await loadAddress()
        }
        .resumableFlowProgress(
            path: ["card.\(currentIndex)"],
            answers: [:]
        ) { restored in
            currentIndex = min(max(FlowProgressCoding.cardIndex(from: restored.path), 0), totalCards - 1)
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
            guidanceCard

        default:
            EmptyView()
        }
    }

    private var guidanceCard: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(
                taskTitle: taskTitle,
                showBack: true,
                onBack: { currentIndex = 0 }
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                    Text("Internet checklist for \(addressLabel)")
                        .font(.title3.bold())
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("internet.address")

                    Text("Availability and terms change by address. Confirm each item on the provider's official site or by phone before ordering.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("internet.coverage_note")

                    guidanceRow(
                        icon: "mappin.and.ellipse",
                        title: "Check your exact address",
                        body: "Confirm service availability, the final monthly price, equipment and installation fees, data limits, contract terms, and offer eligibility."
                    )

                    guidanceRow(
                        icon: "calendar.badge.clock",
                        title: "Order ahead",
                        body: "Order service two to three weeks before move day. Choose an activation date before you need it, then confirm equipment delivery or the technician window."
                    )

                    guidanceRow(
                        icon: "shippingbox.and.arrow.backward",
                        title: "Ask about self-install",
                        body: "If the home is pre-wired, ask whether it qualifies for self-install. Compare the timing and all current fees with provider installation."
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, PeezyTheme.Layout.verticalSpacing)
            }
            .scrollIndicators(.hidden)

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
                isSubmitting ? "Saving…" : (submissionError == nil ? "Save my checklist" : "Try again"),
                disabled: isSubmitting,
                action: submitAndComplete
            )
            .accessibilityIdentifier("internet.complete")
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("internet.guidance")
    }

    private func guidanceRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)

                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(PeezyTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.62), in: .rect(cornerRadius: PeezyTheme.Layout.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func loadAddress() async {
        if let address = await IdentityService.shared.loadOrMigrate(userId: userId)?.newAddress {
            addressLabel = Self.cityAndZIP(from: address)
        } else {
            addressLabel = "Kansas City"
        }
    }

    private func submitAndComplete() {
        guard !isSubmitting else { return }
        isSubmitting = true
        submissionError = nil

        var workflowAnswers = WorkflowAnswers(workflowId: workflowId)
        workflowAnswers.answers = [
            "internet_guidance": ["reviewed"],
            "internet_address": [addressLabel]
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
        let label: String = [locality, address.zip]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "Kansas City" : label
    }
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
