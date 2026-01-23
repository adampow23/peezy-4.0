//
//  SnoozeCardView.swift
//  Peezy
//
//  Card views for the snooze flow - appears as overlay, not in swipeable stack
//
//  Three states:
//  1. Options - Quick time options (Tomorrow, Weekend, Next Week, etc.)
//  2. Date Picker - Custom date selection (minimum: tomorrow)
//  3. Confirmation - Brief "Got it!" message (0.9s) before dismissing
//

import SwiftUI

// MARK: - Main Snooze Card View

struct SnoozeCardView: View {
    let card: SnoozeCard
    let options: [SnoozeOption]
    @Binding var selectedDate: Date
    let isLoading: Bool

    let onSelectOption: (SnoozeOption) -> Void
    let onPickDate: () -> Void
    let onConfirmDate: () -> Void
    let onCancel: () -> Void

    // Minimum date is tomorrow
    private var minimumDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 10)

            switch card {
            case .swipeable:
                // Swipeable cards are handled by SwipeableSnoozeCardView
                // This legacy view shouldn't receive this case
                EmptyView()

            case .options(_, let taskTitle):
                SnoozeOptionsContent(
                    taskTitle: taskTitle,
                    options: options,
                    onSelect: onSelectOption,
                    onPickDate: onPickDate,
                    onCancel: onCancel
                )

            case .datePicker(_, let taskTitle):
                SnoozeDatePickerContent(
                    taskTitle: taskTitle,
                    selectedDate: $selectedDate,
                    minimumDate: minimumDate,
                    onConfirm: onConfirmDate,
                    onBack: onCancel
                )

            case .confirmation(let taskTitle, let snoozeDate, _):
                SnoozeConfirmationContent(
                    taskTitle: taskTitle,
                    snoozeDate: snoozeDate
                )
            }

            // Loading overlay
            if isLoading {
                RoundedRectangle(cornerRadius: 36)
                    .fill(Color.white.opacity(0.9))

                ProgressView()
                    .scaleEffect(1.2)
            }
        }
        .frame(width: 340, height: 500)
    }
}

// MARK: - Options Content

struct SnoozeOptionsContent: View {
    let taskTitle: String
    let options: [SnoozeOption]
    let onSelect: (SnoozeOption) -> Void
    let onPickDate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("REMIND ME")
                    .font(.caption).bold()
                    .foregroundStyle(.gray)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.gray.opacity(0.5))
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 28)

            // Task title
            Text(taskTitle)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.black)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 16)

            Text("When should I bring this back?")
                .font(.subheadline)
                .foregroundStyle(.gray)
                .padding(.top, 4)

            // Options
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(options) { option in
                        SnoozeOptionButton(option: option) {
                            onSelect(option)
                        }
                    }

                    // Custom date option
                    Button(action: onPickDate) {
                        HStack(spacing: 14) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.title3)
                                .foregroundStyle(Color(red: 0.98, green: 0.85, blue: 0.29))
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pick a Date")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.black)

                                Text("Choose specific day")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }

            Spacer()

            // Cancel hint
            Text("Tap X to go back")
                .font(.caption)
                .foregroundStyle(.gray.opacity(0.5))
                .padding(.bottom, 24)
        }
    }
}

// MARK: - Option Button

struct SnoozeOptionButton: View {
    let option: SnoozeOption
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: option.icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.black)

                    if let sublabel = option.sublabel {
                        Text(sublabel)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.gray.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(14)
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }

    private var iconColor: Color {
        switch option.id {
        case "tomorrow": return .orange
        case "weekend": return .blue
        case "next_week": return .purple
        case "two_weeks": return .indigo
        case "smart": return Color(red: 0.98, green: 0.85, blue: 0.29)
        default: return .gray
        }
    }
}

// MARK: - Date Picker Content

struct SnoozeDatePickerContent: View {
    let taskTitle: String
    @Binding var selectedDate: Date
    let minimumDate: Date
    let onConfirm: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                }

                Spacer()
            }
            .padding(.top, 28)
            .padding(.horizontal, 28)

            Text("Pick a Date")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.black)
                .padding(.top, 16)

            Text(taskTitle)
                .font(.subheadline)
                .foregroundStyle(.gray)
                .lineLimit(1)
                .padding(.horizontal, 28)
                .padding(.top, 4)

            // Date Picker - minimum is tomorrow
            DatePicker(
                "Snooze until",
                selection: $selectedDate,
                in: minimumDate...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(Color(red: 0.98, green: 0.85, blue: 0.29))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            // Confirm button
            Button(action: onConfirm) {
                Text("Remind me on \(formattedDate)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.black)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: selectedDate)
    }
}

// MARK: - Confirmation Content

struct SnoozeConfirmationContent: View {
    let taskTitle: String
    let snoozeDate: Date

    @State private var checkmarkScale: CGFloat = 0
    @State private var checkmarkOpacity: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Animated checkmark
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.green)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)
            }

            Text("Got it!")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.black)

            Text("I'll remind you about")
                .font(.subheadline)
                .foregroundStyle(.gray)

            Text(taskTitle)
                .font(.headline)
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Text("on \(formattedDate)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(red: 0.98, green: 0.85, blue: 0.29))

            Spacer()
        }
        .onAppear {
            // Animate checkmark
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
                checkmarkScale = 1.0
                checkmarkOpacity = 1.0
            }

            // Haptic feedback
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: snoozeDate)
    }
}

// MARK: - Preview

#Preview("Options") {
    let options = SnoozeOption.quickOptions(
        moveDate: Date().addingTimeInterval(86400 * 45),
        taskDueDate: Date().addingTimeInterval(86400 * 14)
    )

    return SnoozeCardView(
        card: .options(taskId: "test", taskTitle: "Book Moving Company"),
        options: options,
        selectedDate: .constant(Date().addingTimeInterval(86400)),
        isLoading: false,
        onSelectOption: { _ in },
        onPickDate: {},
        onConfirmDate: {},
        onCancel: {}
    )
}

#Preview("Date Picker") {
    SnoozeCardView(
        card: .datePicker(taskId: "test", taskTitle: "Book Moving Company"),
        options: [],
        selectedDate: .constant(Date().addingTimeInterval(86400 * 3)),
        isLoading: false,
        onSelectOption: { _ in },
        onPickDate: {},
        onConfirmDate: {},
        onCancel: {}
    )
}

#Preview("Confirmation") {
    SnoozeCardView(
        card: .confirmation(taskTitle: "Book Moving Company", snoozeDate: Date().addingTimeInterval(86400 * 7), action: .snoozed),
        options: [],
        selectedDate: .constant(Date().addingTimeInterval(86400)),
        isLoading: false,
        onSelectOption: { _ in },
        onPickDate: {},
        onConfirmDate: {},
        onCancel: {}
    )
}
