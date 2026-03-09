import SwiftUI

struct InventoryProcessingView: View {
    let progressMessage: String

    @State private var iconRotation: Double = 0
    @State private var glowScale: CGFloat = 1.0
    @State private var displayedMessage: String = ""
    @State private var messageIndex = 0

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

                ZStack {
                    // Pulsing glow behind icon
                    Circle()
                        .fill(PeezyTheme.Colors.brandYellow.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .scaleEffect(glowScale)

                    // Scanning icon with rotation
                    Image(systemName: "viewfinder")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .rotationEffect(.degrees(iconRotation))
                }

                // Typewriter-style message
                TypingText(
                    fullText: displayedMessage,
                    speed: 0.03
                )
                .font(PeezyTheme.Typography.title2)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .multilineTextAlignment(.center)
                .frame(height: 60)
                .padding(.horizontal, 40)

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
                displayedMessage = newValue
            }
        }
    }

    private func startAnimations() {
        // Continuous icon rotation
        withAnimation(
            .linear(duration: 4)
            .repeatForever(autoreverses: false)
        ) {
            iconRotation = 360
        }

        // Pulsing glow
        withAnimation(
            PeezyTheme.Animation.spring
                .repeatForever(autoreverses: true)
        ) {
            glowScale = 1.2
        }
    }

    private func startMessageCycling() {
        // Cycle through messages every 3 seconds
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { timer in
            messageIndex = (messageIndex + 1) % messages.count
            withAnimation(PeezyTheme.Animation.spring) {
                displayedMessage = messages[messageIndex]
            }
        }
    }
}
