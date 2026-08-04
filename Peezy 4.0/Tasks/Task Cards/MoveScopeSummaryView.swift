//
//  MoveScopeSummaryView.swift
//  Peezy 4.0
//

import SwiftUI

struct MoveScopeSummaryView: View {
    let userId: String
    let totalCubicFeet: Double
    let distanceMiles: Double?
    let homeSummary: String
    let cubeSummary: String
    let accessSummary: String
    let storageSummary: String?
    let priceBasis: String
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Book your movers", showBack: true, onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                    Text("Here's the scope we're pricing")
                        .font(.title)
                        .bold()
                        .foregroundStyle(PeezyTheme.Colors.deepInk)

                    Label(homeSummary, systemImage: "bed.double.fill")
                    Label(cubeSummary, systemImage: "shippingbox.fill")
                    Label(accessSummary, systemImage: "stairs")
                    if let storageSummary {
                        Label(storageSummary, systemImage: "archivebox.fill")
                    }

                    Text("Price basis: \(priceBasis)")
                        .font(.footnote)
                        .bold()
                        .padding(.horizontal, PeezyTheme.Layout.cardPaddingSmall)
                        .padding(.vertical, PeezyTheme.Layout.verticalSpacingSmall)
                        .background(PeezyTheme.Colors.brandYellow.opacity(0.6), in: .capsule)

                    TruckSizeView(
                        userId: userId,
                        totalCubicFeet: totalCubicFeet,
                        distanceMiles: distanceMiles
                    )
                }
                .font(.body)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, PeezyTheme.Layout.verticalSpacing)
            }

            PeezyAssessmentButton("Confirm the details", action: onContinue)
                .accessibilityIdentifier("movers.scope.continue")
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .accessibilityIdentifier("movers.scope")
    }
}
