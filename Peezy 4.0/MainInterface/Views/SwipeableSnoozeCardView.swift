//
//  SwipeableSnoozeCardView.swift
//  Peezy
//
//  Swipeable snooze card that matches the main task card styling.
//  Uses same charcoal glass design as CardView in PeezyStackView.
//
//  Swipe Actions:
//  - Right: Tomorrow (snooze until tomorrow)
//  - Left: Never (dismiss task permanently)
//  - Up: Other (show date picker for custom date)
//
//  Note: SnoozeSwipeAction enum is defined in SnoozeManager.swift
//

import SwiftUI

// MARK: - Swipeable Snooze Card View

struct SwipeableSnoozeCardView: View {
    let taskTitle: String
    let taskId: String
    let onSwipe: (SnoozeSwipeAction) -> Void

    @State private var offset: CGSize = .zero
    @State private var showContent = false

    // The specific "Text Input" Charcoal Gray (matching CardView)
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. THE GLASS STACK (identical to CardView)
                ZStack {
                    // A. The Blur Effect (Apple's native glass material)
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .foregroundStyle(.ultraThinMaterial)

                    // B. The Charcoal Tint (Semi-transparent)
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(charcoalColor.opacity(0.6))
                }
                // C. The Edge Highlight (Makes it look premium)
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        .padding(1)
                )
                // D. Deep Shadow for 3D depth
                .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 15)

                // 2. THE CONTENT
                VStack(spacing: 0) {
                    // Dynamic Header
                    ZStack {
                        // Default State
                        if offset.width == 0 && offset.height >= -20 {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("SNOOZE")
                                Spacer()
                            }
                            .font(.caption).bold()
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.top, 30)
                            .padding(.horizontal, 30)
                        }

                        // "NEVER" Label (Left Drag)
                        if offset.width < -20 {
                            Text("NEVER")
                                .font(.system(size: 60, weight: .black))
                                .foregroundStyle(.red.gradient)
                                .opacity(Double(abs(offset.width) / 100))
                        }

                        // "TOMORROW" Label (Right Drag)
                        if offset.width > 20 {
                            Text("TOMORROW")
                                .font(.system(size: 48, weight: .black))
                                .foregroundStyle(.green.gradient)
                                .opacity(Double(abs(offset.width) / 100))
                        }

                        // "OTHER" Label (Up Drag)
                        if offset.height < -20 && abs(offset.height) > abs(offset.width) {
                            Text("OTHER")
                                .font(.system(size: 60, weight: .black))
                                .foregroundStyle(.blue.gradient)
                                .opacity(Double(abs(offset.height) / 100))
                        }
                    }
                    .frame(height: 80)

                    Spacer()

                    // Main Content
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Remind Me")
                            .font(.system(size: 48, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        Text(taskTitle)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(3)
                    }
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    // Action Hints
                    VStack(spacing: 16) {
                        // Top hint (swipe up)
                        VStack {
                            Image(systemName: "chevron.up")
                                .font(.caption)
                            Text("Other")
                                .font(.caption2).bold()
                        }
                        .foregroundColor(.blue)
                        .opacity(0.8)

                        HStack {
                            // Never (Left)
                            VStack {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                Text("Never")
                                    .font(.caption2).bold()
                            }
                            .foregroundColor(.red)
                            .opacity(0.8)

                            Spacer()

                            // Tomorrow (Right)
                            VStack {
                                Image(systemName: "sunrise.fill")
                                    .font(.title2)
                                Text("Tomorrow")
                                    .font(.caption2).bold()
                            }
                            .foregroundColor(.green)
                            .opacity(0.8)
                        }
                    }
                    .padding(30)
                }
            }
            // Gesture and rotation logic
            .rotationEffect(.degrees(Double(offset.width / 20)))
            .offset(x: offset.width, y: min(offset.height * 0.4, 0)) // Only allow negative Y for upward swipe
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        offset = gesture.translation
                    }
                    .onEnded { _ in
                        // Determine primary direction
                        let isVerticalDominant = abs(offset.height) > abs(offset.width)

                        if isVerticalDominant && offset.height < -100 {
                            // Swipe up - Other
                            swipeAway(direction: .up, geometry: geometry)
                        } else if offset.width > 100 {
                            // Swipe right - Tomorrow
                            swipeAway(direction: .right, geometry: geometry)
                        } else if offset.width < -100 {
                            // Swipe left - Never
                            swipeAway(direction: .left, geometry: geometry)
                        } else {
                            // Return to center
                            withAnimation(.spring()) {
                                offset = .zero
                            }
                        }
                    }
            )
            .scaleEffect(showContent ? 1 : 0.8)
            .opacity(showContent ? 1 : 0)
        }
        .frame(width: 340, height: 500)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showContent = true
            }
        }
    }

    private enum SwipeDirection {
        case left, right, up
    }

    private func swipeAway(direction: SwipeDirection, geometry: GeometryProxy) {
        withAnimation(.easeIn(duration: 0.2)) {
            switch direction {
            case .right:
                offset.width = geometry.size.width + 100
            case .left:
                offset.width = -(geometry.size.width + 100)
            case .up:
                offset.height = -(geometry.size.height + 100)
            }
        }

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch direction {
            case .right: onSwipe(.tomorrow)
            case .left: onSwipe(.never)
            case .up: onSwipe(.other)
            }
        }
    }
}

