import SwiftUI

struct HasDeclutter: View {
    let header      = "Any items you're planning to part with before the move?"
    let subtext     : String? = "Clothes, furniture, electronics — anything you don't want making the trip."
    let options     = ["Yes", "No"]
    let icons       = ["hand.thumbsup.fill", "hand.thumbsdown.fill"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        SingleSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.hasDeclutter
        ) { value in
            data.hasDeclutter = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    HasDeclutter().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
