//
//  TextEntryTemplate.swift
//  Peezy
//
//  Complete page template for text entry assessment questions.
//  Keyboard opens simultaneously with field animation — one fluid motion.
//  ALL layout values are in the CONTROL BOARD below.
//

import SwiftUI

struct TextEntryTemplate: View {

    // ╔═══════════════════════════════════════════════════════════╗
    // ║  CONTENT — passed from the question file                  ║
    // ╚═══════════════════════════════════════════════════════════╝
    let header: String
    let subtext: String?
    let placeholder: String
    let text: Binding<String>
    let buttonText: String
    let onContinue: () -> Void

    // ╔═══════════════════════════════════════════════════════════╗
    // ║  CONTROL BOARD — change any number, see it in preview     ║
    // ╠═══════════════════════════════════════════════════════════╣
    var heroFontSize: CGFloat = 34
    var heroSubtextSize: CGFloat = 16
    var morphedFontSize: CGFloat = 24
    var morphedSubtextSize: CGFloat = 14
    var morphTopPad: CGFloat = 24
    var morphBottomPad: CGFloat = 40
    var fieldFontSize: CGFloat = 22
    var fieldPadH: CGFloat = 24
    var fieldHeight: CGFloat = 52
    var fieldCorner: CGFloat = 16
    var buttonPadH: CGFloat = 24
    var buttonPadBottom: CGFloat = 24
    var morphDelay: Double = 0.4
    var textSidePad: CGFloat = 24
    var lineSpacing: CGFloat = 4
    var subtextLineSpacing: CGFloat = 3
    var keyboardType: UIKeyboardType = .default
    var autocap: TextInputAutocapitalization = .words
    var disableAutocorrect: Bool = false
    var contentType: UITextContentType? = nil
    // ╚═══════════════════════════════════════════════════════════╝

    @State private var showControls = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea(.keyboard)

            VStack(spacing: 0) {

                // ── TEXT AREA ──
                VStack(spacing: 8) {
                    Text(header)
                        .font(.system(size: morphedFontSize, weight: .heavy))
                        .foregroundColor(PeezyTheme.Colors.deepInk)
                        .lineSpacing(lineSpacing)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let sub = subtext {
                        Text(sub)
                            .font(.system(size: morphedSubtextSize, weight: .medium))
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .lineSpacing(subtextLineSpacing)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, textSidePad)
                .padding(.top, morphTopPad)
                .padding(.bottom, morphBottomPad)

                if showControls { Spacer() }

                // ── TEXT FIELD ──
                if showControls {
                    TextField("", text: text, prompt: Text(placeholder).foregroundColor(Color.gray.opacity(0.5)))
                        .font(.system(size: fieldFontSize, weight: .medium))
                        .foregroundColor(PeezyTheme.Colors.deepInk)
                        .tint(PeezyTheme.Colors.accentBlue)
                        .multilineTextAlignment(.center)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(autocap)
                        .autocorrectionDisabled(disableAutocorrect)
                        .textContentType(contentType)
                        .focused($isFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(minHeight: fieldHeight)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: fieldCorner, style: .continuous)
                                    .fill(.regularMaterial)
                                RoundedRectangle(cornerRadius: fieldCorner, style: .continuous)
                                    .fill(Color.black.opacity(0.06))
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: fieldCorner, style: .continuous)
                                .stroke(
                                    isFocused ? PeezyTheme.Colors.accentBlue.opacity(0.6) : Color.black.opacity(0.1),
                                    lineWidth: isFocused ? 2 : 1
                                )
                        )
                        .shadow(
                            color: isFocused ? PeezyTheme.Colors.accentBlue.opacity(0.2) : Color.black.opacity(0.1),
                            radius: 10, y: 5
                        )
                        .padding(.horizontal, fieldPadH)
                        .transition(.opacity)
                }

                if showControls { Spacer() }

                // ── CONTINUE BUTTON ──
                if showControls {
                    PeezyAssessmentButton(buttonText, disabled: text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        onContinue()
                    }
                    .padding(.horizontal, buttonPadH)
                    .padding(.bottom, buttonPadBottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = false }
        .onAppear { triggerMorph() }
    }

    // ── MORPH LOGIC ─────────────────────────────────────────────
    // Field + button animate in AND keyboard opens in one motion.

    private func triggerMorph() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.3)) {
                showControls = true
            }
            // Focus immediately — keyboard animates up with the field
            isFocused = true
        }
    }
}

// ── PREVIEW ─────────────────────────────────────────────────
#if DEBUG
#Preview {
    @Previewable @State var name = ""
    TextEntryTemplate(
        header: "What's your first name?",
        subtext: nil,
        placeholder: "First name",
        text: $name,
        buttonText: "Continue",
        onContinue: { print("Continue with: \(name)") }
    )
}
#endif
