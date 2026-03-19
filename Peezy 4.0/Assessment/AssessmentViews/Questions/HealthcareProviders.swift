import SwiftUI

struct HealthcareProviders: View {

    let header      = "Now for any health-related accounts?"
    let subtext     : String? = "Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you."
    let buttonText  = "Continue"

    // OPTIONS — must match taskCatalogData.json condition values EXACTLY
    let options: [(String, String)] = [
        ("Doctor", "stethoscope"),
        ("Dentist", "mouth.fill"),
        ("Specialists", "cross.circle.fill"),
        ("Pharmacy", "pills.fill")
    ]

    @State private var selected: Set<String> = []
    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        MultiSelectTemplate(
            header: header, subtext: subtext,
            options: options,
            selected: selected,
            buttonText: buttonText,
            onToggle: { option in
                if selected.contains(option) {
                    let current = data.healthcareCounts[option] ?? 1
                    data.healthcareCounts[option] = current + 1
                } else {
                    selected.insert(option)
                    data.healthcareCounts[option] = 1
                }
            },
            onContinue: {
                data.healthcareProviders = Array(selected)
                coordinator.goToNext()
            },
            counts: data.healthcareCounts
        )
        .onAppear {
            selected = Set(data.healthcareProviders)
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    HealthcareProviders().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
