import SwiftUI

struct PostFlowForkView: View {
    let onComplete: () -> Void

    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var research: TaskResearchModel
    @State private var phase: Phase = .fork
    @State private var pendingResearchRequest: TaskResearchRequest?
    @State private var didComplete = false

    private enum Phase {
        case fork
        case paywall
        case research
    }

    init(
        userId: String,
        configuration: TaskResearchConfiguration,
        flowAnswers: [String: [String]],
        onComplete: @escaping () -> Void
    ) {
        self.onComplete = onComplete
        let research = TaskResearchModel(userId: userId)
        research.configure(configuration: configuration, flowAnswers: flowAnswers)
        _research = State(initialValue: research)
    }

    var body: some View {
        Group {
            switch phase {
            case .fork:
                forkView
            case .paywall:
                PaywallGateSheet(surface: .research, onFinished: paywallFinished)
                    .accessibilityIdentifier("post_flow.paywall")
            case .research:
                researchView
            }
        }
        .onDisappear {
            research.stop()
        }
        .accessibilityIdentifier("post_flow.surface")
    }

    private var forkView: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: 1, currentIndex: 0) {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)

                    ZStack {
                        Circle()
                            .fill(PeezyTheme.Colors.deepInk.opacity(0.08))
                        Image(systemName: "sparkles")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                    }
                    .frame(width: 68, height: 68)
                    .accessibilityHidden(true)

                    Text("Want us to dig into this for you?")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("post_flow.fork_title")

                    Text("We'll find the exact steps, who to contact, and what to say.")
                        .font(.body.weight(.medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("post_flow.fork_body")

                    Spacer(minLength: 24)

                    VStack(spacing: 12) {
                        PeezyAssessmentButton("Help me out") {
                            helpRequested()
                        }
                        .accessibilityIdentifier("forkHelpButton")

                        Button("I've got it from here") {
                            finish()
                        }
                        .font(.headline)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            Color.white.opacity(0.42),
                            in: RoundedRectangle(
                                cornerRadius: PeezyTheme.Layout.cornerRadiusMedium,
                                style: .continuous
                            )
                        )
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("forkSelfButton")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .accessibilityIdentifier("post_flow.fork_card")
            }
        }
    }

    private var researchView: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: 1, currentIndex: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Your research brief")
                            .font(.largeTitle.bold())
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("post_flow.research_title")

                        TaskResearchModuleView(
                            model: research,
                            startButtonTitle: "Start research",
                            hasAccess: subscriptionManager.isSubscribed,
                            onRequest: handleResearchRequest,
                            onDone: finish
                        )
                    }
                    .padding(24)
                }
                .accessibilityIdentifier("post_flow.research_card")
            }
        }
    }

    private func helpRequested() {
        if PaywallPolicy.requiresMovePass(for: .research),
           !subscriptionManager.isSubscribed {
            phase = .paywall
        } else {
            openResearch(automaticallyGenerate: true)
        }
    }

    private func paywallFinished(subscribed: Bool) {
        guard subscribed else {
            pendingResearchRequest = nil
            phase = .fork
            return
        }

        let request = pendingResearchRequest
        pendingResearchRequest = nil
        openResearch(automaticallyGenerate: request == nil)
        if let request {
            performResearchRequest(request)
        }
    }

    private func openResearch(automaticallyGenerate: Bool) {
        phase = .research
        research.start()
        guard automaticallyGenerate, !research.hasPreferences else { return }
        Task { await research.generateResearch(force: false) }
    }

    private func handleResearchRequest(_ request: TaskResearchRequest) {
        guard subscriptionManager.isSubscribed else {
            pendingResearchRequest = request
            phase = .paywall
            return
        }
        performResearchRequest(request)
    }

    private func performResearchRequest(_ request: TaskResearchRequest) {
        switch request {
        case .generate(let force):
            Task { await research.generateResearch(force: force) }
        case .reveal:
            break
        }
    }

    private func finish() {
        guard !didComplete else { return }
        didComplete = true
        research.stop()
        onComplete()
    }
}
