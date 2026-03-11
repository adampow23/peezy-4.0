import SwiftUI

struct AddressChangeIntro: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let icon        = "envelope.fill"
    let header      = "Time to make sure everyone knows where to find you."
    let subtext     : String? = "You'll need to update your address with certain companies. We can help with that — and if you need to cancel something or find a new provider, we've got you covered."
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
    AddressChangeIntro().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
