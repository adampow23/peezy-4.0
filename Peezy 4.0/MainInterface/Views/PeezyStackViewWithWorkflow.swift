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
                    // Dismiss on background tap (only for non-swipeable cards)
                    if case .swipeable = viewModel.snoozeManager.snoozeCard {
                        // Don't dismiss swipeable card on background tap
                    } else {
                        viewModel.snoozeManager.cancelSnooze()
                    }
                }

            // Snooze card - render based on type
            if let snoozeCard = viewModel.snoozeManager.snoozeCard {
                switch snoozeCard {
                case .swipeable(let taskId, let taskTitle):
                    // New swipeable snooze card (matches main card style)
                    SwipeableSnoozeCardView(
                        taskTitle: taskTitle,
                        taskId: taskId,
                        onSwipe: { action in
                            Task {
                                await viewModel.snoozeManager.handleSwipeAction(action)
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity
                    ))

                case .datePicker(_, let taskTitle):
                    // Date picker card (charcoal glass style)
                    SnoozeDatePickerCardView(
                        taskTitle: taskTitle,
                        selectedDate: Binding(
                            get: { viewModel.snoozeManager.selectedDate },
                            set: { viewModel.snoozeManager.selectedDate = $0 }
                        ),
                        minimumDate: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!,
                        onConfirm: {
                            Task {
                                await viewModel.snoozeManager.confirmCustomDate()
                            }
                        },
                        onBack: {
                            // Go back to swipeable card
                            if let taskId = viewModel.snoozeManager.currentTaskId,
                               let title = viewModel.snoozeManager.currentTaskTitle {
                                viewModel.snoozeManager.snoozeCard = .swipeable(taskId: taskId, taskTitle: title)
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))

                case .confirmation(let taskTitle, let snoozeDate, let action):
                    // Confirmation card (charcoal glass style)
                    SnoozeConfirmationCardView(
                        taskTitle: taskTitle,
                        snoozeDate: snoozeDate,
                        action: action == .dismissed ? .never : .tomorrow
                    )
                    .transition(.scale(scale: 0.9).combined(with: .opacity))

                case .options(_, let taskTitle):
                    // Legacy options card (fallback)
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

                // Loading overlay
                if viewModel.snoozeManager.isLoading {
                    Color.black.opacity(0.3)
                        .cornerRadius(36)
                        .frame(width: 340, height: 500)

                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
        }
        .animation(.spring(response: 0.35), value: viewModel.snoozeManager.snoozeCard?.id)
    }
}

// MARK: - Preview

#Preview {
    PeezyStackViewWithWorkflow(
        userState: UserState(userId: "preview", name: "Kierstin")
    )
}
