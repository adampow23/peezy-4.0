import SwiftUI

struct CurrentRentOrOwn: View {
    let header      = "Are you currently renting or do you own?"
    let subtext     : String? = nil
    let options     = ["Rent", "Own"]
    let icons       = ["key.fill", "house.fill"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        SingleSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.currentRentOrOwn
        ) { value in
            data.currentRentOrOwn = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    CurrentRentOrOwn().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
