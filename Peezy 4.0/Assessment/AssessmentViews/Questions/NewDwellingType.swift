import SwiftUI
struct NewDwellingType: View {
    let header = "What kind of place is the new one?"
    let options = ["House", "Apartment", "Condo", "Townhouse"]
    let icons = ["house.fill", "building.2.fill", "building.fill", "house.and.flag.fill"]
    let speed = 0.04

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(header: header, options: options, icons: icons, speed: speed, selected: data.newDwellingType) { value in
            data.newDwellingType = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}
#Preview { let dm = AssessmentDataManager(); NewDwellingType().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm)) }
