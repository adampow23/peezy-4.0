import SwiftUI

struct TransferDecisionView: View {
    let task: PeezyCard
    let isInterstate: Bool
    let onUpdate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            glassCard {
                VStack(alignment: .leading, spacing: 0) {
                    
                    // MARK: - Header Label
                    HStack {
                        Image(systemName: task.icon)
                            .accessibilityHidden(true)
                        Text(task.headerLabel)
                        Spacer()
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .textCase(.uppercase)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                    Spacer()

                    // MARK: - Main Content
                    VStack(alignment: .leading, spacing: 12) {
                        Text(task.title)
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)

                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 50, height: 2)

                        Text(recommendationText)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // MARK: - 50/50 Decision Buttons
                    VStack(spacing: 12) {
                        PeezyAssessmentButton("Update with current provider") {
                            onUpdate()
                        }

                        Button(action: onCancel) {
                            Text("Cancel and find a new one")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(PeezyTheme.Colors.deepInk)
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .background {
                            ZStack {
                                // UX Fix: Swapped to Capsule() to perfectly match the primary button shape
                                Capsule()
                                    .foregroundStyle(.regularMaterial)
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                            }
                            .overlay {
                                Capsule()
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var recommendationText: String {
        isInterstate
            ? "Moving to a new state — you may want to cancel and set up fresh."
            : "You're staying local — updating your address is probably all you need."
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
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 15)

            content()
        }
        .frame(width: 340, height: 500)
    }
}

#Preview("Local Move") {
    TransferDecisionView(task: .previewTransfer, isInterstate: false, onUpdate: {}, onCancel: {})
}

#Preview("Interstate Move") {
    TransferDecisionView(task: .previewTransfer, isInterstate: true, onUpdate: {}, onCancel: {})
}
