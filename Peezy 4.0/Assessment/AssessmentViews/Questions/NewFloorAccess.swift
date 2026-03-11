import SwiftUI
struct NewFloorAccess: View {
    let header = "What's access like?"
    let options = ["Elevator", "Stairs", "Ground Floor"]
    let icons = ["arrow.up.arrow.down", "figure.stairs", "arrow.right.to.line"]
    let speed = 0.04

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(header: header, options: options, icons: icons, speed: speed, selected: data.newFloorAccess) { value in
            data.newFloorAccess = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}
#Preview { let dm = AssessmentDataManager(); NewFloorAccess().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm)) }
