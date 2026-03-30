import SwiftUI

struct SubmittedView: View {
    let task: PeezyCard
    let onDone: () -> Void

    @State private var checkmarkScale: CGFloat = 0.3
    @State private var checkmarkOpacity: Double = 0

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            glassCard {
                VStack(spacing: 0) {
                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.green)
                        .scaleEffect(checkmarkScale)
                        .opacity(checkmarkOpacity)
                        .padding(.bottom, 24)

                    Text("We're on it!")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .padding(.bottom, 10)

                    Text("We'll notify you when we have more information.")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.bottom, 16)

                    Text(task.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)

                    Spacer()

                    PeezyAssessmentButton("Back to Tasks") {
                        onDone()
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
                .frame(minHeight: 420)
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.15)) {
                checkmarkScale = 1.0
                checkmarkOpacity = 1.0
            }
        }
    }

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
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    .padding(1)
            }
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 15)

            content()
        }
        .frame(width: 340)
    }
}

#Preview {
    SubmittedView(
        task: PeezyCard(
            type: .task,
            title: "Research Internet Providers",
            subtitle: "Find the best internet plan at your new address.",
            taskType: "research"
        ),
        onDone: {}
    )
}
