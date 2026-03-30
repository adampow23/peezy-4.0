import SwiftUI

struct ResearchIntroView: View {
    let task: PeezyCard
    let onPeezyHandle: () -> Void
    let onSelfHandle: () -> Void

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            glassCard {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Image(systemName: task.icon)
                        Text(task.headerLabel)
                        Spacer()
                    }
                    .font(.caption).bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                    .padding(.horizontal, 30)
                    .padding(.top, 30)

                    Spacer()

                    VStack(alignment: .leading, spacing: 12) {
                        Text(task.title)
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .lineLimit(3)
                            .minimumScaleFactor(0.6)

                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .frame(width: 50, height: 2)

                        Text(task.subtitle)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)

                        Text("A few quick details to confirm. We'll handle the rest.")
                            .font(.subheadline)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 30)

                    Spacer()

                    VStack(spacing: 12) {
                        PeezyAssessmentButton("Let Peezy Handle This") {
                            onPeezyHandle()
                        }

                        Button("I'll take care of it myself") {
                            onSelfHandle()
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
                .frame(minHeight: 440)
            }
            .padding(.horizontal, 20)
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
    ResearchIntroView(
        task: PeezyCard(
            type: .task,
            title: "Find Internet Providers",
            subtitle: "We'll research the best options available at your new address and send you a summary.",
            taskType: "research"
        ),
        onPeezyHandle: {},
        onSelfHandle: {}
    )
}
