import SwiftUI

struct UserName: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let header      = "What's your first name?"
    let subtext     : String? = nil
    let placeholder = "First name"
    let buttonText  = "Continue"

    // ═══════════════════════════════════════════
    //  WIRING
    // ═══════════════════════════════════════════

    @State private var name = ""
    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        TextEntryTemplate(
            header: header, subtext: subtext,
            placeholder: placeholder,
            text: $name,
            buttonText: buttonText,
            onContinue: {
                data.userName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                coordinator.goToNext()
            },
            disableAutocorrect: true, contentType: .givenName
        )
        .onAppear {
            name = data.userName
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    UserName().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
