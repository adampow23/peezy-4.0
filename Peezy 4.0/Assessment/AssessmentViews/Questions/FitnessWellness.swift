import SwiftUI

struct FitnessWellness: View {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    let header      = "And lastly, do you have any wellness-related memberships?"
    let subtext     : String? = "Tap once for each that you have an account with - if you have more than one of any, each tap will add a new task for you."
    let buttonText  = "Continue"
    let options: [(String, String)] = [
            ("Gym / CrossFit", "dumbbell.fill"),
            ("Yoga / Pilates", "figure.yoga"),
            ("Spin / Cycling", "figure.outdoor.cycle"),
            ("Massage / Spa", "sparkles"),
            ("Country Club / Golf", "figure.golf")
        ]

    // ═══════════════════════════════════════════
    //  WIRING
    // ═══════════════════════════════════════════

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
                    let current = data.fitnessCounts[option] ?? 1
                    data.fitnessCounts[option] = current + 1
                } else {
                    selected.insert(option)
                    data.fitnessCounts[option] = 1
                }
            },
            onContinue: {
                data.fitnessWellness = Array(selected)
                coordinator.goToNext()
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
