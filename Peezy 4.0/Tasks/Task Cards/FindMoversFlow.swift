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
    @State private var showPaywallGate = false

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
            await model.prepare(userId: userId, taskId: taskId)
            showCapture = model.stage == .capture
        }
        .onChange(of: model.stage) { _, stage in
            if stage == .capture { showCapture = true }
        }
        .fullScreenCover(isPresented: $showCapture) {
            InventoryFlowView(
                onUserDismiss: { showCapture = false },
                onSubmitted: {
                    showCapture = false
                    Task { await model.captureFinished() }
                },
                onLater: { showCapture = false }
            )
        }
        .fullScreenCover(isPresented: $showPaywallGate) {
            PaywallGateSheet { subscribed in
                showPaywallGate = false
                if subscribed { model.showBooking() }
            }
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
                onFallback: { Task { await model.useHomeDetailsInstead() } },
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
            MoversComparisonView(
                quotes: model.quotes,
                selectedId: model.selectedQuote?.id,
                arrivalWindow: model.requestedArrivalWindow,
                priceBasis: model.priceBasis,
                onSelect: selectQuote,
                onBack: model.goBack
            )

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
            MoversConfirmationView(
                vendorName: model.selectedQuote?.vendor.name ?? "your selected company",
                onDone: {
                    model.markComplete()
                    onComplete()
                }
            )

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
        if PaywallPolicy.allows(.vendorBooking) {
            model.showBooking()
        } else {
            showPaywallGate = true
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
