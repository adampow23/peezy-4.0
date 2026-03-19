import SwiftUI

struct StorageSize: View {
    let header      = "How big is the unit?"
    let subtext     : String? = nil
    let options     = ["Small", "Medium", "Large"]
    let icons       = ["suitcase.fill", "car.fill", "truck.box.fill"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.storageSize
        ) { value in
            data.storageSize = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    StorageSize().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
