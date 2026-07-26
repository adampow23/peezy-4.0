//
//  MoversComparisonView.swift
//  Peezy 4.0
//

import SwiftUI

struct MoversComparisonView: View {
    let quotes: [MoversVendorQuote]
    let selectedId: String?
    let arrivalWindow: String
    let priceBasis: String
    let onSelect: (MoversVendorQuote) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Book your movers", showBack: true, onBack: onBack)

            VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                Text("Same scope. Three prices.")
                    .font(.title2)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                Text("Ordered by estimated total.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, PeezyTheme.Layout.verticalSpacing)

            ScrollView {
                LazyVStack(spacing: PeezyTheme.Layout.itemSpacing) {
                    ForEach(quotes) { quote in
                        ComparisonCardView(
                            model: quote.comparisonModel(
                                arrivalWindow: arrivalWindow,
                                priceBasis: priceBasis
                            ),
                            isSelected: selectedId == quote.id,
                            onSelect: { onSelect(quote) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("movers.comparison")
    }
}
