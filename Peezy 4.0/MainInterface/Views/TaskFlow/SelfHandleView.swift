import SwiftUI

struct TaskChoiceView: View {
    let task: PeezyCard
    let onPeezyHandle: () -> Void
    let onSelfHandle: () -> Void

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
                    // UX Fix: Matched the Section Label styling from StaticInfoView for systemic consistency
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .textCase(.uppercase)
                    .padding(.horizontal, 24) // UX Fix: Standardized to 24pt margins
                    .padding(.top, 24)

                    Spacer()

                    // MARK: - Main Content
                    VStack(alignment: .leading, spacing: 12) {
                        Text(task.title)
                            // UX Fix: Standardized to 34pt Large Title to match other cards
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)

                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 50, height: 2)

                        Text("How would you like to handle this?")
                            // UX Fix: Standardized to 16pt body text
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // MARK: - Actions
                    VStack(spacing: 12) {
                        PeezyAssessmentButton("Have Peezy handle it") {
                            onPeezyHandle()
                        }

                        Button("I'll take care of it") {
                            onSelfHandle()
                        }
                        // UX Fix: Standardized to 16pt semibold to match StaticInfoView exactly
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
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
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 15) // Standardized shadow color

            content()
        }
        .frame(width: 340, height: 500)
    }
}

#Preview {
    TaskChoiceView(task: .previewResearch, onPeezyHandle: {}, onSelfHandle: {})
}
