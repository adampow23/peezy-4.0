//
//  TasksFlowCompactTilesCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Task Flow Compact Tiles Card
// Side-by-side tile layout for binary questions (yes/no, thumbs up/down).
// Tiles are pushed toward bottom for aesthetic spacing.
// Auto-advances on selection (single-select only).

struct TaskFlowCompactTilesCard: View {
    let taskTitle: String
    let question: String
    let options: [FlowOption]
    let selectedId: String?
    var showBack: Bool = false
    let onSelect: (String) -> Void
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: taskTitle, showBack: showBack, onBack: onBack)

            Spacer()

            // Question text
            VStack(alignment: .leading, spacing: 15) {
                Text(question)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
            Spacer()

            // Side-by-side tiles
            HStack(spacing: 12) {
                ForEach(options) { option in
                    compactTile(
                        option: option,
                        isSelected: selectedId == option.id
                    ) {
                        onSelect(option.id)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Compact Tile

    private func compactTile(option: FlowOption, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: {
            PeezyHaptics.light()
            onTap()
        }) {
            VStack(spacing: 10) {
                Image(systemName: option.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(isSelected ? .white : PeezyTheme.Colors.deepInk.opacity(0.4))

                Text(option.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : PeezyTheme.Colors.deepInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? PeezyTheme.Colors.deepInk : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.primary.opacity(0.07), lineWidth: 1)
            )
            .shadow(
                color: isSelected ? PeezyTheme.Colors.deepInk.opacity(0.2) : Color.black.opacity(0.05),
                radius: isSelected ? 8 : 4,
                x: 0,
                y: isSelected ? 4 : 2
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
    }
}
