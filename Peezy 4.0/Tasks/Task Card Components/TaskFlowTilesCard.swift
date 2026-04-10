//
//  TaskFlowTilesCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Task Flow Tiles Card
// Question card with vertical list of tappable options.
// Supports single-select (auto-advance) and multi-select (Continue button).
// Optional skipLabel shows a bottom button that advances without selecting.

enum TileSelectMode {
    case single
    case multi
}

struct TaskFlowTilesCard: View {
    let taskTitle: String
    let question: String
    var subtitle: String? = nil
    let options: [FlowOption]
    var mode: TileSelectMode = .single
    let selectedIds: Set<String>
    var skipLabel: String? = nil
    var showBack: Bool = false
    let onSelect: (String) -> Void
    var onContinue: (() -> Void)? = nil
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

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            // UX Ergonomic Fix: This spacer pushes the tiles down into the Thumb Zone
            Spacer()

            // Option tiles
            VStack(spacing: 10) {
                ForEach(options) { option in
                    flowTile(
                        option: option,
                        isSelected: selectedIds.contains(option.id)
                    ) {
                        onSelect(option.id)
                    }
                }
            }
            .padding(.horizontal, 24)

            // UX Ergonomic Fix: Fixed 24pt gap glues the tiles to the top of the button
            Spacer().frame(height: 24)

            // Bottom button
            if mode == .multi {
                PeezyAssessmentButton(selectedIds.isEmpty ? "None" : "Continue") {
                    onContinue?()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            } else if let skipLabel {
                PeezyAssessmentButton(skipLabel) {
                    onContinue?()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            } else {
                // Hidden spacer to maintain layout consistency
                PeezyAssessmentButton("Continue") {}
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .hidden()
            }
        }
    }

    // MARK: - Tile Row

    private func flowTile(option: FlowOption, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: {
            PeezyHaptics.light()
            onTap()
        }) {
            HStack(spacing: 14) {
                Image(systemName: option.icon)
                    .font(.system(size: 20))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 16, weight: .medium))
                        // UX Typography Fix: Prevents truncation by allowing vertical expansion
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if let subtitle = option.subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                            // UX Typography Fix: Prevents subtitle truncation
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12) // Ensures text never physically overlaps the checkmark

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? PeezyTheme.Colors.deepInk : Color.clear)
            )
            .foregroundStyle(isSelected ? .white : PeezyTheme.Colors.deepInk)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
