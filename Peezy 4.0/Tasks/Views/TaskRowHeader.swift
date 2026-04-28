import SwiftUI

struct TaskRowHeader: View {
    let task: PeezyCard
    let isExpanded: Bool
    let section: TaskSection
    let onTap: () -> Void

    private var isCompleted: Bool { section == .done }

    private var isSnoozed: Bool {
        TaskGrouping.isSnoozedEffective(task)
    }

    private var isMatchingInProgress: Bool {
        task.status == .matchingInProgress
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            iconCircle

            VStack(alignment: .leading, spacing: 8) {
                titleRow
                subtitleText
                badgeRow
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
        .onTapGesture {
            PeezyHaptics.light()
            onTap()
        }
    }

    private var iconCircle: some View {
        ZStack {
            Circle()
                .fill(PeezyTheme.Colors.deepInk.opacity(0.05))
                .frame(width: 48, height: 48)
            Image(systemName: TaskCategoryIcon.name(for: task.taskCategory))
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(isCompleted ? PeezyTheme.Colors.deepInk.opacity(0.3) : PeezyTheme.Colors.deepInk.opacity(0.7))
        }
        .padding(.top, 4)
    }

    private var titleRow: some View {
        HStack(alignment: .top) {
            Text(task.title)
                .font(PeezyTheme.Typography.bodyMedium)
                .foregroundStyle(isCompleted ? PeezyTheme.Colors.deepInk.opacity(0.4) : PeezyTheme.Colors.deepInk)
                .strikethrough(isCompleted, color: PeezyTheme.Colors.deepInk.opacity(0.3))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Image(systemName: "chevron.down")
                .font(PeezyTheme.Typography.captionMedium)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                .rotationEffect(.degrees(isExpanded ? -180 : 0))
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isExpanded)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var subtitleText: some View {
        if !task.subtitle.isEmpty && !isCompleted {
            Text(task.subtitle)
                .font(PeezyTheme.Typography.callout)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : 2)
        }
    }

    @ViewBuilder
    private var badgeRow: some View {
        switch section {
        case .userInProgress:
            badge(text: "You're on it", color: PeezyTheme.Colors.infoBlue)
        case .peezyOnIt:
            badge(text: isMatchingInProgress ? "Matching vendors" : "Peezy is on it", color: PeezyTheme.Colors.accentBlue)
        case .todo where isSnoozed:
            badge(text: "Snoozed", color: PeezyTheme.Colors.warningOrange)
        default:
            EmptyView()
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(PeezyTheme.Typography.captionMedium)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
            .padding(.top, 4)
    }

}
