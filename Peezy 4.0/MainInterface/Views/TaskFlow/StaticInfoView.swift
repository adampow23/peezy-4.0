import SwiftUI

struct StaticInfoView: View {
    let task: PeezyCard
    let onComplete: () -> Void
    let onLater: () -> Void

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            glassCard {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(task.title)
                            .font(.system(size: 44, weight: .heavy))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)

                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .frame(width: 50, height: 2)
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 30)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            sectionLabel("Why this matters")
                            Text(task.subtitle)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 30)

                            sectionLabel("What to do")
                            Text(task.briefingMessage ?? task.subtitle)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 30)

                            sectionLabel("Tips")
                            Text(task.briefingMessage ?? task.subtitle)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                                .padding(.horizontal, 30)
                                .padding(.bottom, 8)
                        }
                    }

                    VStack(spacing: 12) {
                        PeezyAssessmentButton("Already done") {
                            onComplete()
                        }

                        Button("I'll take care of it") {
                            onLater()
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.45))
            .tracking(1)
            .textCase(.uppercase)
            .padding(.horizontal, 30)
            .padding(.top, 20)
            .padding(.bottom, 6)
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
        .frame(width: 340, height: 500)
    }
}

#Preview {
    StaticInfoView(task: .previewProvideInfo, onComplete: {}, onLater: {})
}
