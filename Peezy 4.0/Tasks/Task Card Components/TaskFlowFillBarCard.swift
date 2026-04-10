//
//  TasksFlowFillBarCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Task Flow Fill Bar Card
// Tile options rendered as horizontal fill bars.
// Fill percentage determines how much of the bar is filled with ink color.
// Text positioned outside fill for low percentages, inside (white) for high.

struct TaskFlowFillBarCard: View {
    let taskTitle: String
    let question: String
    let options: [FlowOption]  // Must have fillPercent set on each
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

            // Fill bar tiles
            VStack(spacing: 10) {
                ForEach(options) { option in
                    fillBar(
                        option: option,
                        isSelected: selectedId == option.id
                    ) {
                        onSelect(option.id)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            // Hidden button for layout consistency
            PeezyAssessmentButton("Continue") {}
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .hidden()
        }
    }

    // MARK: - Fill Bar Tile

    private func fillBar(option: FlowOption, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        let percent = option.fillPercent ?? 0
        let textInside = percent >= 0.75

        return Button(action: {
            PeezyHaptics.light()
            onTap()
        }) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.04))

                    // Fill bar
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(PeezyTheme.Colors.deepInk)
                        .frame(width: geo.size.width * percent)

                    // Label
                    HStack(spacing: 0) {
                        if textInside {
                            Spacer()
                                .frame(width: max(0, geo.size.width * percent - labelWidth(option.label) - 16))
                            Text(option.label)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.leading, 4)
                        } else {
                            Spacer()
                                .frame(width: geo.size.width * percent + 12)
                            Text(option.label)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(PeezyTheme.Colors.deepInk)
                        }
                        Spacer()
                    }

                    // Selected checkmark
                    if isSelected {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(textInside ? .white : PeezyTheme.Colors.deepInk)
                                .padding(.trailing, 16)
                        }
                    }
                }
            }
            .frame(height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? PeezyTheme.Colors.deepInk : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
    }

    private func labelWidth(_ text: String) -> CGFloat {
        CGFloat(text.count) * 11
    }
}
