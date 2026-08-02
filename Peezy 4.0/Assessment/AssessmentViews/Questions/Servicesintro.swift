import SwiftUI

struct ServicesIntro: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let icon        = "hammer.fill"
    let header      = "Time to talk services."
    let subtext     : String? = "Movers, packers, cleaners — tell us who you're hiring, or just curious about, and we'll line up the quotes."
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
