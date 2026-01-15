//
//  GlassmorphismToast.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 1/12/26.
//


//
//  GlassmorphismToast.swift
//  Peezy
//
//  Glassmorphism toast notification for success messages
//

import SwiftUI

struct GlassmorphismToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            // Success checkmark icon
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 40, height: 40)
                    .peezyLiquidGlass(
                        cornerRadius: 20,
                        intensity: 0.55,
                        speed: 0.22,
                        tintOpacity: 0.05,
                        highlightOpacity: 0.12
                    )

                Circle()
                    .fill(Color(red: 0.98, green: 0.85, blue: 0.29).opacity(0.5))
                    .frame(width: 40, height: 40)

                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
            }

            // Message text
            Text(message)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.clear)
                    .peezyLiquidGlass(
                        cornerRadius: 16,
                        intensity: 0.55,
                        speed: 0.22,
                        tintOpacity: 0.05,
                        highlightOpacity: 0.12
                    )

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.9))
            }
            .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
        )
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        VStack {
            Spacer()
            GlassmorphismToast(message: "Task completed! ✨")
                .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}