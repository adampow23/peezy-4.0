import SwiftUI
struct ServicesIntro: View {
    let header = "Now let's talk about any professional help you might need."
    let subtext = "We'll ask about services you're planning to hire or even just interested in receiving quotes from — movers, packers, cleaners, and more."
    let speed = 0.04

    @EnvironmentObject var coordinator: AssessmentCoordinator
    @State private var showButton = false

    var body: some View {
        ZStack {
            InteractiveBackground()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 60))
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.15))
                    TypingText(fullText: header, speed: speed, visibleColor: PeezyTheme.Colors.deepInk, onComplete: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showButton = true }
                    })
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    Text(subtext)
                        .font(.system(size: 16))
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                Spacer()
                if showButton {
                    PeezyAssessmentButton("Continue") { coordinator.goToNext() }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                        .transition(.opacity)
                }
            }
        }
    }
}
#Preview { let dm = AssessmentDataManager(); ServicesIntro().environmentObject(AssessmentCoordinator(dataManager: dm)) }
