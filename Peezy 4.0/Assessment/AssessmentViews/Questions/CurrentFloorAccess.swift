import SwiftUI

struct CurrentFloorAccess: View {
    let header      = "What's access like at the current place?"
    let subtext     : String? = nil
    let options     = ["Ground Floor", "Stairs", "Elevator", "Reserved Elevator"]
        let icons       = ["figure.walk", "stairs", "arrow.up.arrow.down", "calendar.badge.clock"] 

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.currentFloorAccess
        ) { value in
            data.currentFloorAccess = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    CurrentFloorAccess().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
