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

                        Text("How would you like to handle this?")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.65))
                    }
                    .padding(.horizontal, 30)

                    Spacer()

                    VStack(spacing: 12) {
                        PeezyAssessmentButton("Have Peezy handle it") {
                            onPeezyHandle()
                        }

                        Button("I'll take care of it") {
                            onSelfHandle()
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

#Preview {
    TaskChoiceView(task: .previewResearch, onPeezyHandle: {}, onSelfHandle: {})
}
