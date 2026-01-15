//
//  PeezyStackViewWithWorkflow.swift
//  Peezy
//
//  Extends PeezyStackView with workflow card overlay
//

import SwiftUI

struct PeezyStackViewWithWorkflow: View {
    // Create own viewModel (shared with PeezyStackView)
    @State private var viewModel = PeezyStackViewModel()

    // User state passed from parent
    var userState: UserState?

    var body: some View {
        ZStack {
            // Base stack view - pass shared viewModel
            PeezyStackView(viewModel: viewModel, userState: userState)

            // Workflow overlay when active
            if viewModel.isInWorkflow {
                workflowOverlay
            }

            // Snooze overlay when active
            if viewModel.isSnoozing {
                snoozeOverlay
            }
        }
    }

    // MARK: - Workflow Overlay

    @ViewBuilder
    private var workflowOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black
                .opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    // Optional: dismiss on background tap
                    viewModel.workflowManager.cancelWorkflow()
                    viewModel.onWorkflowDismissed()
                }

            // Workflow cards
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
                        viewModel.handleWorkflowComplete()
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }

            // Loading overlay
            if viewModel.workflowManager.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }

            // Error toast (if needed)
            if let error = viewModel.workflowManager.error {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.9))
                        .cornerRadius(10)
                        .padding(.bottom, 50)
                }
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(response: 0.4), value: viewModel.workflowManager.workflowCards.count)
    }

    // MARK: - Snooze Overlay

    @ViewBuilder
    private var snoozeOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black
                .opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    // Dismiss on background tap
                    viewModel.snoozeManager.cancelSnooze()
                }

            // Snooze card
            if let snoozeCard = viewModel.snoozeManager.snoozeCard {
                SnoozeCardView(
                    card: snoozeCard,
                    options: viewModel.snoozeManager.quickOptions,
                    selectedDate: Binding(
                        get: { viewModel.snoozeManager.selectedDate },
                        set: { viewModel.snoozeManager.selectedDate = $0 }
                    ),
                    isLoading: viewModel.snoozeManager.isLoading,
                    onSelectOption: { option in
                        Task {
                            await viewModel.snoozeManager.selectOption(option)
                        }
                    },
                    onPickDate: {
                        viewModel.snoozeManager.showDatePicker()
                    },
                    onConfirmDate: {
                        Task {
                            await viewModel.snoozeManager.confirmCustomDate()
                        }
                    },
                    onCancel: {
                        viewModel.snoozeManager.cancelSnooze()
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.35), value: viewModel.snoozeManager.snoozeCard?.id)
    }
}

// MARK: - Preview

#Preview {
    PeezyStackViewWithWorkflow(
        userState: UserState(userId: "preview", name: "Adam")
    )
}
