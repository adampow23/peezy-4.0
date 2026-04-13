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
    private let deepInk = PeezyTheme.Colors.deepInk

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
                            .foregroundColor(PeezyTheme.Colors.deepInk)

                        Text("Sign up to get started with Peezy")
                            .font(PeezyTheme.Typography.callout)
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
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
                            keyboardType: .emailAddress,
                            fieldAccessibilityId: "signup_email_field"
                        )

                        FormField(
                            label: "Password",
                            placeholder: "Min. 6 characters",
                            text: $password,
                            isSecure: true,
                            contentType: .newPassword,
                            fieldAccessibilityId: "signup_password_field"
                        )

                        FormField(
                            label: "Confirm Password",
                            placeholder: "Re-enter password",
                            text: $confirmPassword,
                            isSecure: true,
                            contentType: .newPassword,
                            fieldAccessibilityId: "signup_confirm_password_field"
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
                    AuthFormButton(
                        title: "Sign up",
                        isLoading: isLoading,
                        isDisabled: !isFormValid,
                        action: handleSignUp
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .accessibilityIdentifier("signup_submit_button")

                    Spacer()

                    // Already have account
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                            Text("Log in")
                                .foregroundColor(PeezyTheme.Colors.accentBlue)
                                .fontWeight(.medium)
                        }
                        .font(PeezyTheme.Typography.callout)
                    }
                    .padding(.bottom, PeezyTheme.Layout.sectionSpacing)
                    .accessibilityIdentifier("signup_login_link")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(PeezyTheme.Colors.deepInk)
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
            DispatchQueue.main.async {
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
}

// MARK: - FormField

private struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var contentType: UITextContentType?
    var keyboardType: UIKeyboardType = .default
    var fieldAccessibilityId: String? = nil

    var body: some View {
        PeezyFormField2(
            label: label,
            placeholder: placeholder,
            text: $text,
            isSecure: isSecure,
            contentType: contentType,
            keyboardType: keyboardType,
            autocapitalization: .never,
            fieldAccessibilityId: fieldAccessibilityId
        )
    }
}

// MARK: - Preview

#Preview {
    SignUpView()
        .environmentObject(AuthViewModel())
}
