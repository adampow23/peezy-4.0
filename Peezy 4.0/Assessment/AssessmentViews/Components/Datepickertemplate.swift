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
    var heroFontSize: CGFloat = 34        // UX Fix: Standardized to 34pt Large Title
    var heroSubtextSize: CGFloat = 16
    var morphedFontSize: CGFloat = 24     // UX Fix: Bumped to 24pt for better hierarchy
    var morphedSubtextSize: CGFloat = 14
    var morphTopPad: CGFloat = 24
    var morphBottomPad: CGFloat = 24
    var textSidePad: CGFloat = 24
    var morphDelay: Double = 0.4

    // ── STATE ──
    @State private var headerDone = false
    @State private var subtextDone = false
    @State private var showControls = false
    @State private var skipped = false
    @State private var dateWasSelected = false

    var body: some View {
        ZStack {
            InteractiveBackground()

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
                    // UX Fix: Swapped .semibold to .heavy, removed rogue .rounded design
                    .font(.system(size: morphedFontSize, weight: .heavy))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
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
                            // UX Fix: Added .medium weight, removed rogue .rounded design
                            .font(.system(size: morphedSubtextSize, weight: .medium))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, textSidePad)
                .padding(.top, morphTopPad)
                .padding(.bottom, morphBottomPad)
                .contentShape(Rectangle())
                .onTapGesture {
                    skipToControls()
                }

                if showControls { Spacer(minLength: 16) }

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
                    .transition(.opacity)
                }

                if showControls { Spacer(minLength: 32) }

                // ── CONTINUE BUTTON ──
                if showControls {
                    PeezyAssessmentButton(buttonText, disabled: !dateWasSelected) {
                        onContinue()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24) // UX Fix: Standardized 32 -> 24pt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // ── MORPH LOGIC ──

    private func triggerMorph() {
        Task {
            try? await Task.sleep(for: .seconds(0.2))
            withAnimation(.easeOut(duration: 0.35)) {
                showControls = true
            }
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
