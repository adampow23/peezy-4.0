import SwiftUI

struct MoveDateType: View {
    let header      = "Is your move date flexible?"
    let subtext     : String? = nil
    let options     = ["Strict", "Flexible"]
    let icons       = ["arrow.left.arrow.right", "checkmark.circle"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        SingleSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.moveDateType
        ) { value in
            data.moveDateType = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    MoveDateType().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
