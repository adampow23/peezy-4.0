import SwiftUI
struct HowHeard: View {
    let header = "Before we get to the fun stuff, we'd love to know what put Peezy on your radar?"
    let options = ["Google Search", "Social Media", "Friend/Family", "Realtor", "Moving Company", "Other"]
    let icons = ["magnifyingglass", "bubble.left.fill", "person.2.fill", "house.circle.fill", "truck.box.fill", "ellipsis.circle.fill"]
    let speed = 0.04

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(header: header, options: options, icons: icons, speed: speed, columns: 2, selected: data.howHeard) { value in
            data.howHeard = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}
#Preview { let dm = AssessmentDataManager(); HowHeard().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm)) }
