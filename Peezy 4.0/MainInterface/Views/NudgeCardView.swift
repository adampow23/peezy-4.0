import SwiftUI

// MARK: - Nudge Card (Spec 09 Phase 3)
// One-question opt-in card rendered inline on Home — never inside the flow
// cover. Yes converts the nudge into its real task; No dismisses it for good.
// Composition mirrors TaskFlowDecisionCard's icon/question/button stack.

struct NudgeCardView: View {
    let prompt: String
    let answerState: NudgeAnswerState
    let errorMessage: String?
    let onYes: () -> Void
    let onNo: () -> Void
    let onRetry: () -> Void

    private var isInFlight: Bool {
        if case .inFlight = answerState {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            PeezyLucideIcon(
                id: "circle-question-mark",
                size: 56,
                color: PeezyTheme.Colors.deepInk.opacity(0.3)
            )
            .padding(.bottom, 20)

            Text(prompt)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .lineLimit(4)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            VStack(spacing: 12) {
                if case .failed(let choice, _) = answerState {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)

                        Text(errorMessage ?? "We couldn't save your answer. Try again.")
                            .font(.subheadline)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PeezyAssessmentButton("Try again", action: onRetry)
                        .accessibilityLabel(retryAccessibilityLabel(for: choice))
                        .accessibilityIdentifier("nudgeRetryButton")
                } else {
                    PeezyAssessmentButton("Yes", disabled: isInFlight, action: onYes)
                        .accessibilityIdentifier("nudgeYesButton")

                    Button(action: {
                        PeezyHaptics.light()
                        onNo()
                    }) {
                        Text("No")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isInFlight)
                    .opacity(isInFlight ? 0.4 : 1)
                    .accessibilityIdentifier("nudgeNoButton")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .peezyCardChrome()
        .accessibilityIdentifier("nudgeCard")
    }

    private func retryAccessibilityLabel(for choice: NudgeChoice) -> String {
        switch choice {
        case .converted:
            return "Try Yes again"
        case .dismissed:
            return "Try No again"
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Nudge") {
    NudgeCardView(
        prompt: "Sounds like you might need a storage unit — want us to line one up?",
        answerState: .idle,
        errorMessage: nil,
        onYes: { print("Yes") },
        onNo: { print("No") },
        onRetry: { print("Retry") }
    )
}
#endif