// MARK: - Snooze Date Picker Card (Charcoal Glass Style)

struct SnoozeDatePickerCardView: View {
    let taskTitle: String
    @Binding var selectedDate: Date
    let minimumDate: Date
    let onConfirm: () -> Void
    let onBack: () -> Void

    @State private var showContent = false

    // Charcoal color for glass tint
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)

    var body: some View {
        ZStack {
            // Glass background
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

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()
                }
                .padding(.top, 28)
                .padding(.horizontal, 28)

                Text("Pick a Date")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 16)

                Text(taskTitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                    .padding(.horizontal, 28)
                    .padding(.top, 4)

                // Date Picker
                DatePicker(
                    "Snooze until",
                    selection: $selectedDate,
                    in: minimumDate...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(Color(red: 0.2, green: 0.5, blue: 1.0))
                .colorScheme(.dark)
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
                        .background(Color(red: 0.2, green: 0.5, blue: 1.0))
                        .cornerRadius(16)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .frame(width: 340, height: 500)
        .scaleEffect(showContent ? 1 : 0.8)
        .opacity(showContent ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showContent = true
            }
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: selectedDate)
    }
}

// MARK: - Snooze Confirmation Card (Charcoal Glass Style)

struct SnoozeConfirmationCardView: View {
    let taskTitle: String
    let snoozeDate: Date
    let action: SnoozeSwipeAction

    @State private var checkmarkScale: CGFloat = 0
    @State private var showContent = false

    // Charcoal color for glass tint
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)

    var body: some View {
        ZStack {
            // Glass background
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

            VStack(spacing: 20) {
                Spacer()

                // Animated icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.2))
                        .frame(width: 100, height: 100)

                    Image(systemName: iconName)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(iconColor)
                        .scaleEffect(checkmarkScale)
                }

                Text(titleText)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                if action == .never {
                    Text(taskTitle)
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Text("removed from your list")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    Text("I'll remind you about")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))

                    Text(taskTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Text("on \(formattedDate)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(red: 0.2, green: 0.5, blue: 1.0))
                }

                Spacer()
            }
        }
        .frame(width: 340, height: 500)
        .scaleEffect(showContent ? 1 : 0.8)
        .opacity(showContent ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showContent = true
            }

            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
                checkmarkScale = 1.0
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private var iconName: String {
        switch action {
        case .never: return "xmark"
        case .tomorrow, .other: return "checkmark"
        }
    }

    private var iconColor: Color {
        switch action {
        case .never: return .red
        case .tomorrow, .other: return .green
        }
    }

    private var titleText: String {
        switch action {
        case .never: return "Got it!"
        case .tomorrow, .other: return "Got it!"
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: snoozeDate)
    }
}

// MARK: - Preview

#Preview("Swipeable Snooze Card") {
    ZStack {
        // Background
        Color(red: 0.02, green: 0.02, blue: 0.06)
            .ignoresSafeArea()

        SwipeableSnoozeCardView(
            taskTitle: "Book Moving Company",
            taskId: "test-123",
            onSwipe: { action in
                print("Swiped: \(action)")
            }
        )
    }
}

#Preview("Date Picker") {
    ZStack {
        Color(red: 0.02, green: 0.02, blue: 0.06)
            .ignoresSafeArea()

        SnoozeDatePickerCardView(
            taskTitle: "Book Moving Company",
            selectedDate: .constant(Date().addingTimeInterval(86400 * 3)),
            minimumDate: Date().addingTimeInterval(86400),
            onConfirm: {},
            onBack: {}
        )
    }
}

#Preview("Confirmation - Tomorrow") {
    ZStack {
        Color(red: 0.02, green: 0.02, blue: 0.06)
            .ignoresSafeArea()

        SnoozeConfirmationCardView(
            taskTitle: "Book Moving Company",
            snoozeDate: Date().addingTimeInterval(86400),
            action: .tomorrow
        )
    }
}

#Preview("Confirmation - Never") {
    ZStack {
        Color(red: 0.02, green: 0.02, blue: 0.06)
            .ignoresSafeArea()

        SnoozeConfirmationCardView(
            taskTitle: "Book Moving Company",
            snoozeDate: Date(),
            action: .never
        )
    }
}
