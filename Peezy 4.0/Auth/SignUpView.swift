//
//  SignUpView.swift
//  PeezyV1.0
//
//  Created by user285836 on 11/11/25.
//

import SwiftUI

// MARK: - SignUpView

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: AuthViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var isFormValid: Bool {
        !email.isEmpty &&
        email.contains("@") &&
        !password.isEmpty &&
        password.count >= 6
    }

    // Charcoal glass color
    private let charcoalColor = PeezyTheme.Colors.charcoalGlass

    var body: some View {
        NavigationStack {
            ZStack {
                // Dark background
                InteractiveBackground()

                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Create Account")
                            .font(PeezyTheme.Typography.largeTitle)
                            .foregroundColor(.white)

                        Text("Sign up to get started with Peezy")
                            .font(PeezyTheme.Typography.callout)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 20)

                    // Form
                    VStack(spacing: PeezyTheme.Layout.cardPadding) {
                        FormField(
                            label: "Email",
                            placeholder: "your@email.com",
                            text: $email,
                            contentType: .emailAddress,
                            keyboardType: .emailAddress
                        )

                        FormField(
                            label: "Password",
                            placeholder: "Min. 6 characters",
                            text: $password,
                            isSecure: true,
                            contentType: .newPassword
                        )

                        FormField(
                            label: "Confirm Password",
                            placeholder: "Re-enter password",
                            text: $confirmPassword,
                            isSecure: true,
                            contentType: .newPassword
                        )

                        // Inline password mismatch error
                        if !confirmPassword.isEmpty && password != confirmPassword {
                            Text("Passwords do not match")
                                .font(.caption)
                                .foregroundColor(PeezyTheme.Colors.emotionalRed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, -8)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Sign Up Button
                    Button(action: handleSignUp) {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Sign Up")
                                    .font(PeezyTheme.Typography.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundColor(.white)
                        .background(
                            ZStack {
                                // Glass blur effect
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)

                                // Charcoal tint (or accent blue when valid)
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(isFormValid ? PeezyTheme.Colors.accentBlue : charcoalColor.opacity(0.6))
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: isFormValid ? PeezyTheme.Colors.accentBlue.opacity(0.3) : Color.black.opacity(0.3), radius: 10, y: 5)
                    }
                    .disabled(!isFormValid || isLoading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    Spacer()

                    // Already have account
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .foregroundColor(.white.opacity(0.6))
                            Text("Log in")
                                .foregroundColor(PeezyTheme.Colors.accentBlue)
                                .fontWeight(.medium)
                        }
                        .font(PeezyTheme.Typography.callout)
                    }
                    .padding(.bottom, PeezyTheme.Layout.sectionSpacing)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func handleSignUp() {
        // Check password match before proceeding
        guard password == confirmPassword else {
            PeezyHaptics.error()
            errorMessage = "Passwords do not match"
            showError = true
            return
        }
        
        isLoading = true
        PeezyHaptics.medium()

        viewModel.signUp(email: email, password: password) { error in
            isLoading = false

            if let error = error {
                PeezyHaptics.error()
                errorMessage = error.localizedDescription
                showError = true
            } else {
                PeezyHaptics.success()
                dismiss()
            }
        }
    }
}

// MARK: - FormField

private struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var contentType: UITextContentType?
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        PeezyFormField2(
            label: label,
            placeholder: placeholder,
            text: $text,
            isSecure: isSecure,
            contentType: contentType,
            keyboardType: keyboardType,
            autocapitalization: .never
        )
    }
}

// MARK: - Preview

#Preview {
    SignUpView()
        .environmentObject(AuthViewModel())
}
