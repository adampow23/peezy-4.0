//
//  floatingTextInput.swift
//  PeezyV1.0
//
//  Created by user285836 on 11/9/25.
//

import SwiftUI

struct floatingTextInput: View {
    let question: String
    let placeholder: String
    let stepNumber: Int
    let totalSteps: Int
    @Binding var text: String
    let keyboardType: UIKeyboardType
    let onContinue: () -> Void
    let onBack: () -> Void

    // Animation states
    @State private var showContent = false

    init(
        question: String,
        placeholder: String = "",
        stepNumber: Int,
        totalSteps: Int = 10,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        onContinue: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.question = question
        self.placeholder = placeholder
        self.stepNumber = stepNumber
        self.totalSteps = totalSteps
        self._text = text
        self.keyboardType = keyboardType
        self.onContinue = onContinue
        self.onBack = onBack
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated Progress Header
            AssessmentProgressHeader(
                currentStep: stepNumber,
                totalSteps: totalSteps,
                onBack: onBack,
                onCompletion: {
                    // Not used for intermediate steps
                }
            )
            
            // Equal spacing region below the progress line
            GeometryReader { geo in
                VStack(spacing: 0) {
                    // Gap 1: Progress → Question
                    Spacer(minLength: 0)
                    
                    // Question
                    HStack {
                        Text(question)
                            .font(.system(size: 34, weight: .bold))
                            .frame(width: geo.size.width * 0.6, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                        Spacer(minLength: 0)
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(x: showContent ? 0 : -20)
                    .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)
                    
                    // Gap 2: Question → TextField
                    Spacer(minLength: 0)
                    
                    // Large floating text input with sleek design
                    VStack(spacing: 8) {
                        TextField(placeholder, text: $text)
                            .font(.system(size: 48, weight: .regular))
                            .multilineTextAlignment(.center)
                            .keyboardType(keyboardType)
                            .foregroundColor(.primary)
                            .tint(Color(red: 0.98, green: 0.85, blue: 0.29).opacity(0.5))
                            .padding(.vertical, 20)
                            .padding(.horizontal, 24)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.clear)
                                        .peezyLiquidGlass(
                                            cornerRadius: 16,
                                            intensity: 0.55,
                                            speed: 0.22,
                                            tintOpacity: 0.05,
                                            highlightOpacity: 0.12
                                        )

                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(PeezyTheme.Colors.brandYellow.opacity(0.06))

                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(
                                            text.isEmpty ? Color.gray.opacity(0.3) : PeezyTheme.Colors.brandYellow.opacity(0.35),
                                            lineWidth: 2
                                        )
                                }
                            )
                            .shadow(
                                color: text.isEmpty ? Color.clear : Color(red: 0.98, green: 0.85, blue: 0.29).opacity(0.2),
                                radius: 8,
                                x: 0,
                                y: 4
                            )

                        // Subtle helper text
                        if text.isEmpty {
                            Text("Tap to enter your name")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 40)
                    .animation(.easeInOut(duration: 0.2), value: text.isEmpty)
                    .opacity(showContent ? 1 : 0)
                    .scaleEffect(showContent ? 1.0 : 0.9)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3), value: showContent)
                    
                    // Gap 3: TextField → Bottom
                    Spacer(minLength: 0)
                }
            }

            // Continue button
            PeezyAssessmentButton("Continue", disabled: text.isEmpty) {
                onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .background(Color(.systemBackground))
        .onAppear {
            withAnimation {
                showContent = true
            }
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

#Preview {
    @Previewable @State var name = ""
    
    floatingTextInput(
        question: "What's your first name?",
        placeholder: "",
        stepNumber: 1,
        text: $name,
        onContinue: { print("Continue tapped") },
        onBack: { print("Back tapped") }
    )
}
