//
//  ComparisonCardView.swift
//  Peezy 4.0
//
//  Vertical-neutral comparison surface reused by service and plan adapters.
//

import SwiftUI

struct ComparisonCardLabels {
    let firstIcon: String
    let secondIcon: String
    let thirdIcon: String
    let detailIcon: String
    let footerPrefix: String
    let accessibilityHint: String

    static let moving = ComparisonCardLabels(
        firstIcon: "clock",
        secondIcon: "calendar.badge.clock",
        thirdIcon: "shield.checkered",
        detailIcon: "shippingbox.fill",
        footerPrefix: "Price basis",
        accessibilityHint: "Select this option"
    )

    static let internet = ComparisonCardLabels(
        firstIcon: "speedometer",
        secondIcon: "tag.fill",
        thirdIcon: "doc.text.fill",
        detailIcon: "wifi",
        footerPrefix: "Coverage",
        accessibilityHint: "Open this provider's plan details in the app"
    )
}

struct ComparisonCardView: View {
    let model: ComparisonCardModel
    let isSelected: Bool
    let labels: ComparisonCardLabels
    let onSelect: () -> Void

    init(
        model: ComparisonCardModel,
        isSelected: Bool,
        labels: ComparisonCardLabels = .moving,
        onSelect: @escaping () -> Void
    ) {
        self.model = model
        self.isSelected = isSelected
        self.labels = labels
        self.onSelect = onSelect
    }

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
                    Label(model.durationAndTeam, systemImage: labels.firstIcon)
                    Label(model.arrivalWindow, systemImage: labels.secondIcon)
                    Label(model.insuranceTier, systemImage: labels.thirdIcon)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text(model.why)
                    .font(.subheadline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(model.detailNotes, id: \.self) { note in
                    Label(note, systemImage: labels.detailIcon)
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                }

                Text("\(labels.footerPrefix): \(model.priceBasis)")
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
        .accessibilityLabel(
            ([
                model.providerName,
                model.priceRange,
                model.durationAndTeam,
                model.arrivalWindow,
                model.insuranceTier,
                model.why,
                "\(labels.footerPrefix): \(model.priceBasis)"
            ]
                + model.detailNotes).joined(separator: ", ")
        )
        .accessibilityHint(labels.accessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("comparison.\(model.id)")
    }
}
