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
    private let charcoalColor = PeezyTheme.Colors.charcoalGlass

    var body: some View {
        ZStack {
            // Animated orb background matching the rest of the app
            InteractiveBackground()

            VStack(spacing: 0) {
                Spacer()

                // Header
                TypewriterText(
                    phrases: ["F*ck moving.", "Moving made Peezy.", "Your move, on autopilot."],
                    font: .system(size: 32, weight: .semibold),
                    foregroundColor: .white
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
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .cornerRadius(PeezyTheme.Layout.cornerRadiusSmall)
                        .disabled(isAnyLoading)
                        .opacity(isAppleLoading ? 0.6 : 1)

                        if isAppleLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                    .animation(.easeOut(duration: 0.5).delay(0.4), value: showContent)

                    // Sign in with Google
                    AuthButton(
                        title: "Continue with Google",
                        icon: "g.circle.fill",
                        backgroundColor: .white,
                        textColor: .black,
                        isLoading: isGoogleLoading,
                        isDisabled: isAnyLoading,
                        hasBorder: true
                    ) {
                        PeezyHaptics.light()
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
                        backgroundColor: Color.gray.opacity(0.15),
                        textColor: .white.opacity(0.8),
                        isLoading: false,
                        isDisabled: isAnyLoading
                    ) {
                        PeezyHaptics.medium()
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
                                .foregroundColor(.white.opacity(0.6))
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
                        .fill(.ultraThinMaterial)

                        // Charcoal tint
                        UnevenRoundedRectangle(
                            topLeadingRadius: 30,
                            topTrailingRadius: 30
                        )
                        .fill(charcoalColor.opacity(0.6))
                    }
                )
                .overlay(
                    // Edge highlight at top
                    UnevenRoundedRectangle(
                        topLeadingRadius: 30,
                        topTrailingRadius: 30
                    )
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
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
    private let charcoalColor = PeezyTheme.Colors.charcoalGlass

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
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(PeezyTheme.Layout.cardPadding)
            .background(
                ZStack {
                    // Glass blur effect
                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // Charcoal tint
                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                        .fill(charcoalColor.opacity(0.6))

                    // Red border for error
                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                        .strokeBorder(PeezyTheme.Colors.emotionalRed.opacity(0.4), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6)
            )
            .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
            .padding(.top, 60)

            Spacer()
        }
    }
}

// MARK: - AuthButton

private struct AuthButton: View {
    let title: String
    let icon: String?
    let backgroundColor: Color
    let textColor: Color
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var hasBorder: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 10) {
                    if let icon = icon, !isLoading {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                    }

                    if !isLoading {
                        Text(title)
                            .font(PeezyTheme.Typography.bodyMedium)
                    }
                }
                .foregroundColor(textColor)
                .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: textColor))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                        .fill(Color.clear)
                        .peezyLiquidGlass(
                            cornerRadius: PeezyTheme.Layout.cornerRadiusSmall,
                            intensity: 0.55,
                            speed: 0.22,
                            tintOpacity: 0.05,
                            highlightOpacity: 0.12
                        )
                    
                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                        .fill(backgroundColor)
                    
                    if hasBorder {
                        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                            .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                    }
                }
            )
            .opacity(isDisabled ? 0.6 : 1.0)
        }
        .buttonStyle(.peezyPress)
        .disabled(isDisabled)
    }
}

// MARK: - Preview

#Preview {
    AuthView()
}
