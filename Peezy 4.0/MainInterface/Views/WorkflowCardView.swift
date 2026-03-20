//
//  WorkflowCardView.swift
//  Peezy
//
//  Card component for workflow qualifying questions.
//  Fixed-region layout: header, question, tiles, button all have defined zones.
//  Spacers enforce equal spacing between zones.
//  Max 4 options per question (2x2 grid). Split larger questions in workflowQualifying.js.
//

import SwiftUI

struct WorkflowCardView: View {
    let card: WorkflowCard
    let answers: WorkflowAnswers
    let onContinue: () -> Void
    let onSelect: (String, String, Bool) -> Void
    let onComplete: () -> Void

    @State private var offset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Card Background
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

                    // Body
                    switch card.cardType {
                    case .intro:
                        WorkflowIntroContent(
                            intro: card.qualifying.intro,
                            onContinue: {
                                dismissLeft { onContinue() }
                            }
                        )

                    case .question:
                        if let question = card.currentQuestion {
                            WorkflowQuestionContent(
                                question: question,
                                selectedIds: answers.getAnswer(questionId: question.id),
                                onSelect: { optionId, isExclusive in
                                    onSelect(question.id, optionId, isExclusive)
                                    if question.type == .single_select {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            dismissLeft { onContinue() }
                                        }
                                    }
                                },
                                onContinue: {
                                    dismissLeft { onContinue() }
                                }
                            )
                        }

                    case .recap:
                        WorkflowRecapContent(
                            recap: card.qualifying.recapOrDefault,
                            answers: answers,
                            questions: card.qualifying.questions,
                            onComplete: {
                                dismissLeft { onComplete() }
                            }
                        )
                    }
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .offset(offset)
        }
    }

    // MARK: - Dismiss Animation

    private func dismissLeft(then action: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.25)) {
            offset = CGSize(width: -UIScreen.main.bounds.width * 1.5, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            action()
        }
    }
}

// MARK: - Card Header

struct WorkflowCardHeader: View {
    let workflowTitle: String
    let progress: String?

    var body: some View {
        HStack {
            Text(workflowTitle.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.35))
                .tracking(1.5)

            Spacer()

            if let progress = progress {
                Text(progress)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.3))
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }
}

// MARK: - Intro Content

struct WorkflowIntroContent: View {
    let intro: WorkflowIntro
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
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

            PeezyAssessmentButton("Continue") {
                onContinue()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Question Content (FIXED REGION LAYOUT)

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

            // ── QUESTION TEXT (fixed at top) ──
            VStack(alignment: .leading, spacing: 8) {
                Text(question.question)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = question.subtitle {
                    Text(subtitle)
                        .font(PeezyTheme.Typography.callout)
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 8)

            // ── CENTER: tiles between question and button ──
            if !question.options.isEmpty {
                Spacer()

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
                .padding(.horizontal, 24)

                Spacer()
            } else {
                // Context-only card (no options, e.g. insurance info)
                Spacer()
            }

            // ── BUTTON (fixed at bottom) ──
            if question.options.isEmpty {
                // Context-only: Continue button
                PeezyAssessmentButton("Continue") {
                    onContinue()
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            } else if question.type == .multi_select && !selectedIds.isEmpty {
                // Multi-select: Continue after selection
                PeezyAssessmentButton("Continue") {
                    onContinue()
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: selectedIds.isEmpty)
            } else if question.type == .single_select {
                // Single-select: no button needed (auto-advances)
                Color.clear.frame(height: 28)
            } else {
                // Multi-select with no selection yet: reserve space
                Color.clear.frame(height: 28)
            }
        }
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
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Text(recap.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(PeezyTheme.Colors.deepInk)

                // Answer summary
                ForEach(questions, id: \.id) { question in
                    let answerIds = answers.getAnswer(questionId: question.id)
                    if !answerIds.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(question.question)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.4))

                            let labels = question.options
                                .filter { answerIds.contains($0.id) }
                                .map { $0.label }
                                .joined(separator: ", ")

                            Text(labels)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(PeezyTheme.Colors.deepInk)
                        }
                    }
                }

                Text(recap.closing)
                    .font(PeezyTheme.Typography.callout)
                    .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)

            Spacer()

            PeezyAssessmentButton(recap.button) {
                onComplete()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
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
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            onTap()
        }) {
            VStack(spacing: 8) {
                // Icon
                Image(systemName: option.icon)
                    .font(.system(size: 24))
                    .foregroundColor(
                        isSelected
                            ? PeezyTheme.Colors.lightBase
                            : PeezyTheme.Colors.deepInk.opacity(0.12)
                    )
                    .scaleEffect(isSelected ? 1.05 : 1.0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.5), value: isSelected)

                // Label
                Text(option.label)
                    .font(PeezyTheme.Typography.calloutSemibold)
                    .foregroundColor(isSelected ? PeezyTheme.Colors.lightBase : PeezyTheme.Colors.deepInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                // Subtitle
                if let subtitle = option.subtitle {
                    Text(subtitle)
                        .font(PeezyTheme.Typography.caption)
                        .foregroundColor(
                            isSelected
                                ? PeezyTheme.Colors.lightBase.opacity(0.8)
                                : PeezyTheme.Colors.deepInk.opacity(0.5)
                        )
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
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
            .shadow(
                color: isSelected ? PeezyTheme.Colors.deepInk.opacity(0.25) : Color.black.opacity(0.1),
                radius: isPressed ? 4 : (isSelected ? 10 : 12),
                x: 0,
                y: isPressed ? 1 : (isSelected ? 4 : 8)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Preview

#Preview {
    let sampleQualifying = WorkflowQualifying(
        workflowId: "book_movers",
        intro: WorkflowIntro(
            title: "Let's find the right movers",
            subtitle: "A few quick questions so we can match you with companies that fit your move."
        ),
        questions: [
            WorkflowQuestion(
                id: "locally_owned",
                question: "Do you prefer working with a locally owned company?",
                options: [
                    QuestionOption(id: "yes", label: "Yes, prefer local", icon: "building.2"),
                    QuestionOption(id: "no_preference", label: "No preference", icon: "hand.thumbsup")
                ]
            )
        ],
        recap: WorkflowRecap(
            title: "Got it — here's what I'm looking for",
            closing: "I'll match you with movers who fit your specific needs.",
            button: "Find my movers"
        )
    )

    let card = WorkflowCard(
        id: "preview-1",
        workflowId: "book_movers",
        workflowTitle: "Book Movers",
        cardType: .question,
        qualifying: sampleQualifying,
        questionIndex: 0
    )

    ZStack {
        InteractiveBackground()

        WorkflowCardView(
            card: card,
            answers: WorkflowAnswers(workflowId: "book_movers"),
            onContinue: { print("Continue") },
            onSelect: { q, o, e in print("Selected \(o)") },
            onComplete: { print("Complete") }
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
    }
}
