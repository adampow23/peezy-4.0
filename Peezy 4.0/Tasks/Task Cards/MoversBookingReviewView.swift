//
//  MoversBookingReviewView.swift
//  Peezy 4.0
//

import SwiftUI

struct MoversBookingReviewView: View {
    @Bindable var model: MoversFlowViewModel
    let quote: MoversVendorQuote
    let onSubmit: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Book your movers", showBack: true, onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                    Text("Send the booking request")
                        .font(.title2)
                        .bold()
                        .foregroundStyle(PeezyTheme.Colors.deepInk)

                    ComparisonCardView(
                        model: quote.comparisonModel(
                            arrivalWindow: model.requestedArrivalWindow,
                            priceBasis: model.priceBasis
                        ),
                        isSelected: true,
                        onSelect: {}
                    )
                    .allowsHitTesting(false)

                    TextField("Anything the company should know?", text: $model.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(PeezyTheme.Layout.cardPaddingSmall)
                        .background(Color.white.opacity(0.65), in: .rect(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall))
                        .accessibilityIdentifier("movers.booking.notes")

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("movers.booking.error")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, PeezyTheme.Layout.verticalSpacing)
            }
            .scrollIndicators(.hidden)

            PeezyAssessmentButton(
                model.isSubmitting ? "Sending…" : "Request this company",
                disabled: model.isSubmitting,
                action: onSubmit
            )
            .accessibilityIdentifier("movers.booking.submit")
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("movers.booking")
    }
}
