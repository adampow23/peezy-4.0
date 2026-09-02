//
//  InventoryScanCoachingView.swift
//  Peezy 4.0
//
//  FaceTime-style walkthrough guidance shown before a user's first scan.
//

import SwiftUI

struct InventoryScanCoachingView: View {
    let onStart: () -> Void

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: "video.bubble.left.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .frame(width: 72, height: 72)
                        .background(PeezyTheme.Gradients.infoBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Scan it like you'd show a friend")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)

                        Text("Imagine you're on FaceTime showing a friend everything you own. You wouldn't spin in a circle — you'd walk up to the bookshelf, angle around the desk, open the closet. Do that. Peezy sees what you show it.")
                            .font(.body)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 12) {
                        tip(
                            "Walk close to furniture — don't pan from the doorway",
                            systemImage: "figure.walk.motion"
                        )
                        tip(
                            "Show a second angle around big pieces",
                            systemImage: "arrow.triangle.2.circlepath.camera"
                        )
                        tip(
                            "Open closets and show what's inside",
                            systemImage: "door.left.hand.open"
                        )
                        tip(
                            "Talk while you scan — what's staying, what's full, what's not yours.",
                            systemImage: "mic.fill"
                        )
                    }

                    Label {
                        Text("Your video never leaves your phone. Peezy uploads still frames only, and deletes them after your inventory is confirmed — keeping just the snapshots that show where your items are.")
                            .font(.footnote)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                    }
                    .accessibilityIdentifier("inventory.coaching.privacy")

                    PeezyAssessmentButton("Start scanning", action: onStart)
                        .accessibilityIdentifier("inventory.coaching.start")
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
                .padding(.top, 32)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("inventory.scan.coaching")
    }

    private func tip(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(width: 32, height: 32)
                .background(PeezyTheme.Colors.infoBlue.opacity(0.45))
                .clipShape(Circle())
                .accessibilityHidden(true)

            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: PeezyTheme.Layout.cornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: PeezyTheme.Layout.cornerRadius,
                style: .continuous
            )
            .stroke(PeezyTheme.Colors.deepInk.opacity(0.08), lineWidth: 1)
        }
    }
}

#if DEBUG
#Preview("Scan coaching") {
    InventoryScanCoachingView(onStart: {})
}
#endif
