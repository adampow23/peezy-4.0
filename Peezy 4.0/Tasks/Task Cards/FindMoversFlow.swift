//
//  FindMoversFlow.swift
//  Peezy 4.0
//
//  Custom Swift implementation of the mover workflow spine. BOOK_MOVERS stays
//  in TaskFlowRouter's custom map; FlowDefinition intentionally does not model
//  capture or comparison stages.
//

import SwiftUI

struct FindMoversFlow: View {
    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var model = MoversFlowViewModel()
    @State private var showCapture = false
    @State private var captureChoice: String?
    @State private var didPrepare = false
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(FlowExitCoordinator.self) private var exitCoordinator

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(
                cardsRemaining: model.stage.cardsRemaining,
                currentIndex: model.stage.stackIndex
            ) {
                stageContent
            }
        }
        .task {
            let restored = await exitCoordinator.restore()
            await model.prepare(userId: userId, taskId: taskId)
            await model.restoreFlowProgress(restored)
            captureChoice = restored.answers["capture_choice"]?.first
            didPrepare = true
        }
        .onChange(of: moversProgressSnapshot) { _, snapshot in
            guard didPrepare else { return }
            exitCoordinator.persist(snapshot)
        }
        .fullScreenCover(isPresented: $showCapture) {
            if PaywallPolicy.requiresMovePass(for: .scanner),
               !subscriptionManager.isSubscribed {
                PaywallGateSheet(surface: .scanner) { subscribed in
                    if !subscribed {
                        showCapture = false
                    }
                }
            } else {
                InventoryFlowView(
                    onUserDismiss: {
                        showCapture = false
                        Task {
                            await model.captureDismissed()
                            if model.hasInventory { captureChoice = "inventory" }
                        }
                    },
                    onSubmitted: {
                        showCapture = false
                        captureChoice = "inventory"
                        Task { await model.captureFinished() }
                    },
                    onLater: { showCapture = false }
                )
            }
        }
        .flowAnswerProbe {
            model.isSubmitting || moversProgressSnapshot.hasRecordedAnswers
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch model.stage {
        case .loading:
            ProgressView("Preparing your move scope…")
                .tint(PeezyTheme.Colors.deepInk)
                .accessibilityIdentifier("movers.loading")

        case .capture:
            MoversCaptureCard(
                onScan: { showCapture = true },
                onFallback: {
                    captureChoice = "home_details"
                    Task { await model.useHomeDetailsInstead() }
                },
                onDismiss: onDismiss
            )

        case .scope:
            MoveScopeSummaryView(
                homeSummary: model.homeSummary,
                cubeSummary: model.cubeSummary,
                accessSummary: model.accessSummary,
                storageSummary: model.storageSummary,
                priceBasis: model.priceBasis,
                onContinue: model.showRefinement,
                onBack: model.goBack
            )

        case .refinement:
            MoveRefinementView(
                model: model,
                onContinue: { Task { await model.prepareComparisons() } },
                onBack: model.goBack
            )

        case .comparison:
            if model.isQuoteRequest {
                conciergeQuoteCard
            } else {
                MoversComparisonView(
                    quotes: model.quotes,
                    selectedId: model.selectedQuote?.id,
                    arrivalWindow: model.requestedArrivalWindow,
                    priceBasis: model.priceBasis,
                    onSelect: selectQuote,
                    onBack: model.goBack
                )
            }

        case .booking:
            if let selectedQuote = model.selectedQuote {
                MoversBookingReviewView(
                    model: model,
                    quote: selectedQuote,
                    onSubmit: { Task { await model.submitBooking() } },
                    onBack: model.goBack
                )
            }

        case .confirmation:
            if model.isQuoteRequest {
                conciergeConfirmationCard
            } else {
                MoversConfirmationView(
                    vendorName: model.selectedQuote?.vendor.name ?? "your selected company",
                    onDone: completeFlow
                )
            }

        case .failure:
            MoversFlowErrorView(
                message: model.errorMessage ?? "An unexpected error occurred.",
                onRetry: { Task { await model.retry() } },
                onDismiss: onDismiss
            )
        }
    }

    private func selectQuote(_ quote: MoversVendorQuote) {
        model.select(quote)
        model.showBooking()
    }

    private var conciergeQuoteCard: some View {
        MoversConciergeQuoteCard(
            copy: model.conciergeCopy,
            notes: $model.notes,
            errorMessage: model.errorMessage,
            isSubmitting: model.isSubmitting,
            onBack: model.goBack,
            onSubmit: { Task { await model.submitQuoteRequest() } }
        )
    }

    private var conciergeConfirmationCard: some View {
        VStack(spacing: PeezyTheme.Layout.itemSpacing) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(PeezyTheme.Colors.successGreen)
                .accessibilityHidden(true)
            Text("Your quote request is in")
                .font(.title2)
                .bold()
                .foregroundStyle(PeezyTheme.Colors.deepInk)
            Text("We'll follow up with your hand-built mover quote within a day.")
                .multilineTextAlignment(.center)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
            PeezyAssessmentButton("Done", action: completeFlow)
        }
        .padding(PeezyTheme.Layout.cardPadding)
        .accessibilityIdentifier("movers.quote.confirmation")
    }

    private func completeFlow() {
        model.markComplete()
        onComplete()
    }

    private var moversProgressSnapshot: FlowProgressSnapshot {
        var snapshot = model.flowProgressSnapshot
        if let captureChoice {
            snapshot.answers["capture_choice"] = [captureChoice]
        }
        return snapshot
    }
}

struct MoversConciergeQuoteCard: View {
    let copy: MoversConciergeCopy
    @Binding var notes: String
    let errorMessage: String?
    let isSubmitting: Bool
    let onBack: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Request a mover quote", showBack: true, onBack: onBack)

            Spacer()

            VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                Image(systemName: "map.fill")
                    .font(.largeTitle)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityHidden(true)

                Text(copy.title)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityIdentifier("movers.quote.title")

                Text(copy.body)
                    .font(.body)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("movers.quote.body")

                TextField("Anything we should know?", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(PeezyTheme.Layout.cardPaddingSmall)
                    .background(Color.white.opacity(0.65), in: .rect(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall))
                    .accessibilityIdentifier("movers.quote.notes")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("movers.quote.error")
                }

                PeezyAssessmentButton(
                    isSubmitting ? "Sending…" : "Request my quote",
                    disabled: isSubmitting,
                    action: onSubmit
                )
                .accessibilityIdentifier("movers.quote.submit")
            }
            .padding(PeezyTheme.Layout.cardPadding)
            .background(Color.white.opacity(0.68), in: .rect(cornerRadius: PeezyTheme.Layout.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius)
                    .stroke(PeezyTheme.Colors.deepInk.opacity(0.12))
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("movers.quote.concierge")

            Spacer()
        }
    }
}

#if DEBUG
#Preview("Find Movers Flow") {
    FindMoversFlow(
        userId: "preview-user",
        taskId: "BOOK_MOVERS",
        onComplete: { print("Complete") },
        onDismiss: { print("Dismiss") },
        onStatusAction: { action in print("Status: \(action)") }
    )
}
#endif
