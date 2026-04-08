import SwiftUI

// MARK: - Shared Home Components
// Extracted from PeezyStackView.swift for use across the app.
// These are used by: PeezyHomeView, PeezyStackView, TaskFlowView, ConfirmDetailsView

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(PeezyTheme.Colors.deepInk)
            Text("Loading your tasks...")
                .font(.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.8))
        }
    }
}

struct EmptyStateView: View {
    private var timeOfDay: TimeOfDay { TimeOfDay.current }

    var body: some View {
        VStack(spacing: 16) {
            timeOfDay.emptyStateIconStyle
                .font(.system(size: 80))
                .padding(.bottom, 4)

            Text(timeOfDay.emptyStateHeadline)
                .font(.largeTitle).bold()
                .foregroundStyle(PeezyTheme.Colors.deepInk)

            Text("You're all caught up.")
                .font(.subheadline)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
        }
    }
}

struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button("Dismiss", systemImage: "xmark.circle.fill", action: onDismiss)
                .foregroundStyle(.gray)
                .labelStyle(.iconOnly)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal)
    }
}

struct InteractiveBackground: View {
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PeezyTheme.Colors.lightBase
                .ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(PeezyTheme.Colors.iceBlue.opacity(0.8))
                        .frame(width: geo.size.width * 0.9)
                        .blur(radius: 60)
                        .offset(x: animate ? -30 : 30, y: animate ? -80 : 40)

                    Circle()
                        .fill(PeezyTheme.Colors.softLavender.opacity(0.6))
                        .frame(width: geo.size.width * 0.9)
                        .blur(radius: 60)
                        .offset(x: animate ? 80 : -80, y: animate ? 150 : -20)
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}
