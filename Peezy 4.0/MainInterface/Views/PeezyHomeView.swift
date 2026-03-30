//
//  PeezyHomeView.swift
//  Peezy
//
//  Main home screen with 3-state flow: welcome → task → done
//  Replaces PeezyStackViewWithWorkflow as the home tab view.
//
//  Reuses from PeezyStackView.swift (same module, accessible):
//  - InteractiveBackground
//  - LoadingView
//  - EmptyStateView
//  - ErrorToast
//
//  Reuses from WorkflowCardView.swift (unchanged):
//  - WorkflowCardView
//
//  Reuses from ChatView.swift (unchanged):
//  - ChatView
//
//

import SwiftUI

// MARK: - Card Success State

enum CardSuccessState: Equatable {
    case userHandling
    case completed

    var icon: String {
        switch self {
        case .userHandling: return "hand.thumbsup.fill"
        case .completed:    return "checkmark.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .userHandling: return "You've got this!"
        case .completed:    return "Done!"
        }
    }

    var subtitle: String {
        switch self {
        case .userHandling: return "We moved it to your In Progress list."
        case .completed:    return "Great job checking that off."
        }
    }

    var iconColor: Color {
        switch self {
        case .userHandling: return PeezyTheme.Colors.deepInk.opacity(0.8)
        case .completed:    return .green
        }
    }
}

// MARK: - Interactive Home Task Card

struct InteractiveHomeTaskCard: View {
    let task: PeezyCard

    // Actions from view model — called AFTER celebration pause
    let onStartWorkflow: () -> Void
    let onComplete: () -> Void
    let onUserHandle: () -> Void
    let onSkip: () -> Void

    // Internal celebration state
    @State private var successState: CardSuccessState? = nil
    @State private var dismissOffset: CGFloat = 0

    private var isWorkflow: Bool {
        !(task.workflowId ?? "").isEmpty
    }

    var body: some View {
        ZStack {
            // Glass card background (same as glassCard helper)
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .foregroundStyle(.regularMaterial)
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.white.opacity(0.15))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    .padding(1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 15)

            // Content switcher — crossfade between task and celebration
            ZStack {
                if let state = successState {
                    // MARK: Celebration State
                    VStack(spacing: 20) {
                        Image(systemName: state.icon)
                            .font(.system(size: 72))
                            .foregroundColor(state.iconColor)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))

                        VStack(spacing: 8) {
                            Text(state.title)
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundColor(PeezyTheme.Colors.deepInk)

                            Text(state.subtitle)
                                .font(.title3)
                                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 30)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .opacity
                    ))

                } else {
                    // MARK: Standard Task Content
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Image(systemName: task.icon)
                            Text(task.headerLabel)
                            Spacer()
                        }
                        .font(.caption).bold()
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .padding(.top, 30)
                        .padding(.horizontal, 30)

                        Spacer()

                        // Content
                        VStack(alignment: .leading, spacing: 15) {
                            Text(task.title)
                                .font(.system(size: 44, weight: .heavy))
                                .foregroundColor(PeezyTheme.Colors.deepInk)
                                .lineLimit(2)
                                .minimumScaleFactor(0.5)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(task.subtitle)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                                .lineLimit(nil)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 30)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer()

                        // Action buttons
                        actionButtons
                    }
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    ))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: successState)
        }
        .frame(width: 340, height: 500)
        .offset(x: dismissOffset)
        .rotationEffect(.degrees(Double(dismissOffset) / 30))
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Later (skip) — NO celebration, fly off left
                Button(action: {
                    PeezyHaptics.light()
                    withAnimation(.easeIn(duration: 0.3)) {
                        dismissOffset = -UIScreen.main.bounds.width
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onSkip()
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18))
                        Text("Later")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )
                }
                .buttonStyle(.peezySecondary)

                // I'm on it (user in progress) — CELEBRATION then action
                if !isWorkflow {
                    Button(action: {
                        triggerSuccess(state: .userHandling, finalAction: onUserHandle)
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "figure.walk.circle.fill")
                                .font(.system(size: 18))
                            Text("I'm on it")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                                .fill(.regularMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                                .stroke(Color.black.opacity(0.05), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.peezySecondary)
                }

                // Done / Start
                Button(action: {
                    if isWorkflow {
                        // Start workflow — NO celebration, begins multi-step flow
                        PeezyHaptics.medium()
                        onStartWorkflow()
                    } else {
                        // Complete — CELEBRATION then action
                        triggerSuccess(state: .completed, finalAction: onComplete)
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: isWorkflow ? "arrow.forward.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 18))
                        Text(isWorkflow ? "Start" : "Done")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(PeezyTheme.Colors.deepInk)
                    )
                }
                .buttonStyle(.peezyPrimary)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Celebration Trigger

    private func triggerSuccess(state: CardSuccessState, finalAction: @escaping () -> Void) {
        PeezyHaptics.medium()

        // 1. Morph the card to celebration state
        successState = state

        // 2. Hold for 1.5 seconds, then fly off right
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeIn(duration: 0.3)) {
                dismissOffset = UIScreen.main.bounds.width
            }
            // 3. After fly-off completes, fire the backend action
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                finalAction()
            }
        }
    }
}

