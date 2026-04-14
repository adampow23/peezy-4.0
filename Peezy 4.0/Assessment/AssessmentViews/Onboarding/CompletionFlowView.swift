//
//  CompletionFlowView.swift
//  Peezy
//
//  Linear completion flow after assessment:
//    Stage 1 — PercentageGeneratingView (0-100% radial progress + cycling messages)
//    Stage 2 — ReadyView (checkmark + "See Your Custom Plan")
//    Stage 3 — SummaryView (confetti + task count + "Let's Get Started")
//              → routes directly to main app
//
//  Presented via .fullScreenCover from AssessmentFlowView when coordinator.isComplete = true.
//  Only one stage renders at a time via a switch — no overlapping ZStacks.
//

import SwiftUI

struct CompletionFlowView: View {

    @ObservedObject var coordinator: AssessmentCoordinator
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    // MARK: - Stage Machine

    enum Stage: Int, Comparable {
        case generating = 0
        case ready = 1
        case summary = 2
        case paywall = 3
        case paywallGate = 4

        static func < (lhs: Stage, rhs: Stage) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: Stage = .generating
    @State private var taskCount: Int = 0
    @State private var showContent = true

    /// Ensures stage can only advance forward, never go back.
    private func advanceStage(to newStage: Stage) {
        guard newStage.rawValue > stage.rawValue else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.45, dampingFraction: 0.9)) {
            stage = newStage
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            InteractiveBackground()

            if showContent {
                // Utilizing a ZStack + ID allows SwiftUI to transition smoothly between switch cases
                ZStack {
                    switch stage {
                    case .generating:
                        PercentageGeneratingView(
                            isSaving: coordinator.isSaving,
                            onTasksCounted: { count in
                                taskCount = count
                            },
                            onReady: {
                                advanceStage(to: .ready)
                            }
                        )
                        .transition(stageTransition)
                        
                    case .ready:
                        ReadyView(onContinue: {
                            advanceStage(to: .summary)
                        })
                        .transition(stageTransition)
                        
                    case .summary:
                        SummaryView(
                            userName: coordinator.dataManager.userName,
                            taskCount: taskCount,
                            onGetStarted: {
                                advanceStage(to: .paywall)
                            }
                        )
                        .transition(stageTransition)

                    case .paywall:
                        PaywallValueView(onContinue: {
                            advanceStage(to: .paywallGate)
                        })
                        .transition(paywallTransition)

                    case .paywallGate:
                        PaywallGateView(onDismiss: {
                            routeToMainApp()
                        })
                        .environmentObject(subscriptionManager)
                        .transition(paywallTransition)
                    }
                }
                // Attaching the ID forces SwiftUI to treat each stage change as a distinct view replacement, triggering the transitions.
                .id(stage.rawValue)
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Transitions
    
    // Soft, spatial push forward for the loading/completion states
    private var stageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)),
            removal: .opacity.combined(with: .scale(scale: 1.04))
        )
    }
    
    // Traditional slide for paywall flows
    private var paywallTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Route to Main App

    private func routeToMainApp() {
        showContent = false
        NotificationCenter.default.post(name: .assessmentCompleted, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            coordinator.isComplete = false
        }

        // FAILSAFE
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if coordinator.isComplete {
                coordinator.isComplete = false
                NotificationCenter.default.post(name: .assessmentCompleted, object: nil)
            }
        }
    }
}

// MARK: - Beautiful 0-100% Progress View

struct PercentageGeneratingView: View {
    var isSaving: Bool
    var onTasksCounted: (Int) -> Void
    var onReady: () -> Void

    @State private var progress: Double = 0
    @State private var messageIndex = 0
    @State private var messageTimer: Timer?
    
    private let messages = [
        "Analyzing your responses...",
        "Identifying patterns...",
        "Building your custom plan...",
        "Applying the finishing touches..."
    ]

    var body: some View {
        VStack(spacing: 40) {
            ZStack {
                // Subtle background track
                Circle()
                    .stroke(Color.primary.opacity(0.06), style: StrokeStyle(lineWidth: 12, lineCap: .round))

                // Vibrant, glowing progress track
                Circle()
                    .trim(from: 0, to: CGFloat(progress) / 100.0)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.blue, .purple, .blue]),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    // Subtle glow effect
                    .shadow(color: .purple.opacity(0.3), radius: 10, x: 0, y: 4)

                // Large, stable numeric counter
                Text("\(Int(progress))%")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit() // Prevents horizontal jitter as numbers change
                    .contentTransition(.numericText(value: progress))
                    .foregroundStyle(Color.primary)
            }
            .frame(width: 180, height: 180)

            // Softly fading status messages
            Text(messages[messageIndex])
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .id(messageIndex)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
        }
        .padding(.horizontal, 32)
        .onAppear {
            startSimulations()
        }
        .onChange(of: isSaving) { saving in
            if !saving {
                finishSimulation()
            }
        }
        .onDisappear {
            messageTimer?.invalidate()
        }
    }

    // MARK: - Simulation Logic
    
    private func startSimulations() {
        // 1. Start cycling messages
        messageTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                if messageIndex < messages.count - 1 {
                    messageIndex += 1
                }
            }
        }
        
        // 2. Animate progress swiftly to 85%, then hold for the backend
        withAnimation(.easeOut(duration: 2.5)) {
            progress = 85
        }
    }

    private func finishSimulation() {
        // Rush to 100%
        withAnimation(.easeOut(duration: 0.5)) {
            progress = 100
        }
        
        // Give the user a brief moment to actually see the "100%" before jumping screens
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            // NOTE: If your backend provides the task count, pass it here.
            // Otherwise, provide a fallback.
            onTasksCounted(Int.random(in: 4...8))
            onReady()
        }
    }
}
