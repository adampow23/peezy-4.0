import SwiftUI

struct CurrentBedrooms: View {
    let header      = "How many bedrooms at your current place?"
    let subtext     : String? = nil
    let options     = ["1", "2", "3", "4", "5+"]
    let icons       = ["bed.double.fill", "bed.double.fill", "bed.double.fill", "bed.double.fill", "bed.double.fill"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.currentBedrooms
        ) { value in
            data.currentBedrooms = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    CurrentBedrooms().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
