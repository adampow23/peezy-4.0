// ════════════════════════════════════════════════════════════
// FILE 1: AnyKids.swift
// ════════════════════════════════════════════════════════════

import SwiftUI

struct AnyKids: View {
    let header      = "Will any children be making the move with you?"
    let subtext     : String? = nil
    let options     = ["Yes", "No"]
    let icons       = ["hand.thumbsup.fill", "hand.thumbsdown.fill"]

    @EnvironmentObject var data: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        SingleSelectTemplate(
            header: header, subtext: subtext, options: options, icons: icons,
            selected: data.anyKids
        ) { value in
            data.anyKids = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { coordinator.goToNext() }
        }
    }
}

#Preview {
    let dm = AssessmentDataManager()
    AnyKids().environmentObject(dm).environmentObject(AssessmentCoordinator(dataManager: dm))
}
