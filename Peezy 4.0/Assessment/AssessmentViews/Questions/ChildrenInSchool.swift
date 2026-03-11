import SwiftUI

struct ChildrenInSchool: View {
    let header      = "Will any of them need to transfer schools?"
    let subtext     : String? = nil
    let options     = ["Yes", "No"]
    let icons       = ["hand.thumbsup.fill", "hand.thumbsdown.fill"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        SingleSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.childrenInSchool
        ) { value in
            data.childrenInSchool = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    ChildrenInSchool().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
