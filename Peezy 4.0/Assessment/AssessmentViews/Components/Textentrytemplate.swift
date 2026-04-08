//
//  TextEntryTemplate.swift
//  Peezy
//
//  Complete page template for text entry assessment questions.
//  Keyboard auto-opens when morph completes. SwiftUI handles keyboard avoidance
//  natively — no manual KeyboardObserver needed. Spacers compress to keep
//  the text field centered and button above the keyboard.
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
    // ║                                                           ║
    // ║  TYPEWRITER                                               ║
    var speed: Double = 0.04            //  seconds per character
    // ║                                                           ║
    // ║  HERO STATE (centered, large)                             ║
    var heroFontSize: CGFloat = 34      // UX Fix: Standardized to 34pt Large Title
    var heroSubtextSize: CGFloat = 16   //  subtext size
    // ║                                                           ║
    // ║  MORPHED STATE (top-left, small)                          ║
    var morphedFontSize: CGFloat = 24   // UX Fix: Bumped to 24pt for better hierarchy
    var morphedSubtextSize: CGFloat = 14 // subtext after morph
    var morphTopPad: CGFloat = 24       //  space above text
    var morphBottomPad: CGFloat = 40    //  space between text and field
    // ║                                                           ║
    // ║  TEXT FIELD                                               ║
    var fieldFontSize: CGFloat = 22     //  text field font size
    var fieldPadH: CGFloat = 24         //  field side padding
    var fieldHeight: CGFloat = 52       //  minimum field height
    var fieldCorner: CGFloat = 16       //  field corner radius
    // ║                                                           ║
    // ║  BUTTON                                                   ║
    var buttonPadH: CGFloat = 24        //  button side padding
    var buttonPadBottom: CGFloat = 24   // UX Fix: Standardized 32 -> 24pt
    // ║                                                           ║
    // ║  TIMING                                                   ║
    var morphDelay: Double = 0.4        //  pause after typing before morph
    // ║                                                           ║
    // ║  TEXT                                                     ║
    var textSidePad: CGFloat = 24       //  text left/right padding
    var lineSpacing: CGFloat = 4        //  header line spacing
    var subtextLineSpacing: CGFloat = 3 //  subtext line spacing
    // ║                                                           ║
    // ║  KEYBOARD                                                 ║
    var keyboardType: UIKeyboardType = .default
    var autocap: TextInputAutocapitalization = .words
    var disableAutocorrect: Bool = false
    var contentType: UITextContentType? = nil
    // ║                                                           ║
    // ╚═══════════════════════════════════════════════════════════╝

    // ── STATE (don't touch) ─────────────────────────────────────
    @State private var headerDone = false
    @State private var subtextDone = false
    @State private var showControls = false
    @State private var skipped = false
    @FocusState private var isFocused: Bool

    // ── BODY ────────────────────────────────────────────────────
    var body: some View {
        ZStack {
            // Background ignores keyboard so it doesn't squish
            InteractiveBackground()
                .ignoresSafeArea(.keyboard)

            VStack(spacing: 0) {

                // ── TEXT AREA ──
                VStack(spacing: 8) {
                    Group {
                        if skipped {
                            Text(header)
                        } else {
                            TypingText(
                                fullText: header,
                                speed: speed,
                                visibleColor: PeezyTheme.Colors.deepInk,
                                onComplete: {
                                    headerDone = true
                                    if subtext == nil { triggerMorph() }
                                }
                            )
                        }
                    }
                    // UX Fix: Swapped .semibold to .heavy to match primary app typography
                    .font(.system(size: morphedFontSize, weight: .heavy))
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .lineSpacing(lineSpacing)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let sub = subtext {
                        if headerDone || skipped {
                            Group {
                                if skipped {
                                    Text(sub)
                                } else {
                                    TypingText(
                                        fullText: sub,
                                        speed: speed,
                                        visibleColor: PeezyTheme.Colors.deepInk.opacity(0.5),
                                        onComplete: {
                                            subtextDone = true
                                            triggerMorph()
                                        }
                                    )
                                }
                            }
                            // UX Fix: Added .medium weight to match 16pt body text standard
                            .font(.system(size: morphedSubtextSize, weight: .medium))
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .lineSpacing(subtextLineSpacing)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, textSidePad)
                .padding(.top, morphTopPad)
                .padding(.bottom, morphBottomPad)

                // Center text field between header and button
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
    }

    // ── MORPH LOGIC ─────────────────────────────────────────────

    private func triggerMorph() {
        Task {
            try? await Task.sleep(for: .seconds(0.2))
            withAnimation(.easeOut(duration: 0.35)) {
                showControls = true
            }
            try? await Task.sleep(for: .seconds(0.2))
            isFocused = true
        }
    }

    private func skipToControls() {
        guard !showControls else { return }
        skipped = true
        headerDone = true
        subtextDone = true
        withAnimation(.easeOut(duration: 0.2)) {
            showControls = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isFocused = true
        }
    }
}

// ── PREVIEW ─────────────────────────────────────────────────
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
