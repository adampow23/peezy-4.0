import SwiftUI

struct NewRentOrOwn: View {
    let header      = "And the new place — renting or buying?"
    let subtext     : String? = nil
    let options     = ["Rent", "Own"]
    let icons       = ["key.fill", "house.fill"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        SingleSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.newRentOrOwn
        ) { value in
            data.newRentOrOwn = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    NewRentOrOwn().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
