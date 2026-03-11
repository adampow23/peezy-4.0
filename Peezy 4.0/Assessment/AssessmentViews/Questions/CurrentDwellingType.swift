import SwiftUI
struct CurrentDwellingType: View {
    let header = "What kind of place are you in now?"
    let options = ["House", "Apartment", "Condo", "Townhouse"]
    let icons = ["house.fill", "building.2.fill", "building.fill", "house.and.flag.fill"]
    let speed = 0.04

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        GridSelectTemplate(header: header, options: options, icons: icons, speed: speed, selected: data.currentDwellingType) { value in
            data.currentDwellingType = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}
#Preview { let dm = AssessmentDataManager(); CurrentDwellingType().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm)) }
