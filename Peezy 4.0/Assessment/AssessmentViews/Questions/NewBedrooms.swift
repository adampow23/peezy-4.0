import SwiftUI

struct NewBedrooms: View {
    let header      = "How many bedrooms at the new place?"
    let subtext     : String? = nil
    let options     = ["1", "2", "3", "4", "5+"]
    let icons       = ["bed.double.fill", "bed.double.fill", "bed.double.fill", "bed.double.fill", "bed.double.fill"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.newBedrooms
        ) { value in
            data.newBedrooms = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    NewBedrooms().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
