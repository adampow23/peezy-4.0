//
//  DatePickerTemplate.swift
//  Peezy
//
//  Complete page template for date picker assessment questions.
//  Typewriter + morph, then inline date wheel centered, Continue button at bottom.
//  ALL layout values are in the CONTROL BOARD below.
//

import SwiftUI

struct DatePickerTemplate: View {

    // ╔═══════════════════════════════════════════════════════════╗
    // ║  CONTENT — passed from the question file                 ║
    // ╚═══════════════════════════════════════════════════════════╝
    let header: String
    let subtext: String?
    let date: Binding<Date>
    let buttonText: String
    let onContinue: () -> Void

    // ╔═══════════════════════════════════════════════════════════╗
    // ║  CONTROL BOARD — change any number, see it in preview    ║
    // ╠═══════════════════════════════════════════════════════════╣
    // ║                                                          ║
    // ║  TYPEWRITER                                              ║
    var speed: Double = 0.04            //  seconds per character
    // ║                                                          ║
    // ║  HERO STATE (centered, large)                            ║
    var heroFontSize: CGFloat = 32      //  header text size
    var heroSubtextSize: CGFloat = 16   //  subtext size
    // ║                                                          ║
    // ║  MORPHED STATE (top-left, small)                         ║
    var morphedFontSize: CGFloat = 22   //  header after morph
    var morphedSubtextSize: CGFloat = 14 // subtext after morph
    var morphTopPad: CGFloat = 24       //  space above text
    var morphBottomPad: CGFloat = 40    //  space between text and picker
    // ║                                                          ║
    // ║  DATE PICKER                                             ║
    var pickerPadH: CGFloat = 24        //  picker side padding
    // ║                                                          ║
    // ║  BUTTON                                                  ║
    var buttonPadH: CGFloat = 24        //  button side padding
    var buttonPadBottom: CGFloat = 32   //  button bottom padding
    // ║                                                          ║
    // ║  TIMING                                                  ║
    var morphDelay: Double = 0.4        //  pause after typing before morph
    // ║                                                          ║
    // ║  TEXT                                                     ║
    var textSidePad: CGFloat = 24       //  text left/right padding
    var lineSpacing: CGFloat = 4        //  header line spacing
    var subtextLineSpacing: CGFloat = 3 //  subtext line spacing
    // ║                                                          ║
    // ╚═══════════════════════════════════════════════════════════╝

    // ── ANIMATION STATE (don't touch) ───────────────────────────
    @State private var headerDone = false
    @State private var subtextDone = false
    @State private var showControls = false
    @State private var isHero = true
    @State private var skipped = false

    // ── BODY ────────────────────────────────────────────────────
    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea(.keyboard)

            VStack(spacing: 0) {

                if isHero { Spacer() }

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
                    .font(.system(size: isHero ? heroFontSize : morphedFontSize, weight: .semibold))
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .lineSpacing(lineSpacing)
                    .multilineTextAlignment(isHero ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: isHero ? .center : .leading)

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
                            .font(.system(size: isHero ? heroSubtextSize : morphedSubtextSize))
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .lineSpacing(subtextLineSpacing)
                            .multilineTextAlignment(isHero ? .center : .leading)
                            .frame(maxWidth: .infinity, alignment: isHero ? .center : .leading)
                        }
                    }
                }
                .padding(.horizontal, textSidePad)
                .padding(.top, isHero ? 0 : morphTopPad)
                .padding(.bottom, isHero ? 0 : morphBottomPad)

                if isHero { Spacer() }

                // Center picker between header and button
                if !isHero && showControls { Spacer() }

                // ── DATE PICKER ──
                if showControls {
                    DatePicker("", selection: date, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .padding(.horizontal, pickerPadH)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if !isHero && showControls { Spacer() }

                // ── CONTINUE BUTTON ──
                if showControls {
                    PeezyAssessmentButton(buttonText) {
                        onContinue()
                    }
                    .padding(.horizontal, buttonPadH)
                    .padding(.bottom, buttonPadBottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { skipToControls() }
    }

    // ── MORPH LOGIC ─────────────────────────────────────────────

    private func triggerMorph() {
        DispatchQueue.main.asyncAfter(deadline: .now() + morphDelay) {
            guard isHero else { return }
            performMorph()
        }
    }

    private func performMorph() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            isHero = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.35)) {
                showControls = true
            }
        }
    }

    private func skipToControls() {
        guard isHero else { return }
        skipped = true
        headerDone = true
        subtextDone = true
        performMorph()
    }
}

// ── PREVIEW ─────────────────────────────────────────────────
#Preview {
    @Previewable @State var date = Date()
    DatePickerTemplate(
        header: "When's the big day?",
        subtext: "I'll build your timeline around this date.",
        date: $date,
        buttonText: "Continue",
        onContinue: { print("Date: \(date)") }
    )
}
