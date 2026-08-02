import SwiftUI

struct AddressChangeIntro: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let icon        = "envelope.fill"
    let header      = "Time to make sure everyone knows where to find you."
    let subtext     : String? = "Banks, doctors, memberships — they all need your new address. We'll handle the updates, the cancellations, and finding new ones near you."
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
