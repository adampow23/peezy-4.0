//
//  MoversCaptureCard.swift
//  Peezy 4.0
//

import SwiftUI

struct MoversCaptureCard: View {
    let onScan: () -> Void
    let onFallback: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Book your movers")

            Spacer()

            VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                Image(systemName: "camera.viewfinder")
                    .font(.largeTitle)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityHidden(true)

                Text("First, let's measure the move")
                    .font(.title)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)

                Text("A quick scan gives every company the exact same job to price. No video? Home details work too — the range is just wider.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                PeezyAssessmentButton("Scan my home", action: onScan)
                    .accessibilityIdentifier("movers.capture.scan")

                Button("Use home details instead", action: onFallback)
                    .font(.body)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("movers.capture.fallback")

                Button("Not now", action: onDismiss)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("movers.capture")
    }
}
