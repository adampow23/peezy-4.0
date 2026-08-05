//
//  MoversConfirmationView.swift
//  Peezy 4.0
//

import SwiftUI

struct MoversConfirmationView: View {
    let vendorName: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Book your movers")

            Spacer()

            VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(PeezyTheme.Colors.successGreen)
                    .accessibilityHidden(true)

                Text("Request sent to \(vendorName)")
                    .font(.title)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)

                Text("Same price basis for every mover. If anything changes day-of, that's on them — and on us.")
                    .font(.body)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Your request details are saved. Call \(vendorName) to confirm the arrival window, total price, and next steps.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer()

            PeezyAssessmentButton("Done", action: onDone)
                .accessibilityIdentifier("movers.confirmation.done")
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .accessibilityIdentifier("movers.confirmation")
    }
}
