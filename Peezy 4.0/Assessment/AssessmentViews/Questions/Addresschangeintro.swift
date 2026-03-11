import SwiftUI
struct AddressChangeIntro: View {
    let header = "Time to make sure everyone knows where to find you."
    let subtext = "You'll need to update your address with certain companies. We can help with that — and if you need to cancel something or find a new provider in your area, we've got you covered."
    let speed = 0.04

    @EnvironmentObject var coordinator: AssessmentCoordinator
    @State private var showButton = false

    var body: some View {
        ZStack {
            InteractiveBackground()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "envelope.fill")
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
#Preview { let dm = AssessmentDataManager(); AddressChangeIntro().environmentObject(AssessmentCoordinator(dataManager: dm)) }
