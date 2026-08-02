import SwiftUI

struct HealthcareProviders: View {

    let header      = "Now for any health-related accounts?"
    let subtext     : String? = "Tap everything you have. More than one of something? Tap it once per account — we track each one separately."
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
                if !selected.contains(option) {
                    selected.insert(option)
                    data.healthcareCounts[option] = 1
                }
            },
            onContinue: {
                data.healthcareProviders = Array(selected)
                coordinator.goToNext()
            },
            counts: data.healthcareCounts,
            onIncrement: { option in
                let current = data.healthcareCounts[option] ?? 1
                data.healthcareCounts[option] = current + 1
            },
            onDecrement: { option in
                let current = data.healthcareCounts[option] ?? 1
                if current <= 1 {
                    selected.remove(option)
                    data.healthcareCounts.removeValue(forKey: option)
                } else {
                    data.healthcareCounts[option] = current - 1
                }
            }
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
