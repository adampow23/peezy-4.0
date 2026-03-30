import SwiftUI

struct StaticInfoView: View {
    let task: PeezyCard
    let onComplete: () -> Void
    let onLater: () -> Void

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            ScrollView {
                glassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(task.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .padding(.horizontal, 30)
                            .padding(.top, 30)

                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .frame(width: 50, height: 2)
                            .padding(.horizontal, 30)
                            .padding(.top, 12)

                        sectionLabel("Why this matters")
                        Text(task.subtitle)
                            .font(.body)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 30)

                        sectionLabel("How to do it")
                        Text(task.subtitle)
                            .font(.body)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 30)

                        sectionLabel("Tips")
                        Text("Tips will appear here")
                            .font(.body)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .padding(.horizontal, 30)

                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.caption)
                            Text("~1 hour")
                                .font(.caption)
                        }
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .padding(.horizontal, 30)
                        .padding(.top, 20)

                        VStack(spacing: 12) {
                            PeezyAssessmentButton("I've Handled This") {
                                onComplete()
                            }

                            Button("I'll Do It Later") {
                                onLater()
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 24)
                        .padding(.bottom, 30)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 40)
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
        .frame(width: 340)
    }
}

#Preview {
    StaticInfoView(
        task: PeezyCard(
            type: .task,
            title: "Set Up Utilities",
            subtitle: "Contact your utility providers to transfer or set up service at your new address before move day.",
            taskType: "provide_info"
        ),
        onComplete: {},
        onLater: {}
    )
}
