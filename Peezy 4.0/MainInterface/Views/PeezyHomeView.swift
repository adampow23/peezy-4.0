//
//  PeezyHomeView.swift
//  Peezy
//
//  Main home screen with state machine: welcome → task → done
//
//  CRASH FIX (Apr 2026): onDismiss + cleanupTaskFlow() for safe flowId clearing.
//  SPINNER FIX (Apr 2026): pendingAdvance defers next task until dismiss completes.
//  CONFETTI FIX (Apr 2026): Confetti moved to SummaryCard/StatusCard — celebration
//  happens at the moment of accomplishment, not on the recap screen.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct PeezyHomeView: View {

    var userState: UserState?
    @Binding var focusedTask: PeezyCard?

    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var viewModel = PeezyHomeViewModel()
    @State private var welcomePage: Int = 0

    private let deepInk = PeezyTheme.Colors.deepInk
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private var showTaskFlowBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showTaskFlow },
            set: { newValue in
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    viewModel.showTaskFlow = newValue
                }
            }
        )
    }

    // MARK: - Initializers

    init(userState: UserState?, focusedTask: Binding<PeezyCard?>) {
        self.userState = userState
        self._focusedTask = focusedTask
    }

    #if DEBUG
    init(previewViewModel: PeezyHomeViewModel) {
        self.userState = previewViewModel.userState
        self._focusedTask = .constant(nil)
        self._viewModel = State(initialValue: previewViewModel)
    }
    #endif

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

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

            VStack(spacing: 0) {
                PeezyWordmark()
                Spacer()
            }

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
                return
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
        .fullScreenCover(isPresented: showTaskFlowBinding, onDismiss: {
            viewModel.cleanupTaskFlow()
        }) {
            if let flowId = viewModel.taskFlowWorkflowId {
                TaskFlowRouter.flow(
                    for: flowId,
                    userId: Auth.auth().currentUser?.uid ?? "",
                    taskId: viewModel.currentTask?.id,
                    userState: viewModel.userState,
                    onComplete: { viewModel.completeTaskFlow() },
                    onDismiss: { viewModel.dismissTaskFlow() },
                    onStatusAction: { action in
                        switch action {
                        case .done: viewModel.statusActionDone()
                        case .inProgress: viewModel.statusActionInProgress()
                        case .later: viewModel.statusActionLater()
                        }
                    }
                )
            }
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
                Spacer()

                VStack(alignment: .leading, spacing: 16) {
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

                    Text(welcomePageBody)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .id(welcomePage)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                Spacer()

                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == welcomePage ? Color.primary.opacity(0.4) : Color.primary.opacity(0.12))
                            .frame(width: 7, height: 7)
                            .accessibilityIdentifier("welcome_dot_\(i)")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                PeezyAssessmentButton(welcomePage < 2 ? "Continue" : "Let's do this") {
                    if welcomePage < 2 {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.85)) {
                            welcomePage += 1
                        }
                    } else {
                        viewModel.dismissFirstTimeWelcome()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .accessibilityIdentifier(welcomePage < 2 ? "welcome_continue_button" : "welcome_start_button")
            }
        }
        .accessibilityIdentifier("welcome_card")
    }

    private var welcomePageHeadline: String {
        switch welcomePage {
        case 0: return viewModel.firstTimeWelcomeGreeting
        case 1: return "Stay in control."
        default: return "We're here to help."
        }
    }

    private var welcomePageBody: String {
        switch welcomePage {
        case 0:
            let daily = viewModel.dailyTarget
            if daily > 0 {
                let taskWord = daily == 1 ? "task" : "tasks"
                return "Just \(daily) \(taskWord) per day to stay on pace.\n\nCheck in once a day, knock them out, and you're set."
            } else {
                return "Check in once a day, complete your daily tasks, and you'll be on pace to get everything done."
            }
        case 1:
            return "Your full task list is in the Tasks tab below.\n\nNeed to update move details? Head to Settings. Questions or feedback? Use the Chat tab."
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
                .accessibilityIdentifier("greeting_start_button")
            }
        }
        .accessibilityIdentifier("daily_greeting_card")
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
                .accessibilityIdentifier("returning_continue_button")
            }
        }
        .accessibilityIdentifier("returning_card")
    }

    // MARK: - Active Task Content

    @ViewBuilder
    private var activeTaskContent: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(PeezyTheme.Colors.deepInk)
            Text("Loading your task...")
                .font(.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.8))
        }
    }

    // MARK: - Daily Complete Card (no confetti — moved to task cards)

    private var dailyCompleteCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 15) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color(uiColor: .systemGreen))

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
                        viewModel.getAhead()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .accessibilityIdentifier("get_ahead_button")
                }
            }
        }
        .accessibilityIdentifier("daily_complete_view")
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
        .accessibilityIdentifier("all_complete_view")
    }

    // MARK: - Glass Card Container

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .peezyCardChrome()
    }
}

// MARK: - Previews

#if DEBUG

#Preview("First Time Welcome") {
    PeezyHomeView(previewViewModel: .preview(state: .firstTimeWelcome))
}

#Preview("Daily Greeting") {
    PeezyHomeView(previewViewModel: .preview(state: .dailyGreeting))
}

#Preview("Returning Mid-Day") {
    PeezyHomeView(previewViewModel: .preview(state: .returningMidDay))
}

#Preview("Daily Complete") {
    PeezyHomeView(previewViewModel: .preview(state: .dailyComplete))
}

#Preview("All Complete") {
    PeezyHomeView(previewViewModel: .preview(state: .allComplete, tasks: []))
}

#endif
