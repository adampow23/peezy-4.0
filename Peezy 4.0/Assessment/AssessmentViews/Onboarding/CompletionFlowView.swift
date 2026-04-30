//
//  CompletionFlowView.swift
//  Peezy
//
//  Linear completion flow after assessment:
//    Stage 1 — GeneratingView (polls generated task count)
//    Stage 2 — ReadyView (checkmark + "See Your Custom Plan")
//    Stage 3 — SummaryView (confetti + task count + "Let's Get Started")
//    Stage 4 — PaywallGateView (single-screen subscription paywall)
//              → Skipped entirely for users with an active subscription
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
        case paywallGate = 3

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
        withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .easeInOut(duration: 0.5)) {
            stage = newStage
        }
    }

    /// Called from SummaryView when the user taps "Let's Get Started".
    /// Active subscribers bypass the paywall entirely; everyone else
    /// advances to the paywall gate.
    private func handleSummaryGetStarted() {
        if subscriptionManager.isSubscribed {
            routeToMainApp()
        } else {
            advanceStage(to: .paywallGate)
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
                        GeneratingView(
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
                                handleSummaryGetStarted()
                            }
                        )
                        .transition(stageTransition)

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

    private var stageTransition: AnyTransition {
        .opacity
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
