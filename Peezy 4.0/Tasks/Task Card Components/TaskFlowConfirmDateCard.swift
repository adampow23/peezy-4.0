//
//  TaskFlowConfirmDateCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI

// MARK: - Task Flow Confirm Date Card
// Displays the user's move date and asks them to confirm or update it.
// Read state: display container + confirm/change buttons (vertical stack).
// Edit state: graphical date picker + cancel/save buttons (horizontal stack).
// Question text hides in edit mode to make room for the ~320pt picker.
//
// Usage:
//   TaskFlowConfirmDateCard(
//       taskTitle: "Reserve unloading elevator",
//       question: "Is this your move date?",
//       currentDate: userMoveDate,
//       onConfirm: { date in advance() },
//       onBack: { goBack() }
//   )

struct TaskFlowConfirmDateCard: View {
    let taskTitle: String
    let question: String
    let currentDate: Date
    var confirmLabel: String = "That's right"
    var changeLabel: String = "Update this"
    var showBack: Bool = false
    let onConfirm: (Date) -> Void
    var onBack: (() -> Void)? = nil

    // MARK: - State

    @State private var isEditing = false
    @State private var confirmedDate: Date = Date()
    @State private var draftDate: Date = Date()

    // MARK: - Formatting

    private var formattedDate: String {
        confirmedDate.formatted(.dateTime.month(.wide).day().year())
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: taskTitle, showBack: showBack, onBack: onBack)

            if !isEditing {
                readState
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                editState
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.15), value: isEditing)
        .onAppear {
            confirmedDate = currentDate
            draftDate = currentDate
        }
    }

    // MARK: - Read State

    private var readState: some View {
        VStack(spacing: 0) {
            Spacer()

            // Question text
            VStack(alignment: .leading, spacing: 15) {
                Text(question)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Display container
            HStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))

                Text(formattedDate)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .padding(.horizontal, 24)

            Spacer().frame(height: 24)

            // Buttons — vertical (flow navigation pattern)
            VStack(spacing: 12) {
                PeezyAssessmentButton(confirmLabel) {
                    onConfirm(confirmedDate)
                }

                Button(action: {
                    PeezyHaptics.light()
                    draftDate = confirmedDate
                    withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                        isEditing = true
                    }
                }) {
                    Text(changeLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Edit State

    private var editState: some View {
        VStack(spacing: 0) {

            // Graphical date picker — question text hidden to make room
            DatePicker(
                "Select date",
                selection: $draftDate,
                in: Date()...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(PeezyTheme.Colors.deepInk)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            // Buttons — horizontal (edit/modal pattern)
            HStack(spacing: 12) {
                // Cancel
                Button(action: {
                    PeezyHaptics.light()
                    withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                        isEditing = false
                    }
                }) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)

                // Save
                Button(action: {
                    PeezyHaptics.light()
                    confirmedDate = draftDate
                    withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                        isEditing = false
                    }
                }) {
                    Text("Save")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(PeezyTheme.Colors.deepInk)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Confirm Date — Read") {
    TaskFlowConfirmDateCard(
        taskTitle: "Reserve unloading elevator",
        question: "Is this your move date?",
        currentDate: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date(),
        showBack: true,
        onConfirm: { date in print("✅ Confirmed: \(date)") },
        onBack: { print("⏪ Back") }
    )
    .peezyCardChrome()
}

#Preview("Confirm Date — Far Out") {
    TaskFlowConfirmDateCard(
        taskTitle: "Reserve loading parking",
        question: "Is this your move date?",
        currentDate: Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date(),
        showBack: true,
        onConfirm: { date in print("✅ Confirmed: \(date)") },
        onBack: { print("⏪ Back") }
    )
    .peezyCardChrome()
}
#endif
