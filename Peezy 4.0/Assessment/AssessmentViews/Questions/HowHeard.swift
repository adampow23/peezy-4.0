import SwiftUI

struct HowHeard: View {
    let header      = "How did you hear about Peezy?"
    let subtext     : String? = nil
    let options     = ["Friend or Family", "Social Media", "Google Search", "Real Estate Agent", "Moving Company", "Other"]
    let icons       = ["person.2.fill", "iphone", "magnifyingglass", "house.fill", "truck.box.fill", "ellipsis"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.howHeard
        ) { value in
            data.howHeard = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    HowHeard().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
