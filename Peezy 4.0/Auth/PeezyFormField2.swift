//
//  PeezyFormField.swift
//  PeezyV1.0
//
//  Unified text/secure field styling for consistent forms.
//

import SwiftUI

struct PeezyFormField2: View {
    let label: String?
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var leadingIcon: String? = nil
    var helper: String? = nil
    var error: String? = nil
    var contentType: UITextContentType? = nil
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .never
    // Explicit control instead of trying to compare TextInputAutocapitalization
    var disableAutocorrection: Bool = false

    @FocusState private var isFocused: Bool

    // Charcoal glass colors
    private let charcoalColor = PeezyTheme.Colors.charcoalGlass
    private let accentBlue = PeezyTheme.Colors.accentBlue

    private var hasError: Bool { !(error ?? "").isEmpty }

    private var strokeColor: Color {
        if hasError { return PeezyTheme.Colors.emotionalRed }
        if isFocused { return accentBlue.opacity(0.6) }
        return Color.white.opacity(0.1)
    }

    private var shadowColor: Color {
        if hasError { return PeezyTheme.Colors.emotionalRed.opacity(0.2) }
        if isFocused { return accentBlue.opacity(0.2) }
        return Color.black.opacity(0.3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label = label, !label.isEmpty {
                Text(label)
                    .font(PeezyTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.6))
            }

            HStack(spacing: 12) {
                if let icon = leadingIcon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isFocused ? accentBlue : .white.opacity(0.5))
                }

                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                            .textContentType(contentType)
                            .keyboardType(keyboardType)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .focused($isFocused)
                    } else {
                        TextField(placeholder, text: $text)
                            .textContentType(contentType)
                            .keyboardType(keyboardType)
                            .textInputAutocapitalization(autocapitalization)
                            .autocorrectionDisabled(disableAutocorrection)
                            .focused($isFocused)
                    }
                }
                .font(PeezyTheme.Typography.body)
                .foregroundColor(.white)
                .tint(accentBlue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 52)
            .background(
                ZStack {
                    // Glass blur effect
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // Charcoal tint
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(charcoalColor.opacity(0.6))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(strokeColor, lineWidth: hasError || isFocused ? 2 : 1)
            )
            .shadow(color: shadowColor, radius: 10, y: 5)

            if let error = error, !error.isEmpty {
                Text(error)
                    .font(PeezyTheme.Typography.footnote)
                    .foregroundColor(PeezyTheme.Colors.emotionalRed)
            } else if let helper = helper, !helper.isEmpty {
                Text(helper)
                    .font(PeezyTheme.Typography.footnote)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    VStack(spacing: 20) {
        PeezyFormField2(
            label: "Email",
            placeholder: "name@domain.com",
            text: $text,
            contentType: .emailAddress,
            keyboardType: .emailAddress,
            autocapitalization: .never,
            disableAutocorrection: true
        )
        PeezyFormField2(
            label: "Password",
            placeholder: "••••••••",
            text: $text,
            isSecure: true,
            helper: "Use 8+ characters",
            contentType: .password
        )
        PeezyFormField2(
            label: "Error example",
            placeholder: "Type here",
            text: $text,
            error: "This field is required"
        )
    }
    .padding()
}
