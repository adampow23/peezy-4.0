import SwiftUI

struct HasVehicles: View {
    let header      = "Will any vehicles be moving with you?"
    let subtext     : String? = nil
    let options     = ["Yes", "No"]
    let icons       = ["hand.thumbsup.fill", "hand.thumbsdown.fill"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.hasVehicles
        ) { value in
            data.hasVehicles = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    HasVehicles().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
