//
//  ComparisonCardView.swift
//  Peezy 4.0
//
//  Vertical-neutral comparison surface reused by service and plan adapters.
//

import SwiftUI

struct ComparisonCardView: View {
    let model: ComparisonCardModel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.providerName)
                        .font(.headline)
                        .bold()
                        .foregroundStyle(PeezyTheme.Colors.deepInk)

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? PeezyTheme.Colors.successGreen : .secondary)
                        .accessibilityHidden(true)
                }

                Text(model.priceRange)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)

                VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                    Label(model.durationAndTeam, systemImage: "clock")
                    Label(model.arrivalWindow, systemImage: "calendar.badge.clock")
                    Label(model.insuranceTier, systemImage: "shield.checkered")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text(model.why)
                    .font(.subheadline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Price basis: \(model.priceBasis)")
                    .font(.footnote)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .padding(.horizontal, PeezyTheme.Layout.cardPaddingSmall)
                    .padding(.vertical, PeezyTheme.Layout.verticalSpacingSmall)
                    .background(PeezyTheme.Colors.brandYellow.opacity(0.55), in: .capsule)
            }
            .padding(PeezyTheme.Layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? PeezyTheme.Colors.brandYellow.opacity(0.22) : Color.white.opacity(0.62), in: .rect(cornerRadius: PeezyTheme.Layout.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius)
                    .stroke(
                        isSelected ? PeezyTheme.Colors.deepInk : PeezyTheme.Colors.deepInk.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.providerName), \(model.priceRange), \(model.durationAndTeam), \(model.arrivalWindow), \(model.insuranceTier)")
        .accessibilityHint("Select this option")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("comparison.\(model.id)")
    }
}
