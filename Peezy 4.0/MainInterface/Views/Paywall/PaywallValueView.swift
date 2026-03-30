import SwiftUI
import StoreKit

// MARK: - PaywallValueView
//
// Shown once after assessment completion, before entering the main app.
// Presents the value proposition and offers a 3-day free trial.
// onStartTrial: triggers purchase of the annual plan (with trial)
// onSkip: lets user enter the app without subscribing

struct PaywallValueView: View {

    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    let onStartTrial: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            glassCard {
                VStack(spacing: 0) {
                    // Header label
                    Text("YOUR PLAN IS READY")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .tracking(1.5)
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 30)
                        .padding(.top, 30)

                    Spacer()

                    // Value copy
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Can you really put a price on peace of mind?")
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("We did. And then we made it free for 3 days so you don't have to take our word for it.")
                            .font(.system(size: 16))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)

                        Text("25+ hours saved. Zero stress. And less than a dollar a week.")
                            .font(.system(size: 15))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 30)

                    Spacer()

                    // CTA
                    VStack(spacing: 14) {
                        PeezyAssessmentButton("Try it free", action: onStartTrial)
                            .padding(.horizontal, 30)

                        Text("3-day free trial · Then $49.99/year")
                            .font(.caption)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))

                        Button(action: onSkip) {
                            Text("Skip")
                                .font(.caption)
                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 30)
                }
            }
        }
    }

    // MARK: - Glass Card

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
        .frame(width: 340, height: 500)
    }
}

// MARK: - Preview

#Preview {
    PaywallValueView(
        onStartTrial: { print("Start trial") },
        onSkip: { print("Skipped") }
    )
    .environmentObject(SubscriptionManager.shared)
}
