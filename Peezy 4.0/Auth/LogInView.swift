//
//  LoginView.swift
//  PeezyV1.0
//
//  Created by user285836 on 11/11/25.
//

import SwiftUI

// MARK: - LoginView

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: AuthViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var isFormValid: Bool {
        !email.isEmpty &&
        email.contains("@") &&
        !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Welcome Back")
                        .font(PeezyTheme.Typography.largeTitle)

                    Text("Log in to continue your move")
                        .font(PeezyTheme.Typography.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                .padding(.bottom, 20)

                // Form
                VStack(spacing: PeezyTheme.Layout.cardPadding) {
                    LoginFormField(
                        label: "Email",
                        placeholder: "your@email.com",
                        text: $email,
                        contentType: .emailAddress,
                        keyboardType: .emailAddress
                    )

                    LoginFormField(
                        label: "Password",
                        placeholder: "Enter your password",
                        text: $password,
                        isSecure: true,
                        contentType: .password
                    )
                }
                .padding(.horizontal, 24)

                // Log In Button
                Button(action: handleLogin) {
                    Group {
                        if isLoading {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Log In")
                                .font(PeezyTheme.Typography.headline)
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
                                .fill(isFormValid ? PeezyTheme.Colors.brandYellow : Color.gray.opacity(0.3))
                        }
                    )
                    .foregroundColor(.black)
                    .cornerRadius(PeezyTheme.Layout.cornerRadiusSmall)
                }
                .buttonStyle(.peezyPrimary)
                .disabled(!isFormValid || isLoading)
                .padding(.horizontal, 24)
                .padding(.top, 8)

                // Forgot Password
                Button(action: {
                    // TODO: Implement forgot password
                }) {
                    Text("Forgot Password?")
                        .font(PeezyTheme.Typography.callout)
                        .foregroundColor(.blue)
                }
                .padding(.top, 8)

                Spacer()

                // Don't have account
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .foregroundColor(.secondary)
                        Text("Sign up")
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    }
                    .font(PeezyTheme.Typography.callout)
                }
                .padding(.bottom, PeezyTheme.Layout.sectionSpacing)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
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

    private func handleLogin() {
        isLoading = true
        PeezyHaptics.medium()

        viewModel.signIn(email: email, password: password) { error in
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

// MARK: - LoginFormField

private struct LoginFormField: View {
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
    LoginView()
        .environmentObject(AuthViewModel())
}
