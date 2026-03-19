import SwiftUI

struct HireCleaners: View {
    let header      = "And for the final deep clean of your current home, would you like quotes for professional cleaners?"
    let subtext     : String? = nil
    let options     = ["Yes", "No"]
    let icons       = ["hand.thumbsup.fill", "hand.thumbsdown.fill"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        SingleSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.hireCleaners
        ) { value in
            data.hireCleaners = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    HireCleaners().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
