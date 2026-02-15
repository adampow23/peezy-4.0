//
//  MiniAssessmentSheetView.swift
//  Peezy
//
//  Sheet UI for collecting mini-assessment answers.
//  Presented when user swipes "Do It" on a mini-assessment task card.
//
//  Flow:
//  1. User swipes right on a mini-assessment card (e.g., "Children Options")
//  2. This sheet appears with relevant questions
//  3. User answers questions
//  4. On completion, calls MiniAssessmentService to save answers + generate sub-tasks
//

import SwiftUI

struct MiniAssessmentSheetView: View {
    let taskId: String
    let taskTitle: String
    let onComplete: ([String: Any]) -> Void
    let onCancel: () -> Void

    @State private var answers: [String: String] = [:]
    @State private var currentQuestionIndex = 0
    @Environment(\.dismiss) private var dismiss

    // Questions based on task type
    private var questions: [MiniAssessmentQuestion] {
        MiniAssessmentQuestions.getQuestions(for: taskId)
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(red: 0.02, green: 0.02, blue: 0.06)
                    .ignoresSafeArea()

                if questions.isEmpty {
                    // No questions defined for this assessment
                    noQuestionsView
                } else {
                    // Question flow
                    questionFlowView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - No Questions View

    private var noQuestionsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("No questions configured")
                .font(.title2.bold())
                .foregroundColor(.white)

            Text("This mini-assessment doesn't have questions defined yet.")
                .font(.body)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Close") {
                onCancel()
                dismiss()
            }
            .font(.headline)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.white)
            .cornerRadius(16)
            .padding(.horizontal, 40)
            .padding(.top, 20)
        }
    }

    // MARK: - Question Flow View

    private var questionFlowView: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator

            // Header
            headerView

            Spacer()

            // Current question
            if currentQuestionIndex < questions.count {
                questionView(questions[currentQuestionIndex])
            } else {
                // Summary/completion view
                completionView
            }

            Spacer()
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<questions.count, id: \.self) { index in
                Capsule()
                    .fill(index <= currentQuestionIndex ? Color.green : Color.white.opacity(0.2))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 20)
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(taskTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1)

            if currentQuestionIndex < questions.count {
                Text("\(currentQuestionIndex + 1) of \(questions.count)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 30)
        .padding(.top, 20)
    }

    // MARK: - Question View

    private func questionView(_ question: MiniAssessmentQuestion) -> some View {
        VStack(spacing: 30) {
            // Question text
            Text(question.label)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)

            // Options
            VStack(spacing: 12) {
                ForEach(question.options, id: \.self) { option in
                    optionButton(option: option, questionKey: question.key)
                }
            }
            .padding(.horizontal, 30)
        }
    }

    // MARK: - Option Button

    private func optionButton(option: String, questionKey: String) -> some View {
        let isSelected = answers[questionKey] == option

        return Button {
            // Select this option
            withAnimation(.spring(response: 0.3)) {
                answers[questionKey] = option
            }

            // Haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            // Auto-advance after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.4)) {
                    if currentQuestionIndex < questions.count - 1 {
                        currentQuestionIndex += 1
                    } else {
                        // Move to completion
                        currentQuestionIndex = questions.count
                    }
                }
            }
        } label: {
            HStack {
                Text(option)
                    .font(.headline)
                    .foregroundColor(isSelected ? .black : .white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.black)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.green : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Completion View

    private var completionView: some View {
        VStack(spacing: 30) {
            // Success icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.green)
            }

            Text("All set!")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            Text("I'll create personalized tasks based on your answers.")
                .font(.body)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Summary of answers
            VStack(alignment: .leading, spacing: 8) {
                ForEach(questions, id: \.key) { question in
                    if let answer = answers[question.key] {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text(answer)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
            }
            .padding(.horizontal, 30)

            // Done button
            Button {
                // Convert answers to [String: Any] and complete
                var result: [String: Any] = [:]
                for (key, value) in answers {
                    result[key] = value
                }
                onComplete(result)
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.green)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 30)
            .padding(.top, 10)
        }
    }
}

// MARK: - Mini Assessment Question Model

struct MiniAssessmentQuestion {
    let key: String      // Firebase field name
    let label: String    // Display question
    let options: [String]
}

// MARK: - Mini Assessment Questions Database

struct MiniAssessmentQuestions {

    /// Get questions for a specific mini-assessment task
    static func getQuestions(for taskId: String) -> [MiniAssessmentQuestion] {
        switch taskId {

        case "CHILDREN_OPTIONS":
            return [
                MiniAssessmentQuestion(
                    key: "SchoolAgeChildren",
                    label: "How many school-age children (K-12)?",
                    options: ["0", "1", "2", "3+"]
                ),
                MiniAssessmentQuestion(
                    key: "ChildrenUnder5",
                    label: "How many children under 5?",
                    options: ["0", "1", "2", "3+"]
                )
            ]

        case "PET_OPTIONS":
            return [
                MiniAssessmentQuestion(
                    key: "PetType",
                    label: "What type of pet do you have?",
                    options: ["Dog", "Cat", "Bird", "Fish", "Reptile", "Other"]
                ),
                MiniAssessmentQuestion(
                    key: "NumberOfPets",
                    label: "How many pets?",
                    options: ["1", "2", "3+"]
                ),
                MiniAssessmentQuestion(
                    key: "PetSize",
                    label: "What size is your largest pet?",
                    options: ["Small", "Medium", "Large"]
                )
            ]

        case "FITNESS_OPTIONS":
            return [
                MiniAssessmentQuestion(
                    key: "Gym",
                    label: "Do you have a gym membership?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "Yoga",
                    label: "Do you have a yoga studio membership?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "Pilates",
                    label: "Do you have a Pilates membership?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "Crossfit",
                    label: "Do you have a CrossFit membership?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "SpinCycling",
                    label: "Do you have a spin/cycling membership?",
                    options: ["Yes", "No"]
                )
            ]

        case "FINANCE_OPTIONS":
            return [
                MiniAssessmentQuestion(
                    key: "BankAccount",
                    label: "Do you have a bank account to update?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "CreditUnion",
                    label: "Do you have a credit union account?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "CreditCard",
                    label: "Do you have credit cards to update?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "InvestmentAccounts",
                    label: "Do you have investment accounts?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "RetirementAccounts",
                    label: "Do you have retirement accounts (401k, IRA)?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "StudentLoans",
                    label: "Do you have student loans?",
                    options: ["Yes", "No"]
                )
            ]

        case "HEALTH_OPTIONS":
            return [
                MiniAssessmentQuestion(
                    key: "Doctor",
                    label: "Do you have a primary care doctor?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "Dentist",
                    label: "Do you have a dentist?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "Pharmacy",
                    label: "Do you use a regular pharmacy?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "Specialists",
                    label: "Do you see any medical specialists?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "Therapy",
                    label: "Do you see a therapist or counselor?",
                    options: ["Yes", "No"]
                )
            ]

        case "INSURANCE_OPTIONS":
            return [
                MiniAssessmentQuestion(
                    key: "HealthInsurance",
                    label: "Do you have health insurance to update?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "DentalInsurance",
                    label: "Do you have dental insurance?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "VisionInsurance",
                    label: "Do you have vision insurance?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "LifeInsurance",
                    label: "Do you have life insurance?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "PetInsurance",
                    label: "Do you have pet insurance?",
                    options: ["Yes", "No"]
                )
            ]

        case "MEMBERSHIP_OPTIONS":
            return [
                MiniAssessmentQuestion(
                    key: "CostcoMembership",
                    label: "Do you have a Costco membership?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "SamsMembership",
                    label: "Do you have a Sam's Club membership?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "CountryClub",
                    label: "Do you have a country club membership?",
                    options: ["Yes", "No"]
                )
            ]

        case "DELIVERY_OPTIONS":
            return [
                MiniAssessmentQuestion(
                    key: "Amazon",
                    label: "Do you use Amazon Prime?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "DoorDash",
                    label: "Do you use DoorDash?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "Instacart",
                    label: "Do you use Instacart?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "UberOne",
                    label: "Do you have Uber One?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "Walmart",
                    label: "Do you use Walmart+?",
                    options: ["Yes", "No"]
                )
            ]

        case "STREAMING_OPTIONS":
            return [
                MiniAssessmentQuestion(
                    key: "Netflix",
                    label: "Do you have Netflix?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "Hulu",
                    label: "Do you have Hulu?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "Disney",
                    label: "Do you have Disney+?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "HBOMax",
                    label: "Do you have HBO Max?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "YoutubeTV",
                    label: "Do you have YouTube TV?",
                    options: ["Yes", "No"]
                )
            ]

        case "TECH_OPTIONS":
            return [
                MiniAssessmentQuestion(
                    key: "AppleAccount",
                    label: "Do you have an Apple account to update?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "UberAccount",
                    label: "Do you use Uber?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "LyftAccount",
                    label: "Do you use Lyft?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "PaypalAccount",
                    label: "Do you have PayPal?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "VenmoAccount",
                    label: "Do you have Venmo?",
                    options: ["Yes", "No"]
                ),
                MiniAssessmentQuestion(
                    key: "CashAppAccount",
                    label: "Do you have Cash App?",
                    options: ["Yes", "No"]
                )
            ]

        default:
            return []
        }
    }

    /// Check if a taskId is a mini-assessment
    static func isMiniAssessment(_ taskId: String) -> Bool {
        let miniAssessmentIds = [
            "CHILDREN_OPTIONS",
            "PET_OPTIONS",
            "FITNESS_OPTIONS",
            "FINANCE_OPTIONS",
            "HEALTH_OPTIONS",
            "INSURANCE_OPTIONS",
            "MEMBERSHIP_OPTIONS",
            "DELIVERY_OPTIONS",
            "STREAMING_OPTIONS",
            "TECH_OPTIONS",
            "PREP_OPTIONS"
        ]
        return miniAssessmentIds.contains(taskId)
    }
}

// MARK: - Preview

#Preview("Children Assessment") {
    MiniAssessmentSheetView(
        taskId: "CHILDREN_OPTIONS",
        taskTitle: "Children Options",
        onComplete: { answers in
            print("Completed with: \(answers)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}

#Preview("Fitness Assessment") {
    MiniAssessmentSheetView(
        taskId: "FITNESS_OPTIONS",
        taskTitle: "Fitness & Memberships",
        onComplete: { answers in
            print("Completed with: \(answers)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}
//
//  MiniAssessmentView.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 2/10/26.
//

