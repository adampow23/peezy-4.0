import SwiftUI
struct StorageFullness: View {
    let header = "How full is it?"
    let options = ["1/4 Full", "Half Full", "3/4 Full", "Completely Full"]
    let icons = ["circle.bottomhalf.filled", "circle.lefthalf.filled", "circle.righthalf.filled", "circle.fill"]
    let speed = 0.04

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(header: header, options: options, icons: icons, speed: speed, selected: data.storageFullness) { value in
            data.storageFullness = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}
#Preview { let dm = AssessmentDataManager(); StorageFullness().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm)) }
