import SwiftUI

struct TransferDecisionView: View {
    let task: PeezyCard
    let isInterstate: Bool
    let onUpdate: () -> Void
    let onCancel: () -> Void
    let onNotSure: () -> Void

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            glassCard {
                VStack(alignment: .leading, spacing: 0) {
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
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .lineLimit(3)
                            .minimumScaleFactor(0.6)

                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .frame(width: 50, height: 2)

                        Text(recommendationText)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 30)

                    Spacer()

                    VStack(spacing: 12) {
                        // Primary recommended action
                        PeezyAssessmentButton(primaryButtonLabel) {
                            isInterstate ? onCancel() : onUpdate()
                        }

                        // Secondary alternative
                        Button(secondaryButtonLabel) {
                            isInterstate ? onUpdate() : onCancel()
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.55))

                        // Not sure option
                        Button("Not sure? Let Peezy figure it out.") {
                            onNotSure()
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.35))
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
                .frame(minHeight: 440)
            }
            .padding(.horizontal, 20)
        }
    }

    private var recommendationText: String {
        isInterstate
            ? "Moving to a new state — you may want to cancel and set up fresh."
            : "You're staying local — updating your address is probably all you need."
    }

    private var primaryButtonLabel: String {
        isInterstate ? "Cancel & Set Up New" : "Update My Address"
    }

    private var secondaryButtonLabel: String {
        isInterstate ? "Just update my address" : "Actually, I want to cancel and start fresh"
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

#Preview("Local Move") {
    TransferDecisionView(
        task: PeezyCard(
            type: .task,
            title: "Transfer or Cancel Gym Membership",
            subtitle: "Decide what to do with your current gym contract.",
            taskType: "transfer_cancel"
        ),
        isInterstate: false,
        onUpdate: {},
        onCancel: {},
        onNotSure: {}
    )
}

#Preview("Interstate Move") {
    TransferDecisionView(
        task: PeezyCard(
            type: .task,
            title: "Transfer or Cancel Gym Membership",
            subtitle: "Decide what to do with your current gym contract.",
            taskType: "transfer_cancel"
        ),
        isInterstate: true,
        onUpdate: {},
        onCancel: {},
        onNotSure: {}
    )
}
