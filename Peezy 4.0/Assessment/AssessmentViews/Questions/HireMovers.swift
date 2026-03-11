//
//  HireMovers.swift
//  Peezy
//
//  ┌─────────────────────────────────────────┐
//  │  EDIT THE CONFIG BELOW TO CUSTOMIZE     │
//  │  Everything else — don't touch it       │
//  └─────────────────────────────────────────┘
//

import SwiftUI

struct HireMovers: View {

    // ═══════════════════════════════════════════
    //  QUESTION CONFIG — what the user sees
    // ═══════════════════════════════════════════

    let header      = "Would you like quotes for professional movers?"
    let subtext     : String? = nil
    let options     = ["Yes", "No"]
    let icons       = ["hand.thumbsup.fill", "hand.thumbsdown.fill"]

    // ═══════════════════════════════════════════
    //  LAYOUT OVERRIDES (optional)
    //  Leave these alone to use template defaults.
    //  Change any number to override just for this question.
    //
    //  let speed = 0.03           ← faster typewriter
    //  let heroFontSize = 28      ← smaller hero text
    //  let morphBottomPad = 60    ← more space before tiles
    // ═══════════════════════════════════════════

    // ═══════════════════════════════════════════
    //  WIRING — change the property name when duplicating
    // ═══════════════════════════════════════════

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        SingleSelectTemplate(
            header: header,
            subtext: subtext,
            options: options,
            icons: icons,
            selected: data.hireMovers
        ) { value in
            data.hireMovers = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                coordinator.goToNext()
            }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    HireMovers()
        .environmentObject(dm)
        .environmentObject(AssessmentCoordinator(dataManager: dm))
}
