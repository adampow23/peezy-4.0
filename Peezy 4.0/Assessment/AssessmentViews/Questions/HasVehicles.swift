import SwiftUI
struct HasVehicles: View {
    let header = "How many vehicles will be moving with you?"
    let options = ["0", "1", "2", "3+"]
    let icons = ["xmark.circle.fill", "car.fill", "car.2.fill", "car.2.fill"]
    let speed = 0.04

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(header: header, options: options, icons: icons, speed: speed, selected: data.hasVehicles) { value in
            data.hasVehicles = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}
#Preview { let dm = AssessmentDataManager(); HasVehicles().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm)) }
