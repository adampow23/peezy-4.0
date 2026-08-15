import SwiftUI

struct MoversScenarioMatrixView: View {
    @Bindable var model: MoversFlowViewModel

    @State private var isExpertThreadPresented = false

    private var isCompleting: Bool {
        model.chain.edgeState == .inFlight
    }

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Compare the real quotes", showBack: true, onBack: model.goBack)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                    VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                        Text("One job. Every time scenario.")
                            .font(.title)
                            .bold()
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .accessibilityIdentifier("movers.matrix.title")

                        Text("Each card applies the same man-hours to every company's rate. This separates the price from the guess.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("movers.matrix.explanation")
                    }

                    ForEach(Array(model.scenarios.enumerated()), id: \.offset) { index, scenario in
                        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
                            Text("If \(scenario.basis.name)'s time is right — \(scenario.basis.manHours.formatted(.number.precision(.fractionLength(0...1)))) man-hours")
                                .font(.title3)
                                .bold()
                                .foregroundStyle(PeezyTheme.Colors.deepInk)
                                .fixedSize(horizontal: false, vertical: true)

                            ForEach(Array(scenario.totals.enumerated()), id: \.offset) { _, total in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(total.company)
                                        .font(.body)
                                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                                    Spacer(minLength: PeezyTheme.Layout.verticalSpacing)
                                    Text(total.total, format: .currency(code: "USD").precision(.fractionLength(0)))
                                        .font(.headline)
                                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                                }
                                .accessibilityElement(children: .combine)
                            }

                            if let lowballCompany = scenario.lowballCompany {
                                Label(
                                    "Lowball: \(lowballCompany)'s own estimate is below this time basis.",
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .font(.callout)
                                .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("movers.matrix.lowball.\(index)")
                            }

                            if scenario.basis.isPeezy {
                                Text("Our estimate runs conservative — companies have reasons to guess low. Use it as your baseline, adjust for what you know about your move.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("movers.matrix.peezyCaption")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .taskContentCard()
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("movers.matrix.scenario.\(index)")
                    }

                    expertReviewSection

                    // Notes persist ONCE, at Done, before the spawn (plan A2).
                    // The old blur-save raced the completion write — removed.
                    TaskNotesSection(notes: $model.notes) {}
                }
                .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
                .padding(.vertical, PeezyTheme.Layout.verticalSpacing)
            }
            .scrollIndicators(.hidden)

            if let actionError = model.actionError {
                Text(actionError)
                    .font(.callout)
                    .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
                    .padding(.bottom, PeezyTheme.Layout.verticalSpacingSmall)
                    .accessibilityIdentifier("movers.matrix.error")
            }

            PeezyAssessmentButton(
                isCompleting ? "Saving…" : "Done",
                disabled: isCompleting,
                action: complete
            )
            .accessibilityIdentifier("movers.matrix.done")
            .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
            .padding(.bottom, PeezyTheme.Layout.verticalSpacing)
        }
        .sheet(isPresented: $isExpertThreadPresented) {
            NavigationStack {
                SupportChatView(
                    chatService: model.supportService,
                    taskContext: model.supportTaskContext
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isExpertThreadPresented = false
                        }
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                    }
                }
            }
            .presentationDragIndicator(.visible)
        }
        .accessibilityIdentifier("movers.matrix.screen")
    }

    // MARK: - Expert review (plan GOAL B — free, rides support, no paywall)

    private var expertReviewSection: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            Button(action: sendExpertReview) {
                Label(
                    model.expertState == .sending
                        ? "Sending your quotes…"
                        : "Have a move expert look these over",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
                .font(PeezyTheme.Typography.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(maxWidth: .infinity, minHeight: PeezyTheme.Layout.buttonHeightSmall)
                .background(
                    PeezyTheme.Colors.deepInk.opacity(model.expertState.buttonDisabled ? 0.14 : 0.42),
                    in: RoundedRectangle(
                        cornerRadius: PeezyTheme.Layout.cornerRadiusMedium,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(model.expertState.buttonDisabled)
            .accessibilityIdentifier("expertReviewButton")

            if case .sent = model.expertState {
                Button("View your request in Chat") {
                    isExpertThreadPresented = true
                }
                .font(PeezyTheme.Typography.callout)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(minHeight: 44)
                .accessibilityIdentifier("movers.matrix.expertThread")
            }

            if model.expertState.showsDeliveryPendingNotice {
                // Honest copy (round-4 finding 4): nothing background-retries,
                // and the non-idempotent callable is never re-invoked.
                Text("Saved in Chat, but we couldn't confirm delivery. Send a new Chat message to alert support.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("movers.matrix.deliveryPending")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .taskContentCard()
        .accessibilityIdentifier("movers.matrix.expertCard")
    }

    private func sendExpertReview() {
        Task {
            let presented = await model.sendExpertReview()
            if presented {
                isExpertThreadPresented = true
            }
        }
    }

    private func complete() {
        guard !isCompleting else { return }
        Task { await model.completeCompareChain() }
    }
}
