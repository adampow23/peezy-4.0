import SwiftUI
struct StorageSize: View {
    let header = "How big is the unit?"
    let options = ["Small", "Medium", "Large"]
    let icons = ["square.fill", "square.fill", "square.fill"]
    let speed = 0.04

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(header: header, options: options, icons: icons, speed: speed, columns: 3, selected: data.storageSize) { value in
            data.storageSize = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}
#Preview { let dm = AssessmentDataManager(); StorageSize().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm)) }
