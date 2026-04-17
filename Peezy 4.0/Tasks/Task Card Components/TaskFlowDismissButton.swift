//
//  TaskFlowDismissButton.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI

// MARK: - Task Flow Dismiss Button
// Kept as a compatibility shim for flows that still include the old top-left
// home affordance. New flows should provide their own close treatment.

struct TaskFlowDismissButton: View {
    let onDismiss: () -> Void

    var body: some View {
        EmptyView()
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Dismiss Button") {
    ZStack(alignment: .topLeading) {
        InteractiveBackground()
            .ignoresSafeArea()

        TaskFlowDismissButton(onDismiss: { print("Dismiss") })
    }
}
#endif
