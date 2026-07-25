import SwiftUI

// Restored from eab4193^ (Spec 02 Phase A): the wantToSell key was always
// empty because this question was never asked. Gates SELL_ITEMS (Yes) and
// REMOVE_ITEMS (No) together with hasDeclutter=Yes.
struct WantToSell: View {
    let header      = "Are you planning to sell any of those items?"
    let subtext     : String? = "We can assist with that process as well as plan b if they don't sell."
    let options     = ["Yes", "No"]
    let icons       = ["hand.thumbsup.fill", "hand.thumbsdown.fill"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        SingleSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.wantToSell
        ) { value in
            data.wantToSell = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
        .accessibilityIdentifier("assessment.wantToSell")
    }
}

#Preview {
    let dm = AssessmentDataManager()
    WantToSell().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
