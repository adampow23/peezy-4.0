import SwiftUI

struct ServicesIntro: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let icon        = "hammer.fill"
    let header      = "Time to talk services."
    let subtext     : String? = "We'll ask about services you might want help with — movers, packers, cleaners, and more."
    let buttonText  = "Continue"

    // ═══════════════════════════════════════════
    //  WIRING
    // ═══════════════════════════════════════════

    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        ExplainerTemplate(
            icon: icon, header: header, subtext: subtext,
            buttonText: buttonText,
            onContinue: { coordinator.goToNext() }
        )
    }
}

#Preview {
    let dm = AssessmentDataManager()
    ServicesIntro().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
