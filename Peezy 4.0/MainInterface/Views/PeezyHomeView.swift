//
//  PeezyHomeView.swift
//  Peezy
//
//  Main home screen with state machine: welcome → task → done
//
//  Reuses from HomeBackgroundComponents.swift:
//  - InteractiveBackground
//  - LoadingView
//  - EmptyStateView
//  - ErrorToast
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - PeezyHomeView

struct PeezyHomeView: View {

    // User state passed from PeezyMainContainer
    var userState: UserState?

    // Task list navigation — when set, this task is loaded as currentTask
    @Binding var focusedTask: PeezyCard?

    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    // View model — owned by this view
    @State private var viewModel = PeezyHomeViewModel()

    // Confetti state for batch-complete celebration card
    @State private var confettiActive = false

    // Onboarding pagination — tracks current welcome page (0, 1, 2)
    @State private var welcomePage: Int = 0

    // Deep ink text color for light theme
    private let deepInk = PeezyTheme.Colors.deepInk

    @Environment(\.accessibilityReduceMotion) var reduceMotion

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
                        .padding(.bottom, 24)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

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
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 50, height: 2)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Body text centered in remaining space between divider and dots
                Spacer()

                Text(welcomePageBody)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(welcomePage)
                    .transition(.opacity)

                Spacer()

                // Dot indicators
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == welcomePage ? Color.primary.opacity(0.4) : Color.primary.opacity(0.12))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                // Swipe hint for pages 0-1, button for page 2
                if welcomePage < 2 {
                    Text("Swipe to continue")
                        .font(.caption)
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                        .padding(.bottom, 24)
                        .accessibilityAction(named: "Next page") {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                welcomePage += 1
                            }
                        }
                } else {
                    PeezyAssessmentButton("Start My First Task") {
                        viewModel.dismissFirstTimeWelcome()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { gesture in
                    let horizontal = gesture.translation.width
                    if horizontal < -50 && welcomePage < 2 {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            welcomePage += 1
                        }
                    } else if horizontal > 50 && welcomePage > 0 {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
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
                    Text(viewModel.greetingText)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 50, height: 2)

                    Text(viewModel.dailyGreetingSubtitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                PeezyAssessmentButton("Get started") {
                    viewModel.startNextTask()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Returning Mid-Day Card

    private var returningMidDayCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 15) {
                    Text(viewModel.returningGreeting)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 50, height: 2)

                    Text(viewModel.returningMidDaySubtitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                PeezyAssessmentButton("Pick up where I left off") {
                    viewModel.startNextTask()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Active Task Content

    @ViewBuilder
    private var activeTaskContent: some View {
        if viewModel.isStartingWorkflow || viewModel.workflowManager.isLoading {
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(PeezyTheme.Colors.deepInk)
                Text("Loading your task...")
                    .font(.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.8))
            }
        } else if let task = viewModel.currentTask {
            let sequence = TaskCardSequenceBuilder.build(
                task: task,
                isSubscribed: subscriptionManager.isSubscribed,
                completedTaskCount: viewModel.totalCompletedCount,
                qualifying: viewModel.workflowManager.loadedQualifying,
                userState: userState
            )
            PeezyTaskCardStackView(
                sequence: sequence,
                userState: userState,
                onComplete: {
                    if sequence.needsWorkflowContinue {
                        viewModel.completeWorkflowTask()
                    } else {
                        viewModel.completeCurrentTask()
                    }
                },
                onSkip: { viewModel.skipCurrentTask() },
                onSubmit: { fields, transferChoice in
                    submitTaskFromCard(fields: fields, transferChoice: transferChoice)
                },
                onWorkflowContinue: { viewModel.handleWorkflowContinue() }
            )
        }
    }

    // MARK: - Task Submission (absorbed from TaskFlowView)

    private func submitTaskFromCard(fields: [String: String], transferChoice: String?) {
        guard let task = viewModel.currentTask else { return }

        // Fire webhook (fire-and-forget, failure is silent)
        WebhookService.sendTaskSubmission(
            userId: userState?.userId ?? "unknown",
            userName: userState?.name ?? "Unknown",
            taskId: task.taskId ?? "unknown",
            taskTitle: task.title,
            taskType: task.taskType ?? "unknown",
            confirmedFields: fields,
            transferChoice: transferChoice
        )

        // Write to Firestore
        guard let userId = Auth.auth().currentUser?.uid,
              let taskId = task.taskId else { return }

        let db = Firestore.firestore()
        let taskRef = db.collection("users").document(userId)
            .collection("tasks").document(taskId)

        Task {
            do {
                try await taskRef.updateData([
                    "status": "PendingPeezy",
                    "confirmedFields": fields,
                    "submittedAt": FieldValue.serverTimestamp()
                ])
            } catch {
                await MainActor.run {
                    viewModel.error = "Submission failed. Please check your connection and try again."
                }
            }
        }
    }

    // MARK: - Daily Complete Card

    private var dailyCompleteCard: some View {
        ZStack {
            glassCard {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()

                    VStack(alignment: .leading, spacing: 15) {
                        Text("You're all done\nfor today!")
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .lineLimit(3)
                            .minimumScaleFactor(0.5)

                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 50, height: 2)

                        Text(viewModel.celebrationSubtext)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    if !viewModel.allActiveTasks.isEmpty {
                        PeezyAssessmentButton(viewModel.currentBatchOffset > 0 ? "Keep going?" :
                            "Want to get ahead?") {
                            confettiActive = false
                            viewModel.getAhead()
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
            }

            ConfettiView(isActive: $confettiActive, intensity: .high)
                .frame(width: 340, height: 500)
                .allowsHitTesting(false)
        }
        .onAppear { if !reduceMotion { confettiActive = true } }
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
                        .foregroundStyle(Color(uiColor: .systemGreen))

                    let name = viewModel.userState?.name ?? ""
                    Text(name.isEmpty ? "You're all set!" : "You're all set, \(name)!")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 50, height: 2)

                    Text(viewModel.allCompleteSubtext)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
        }
    }

    // MARK: - Glass Card Container

    /// Glass card matching assessment theme — uses unified chrome
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .peezyCardChrome()
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
