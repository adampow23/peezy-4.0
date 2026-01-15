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

    private var hasError: Bool { !(error ?? "").isEmpty }

    private var strokeColor: Color {
        if hasError { return PeezyTheme.Colors.emotionalRed }
        if isFocused { return PeezyTheme.Colors.brandYellow.opacity(0.9) }
        return Color.clear
    }

    private var shadowColor: Color {
        if hasError { return PeezyTheme.Colors.emotionalRed.opacity(0.12) }
        if isFocused { return PeezyTheme.Shadows.brandGlow(opacity: 0.25) }
        return Color.clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label = label, !label.isEmpty {
                Text(label)
                    .font(PeezyTheme.Typography.callout)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                if let icon = leadingIcon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isFocused ? PeezyTheme.Colors.brandYellow : .secondary)
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
                .foregroundColor(.primary)
                .tint(PeezyTheme.Colors.brandYellow)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusFixed, style: .continuous)
                    .fill(PeezyTheme.Colors.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusFixed, style: .continuous)
                    .stroke(strokeColor, lineWidth: hasError || isFocused ? 2 : 1)
            )
            .shadow(color: shadowColor, radius: 12, y: 6)

            if let error = error, !error.isEmpty {
                Text(error)
                    .font(PeezyTheme.Typography.footnote)
                    .foregroundColor(PeezyTheme.Colors.emotionalRed)
            } else if let helper = helper, !helper.isEmpty {
                Text(helper)
                    .font(PeezyTheme.Typography.footnote)
                    .foregroundColor(.secondary)
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
