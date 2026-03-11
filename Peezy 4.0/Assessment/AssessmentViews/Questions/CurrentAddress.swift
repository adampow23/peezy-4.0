import SwiftUI

struct CurrentAddress: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let header      = "What's the current address?"
    let subtext     : String? = "I'll use this for mail forwarding, utilities, and more."
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
                data.currentAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
                coordinator.goToNext()
            },
            disableAutocorrect: true, contentType: .fullStreetAddress
        )
        .onAppear {
            address = data.currentAddress
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    CurrentAddress().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
