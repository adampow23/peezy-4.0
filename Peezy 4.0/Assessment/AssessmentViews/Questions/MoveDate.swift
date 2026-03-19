import SwiftUI

struct MoveDate: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let header      = "When's the big day?"
    let subtext     : String? = "If you're unsure, put your best guess and you can update it later."
    let buttonText  = "Continue"

    // ═══════════════════════════════════════════
    //  WIRING
    // ═══════════════════════════════════════════

    @State private var selectedDate = Date()
    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        DatePickerTemplate(
            header: header, subtext: subtext,
            date: $selectedDate,
            buttonText: buttonText,
            onContinue: {
                data.moveDate = selectedDate
                coordinator.goToNext()
            }
        )
        .onAppear {
            selectedDate = data.moveDate
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    MoveDate().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