// MARK: - PeezyHomeView

struct PeezyHomeView: View {

    // User state passed from PeezyMainContainer
    var userState: UserState?

    // Task list navigation — when set, this task is loaded as currentTask
    @Binding var focusedTask: PeezyCard?

    // View model — owned by this view
    @State private var viewModel = PeezyHomeViewModel()

    // Confetti state for batch-complete celebration card
    @State private var confettiActive = false

    // Onboarding pagination — tracks current welcome page (0, 1, 2)
    @State private var welcomePage: Int = 0

    // Deep ink text color for light theme
    private let deepInk = PeezyTheme.Colors.deepInk

    // MARK: - Initializers

    init(userState: UserState?, focusedTask: Binding<PeezyCard?>) {
        self.userState = userState
        self._focusedTask = focusedTask
    }

    #if DEBUG
    /// Internal init that accepts a pre-configured view model for Xcode Previews.
    /// Bypasses Firebase loading — the view model state is set directly.
    init(previewViewModel: PeezyHomeViewModel) {
        self.userState = previewViewModel.userState
        self._focusedTask = .constant(nil)
        self._viewModel = State(initialValue: previewViewModel)
    }
    #endif

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background (same as existing stack view)
                InteractiveBackground()
                    .ignoresSafeArea()

                // Main Content
                VStack {
                    Spacer()

                    switch viewModel.state {
                    case .loading:
                        LoadingView()

                    case .firstTimeWelcome:
                        firstTimeWelcomeCard

                    case .dailyGreeting:
                        dailyGreetingCard

                    case .returningMidDay:
                        returningMidDayCard

                    case .activeTask:
                        activeTaskContent

                    case .dailyComplete:
                        dailyCompleteCard

                    case .allComplete:
                        allCompleteCard
                    }

                    Spacer()
                }

                // Top Bar — peezy logo
                VStack(spacing: 0) {
                    Text("peezy")
                        .font(.system(size: 18, weight: .light, design: .default))
                        .tracking(6)
                        .foregroundStyle(deepInk.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)

                    Spacer()
                }

