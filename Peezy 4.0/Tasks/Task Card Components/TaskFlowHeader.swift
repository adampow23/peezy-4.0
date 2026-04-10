//
//  TaskFlowHeader.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Task Flow Header
// Shared header for all task flow cards.
// Back arrow left, task title right-aligned, grey color.

struct TaskFlowHeader: View {
    let taskTitle: String
    var showBack: Bool = false
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            if showBack, let onBack {
                Button(action: {
                    PeezyHaptics.light()
                    onBack()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text(taskTitle.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
        }
        .padding(.top, 24)
        .padding(.horizontal, 24)
    }
}
