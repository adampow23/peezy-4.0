import SwiftUI

// Restored from eab4193^ (Spec 02 Phase A): feeds the no-video cube fallback
// (Spec 05) and packageInventory admin emails.
struct CurrentBedrooms: View {
    let header      = "How many bedrooms at your current place?"
    let subtext     : String? = nil
    let options     = ["1 Bedroom", "2 Bedrooms", "3 Bedrooms", "4 Bedrooms", "5 Bedrooms", "6+ Bedrooms"]
    let icons       = ["1.circle", "2.circle", "3.circle", "4.circle", "5.circle", "6.circle"]

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
        .accessibilityIdentifier("assessment.currentBedrooms")
    }
}

#Preview {
    let dm = AssessmentDataManager()
    CurrentBedrooms().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
