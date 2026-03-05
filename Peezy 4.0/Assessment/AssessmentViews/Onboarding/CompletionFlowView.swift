//
//  CompletionFlowView.swift
//  Peezy
//
//  Replaces the monolithic AsessmentCompleteView with a clean linear flow:
//    Stage 1 — GeneratingView (spinner + cycling messages)
//    Stage 2 — ReadyView (checkmark + "See Your Custom Plan")
//    Stage 3 — SummaryView (confetti + task count + "Let's Get Started")
//              → routes to PaywallFlowView → then main app
//
//  Presented via .fullScreenCover from AssessmentFlowView when coordinator.isComplete = true.
//  Only one stage renders at a time via a switch — no overlapping ZStacks.
//

import SwiftUI

struct CompletionFlowView: View {

    @ObservedObject var coordinator: AssessmentCoordinator

    // MARK: - Stage Machine

    enum Stage: Int, Comparable {
        case generating = 0
        case ready = 1
        case summary = 2

        static func < (lhs: Stage, rhs: Stage) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    @State private var stage: Stage = .generating
    @State private var taskCount: Int = 0
    @State private var showPaywall = false
    @State private var showContent = true

    /// Ensures stage can only advance forward, never go back.
    private func advanceStage(to newStage: Stage) {
        guard newStage.rawValue > stage.rawValue else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            stage = newStage
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            InteractiveBackground()

            if showContent {
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
                case .ready:
                    ReadyView(onContinue: {
                        advanceStage(to: .summary)
                    })
                case .summary:
                    SummaryView(
                        userName: coordinator.dataManager.userName,
                        taskCount: taskCount,
                        onGetStarted: {
                            showPaywall = true
                        }
                    )
                }
            }
        }
        .interactiveDismissDisabled()
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallFlowView(onComplete: {
                handlePaywallComplete()
            })
            .environmentObject(SubscriptionManager.shared)
        }
    }

    // MARK: - Paywall Dismissal

    private func handlePaywallComplete() {
        // Immediately hide all content so nothing flashes
        withAnimation(.easeOut(duration: 0.15)) {
            showContent = false
        }

        // Then run the dismissal sequence
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showPaywall = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                coordinator.isComplete = false

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: .assessmentCompleted, object: nil)
                }
            }
        }

        // FAILSAFE: If still showing after 5 seconds, force reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if !showContent {
                showContent = true
                coordinator.isComplete = false
                NotificationCenter.default.post(name: .assessmentCompleted, object: nil)
            }
        }
    }
}
