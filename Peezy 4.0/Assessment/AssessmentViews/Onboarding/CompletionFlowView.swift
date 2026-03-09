//
//  CompletionFlowView.swift
//  Peezy
//
//  Linear completion flow after assessment:
//    Stage 1 — GeneratingView (spinner + cycling messages)
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
                            routeToMainApp()
                        }
                    )
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Route to Main App

    private func routeToMainApp() {
        // Immediately hide all content with zero animation so nothing flashes
        showContent = false

        // Post notification BEFORE dismissing the cover so main app state updates first
        NotificationCenter.default.post(name: .assessmentCompleted, object: nil)

        // Then dismiss the fullScreenCover
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            coordinator.isComplete = false
        }

        // FAILSAFE: If still showing after 5 seconds, force reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if coordinator.isComplete {
                coordinator.isComplete = false
                NotificationCenter.default.post(name: .assessmentCompleted, object: nil)
            }
        }
    }
}
