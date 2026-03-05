//
//  AuthView.swift
//  PeezyV1.0
//
//  Created by user285836 on 11/11/25.
//

import SwiftUI
import AuthenticationServices

// MARK: - AuthView

struct AuthView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var showSignUp = false
    @State private var showLogin = false

    private enum AuthLoadingState: Equatable {
        case none
        case apple
        case google
    }
    @State private var loadingState: AuthLoadingState = .none

    @State private var showContent = false

    @State private var showToast = false
    @State private var toastMessage = ""

    private var isAnyLoading: Bool { loadingState != .none }
    private var isAppleLoading: Bool { loadingState == .apple }
    private var isGoogleLoading: Bool { loadingState == .google }

    // Charcoal glass color
    var body: some View {
        ZStack {
            // Animated orb background matching the rest of the app
            InteractiveBackground()

            VStack(spacing: 0) {
                Spacer()

                // Header
                TypewriterText(
                    phrases: ["F*ck moving.", "Moving made peezy.", "Your move, on autopilot."],
                    font: .system(size: 32, weight: .semibold),
                    foregroundColor: PeezyTheme.Colors.deepInk
                )
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                    .animation(.easeOut(duration: 0.8).delay(0.2), value: showContent)

                Spacer()

                // Auth buttons container
                VStack(spacing: 12) {
                    // Continue with Apple
                    ZStack {
                        SignInWithAppleButton(
                            onRequest: { request in
                                loadingState = .apple
                                viewModel.handleAppleSignInRequest(request)
                            },
                            onCompletion: { result in
                                viewModel.handleAppleSignInCompletion(result) { error in
                                    loadingState = .none
                                    if let error = error {
                                        showErrorToast(error.localizedDescription)
                                    }
                                }
                            }
                        )
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 56)
                        .clipShape(Capsule(style: .continuous))
                        .disabled(isAnyLoading)
                        .opacity(isAppleLoading ? 0.6 : 1)

                        if isAppleLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: PeezyTheme.Colors.deepInk))
                        }
                    }
                    .shadow(
                        color: Color.black.opacity(0.15),
                        radius: 16,
                        x: 0,
                        y: 8
                    )
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                    .animation(.easeOut(duration: 0.5).delay(0.4), value: showContent)

                    // Sign in with Google
                    AuthButton(
                        title: "Continue with Google",
                        customImage: "google-logo",
                        isLoading: isGoogleLoading,
                        isDisabled: isAnyLoading
                    ) {
                        loadingState = .google
                        viewModel.signInWithGoogle { error in
                            loadingState = .none
                            if let error = error {
                                showErrorToast(error.localizedDescription)
                            }
                        }
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                    .animation(.easeOut(duration: 0.5).delay(0.5), value: showContent)

                    // Continue with Email
                    AuthButton(
                        title: "Continue with Email",
                        icon: "envelope.fill",
                        isDisabled: isAnyLoading
                    ) {
                        showSignUp = true
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                    .animation(.easeOut(duration: 0.5).delay(0.6), value: showContent)

                    // Already have an account? Log in link
                    Button {
                        PeezyHaptics.light()
                        showLogin = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                            Text("Log in")
                                .foregroundColor(PeezyTheme.Colors.accentBlue)
                                .fontWeight(.semibold)
                        }
                        .font(PeezyTheme.Typography.callout)
                    }
                    .disabled(isAnyLoading)
                    .padding(.top, 8)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.7), value: showContent)
                }
                .padding(.horizontal, PeezyTheme.Layout.sectionSpacing)
                .padding(.top, PeezyTheme.Layout.sectionSpacing)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
                .background(
                    ZStack {
                        // Glass blur effect
                        UnevenRoundedRectangle(
                            topLeadingRadius: 30,
                            topTrailingRadius: 30
                        )
                        .fill(.regularMaterial)

                        // Semi-transparent white tint — matches glass card style
                        UnevenRoundedRectangle(
                            topLeadingRadius: 30,
                            topTrailingRadius: 30
                        )
                        .fill(Color.white.opacity(0.5))
                    }
                )
                .overlay(
                    // Edge highlight at top
                    UnevenRoundedRectangle(
                        topLeadingRadius: 30,
                        topTrailingRadius: 30
                    )
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: -8)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 50)
                .animation(PeezyTheme.Animation.springSlow.delay(0.3), value: showContent)
            }
            .ignoresSafeArea(edges: .bottom)

            // Toast notification for errors
            if showToast {
                AuthErrorToast(message: toastMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1000)
            }
        }
        .sheet(isPresented: $showSignUp) {
            SignUpView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showLogin) {
            LoginView()
                .environmentObject(viewModel)
        }
        .onAppear {
            withAnimation {
                showContent = true
            }
        }
    }

    // MARK: - Helper Functions

    private func showErrorToast(_ message: String) {
        PeezyHaptics.error()
        toastMessage = message
        withAnimation(PeezyTheme.Animation.spring) {
            showToast = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(PeezyTheme.Animation.spring) {
                showToast = false
            }
        }
    }
}

// MARK: - AuthErrorToast

private struct AuthErrorToast: View {
    let message: String
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(PeezyTheme.Colors.emotionalRed.opacity(0.2))
                        .frame(width: 36, height: 36)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PeezyTheme.Colors.emotionalRed)
                }

                Text(message)
                    .font(PeezyTheme.Typography.calloutMedium)
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(PeezyTheme.Layout.cardPadding)
            .background(
                ZStack {
                    // Glass blur effect
                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                        .fill(.regularMaterial)

                    // Light tint
                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.6))

                    // Red border for error
                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                        .strokeBorder(PeezyTheme.Colors.emotionalRed.opacity(0.4), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 6)
            )
            .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
            .padding(.top, 60)

            Spacer()
        }
    }
}

// MARK: - AuthButton
// Matches PeezyAssessmentButton style: capsule, deepInk, glow shadow, press gesture

private struct AuthButton: View {
    let title: String
    var icon: String? = nil
    var customImage: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    private let deepInk = PeezyTheme.Colors.deepInk

    private var effectiveDisabled: Bool { isDisabled || isLoading }

    var body: some View {
        Button(action: {
            guard !effectiveDisabled else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            ZStack {
                HStack(spacing: 10) {
                    if let customImage = customImage {
                        Image(customImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    } else if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                    }

                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }
                .foregroundColor(effectiveDisabled ? .white.opacity(0.5) : .white)
                .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Capsule(style: .continuous)
                    .fill(deepInk.opacity(effectiveDisabled ? 0.3 : 1.0))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(effectiveDisabled ? 0.0 : 0.25), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: effectiveDisabled ? .clear : deepInk.opacity(isPressed ? 0.2 : 0.4),
                radius: isPressed ? 8 : 16,
                x: 0,
                y: isPressed ? 4 : 8
            )
        }
        .disabled(effectiveDisabled)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: effectiveDisabled)
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !effectiveDisabled && !isPressed {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

// MARK: - Preview

#Preview {
    AuthView()
}
