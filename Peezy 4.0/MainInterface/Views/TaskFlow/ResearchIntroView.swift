import SwiftUI

struct TaskEntryView: View {
    let task: PeezyCard
    let onStart: () -> Void
    let onSkip: () -> Void

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
                            .font(.system(size: 44, weight: .heavy))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)

                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .frame(width: 50, height: 2)

                        Text(task.subtitle)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 30)

                    Spacer()

                    VStack(spacing: 12) {
                        PeezyAssessmentButton("Start task") {
                            onStart()
                        }

                        Button("Skip for now") {
                            onSkip()
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
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
        .frame(width: 340, height: 500)
    }
}

#Preview("Research Entry") {
    TaskEntryView(task: .previewResearch, onStart: {}, onSkip: {})
}

#Preview("Survey Entry") {
    TaskEntryView(task: .previewSurvey, onStart: {}, onSkip: {})
}

#Preview("Provide Info Entry") {
    TaskEntryView(task: .previewProvideInfo, onStart: {}, onSkip: {})
}
