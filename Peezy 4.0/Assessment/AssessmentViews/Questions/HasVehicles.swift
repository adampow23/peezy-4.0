import SwiftUI

// Restored from eab4193^ (Spec 02 Phase A): the hasVehicles key was always
// coerced to "No" because this question was never asked. 2-option questions
// use SingleSelectTemplate per current convention (HasVet, HasDeclutter).
struct HasVehicles: View {
    let header      = "Any vehicles coming along?"
    let subtext     : String? = nil
    let options     = ["Yes", "No"]
    let icons       = ["hand.thumbsup.fill", "hand.thumbsdown.fill"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        SingleSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.hasVehicles
        ) { value in
            data.hasVehicles = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
        .accessibilityIdentifier("assessment.hasVehicles")
    }
}

#Preview {
    let dm = AssessmentDataManager()
    HasVehicles().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
