import SwiftUI

struct FitnessWellness: View {

    let header      = "And lastly, do you have any wellness-related memberships?"
    let subtext     : String? = "Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you."
    let buttonText  = "Continue"

    // OPTIONS — must match taskCatalogData.json condition values EXACTLY
    let options: [(String, String)] = [
        ("Gym / CrossFit", "dumbbell.fill"),
        ("Yoga / Pilates", "figure.yoga"),
        ("Spin / Cycling", "figure.outdoor.cycle"),
        ("Massage / Spa", "sparkles"),
        ("Country Club / Golf", "figure.golf")
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
                    data.fitnessCounts[option] = 1
                }
            },
            onContinue: {
                data.fitnessWellness = Array(selected)
                coordinator.goToNext()
            },
            counts: data.fitnessCounts,
            onIncrement: { option in
                let current = data.fitnessCounts[option] ?? 1
                data.fitnessCounts[option] = current + 1
            },
            onDecrement: { option in
                let current = data.fitnessCounts[option] ?? 1
                if current <= 1 {
                    selected.remove(option)
                    data.fitnessCounts.removeValue(forKey: option)
                } else {
                    data.fitnessCounts[option] = current - 1
                }
            }
        )
        .onAppear {
            selected = Set(data.fitnessWellness)
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    FitnessWellness().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
