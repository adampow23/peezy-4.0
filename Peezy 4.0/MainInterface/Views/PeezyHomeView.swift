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

struct PeezyHomeView: View {

    // User state passed from PeezyMainContainer
    var userState: UserState?

    // Task list navigation — when set, this task is loaded as currentTask
    @Binding var focusedTask: PeezyCard?

    // View model — owned by this view
    @State private var viewModel = PeezyHomeViewModel()

    // Chat sheet
    @State private var showChat = false

    // Confetti state for batch-complete celebration card
    @State private var confettiActive = false

    // Onboarding pagination — tracks current welcome page (0, 1, 2)
    @State private var welcomePage: Int = 0

    // Deep ink text color for light theme
    private let deepInk = PeezyTheme.Colors.deepInk

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background (same as existing stack view)
                InteractiveBackground()

                // Swipe Up Detection Zone (behind card content so buttons remain tappable)
                VStack {
                    Spacer()
                    Color.clear
                        .frame(height: geometry.size.height * 0.3)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 50)
                                .onEnded { gesture in
                                    let vertical = gesture.translation.height
                                    let horizontal = abs(gesture.translation.width)
                                    if vertical < -80 && abs(vertical) > horizontal {
                                        showChat = true
                                    }
                                }
                        )
                }

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

                // Bottom Chat Handle (swipe up or tap to chat)
                VStack {
                    Spacer()
                    Button(action: { showChat = true }) {
                        VStack(spacing: 4) {
                            Image(systemName: "chevron.up")
                                .font(.caption)
                                .foregroundStyle(Color.gray.opacity(0.5))
                            Capsule()
                                .fill(.regularMaterial)
                                .frame(width: 60, height: 6)
                            Text("Swipe up to chat")
                                .font(.caption2)
                                .foregroundStyle(Color.gray)
                        }
                        .padding(.bottom, 10)
                    }
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
        }
        .onAppear {
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
        .sheet(isPresented: $showChat) {
            ChatView(userState: userState, card: nil)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
                // Scrollable page content — keyed by page so identity changes trigger opacity transition
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 15) {
                        Text(welcomePageHeadline)
                            .font(.system(size: 38, weight: .heavy))
                            .foregroundColor(PeezyTheme.Colors.deepInk)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)

                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .frame(width: 50, height: 2)

                        Text(welcomePageBody)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 30)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(welcomePage)
                .transition(.opacity)

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

                // Action button
                PeezyAssessmentButton(welcomePage < 2 ? "Continue" : "Start My First Task") {
                    if welcomePage < 2 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            welcomePage += 1
                        }
                    } else {
                        viewModel.dismissFirstTimeWelcome()
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
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
                return "We break your move into bite-sized daily tasks based on your timeline.\n\nWe've got about \(daily) tasks per day to keep you on track — just work through each day's batch and you're golden."
            } else {
                return "We break your move into bite-sized daily tasks based on your timeline. Each day you'll get a small batch to knock out — just work through them and you're golden."
            }
        case 1:
            return "The task list tab has everything — upcoming, in progress, and done. You can also start tasks ahead of schedule from there.\n\nNeed to update your move details? Tap the menu in the top left."
        default:
            return "Tap the chat icon on any task to get help from Peezy. It knows the context of that specific task and can walk you through it step by step."
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
            // Workflow card (centered, same size as original overlay)
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
        glassCard {
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
                let isWorkflow = !(task.workflowId ?? "").isEmpty
                HStack(spacing: 10) {
                    // Later (skip)
                    Button(action: {
                        PeezyHaptics.light()
                        viewModel.skipCurrentTask()
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

                    // I'm on it (user in progress)
                    if !isWorkflow {
                        Button(action: {
                            PeezyHaptics.light()
                            viewModel.markCurrentTaskUserInProgress()
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

                    // Complete / Get Started
                    Button(action: {
                        PeezyHaptics.medium()
                        if isWorkflow {
                            viewModel.startWorkflowForCurrentTask()
                        } else {
                            viewModel.completeCurrentTask()
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

                    // Get ahead — loads ONE task at a time
                    if !viewModel.allActiveTasks.isEmpty {
                        PeezyAssessmentButton("Keep Going") {
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

// MARK: - Preview

#Preview {
    PeezyHomeView(
        userState: UserState(userId: "preview", name: "Adam"),
        focusedTask: .constant(nil)
    )
}
