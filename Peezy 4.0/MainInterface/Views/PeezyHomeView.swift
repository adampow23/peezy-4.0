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
//  Walkthrough steps wired here:
//  - Step 1: welcomeCard (daily task spotlight)
//  - Step 2: chat handle (pull down to chat)
//  - Step 5: "Get started" button (how services work)
//

import SwiftUI

struct PeezyHomeView: View {

    // User state passed from PeezyMainContainer
    var userState: UserState?

    // Demo workflow trigger from walkthrough completion
    @Binding var startDemo: Bool

    // View model — owned by this view
    @State private var viewModel = PeezyHomeViewModel()

    // Chat sheet
    @State private var showChat = false

    // Demo tooltip visibility
    @State private var showDemoTooltip = false

    #if DEBUG
    @State private var showDebugMenu = false
    #endif

    // Charcoal glass color (matches existing CardView)
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)

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

                    case .welcome:
                        welcomeCard
                            .walkthroughStep(1, cornerRadius: 36) {
                                WalkthroughStepView(
                                    title: "Your Daily Task",
                                    body: "Each day, Peezy gives you one thing to focus on. No overwhelm — just the next most important step for your move."
                                )
                            }

                    case .activeTask:
                        activeTaskContent

                    case .done:
                        doneCard
                    }

                    Spacer()
                }

                // Top Bar — peezy logo
                VStack(spacing: 0) {
                    Text("peezy")
                        .font(.system(size: 18, weight: .light, design: .default))
                        .tracking(6)
                        .foregroundStyle(.white.opacity(0.9))
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
                                .foregroundStyle(.white.opacity(0.3))
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .frame(width: 60, height: 6)
                            Text("Swipe up to chat")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.bottom, 10)
                    }
                    .walkthroughStep(2, cornerRadius: 20) {
                        WalkthroughStepView(
                            title: "Chat with Peezy",
                            body: "Need help or have a question? Pull down anytime to chat. Peezy knows your move details and can help with anything."
                        )
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

                // Demo workflow tooltip — contentShape(.rect) limits hit area to the tooltip only
                if showDemoTooltip, let phase = viewModel.demoPhase {
                    VStack {
                        DemoTooltipView(phase: phase) {
                            withAnimation { showDemoTooltip = false }
                        }
                        .padding(.top, 60)

                        Spacer()
                            .allowsHitTesting(false)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(10)
                }
            }
        }
        .onAppear {
            viewModel.userState = userState
            if viewModel.taskQueue.isEmpty && viewModel.state == .loading {
                Task { await viewModel.loadTasks() }
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
        .onChange(of: startDemo) { _, shouldStart in
            if shouldStart {
                startDemo = false
                viewModel.startDemoWorkflow()
                // Tooltip shown via onChange(of: viewModel.demoPhase) when demoPhase → .intro
            }
        }
        .onChange(of: viewModel.demoPhase) { _, newPhase in
            if newPhase != nil {
                withAnimation { showDemoTooltip = true }
            } else {
                withAnimation { showDemoTooltip = false }
            }
        }
    }

    // MARK: - Welcome Card

    private var welcomeCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 15) {
                    // Greeting
                    Text(viewModel.greetingText)
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    // Thin accent divider
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 50, height: 2)

                    // Subtitle
                    Text(viewModel.welcomeSubtitle)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.7))

                    // Task count
                    HStack(spacing: 12) {
                        Image(systemName: "checklist")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 24)

                        Text(viewModel.taskReadyText)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // Get Started button
                if viewModel.hasMoreTasks {
                    Button(action: { viewModel.startNextTask() }) {
                        Text("Get started")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .cornerRadius(16)
                    }
                    .walkthroughStep(4, cornerRadius: 16) {
                        WalkthroughStepView(
                            title: "How Services Work",
                            body: "When it's time to book a service — movers, internet, cleaning — we walk you through it step by step. Answer a few questions, and Peezy handles the rest."
                        )
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
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
                    .tint(.white)
                Text("Loading your task...")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
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
                    .foregroundStyle(.white.opacity(0.5))
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
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 30)
                .padding(.horizontal, 30)

                Spacer()

                // Content
                VStack(alignment: .leading, spacing: 15) {
                    Text(task.title)
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(task.subtitle)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(nil)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // Action buttons
                HStack(spacing: 16) {
                    // Skip
                    Button(action: { viewModel.skipCurrentTask() }) {
                        Text("Skip")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(16)
                    }

                    // Complete
                    Button(action: { viewModel.completeCurrentTask() }) {
                        Text("Complete")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: - Done Card

    private var doneCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 15) {
                    // Celebration icon
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)

                    // Message
                    Text(doneHeadline)
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    // Thin accent divider
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 50, height: 2)

                    Text(doneSubtitle)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // Next task button (if available)
                if viewModel.hasMoreTasks {
                    Button(action: { viewModel.startNextTask() }) {
                        Text("Start next task")
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
    }

    // MARK: - Done Copy

    private var doneHeadline: String {
        if viewModel.completedThisSession == 1 {
            return "Nice work."
        } else if viewModel.completedThisSession > 1 {
            return "On a roll."
        }
        return "All caught up."
    }

    private var doneSubtitle: String {
        if viewModel.hasMoreTasks {
            let remaining = viewModel.totalTaskCount
            if remaining == 1 {
                return "1 more task whenever you're ready."
            }
            return "\(remaining) more tasks whenever you're ready."
        }
        return "I'll let you know when something comes up."
    }

    // MARK: - Glass Card Container

    /// Charcoal glass card matching existing card aesthetic from PeezyStackView
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            // Glass stack
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .foregroundStyle(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(charcoalColor.opacity(0.6))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    .padding(1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 15)

            // Content
            content()
        }
        .frame(width: 340, height: 500)
    }
}

// MARK: - Demo Tooltip

private struct DemoTooltipView: View {
    let phase: PeezyHomeViewModel.DemoPhase
    let onDismiss: () -> Void

    var message: String {
        switch phase {
        case .intro:
            return "This is how Peezy handles services.\nTap Continue to start."
        case .question(let index):
            return index == 0
                ? "Pick what matters most to you."
                : "Select any that apply, then tap Continue."
        case .recap:
            return "Here's your summary.\nTap 'Sounds Good' to wrap up."
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Button("Got it") {
                onDismiss()
            }
            .font(.caption.bold())
            .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Preview

#Preview {
    PeezyHomeView(
        userState: UserState(userId: "preview", name: "Adam"),
        startDemo: .constant(false)
    )
}
