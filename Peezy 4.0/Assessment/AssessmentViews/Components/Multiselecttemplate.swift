//
//  MultiSelectTemplate.swift
//  Peezy
//
//  Complete page template for multi-select assessment questions.
//  Vertical list of toggleable tiles with checkmarks or count badges.
//  Continue button pinned at bottom. Tiles centered between header and button.
//  ALL layout values are in the CONTROL BOARD below.
//

import SwiftUI

struct MultiSelectTemplate: View {

    // ╔═══════════════════════════════════════════════════════════╗
    // ║  CONTENT — passed from the question file                 ║
    // ╚═══════════════════════════════════════════════════════════╝
    let header: String
    let subtext: String?
    let options: [(String, String)]          // (label, SF Symbol icon)
    let selected: Set<String>
    let buttonText: String
    let onToggle: (String) -> Void
    let onContinue: () -> Void
    var counts: [String: Int] = [:]          // optional — enables number badges
    var onIncrement: ((String) -> Void)? = nil
    var onDecrement: ((String) -> Void)? = nil

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
    var morphBottomPad: CGFloat = 24    //  space between text and tiles
    // ║                                                          ║
    // ║  TILES                                                   ║
    var tilePadH: CGFloat = 20          //  tiles outer side padding
    var tileSpacing: CGFloat = 12       //  space between tiles
    // ║                                                          ║
    // ║  BUTTON                                                  ║
    var buttonPadH: CGFloat = 24        //  button side padding
    var buttonPadBottom: CGFloat = 32   //  button bottom padding
    // ║                                                          ║
    // ║  TIMING                                                  ║
    var morphDelay: Double = 0.4        //  pause after typing before morph
    var tileStagger: Double = 0.06      //  delay between each tile appearing
    // ║                                                          ║
    // ║  TEXT                                                     ║
    var textSidePad: CGFloat = 24       //  text left/right padding
    var lineSpacing: CGFloat = 4        //  space between lines of header
    var subtextLineSpacing: CGFloat = 3 //  space between lines of subtext
    // ║                                                          ║
    // ╚═══════════════════════════════════════════════════════════╝

    // ── ANIMATION STATE (don't touch) ───────────────────────────
    @State private var headerDone = false
    @State private var subtextDone = false
    @State private var showControls = false
    @State private var isHero = false
    @State private var skipped = false
    @State private var showTiles = false

    // ── BODY ────────────────────────────────────────────────────
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

                // Center tiles between header and button
                if !isHero && showControls { Spacer() }

                // ── TILES ──
                if showControls {
                    VStack(spacing: tileSpacing) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            MultiSelectTile(
                                title: option.0,
                                icon: option.1,
                                isSelected: selected.contains(option.0),
                                onTap: { onToggle(option.0) },
                                count: counts[option.0] ?? 0,
                                onIncrement: { onIncrement?(option.0) },
                                onDecrement: { onDecrement?(option.0) }
                            )
                            .opacity(showTiles ? 1 : 0)
                            .offset(y: showTiles ? 0 : 30)
                            .animation(
                                .easeOut(duration: 0.5).delay(tileStagger + Double(index) * tileStagger),
                                value: showTiles
                            )
                        }
                    }
                    .padding(.horizontal, tilePadH)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Push button to bottom
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

    // ── MORPH LOGIC (don't touch) ───────────────────────────────

    private func triggerMorph() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.35)) {
                showControls = true
                showTiles = true
            }
        }
    }

    private func performMorph() {
        withAnimation(.easeOut(duration: 0.35)) {
            showControls = true
            showTiles = true
        }
    }

    private func skipToControls() {
        guard !showControls else { return }
        skipped = true
        headerDone = true
        subtextDone = true
        withAnimation(.easeOut(duration: 0.2)) {
            showControls = true
            showTiles = true
        }
    }
}

// ── PREVIEW ─────────────────────────────────────────────────
#Preview {
    MultiSelectTemplate(
        header: "Which financial accounts do you have?",
        subtext: "Tap once for each. Tap again to add more.",
        options: [
            ("Bank / Credit Union", "building.columns.fill"),
            ("Credit Card", "creditcard.fill"),
            ("Investment Account", "chart.line.uptrend.xyaxis"),
            ("Student Loans", "graduationcap.fill")
        ],
        selected: ["Bank / Credit Union", "Credit Card"],
        buttonText: "Continue",
        onToggle: { print("Toggled: \($0)") },
        onContinue: { print("Continue") },
        counts: ["Bank / Credit Union": 2, "Credit Card": 1]
    )
}
