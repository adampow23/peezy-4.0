//
//  WorkflowCardView.swift
//  Peezy
//
//  Card component for workflow qualifying questions
//  Three modes: intro, question, recap
//

import SwiftUI

struct WorkflowCardView: View {
    let card: WorkflowCard
    let answers: WorkflowAnswers
    let onContinue: () -> Void
    let onSelect: (String, String, Bool) -> Void  // questionId, optionId, isExclusive
    let onComplete: () -> Void

    @State private var offset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Card Background — glass matching assessment theme
                ZStack {
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(.regularMaterial)

                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 15)

                // Content
                VStack(spacing: 0) {
                    // Header
                    WorkflowCardHeader(
                        workflowTitle: card.workflowTitle,
                        progress: card.progressText
                    )

                    // Body - changes based on card type
                    switch card.cardType {
                    case .intro:
                        WorkflowIntroContent(
                            intro: card.qualifying.intro,
                            onContinue: {
                                dismissLeft {
                                    onContinue()
                                }
                            }
                        )

                    case .question:
                        if let question = card.currentQuestion {
                            WorkflowQuestionContent(
                                question: question,
                                selectedIds: answers.getAnswer(questionId: question.id),
                                onSelect: { optionId, isExclusive in
                                    onSelect(question.id, optionId, isExclusive)

                                    // For single select, auto-advance after brief delay
                                    if question.type == .single_select {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            dismissLeft {
                                                onContinue()
                                            }
                                        }
                                    }
                                },
                                onContinue: {
                                    // For multi-select, need explicit continue
                                    dismissLeft {
                                        onContinue()
                                    }
                                }
                            )
                        }

                    case .recap:
                        WorkflowRecapContent(
                            recap: card.qualifying.recapOrDefault,
                            answers: answers,
                            questions: card.qualifying.questions,
                            onComplete: {
                                dismissLeft {
                                    onComplete()
                                }
                            }
                        )
                    }
                }
            }
            .offset(x: offset.width, y: 0)
        }
        // Workflow cards are slightly taller than task cards (520 vs 500)
        // to accommodate progress indicator and more content
        .frame(width: 340, height: 520)
    }

    // MARK: - Dismiss Animation

    private func dismissLeft(completion: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.25)) {
            offset.width = -400
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            completion()
        }
    }
}

// MARK: - Header

struct WorkflowCardHeader: View {
    let workflowTitle: String
    let progress: String?

