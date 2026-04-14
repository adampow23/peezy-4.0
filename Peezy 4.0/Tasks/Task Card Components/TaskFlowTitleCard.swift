import SwiftUI

// MARK: - Task Flow Title Card
// Cover page for every task flow. Clean, high-contrast token left-aligned.
// Uses a controlled typographic rag (forcing a newline before the 3rd word)
// to create a beautiful, balanced text block that fills the negative space.
//
// Character limit: taskTitle max 30 chars, first-person verb + subject.

struct TaskFlowTitleCard: View {
    let taskTitle: String
    let icon: String
    var primaryLabel: String = "Continue"
    let onContinue: () -> Void

    // MARK: - Controlled Rag Logic
    private var formattedTitle: String {
        let words = taskTitle.split(separator: " ")
        
        // If it's a super short title (2 words or less), leave it alone
        guard words.count >= 3 else { return taskTitle }
        
        let firstTwoWords = words.prefix(2).joined(separator: " ")
        let remainingWords = words.dropFirst(2).joined(separator: " ")
        
        return "\(firstTwoWords)\n\(remainingWords)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top spacer pushes content down just enough, but less than the bottom
            // spacer to hit the "optical center" (slightly above true center).
            Spacer()

            // Tightened spacing from 24 to 20 for better Gestalt proximity
            VStack(alignment: .leading, spacing: 20) {
                
                // Modern, soft-tinted anchor token
                ZStack {
                    Circle()
                        // Using a tinted background instead of solid heavy color
                        // makes the UI feel lighter and more elevated.
                        .fill(PeezyTheme.Colors.deepInk.opacity(0.08))
                    
                    Image(systemName: icon)
                        // Scaled down slightly and matched to the deep ink color
                        // for a refined, monochromatic look.
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                }
                .frame(width: 64, height: 64)

                // The formatted title
                Text(formattedTitle)
                    // Upgraded from .largeTitle to a specific heavy display size
                    // for maximum typographic impact and editorial feel.
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    // Tighter line spacing (-2) looks much better on oversized display text
                    .lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Double spacer weight at the bottom pushes the title block up into
            // the upper-middle third of the screen, creating elegant negative space.
            Spacer()
            Spacer()

            // Continue button (Untouched)
            PeezyAssessmentButton(primaryLabel) {
                onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(taskTitle)
        .accessibilityHint("Tap continue to start")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Title — Book Movers") {
    // Becomes "Find my\nmovers"
    TaskFlowTitleCard(
        taskTitle: "Find my movers",
        icon: "truck.box.fill",
        onContinue: { print("Continue") }
    )
    .peezyCardChrome()
}

#Preview("Title — Forward Mail") {
    // Becomes "Forward your\nmail"
    TaskFlowTitleCard(
        taskTitle: "Forward your mail",
        icon: "envelope.fill",
        onContinue: { print("Continue") }
    )
    .peezyCardChrome()
}

#Preview("Title — Auto Insurance") {
    // Becomes "Update your\nauto insurance"
    TaskFlowTitleCard(
        taskTitle: "Update your auto insurance",
        icon: "car.fill",
        onContinue: { print("Continue") }
    )
    .peezyCardChrome()
}
#endif
