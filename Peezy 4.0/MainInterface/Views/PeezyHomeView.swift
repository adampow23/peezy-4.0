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

    #if DEBUG
    @State private var showDebugMenu = false
    #endif

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
                        #if DEBUG
                        .onTapGesture(count: 3) {
                            showDebugMenu = true
                        }
                        #endif

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
        #if DEBUG
        .sheet(isPresented: $showDebugMenu) {
            // DebugMenuView expects PeezyStackViewModel — skip for now
            Text("Debug Menu — use timeline for debug access")
                .padding()
        }
        #endif
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 15) {
                        // Greeting
                        Text(viewModel.firstTimeWelcomeGreeting)
                            .font(.system(size: 38, weight: .heavy))
                            .foregroundColor(PeezyTheme.Colors.deepInk)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)

                        // Thin accent divider
                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .frame(width: 50, height: 2)

                        // Body text
                        Text(viewModel.firstTimeWelcomeText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // "Let's do this" button
                    Button(action: { viewModel.dismissFirstTimeWelcome() }) {
                        Text("Let's do this")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                }
            }
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
                Button(action: { viewModel.startNextTask() }) {
                    Text("Get started")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(16)
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
                Button(action: { viewModel.startNextTask() }) {
                    Text("Pick up where I left off")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(16)
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
                    Button(action: { viewModel.skipCurrentTask() }) {
                        VStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 18))
                            Text("Later")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(Color.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.black.opacity(0.06))
                        .cornerRadius(16)
                    }

                    // I'm on it (user in progress)
                    if !isWorkflow {
                        Button(action: { viewModel.markCurrentTaskUserInProgress() }) {
                            VStack(spacing: 4) {
                                Image(systemName: "figure.walk.circle.fill")
                                    .font(.system(size: 18))
                                Text("I'm on it")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.black.opacity(0.06))
                            .cornerRadius(16)
                        }
                    }

                    // Complete / Get Started
                    Button(action: {
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
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .cornerRadius(16)
                    }
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
                        Button(action: {
                            confettiActive = false
                            viewModel.getAhead()
                        }) {
                            Text(viewModel.gettingAhead ? "Keep going?" : "Get ahead")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white)
                                .cornerRadius(16)
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

    /// Charcoal glass card matching existing card aesthetic from PeezyStackView
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            // Glass stack
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .foregroundStyle(.regularMaterial)

                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.white.opacity(0.5))
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
