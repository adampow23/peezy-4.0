//
//  FindMoversFlow.swift
//  Peezy 4.0
//
//  Movers chain container (plan v7). One role-driven flow backs
//  BOOK_MOVERS (get quotes) and COMPARE_MOVING_QUOTES (compare); legacy
//  mid-flight BOOK_MOVERS docs resume the old quotes/matrix inline.
//

import SwiftUI

struct FindMoversFlow: View {
    let role: MoversFlowRole
    let userId: String
    let taskDocumentId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var model: MoversFlowViewModel
    @Environment(FlowExitCoordinator.self) private var exitCoordinator: FlowExitCoordinator?

    init(
        role: MoversFlowRole,
        userId: String,
        taskDocumentId: String,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onStatusAction: @escaping (TaskFlowStatusAction) -> Void
    ) {
        self.role = role
        self.userId = userId
        self.taskDocumentId = taskDocumentId
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        self.onStatusAction = onStatusAction
        _model = State(initialValue: MoversFlowViewModel(role: role))
    }

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
            await model.prepare(userId: userId, taskDocumentId: taskDocumentId)
        }
        // Exit-lock contract (plan v7): the outer X disables while an edge is
        // in flight and through confirmation; failure unlocks it again.
        .onChange(of: model.chain.isExitLocked, initial: true) { _, locked in
            exitCoordinator?.setExitLocked(locked)
        }
        .accessibilityIdentifier("movers.flow")
    }

    private var headerTitle: String {
        switch role {
        case .getQuotes:
            model.isLegacyInline ? "Compare your moving quotes" : "Get moving quotes"
        case .compareQuotes:
            "Compare your moving quotes"
        case .bookMovers:
            "Book your movers"
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch model.stage {
        case .loading:
            ProgressView("Preparing your quote workspace…")
                .tint(PeezyTheme.Colors.deepInk)
                .accessibilityIdentifier("movers.loading")

        case .protectionEducation:
            MoversEducationView(
                headerTitle: headerTitle,
                title: "Protection isn't insurance",
                message: "Standard valuation is 60 cents per pound. A 10-lb TV pays out $6.",
                callout: "Ask every company what full-value protection costs before booking.",
                systemImage: "shield.lefthalf.filled",
                accessibilityPrefix: "movers.education.protection",
                showBack: false,
                onBack: {},
                onContinue: model.advanceEducation
            )

        case .estimateEducation:
            MoversEducationView(
                headerTitle: headerTitle,
                title: "How estimates really work",
                message: "Quotes are hourly rate × crew × their guess at hours. The lower total is often just a smaller guess, and companies have an incentive to guess low.",
                callout: "The same job costs whatever it actually takes.",
                systemImage: "clock.badge.questionmark",
                accessibilityPrefix: "movers.education.estimates",
                showBack: true,
                onBack: model.goBack,
                onContinue: model.advanceEducation
            )

        case .equip:
            MoversEquipView(
                headerTitle: headerTitle,
                callSheet: model.callSheet,
                inventoryRooms: model.inventoryRooms,
                hasSubmittedInventory: model.hasSubmittedInventory,
                isCompleting: model.chain.edgeState == .inFlight,
                actionError: model.actionError,
                onBack: model.goBack,
                onGetQuotes: completeGetQuotes
            )

        case .quotes:
            MoversQuotesView(model: model)

        case .matrix:
            MoversScenarioMatrixView(model: model)

        case .confirmation:
            MoversChainConfirmationView(
                message: confirmationMessage,
                onDone: { onStatusAction(.completedAlreadyPersisted) }
            )

        case .failure:
            MoversFlowErrorView(
                message: model.errorMessage ?? "Your quote workspace could not be loaded.",
                onRetry: retry,
                onDismiss: onDismiss
            )
        }
    }

    private var confirmationMessage: String {
        switch role {
        case .getQuotes where !model.isLegacyInline:
            "Nice — your next step is waiting in Tasks. When quotes come in, compare them there."
        default:
            "Nice — your next step is waiting in Tasks. Book with the company you chose."
        }
    }

    private func completeGetQuotes() {
        Task { await model.completeGetQuotes() }
    }

    private func retry() {
        Task { await model.retry() }
    }
}

/// Terminal chain confirmation (plan A7): shown only after the edge's writes
/// are durable. Done performs no writes — it routes the already-persisted
/// terminal to Home for local accounting, and it is the only way out.
struct MoversChainConfirmationView: View {
    let message: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: PeezyTheme.Layout.verticalSpacing)

            VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityHidden(true)

                Text("Nice — that's done.")
                    .font(.title)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("movers.confirmation.title")

                Text(message)
                    .font(.body)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("movers.confirmation.message")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .taskContentCard()
            .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
            .accessibilityIdentifier("movers.confirmation.card")

            Spacer(minLength: PeezyTheme.Layout.verticalSpacing)

            PeezyAssessmentButton("Done", action: onDone)
                .accessibilityIdentifier("movers.confirmation.done")
                .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
                .padding(.bottom, PeezyTheme.Layout.verticalSpacing)
        }
        .accessibilityIdentifier("movers.confirmation.screen")
    }
}