    var body: some View {
        HStack {
            // Workflow name
            HStack(spacing: 6) {
                Circle()
                    .fill(PeezyTheme.Colors.infoBlue)
                    .frame(width: 8, height: 8)

                Text(workflowTitle)
                    .font(PeezyTheme.Typography.captionMedium)
                    .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            Spacer()

            // Progress indicator
            if let progress = progress {
                Text(progress)
                    .font(PeezyTheme.Typography.captionMedium)
                    .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(PeezyTheme.Colors.deepInk.opacity(0.08))
                    )
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
    }
}

// MARK: - Intro Content

struct WorkflowIntroContent: View {
    let intro: WorkflowIntro
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Text(intro.title)
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(intro.subtitle)
                    .font(.title3)
                    .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)

            Spacer()

            // Continue button
            PeezyAssessmentButton("Continue") {
                onContinue()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Question Content

struct WorkflowQuestionContent: View {
    let question: WorkflowQuestion
    let selectedIds: [String]
    let onSelect: (String, Bool) -> Void
    let onContinue: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Question text
            VStack(alignment: .leading, spacing: 8) {
                Text(question.question)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = question.subtitle {
                    Text(subtitle)
                        .font(PeezyTheme.Typography.callout)
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 20)

            Spacer()

            // Options grid
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(question.options) { option in
                    WorkflowOptionTile(
                        option: option,
                        isSelected: selectedIds.contains(option.id),
                        onTap: {
                            onSelect(option.id, option.exclusive ?? false)
                        }
                    )
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            // For multi-select, show continue button
            if question.type == .multi_select && !selectedIds.isEmpty {
                PeezyAssessmentButton("Continue") {
                    onContinue()
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                // Spacer for layout consistency
                Color.clear.frame(height: 84)
            }
        }
        .animation(.spring(response: 0.3), value: selectedIds)
    }
}

// MARK: - Option Tile

struct WorkflowOptionTile: View {
    let option: QuestionOption
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            PeezyHaptics.medium()
            onTap()
        }) {
            VStack(spacing: 10) {
                // Icon
                Image(systemName: option.icon)
                    .font(.system(size: 28))
                    .foregroundColor(isSelected ? PeezyTheme.Colors.lightBase : PeezyTheme.Colors.deepInk)

                // Label
                Text(option.label)
                    .font(PeezyTheme.Typography.calloutSemibold)
                    .foregroundColor(isSelected ? PeezyTheme.Colors.lightBase : PeezyTheme.Colors.deepInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                // Subtitle if present
                if let subtitle = option.subtitle {
                    Text(subtitle)
                        .font(PeezyTheme.Typography.caption)
                        .foregroundColor(isSelected ? PeezyTheme.Colors.lightBase.opacity(0.8) : PeezyTheme.Colors.deepInk.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusLarge, style: .continuous)
                            .fill(PeezyTheme.Colors.deepInk)
                    } else {
                        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusLarge, style: .continuous)
                            .fill(.regularMaterial)
                        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusLarge, style: .continuous)
                            .fill(Color.white.opacity(0.15))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusLarge, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.black.opacity(0.05), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        PeezyHaptics.light()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Recap Content

struct WorkflowRecapContent: View {
    let recap: WorkflowRecap
    let answers: WorkflowAnswers
    let questions: [WorkflowQuestion]
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text(recap.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(PeezyTheme.Colors.deepInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 20)

            // Answer summary
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(questions) { question in
                        if let selectedIds = answers.answers[question.id], !selectedIds.isEmpty {
                            RecapAnswerRow(
                                question: question,
                                selectedIds: selectedIds
                            )
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
            }
            .frame(maxHeight: 200)

            Spacer()

            // Closing message
            Text(recap.closing)
                .font(PeezyTheme.Typography.callout)
                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            // Complete button
            PeezyAssessmentButton(recap.button) {
                onComplete()
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Recap Answer Row

struct RecapAnswerRow: View {
    let question: WorkflowQuestion
    let selectedIds: [String]

    var selectedLabels: String {
        let labels = question.options
            .filter { selectedIds.contains($0.id) }
            .map { $0.label }
        return labels.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(PeezyTheme.Colors.successGreen)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedLabels)
                    .font(PeezyTheme.Typography.calloutMedium)
                    .foregroundColor(PeezyTheme.Colors.deepInk)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                .fill(PeezyTheme.Colors.successGreen.opacity(0.08))
        )
    }
}

// MARK: - Preview

#Preview {
    let sampleQualifying = WorkflowQualifying(
        workflowId: "book_movers",
        intro: WorkflowIntro(
            title: "Let's find you the right movers",
            subtitle: "A few quick questions to match you with companies that fit your move."
        ),
        questions: [],
        recap: WorkflowRecap(
            title: "Got it. Here's what I heard:",
            closing: "I'm reaching out to your top 3 matches now.",
            button: "Sounds Good"
        )
    )

    let card = WorkflowCard(
        id: "preview-1",
        workflowId: "book_movers",
        workflowTitle: "Book Movers",
        cardType: .intro,
        qualifying: sampleQualifying
    )

    ZStack {
        Color.black.opacity(0.9).ignoresSafeArea()

        WorkflowCardView(
            card: card,
            answers: WorkflowAnswers(workflowId: "book_movers"),
            onContinue: { print("Continue") },
            onSelect: { q, o, e in print("Selected \(o)") },
            onComplete: { print("Complete") }
        )
    }
}
