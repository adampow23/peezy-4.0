//
//  MoversFlowErrorView.swift
//  Peezy 4.0
//

import SwiftUI

struct MoversFlowErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Book your movers")

            Spacer()

            ContentUnavailableView {
                Label("Couldn't prepare your quote workspace", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(message)
            }

            Spacer()

            VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                PeezyAssessmentButton("Try again", action: onRetry)
                    .accessibilityIdentifier("movers.error.retry")
                Button("Close", action: onDismiss)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("movers.error")
    }
}