                // Error Toast
                if let errorMessage = viewModel.error {
                    VStack {
                        Spacer()
                        ErrorToast(message: errorMessage) {
                            viewModel.error = nil
                        }
                        .padding(.bottom, 80)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

            }
            .padding(.bottom, 80)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                return // Skip loading in previews — use injected state
            }
            #endif
            viewModel.userState = userState
            viewModel.resetDailyCountIfNeededPublic()
            if viewModel.taskQueue.isEmpty && viewModel.state == .loading {
                Task {
                    await viewModel.loadTasks()
                    // focusedTask is set before the view appears (onChange won't fire for initial value),
                    // so we check it here after loading completes and apply it directly.
                    if let task = focusedTask {
                        focusedTask = nil
                        viewModel.focusTask(task)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $viewModel.showInventoryScanner, onDismiss: {
            if let task = viewModel.currentTask, task.actionType == "in-app-inventory" {
                viewModel.completeCurrentTask()
            }
        }) {
            InventoryFlowView()
        }
        .onChange(of: focusedTask) { _, task in
            if let task {
                focusedTask = nil
                viewModel.focusTask(task)
            }
        }
    }

    // MARK: - First Time Welcome Card

    private var firstTimeWelcomeCard: some View {
        glassCard {
            VStack(spacing: 0) {
                // Header pinned at top
                VStack(alignment: .leading, spacing: 15) {
                    Text(welcomePageHeadline)
                        .font(.system(size: 38, weight: .heavy))
                        .foregroundColor(PeezyTheme.Colors.deepInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    Rectangle()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 50, height: 2)
                }
                .padding(.horizontal, 30)
                .padding(.top, 30)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Body text centered in remaining space between divider and dots
                Spacer()

                Text(welcomePageBody)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(welcomePage)
                    .transition(.opacity)

                Spacer()

                // Dot indicators
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == welcomePage ? Color.black.opacity(0.4) : Color.black.opacity(0.12))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                // Swipe hint for pages 0-1, button for page 2
                if welcomePage < 2 {
                    Text("Swipe to continue")
                        .font(.caption)
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.3))
                        .padding(.bottom, 30)
                } else {
                    PeezyAssessmentButton("Start My First Task") {
                        viewModel.dismissFirstTimeWelcome()
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { gesture in
                    let horizontal = gesture.translation.width
                    if horizontal < -50 && welcomePage < 2 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            welcomePage += 1
                        }
                    } else if horizontal > 50 && welcomePage > 0 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            welcomePage -= 1
                        }
                    }
                }
        )
    }

    private var welcomePageHeadline: String {
        switch welcomePage {
        case 0: return "Here's how Peezy works"
        case 1: return "Everything in one place"
        default: return "Got questions? Just ask."
        }
    }

    private var welcomePageBody: String {
        let daily = viewModel.dailyTarget
        switch welcomePage {
        case 0:
            if daily > 0 {
                let taskWord = daily == 1 ? "task" : "tasks"
                return "We break your move into bite-sized daily tasks based on your timeline.\n\nWe've got about \(daily) \(taskWord) per day to keep you on track — just work through each day's batch and you're golden."
            } else {
                return "We break your move into bite-sized daily tasks based on your timeline.\n\nWe'll figure out your daily pace once we know more about your move."
            }
        case 1:
            return "The Tasks tab has everything — upcoming, in progress, and done. You can also start tasks ahead of schedule from there.\n\nNeed to update your move details? Head to Settings."
        default:
            return "Need help with a task? Tap it to learn more, or head to Settings to contact support."
        }
    }

    // MARK: - Daily Greeting Card

    private var dailyGreetingCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 15) {
                    // Greeting
                    Text(viewModel.greetingText)
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundColor(PeezyTheme.Colors.deepInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    // Thin accent divider
                    Rectangle()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 50, height: 2)

                    // Today's count only
                    Text(viewModel.dailyGreetingSubtitle)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // Get Started button
                PeezyAssessmentButton("Get started") {
                    viewModel.startNextTask()
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: - Returning Mid-Day Card

    private var returningMidDayCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 15) {
                    // Greeting
                    Text(viewModel.returningGreeting)
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundColor(PeezyTheme.Colors.deepInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    // Thin accent divider
                    Rectangle()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 50, height: 2)

                    // Progress
                    Text(viewModel.returningMidDaySubtitle)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // Pick up where I left off
                PeezyAssessmentButton("Pick up where I left off") {
                    viewModel.startNextTask()
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: - Active Task Content

    @ViewBuilder
    private var activeTaskContent: some View {
        if viewModel.isStartingWorkflow || viewModel.workflowManager.isLoading {
            // Loading workflow questions
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(PeezyTheme.Colors.deepInk)
                Text("Loading your task...")
                    .font(.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.8))
            }
        } else if viewModel.isInWorkflow {
            // Workflow card (existing WorkflowCardView, unchanged)
            workflowContent
        } else if let task = viewModel.currentTask {
            // Simple task card — no workflow, just complete
            simpleTaskCard(task: task)
        }
    }

    // MARK: - Workflow Content

    private var workflowContent: some View {
        VStack(spacing: 16) {
            // Workflow card (centered, constrained to match other cards)
            ForEach(viewModel.workflowManager.workflowCards) { card in
                WorkflowCardView(
                    card: card,
                    answers: viewModel.workflowManager.answers,
                    onContinue: {
                        viewModel.handleWorkflowContinue()
                    },
                    onSelect: { questionId, optionId, isExclusive in
                        viewModel.handleWorkflowSelect(
                            questionId: questionId,
                            optionId: optionId,
                            isExclusive: isExclusive
                        )
                    },
                    onComplete: {
                        viewModel.completeWorkflowTask()
                    }
                )
                .frame(width: 340, height: 500)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }

            // Skip option
            Button(action: { viewModel.skipCurrentTask() }) {
                Text("Skip for now")
                    .font(.subheadline)
                    .foregroundStyle(Color.gray)
            }
            .padding(.top, 4)

            // Workflow error
            if let workflowError = viewModel.workflowManager.error {
                Text(workflowError)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 30)
            }
        }
        .animation(.spring(response: 0.4), value: viewModel.workflowManager.workflowCards.count)
    }

    // MARK: - Simple Task Card

    private func simpleTaskCard(task: PeezyCard) -> some View {
        InteractiveHomeTaskCard(
            task: task,
            onStartWorkflow: { viewModel.startWorkflowForCurrentTask() },
            onComplete: { viewModel.completeCurrentTask() },
            onUserHandle: { viewModel.markCurrentTaskUserInProgress() },
            onSkip: { viewModel.skipCurrentTask() }
        )
    }

    // MARK: - Daily Complete Card

    private var dailyCompleteCard: some View {
        ZStack {
            glassCard {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()

                    VStack(alignment: .leading, spacing: 15) {
                        Text("You're all done\nfor today!")
                            .font(.system(size: 36, weight: .heavy))
                            .foregroundColor(PeezyTheme.Colors.deepInk)
                            .lineLimit(3)
                            .minimumScaleFactor(0.5)

                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .frame(width: 50, height: 2)

                        Text(viewModel.celebrationSubtext)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    // Subtle "keep going" — not a CTA, just an option
                    if !viewModel.allActiveTasks.isEmpty {
                        PeezyAssessmentButton(viewModel.currentBatchOffset > 0 ? "Keep going?" :
                            "Want to get ahead?") {
                            confettiActive = false
                            viewModel.getAhead()
                        }
                        .padding(.horizontal, 30)
                        .padding(.bottom, 30)
                    }
                }
            }

            ConfettiView(isActive: $confettiActive, intensity: .high)
                .frame(width: 340, height: 500)
                .allowsHitTesting(false)
        }
        .onAppear { confettiActive = true }
        .onDisappear { confettiActive = false }
    }

    // MARK: - All Complete Card

    private var allCompleteCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 15) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)

                    let name = viewModel.userState?.name ?? ""
                    Text(name.isEmpty ? "You're all set!" : "You're all set, \(name)!")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundColor(PeezyTheme.Colors.deepInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    Rectangle()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 50, height: 2)

                    Text(viewModel.allCompleteSubtext)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
        }
    }

    // MARK: - Glass Card Container

    /// Glass card matching assessment theme
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            // Glass stack
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .foregroundStyle(.regularMaterial)

                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.white.opacity(0.15))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    .padding(1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 15)

            // Content
            content()
        }
        .frame(width: 340, height: 500)
    }
}

