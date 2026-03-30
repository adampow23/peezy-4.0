import SwiftUI

struct SelfHandleView: View {
    let task: PeezyCard
    let onSelectDate: (Date) -> Void
    let onAlreadyDone: () -> Void

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            glassCard {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No problem — you've got this!")
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)

                        Text(task.title)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 30)

                    Rectangle()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 50, height: 2)
                        .padding(.horizontal, 30)
                        .padding(.top, 16)

                    Text("When should we check back?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .tracking(0.5)
                        .padding(.horizontal, 30)
                        .padding(.top, 20)
                        .padding(.bottom, 12)

                    VStack(spacing: 10) {
                        checkBackButton("Tomorrow", date: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
                        checkBackButton("This Weekend", date: nextWeekend())
                        checkBackButton("Next Week", date: Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date())
                    }
                    .padding(.horizontal, 30)

                    Button("Actually, I already did this") {
                        onAlreadyDone()
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func checkBackButton(_ label: String, date: Date) -> some View {
        Button {
            onSelectDate(date)
        } label: {
            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                            .foregroundStyle(.regularMaterial)
                        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.2))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func nextWeekend() -> Date {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        // weekday: 1=Sun, 7=Sat
        let daysUntilSaturday = weekday == 7 ? 7 : (7 - weekday)
        return calendar.date(byAdding: .day, value: daysUntilSaturday, to: today) ?? today
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
    SelfHandleView(
        task: PeezyCard(
            type: .task,
            title: "Research Moving Companies",
            subtitle: "Get quotes from at least 3 licensed movers.",
            taskType: "research"
        ),
        onSelectDate: { _ in },
        onAlreadyDone: {}
    )
}
