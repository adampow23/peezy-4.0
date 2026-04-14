//
//  InventoryProcessingView.swift
//  Peezy 4.0
//
//  Theatrical loading screen shown during frame upload and AI processing.
//  Rotating viewfinder icon with pulsing brand glow. Messages cycle with crossfade.
//  No dismiss — user waits for SessionManager to transition state.
//

import SwiftUI

struct InventoryProcessingView: View {
    let progressMessage: String

    @State private var iconRotation: Double = 0
    @State private var glowScale: CGFloat = 1.0
    @State private var messageIndex = 0
    @State private var displayedMessage = ""

    private let messages = [
        "Uploading frames...",
        "Identifying furniture...",
        "Counting items...",
        "Checking for fragile items...",
        "Almost done..."
    ]

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Icon with glow
                ZStack {
                    // Pulsing glow
                    Circle()
                        .fill(PeezyTheme.Colors.brandYellow.opacity(0.15))
                        .frame(width: 120, height: 120)
                        .scaleEffect(glowScale)

                    // Rotating viewfinder
                    Image(systemName: "viewfinder")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .rotationEffect(.degrees(iconRotation))
                }

                // Message
                Text(displayedMessage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .multilineTextAlignment(.center)
                    .frame(height: 60)
                    .padding(.horizontal, 40)
                    .id(displayedMessage)
                    .transition(.opacity)

                Spacer()
            }
        }
        .onAppear {
            displayedMessage = progressMessage.isEmpty ? messages[0] : progressMessage
            startAnimations()
            startMessageCycling()
        }
        .onChange(of: progressMessage) { _, newValue in
            if !newValue.isEmpty {
                withAnimation(.easeInOut(duration: 0.4)) {
                    displayedMessage = newValue
                }
            }
        }
    }

    private func startAnimations() {
        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
            iconRotation = 360
        }
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            glowScale = 1.2
        }
    }

    private func startMessageCycling() {
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            messageIndex = (messageIndex + 1) % messages.count
            withAnimation(.easeInOut(duration: 0.4)) {
                displayedMessage = messages[messageIndex]
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Processing") {
    InventoryProcessingView(progressMessage: "Identifying furniture...")
}
#endif
