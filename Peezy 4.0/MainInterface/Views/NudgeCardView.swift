import SwiftUI

// MARK: - Nudge Card (Spec 09 Phase 3)
// One-question opt-in card rendered inline on Home — never inside the flow
// cover. Yes converts the nudge into its real task; No dismisses it for good.
// Composition mirrors TaskFlowDecisionCard's icon/question/button stack.

struct NudgeCardView: View {
    let prompt: String
    let onYes: () -> Void
    let onNo: () -> Void

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
                PeezyAssessmentButton("Yes") {
                    onYes()
                }
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
                .accessibilityIdentifier("nudgeNoButton")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .peezyCardChrome()
        .accessibilityIdentifier("nudgeCard")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Nudge") {
    NudgeCardView(
        prompt: "Sounds like you might need a storage unit — want us to line one up?",
        onYes: { print("Yes") },
        onNo: { print("No") }
    )
}
#endif
