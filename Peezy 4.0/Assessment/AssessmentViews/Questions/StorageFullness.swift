import SwiftUI

struct StorageFullness: View {
    let header      = "How full is it?"
    let subtext     : String? = nil
    let options     = ["1/4", "1/2", "3/4", "Full"]
    let icons       = ["battery.25percent", "battery.50percent", "battery.75percent", "battery.100percent"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.storageFullness
        ) { value in
            data.storageFullness = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    StorageFullness().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
