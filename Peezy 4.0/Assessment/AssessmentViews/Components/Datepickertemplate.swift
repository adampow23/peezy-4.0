//
//  DatePickerTemplate.swift
//  Peezy
//
//  Complete page template for date picker assessment questions.
//  Typewriter + morph, then native graphical date picker in a glass card, Continue button at bottom.
//  ALL layout values are in the CONTROL BOARD below.
//

import SwiftUI

// MARK: - Date Picker Template (Native Graphical Version)
struct DatePickerTemplate: View {

    let header: String
    let subtext: String?
    @Binding var date: Date
    let buttonText: String
    let onContinue: () -> Void

    // ── CONTROL BOARD ──
    var speed: Double = 0.04
    var heroFontSize: CGFloat = 32
    var heroSubtextSize: CGFloat = 16
    var morphedFontSize: CGFloat = 22
    var morphedSubtextSize: CGFloat = 14
    var morphTopPad: CGFloat = 24
    var morphBottomPad: CGFloat = 24
    var textSidePad: CGFloat = 24
    var morphDelay: Double = 0.4

    // ── STATE ──
    @State private var headerDone = false
    @State private var subtextDone = false
    @State private var showControls = false
    @State private var isHero = false
    @State private var skipped = false
    @State private var dateWasSelected = false

    var body: some View {
        ZStack {
            InteractiveBackground()

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
                    .font(.system(size: isHero ? heroFontSize : morphedFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
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
                            .font(.system(size: isHero ? heroSubtextSize : morphedSubtextSize, design: .rounded))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .multilineTextAlignment(isHero ? .center : .leading)
                            .frame(maxWidth: .infinity, alignment: isHero ? .center : .leading)
                        }
                    }
                }
                .padding(.horizontal, textSidePad)
                .padding(.top, isHero ? 0 : morphTopPad)
                .padding(.bottom, isHero ? 0 : morphBottomPad)
                .contentShape(Rectangle())
                .onTapGesture {
                    skipToControls()
                }

                if isHero { Spacer() }
                if !isHero && showControls { Spacer(minLength: 16) }

                // ── NATIVE DATE PICKER IN GLASS CARD ──
                if showControls {
                    DatePicker(
                        "Select Move Date",
                        selection: $date,
                        in: Date()...,
                        displayedComponents: [.date]
                    )
                    .onChange(of: date) { _, _ in
                        dateWasSelected = true
                    }
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(PeezyTheme.Colors.deepInk)
                    .padding(16)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.regularMaterial)
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.white.opacity(0.6))
                        }
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.03), radius: 20, y: 10)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if !isHero && showControls { Spacer(minLength: 32) }

                // ── CONTINUE BUTTON ──
                if showControls {
                    PeezyAssessmentButton(buttonText, disabled: !dateWasSelected) {
                        onContinue()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // ── MORPH LOGIC ──

    private func triggerMorph() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.35)) {
                showControls = true
            }
        }
    }

    private func performMorph() {
        withAnimation(.easeOut(duration: 0.35)) {
            showControls = true
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
    }
}

// ── PREVIEW ──
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
