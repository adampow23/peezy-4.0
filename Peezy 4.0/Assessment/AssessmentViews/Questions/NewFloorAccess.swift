import SwiftUI

struct NewFloorAccess: View {
    let header      = "What's access like at the new place?"
    let subtext     : String? = nil
    let options     = ["Ground Floor", "Stairs", "Elevator"]
    let icons       = ["figure.walk", "stairs", "arrow.up.arrow.down"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.newFloorAccess
        ) { value in
            data.newFloorAccess = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    NewFloorAccess().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
