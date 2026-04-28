import SwiftUI

struct TasksTabBar: View {
    @Binding var selectedTab: TaskTab
    let counts: [TaskTab: Int]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TaskTab.allCases, id: \.self) { tab in
                Button {
                    PeezyHaptics.light()
                    withAnimation(PeezyTheme.Animation.easeOut) {
                        selectedTab = tab
                    }
                } label: {
                    tabLabel(tab: tab, count: counts[tab] ?? 0)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("timeline_tab_\(tab.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Divider().background(PeezyTheme.Colors.deepInk.opacity(0.06))
        }
    }

    @ViewBuilder
    private func tabLabel(tab: TaskTab, count: Int) -> some View {
        let isSelected = selectedTab == tab
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Text(tab.rawValue)
                    .font(isSelected ? PeezyTheme.Typography.footnoteMedium : PeezyTheme.Typography.footnote)
                    .foregroundStyle(isSelected ? PeezyTheme.Colors.deepInk : PeezyTheme.Colors.deepInk.opacity(0.4))

                if count > 0 {
                    Text("\(count)")
                        .font(PeezyTheme.Typography.captionMedium)
                        .foregroundStyle(isSelected ? PeezyTheme.Colors.deepInk : PeezyTheme.Colors.deepInk.opacity(0.4))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(PeezyTheme.Colors.deepInk.opacity(isSelected ? 0.1 : 0.05))
                        )
                }
            }

            Rectangle()
                .fill(isSelected ? PeezyTheme.Colors.deepInk : Color.clear)
                .frame(height: 2)
                .clipShape(.rect(cornerRadius: 1))
        }
        .frame(maxWidth: .infinity)
    }
}
