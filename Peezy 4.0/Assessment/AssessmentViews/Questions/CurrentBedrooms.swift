import SwiftUI
struct CurrentBedrooms: View {
    let header = "How many bedrooms?"
    let options = ["Studio", "1", "2", "3", "4", "5+"]
    let icons = ["bed.double.fill", "1.circle.fill", "2.circle.fill", "3.circle.fill", "4.circle.fill", "5.circle.fill"]
    let speed = 0.04

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(header: header, options: options, icons: icons, speed: speed, columns: 3, selected: data.currentBedrooms) { value in
            data.currentBedrooms = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}
#Preview { let dm = AssessmentDataManager(); CurrentBedrooms().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm)) }
