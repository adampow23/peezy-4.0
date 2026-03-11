import SwiftUI

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
    }
}

#Preview {
    let dm = AssessmentDataManager()
    WantToSell().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
