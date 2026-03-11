import SwiftUI

struct NewAddress: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let header      = "What's the new address?"
    let subtext     : String? = "I'll use this to get utilities, internet, and everything else set up before you walk in."
    let placeholder = "Street address"
    let buttonText  = "Continue"

    // ═══════════════════════════════════════════
    //  WIRING
    // ═══════════════════════════════════════════

    @State private var address = ""
    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        TextEntryTemplate(
            header: header, subtext: subtext,
            placeholder: placeholder,
            text: $address,
            buttonText: buttonText,
            onContinue: {
                data.newAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
                coordinator.goToNext()
            },
            disableAutocorrect: true, contentType: .fullStreetAddress
        )
        .onAppear {
            address = data.newAddress
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    NewAddress().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
