//
//  ToastView.swift
//  Peezy 4.0
//
//  Global toast notification presentation.
//

import SwiftUI

struct ToastView: View {
    let toast: ToastManager.Toast
    let onTap: () -> Void

    private var accentColor: Color {
        switch toast.style {
        case .standard:
            return PeezyTheme.Colors.deepInk
        case .success:
            return PeezyTheme.Colors.successGreen
        case .error:
            return PeezyTheme.Colors.emotionalRed
        case .warning:
            return PeezyTheme.Colors.warningOrange
        }
    }

    private var icon: String? {
        switch toast.style {
        case .standard:
            return nil
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
            }

            Text(toast.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(accentColor)
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 24)
        .onTapGesture {
            onTap()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.message)
        .accessibilityAddTraits(.isButton)
    }
}

struct ToastOverlay: View {
    @Bindable var manager: ToastManager

    var body: some View {
        VStack {
            Spacer()

            if let toast = manager.currentToast {
                ToastView(toast: toast) {
                    manager.dismissCurrent()
                }
                .id(toast.id)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .padding(.bottom, 100)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: manager.currentToast?.id)
        .allowsHitTesting(manager.currentToast != nil)
    }
}
