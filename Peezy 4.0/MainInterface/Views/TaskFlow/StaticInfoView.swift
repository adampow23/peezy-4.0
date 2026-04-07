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
                    
                    // MARK: - Header Label (Unified with TaskChoiceView)
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
                    
                    // MARK: - Title
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
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16) // UX Fix: Tightened to sit cleanly under the new header
                    .padding(.bottom, 20)

                    // MARK: - Scrollable Content
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            
                            if let why = task.whyNeeded, !why.isEmpty {
                                sectionLabel("Why this matters")
                                Text(why)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 24)
                            }

                            sectionLabel("What to do")
                            Text(task.subtitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 24)

                            if let tips = task.tips, !tips.isEmpty {
                                sectionLabel("Tips")
                                Text(tips)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 8)
                            }
                        }
                    }

                    // MARK: - Footer Actions
                    VStack(spacing: 12) {
                        PeezyAssessmentButton("Already done") {
                            onComplete()
                        }

                        Button("I'll take care of it") {
                            onLater()
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(1)
            .textCase(.uppercase)
            .padding(.horizontal, 24)
            .padding(.top, 16) // UX Fix: Reduced slightly so scroll content feels cohesive
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
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
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    .padding(1)
            }
            // UX Fix: Standardized shadow to match ConfirmDetailsView & TaskChoiceView
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 15)

            content()
        }
        .frame(width: 340, height: 500)
    }
}

#Preview {
    // Note: Assuming .previewProvideInfo exists in your project extensions
    StaticInfoView(task: .previewProvideInfo, onComplete: {}, onLater: {})
}
