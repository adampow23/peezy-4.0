//
//  TaskFlowTitleCardBleed.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI

// MARK: - Task Flow Title Card (Editorial Bleed)
// Cinematic cover page. Oversized icon bleeds off the top-right edge at 3% opacity.
// Title is bold, left-aligned, anchored to the bottom of the card.
// Tap anywhere to continue.
//
// Same API as Premium Token version — swap by renaming the file.
// Character limit: taskTitle max 30 chars, verb + subject format.

struct TaskFlowTitleCardBleed: View {
    let taskTitle: String
    let icon: String
    let onContinue: () -> Void

    var body: some View {
        ZStack {

            // Editorial bleed icon — massive, faint, bleeding off top-right
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: icon)
                        .font(.system(size: 180, weight: .regular))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.03))
                        .offset(x: 50, y: -30)
                }
                Spacer()
            }

            // Content — title anchored to bottom-left
            VStack(alignment: .leading, spacing: 0) {

                Spacer()

                Text(taskTitle)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                // Passive prompt
                Text("Tap to continue")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                    .padding(.top, 20)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            PeezyHaptics.light()
            onContinue()
        }
        .accessibilityLabel(taskTitle)
        .accessibilityHint("Tap to continue")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Bleed — Book Movers") {
    TaskFlowTitleCardBleed(
        taskTitle: "Book your movers",
        icon: "truck.box.fill",
        onContinue: { print("Continue") }
    )
    .peezyCardChrome()
}

#Preview("Bleed — Forward Mail") {
    TaskFlowTitleCardBleed(
        taskTitle: "Forward your mail",
        icon: "envelope.fill",
        onContinue: { print("Continue") }
    )
    .peezyCardChrome()
}

#Preview("Bleed — Handle Dentist") {
    TaskFlowTitleCardBleed(
        taskTitle: "Handle your dentist",
        icon: "mouth.fill",
        onContinue: { print("Continue") }
    )
    .peezyCardChrome()
}

#Preview("Bleed — Auto Insurance") {
    TaskFlowTitleCardBleed(
        taskTitle: "Update your auto insurance",
        icon: "car.side.fill",
        onContinue: { print("Continue") }
    )
    .peezyCardChrome()
}

#Preview("Bleed — Reserve Elevator") {
    TaskFlowTitleCardBleed(
        taskTitle: "Reserve loading elevator",
        icon: "arrow.up.arrow.down",
        onContinue: { print("Continue") }
    )
    .peezyCardChrome()
}
#endif
