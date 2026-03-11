import SwiftUI

struct ChildrenInDaycare: View {
    let header      = "What about any in daycare?"
    let subtext     : String? = nil
    let options     = ["Yes", "No"]
    let icons       = ["hand.thumbsup.fill", "hand.thumbsdown.fill"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        SingleSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.childrenInDaycare
        ) { value in
            data.childrenInDaycare = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    ChildrenInDaycare().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