// MARK: - Previews

#if DEBUG

#Preview("First Time Welcome") {
    PeezyHomeView(
        previewViewModel: .preview(state: .firstTimeWelcome)
    )
}

#Preview("Daily Greeting") {
    PeezyHomeView(
        previewViewModel: .preview(state: .dailyGreeting)
    )
}

#Preview("Returning Mid-Day") {
    PeezyHomeView(
        previewViewModel: .preview(state: .returningMidDay)
    )
}

#Preview("Active Task - Workflow") {
    PeezyHomeView(
        previewViewModel: .preview(
            state: .activeTask,
            task: PreviewData.mockWorkflowTask
        )
    )
}

#Preview("Active Task - Self Service") {
    PeezyHomeView(
        previewViewModel: .preview(
            state: .activeTask,
            task: PreviewData.mockSelfServiceTask
        )
    )
}

#Preview("Active Task - Concierge") {
    PeezyHomeView(
        previewViewModel: .preview(
            state: .activeTask,
            task: PreviewData.mockConciergeTask
        )
    )
}

#Preview("Daily Complete") {
    PeezyHomeView(
        previewViewModel: .preview(state: .dailyComplete)
    )
}

#Preview("All Complete") {
    PeezyHomeView(
        previewViewModel: .preview(state: .allComplete, tasks: [])
    )
}

#endif
