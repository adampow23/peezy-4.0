//
//  PeezyWordmark.swift
//  Peezy 4.0
//
//  The "peezy" brand wordmark that appears at the top of every main view.
//  Always visible — preserves brand continuity as card content changes below.
//

import SwiftUI

struct PeezyWordmark: View {
    var body: some View {
        Text("peezy")
            .font(.system(size: 18, weight: .light, design: .default))
            .tracking(6)
            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .accessibilityHidden(true)
    }
}
