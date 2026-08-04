import SwiftUI

struct ServicesIntro: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let icon        = "hammer.fill"
    let header      = "Time to talk services."
    let subtext     : String? = "Movers, packers, cleaners — tell us who you're hiring or just curious about, so you'll know exactly which quotes to get — and what to ask for."
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
