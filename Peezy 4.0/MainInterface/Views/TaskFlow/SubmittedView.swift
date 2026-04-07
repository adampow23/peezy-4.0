import SwiftUI

struct SubmittedView: View {
    let task: PeezyCard
    let onDone: () -> Void

    @State private var checkmarkScale: CGFloat = 0.3
    @State private var checkmarkOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            glassCard {
                VStack(spacing: 0) {
                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        // Note: If you have PeezyTheme.Colors.successGreen, you can swap .green for it!
                        .foregroundStyle(.green)
                        .scaleEffect(checkmarkScale)
                        .opacity(checkmarkOpacity)
                        .padding(.bottom, 24)
                        .accessibilityHidden(true)

                    Text("We're on it!")
                        // UX Fix: Standardized to 34pt Large Title to match the rest of the flow
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .padding(.bottom, 10)
                        .accessibilityAddTraits(.isHeader)

                    Text("We'll notify you when we have more information.")
                        // UX Fix: Standardized to 16pt body text
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24) // UX Fix: Standardized 24pt margin
                        .padding(.bottom, 16)

                    Text(task.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Spacer()

                    PeezyAssessmentButton("Back to Tasks") {
                        onDone()
                    }
                    .padding(.horizontal, 24) // UX Fix: Standardized 24pt margin
                    .padding(.bottom, 24) // UX Fix: Standardized 24pt margin
                }
            }
        }
        .onAppear {
            if reduceMotion {
                checkmarkScale = 1.0
                checkmarkOpacity = 1.0
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.15)) {
                    checkmarkScale = 1.0
                    checkmarkOpacity = 1.0
                }
            }
        }
    }

    // MARK: - Glass Card Container
    
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .foregroundStyle(.regularMaterial)
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.white.opacity(0.15))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    .padding(1)
            }
            // UX Fix: Standardized shadow to Color.black to prevent glowing in Dark Mode
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 15)

            content()
        }
        .frame(width: 340, height: 500)
    }
}

#Preview {
    SubmittedView(task: .previewResearch, onDone: {})
}
