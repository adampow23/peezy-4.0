import SwiftUI

struct MoveDate: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let header      = "When's the big day?"
    let subtext     : String? = "I'll build your timeline around this date."
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
