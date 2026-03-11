//
//  SingleSelectTemplate.swift
//  Peezy
//
//  Complete page template for 2-option single-select assessment questions.
//  ALL layout values are in the CONTROL BOARD below. Change a number, see it in preview.
//

import SwiftUI

struct SingleSelectTemplate: View {

    // ╔═══════════════════════════════════════════════════════════╗
    // ║  CONTENT — passed from the question file                 ║
    // ╚═══════════════════════════════════════════════════════════╝
    let header: String
    let subtext: String?
    let options: [String]
    let icons: [String]
    let selected: String
    let onSelect: (String) -> Void

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
    var morphBottomPad: CGFloat = 40    //  space between text and tiles
    // ║                                                          ║
    // ║  TILES                                                   ║
    var tilePadH: CGFloat = 20          //  tiles outer side padding
    var tileSpacing: CGFloat = 16       //  space between tiles
    // ║                                                          ║
    // ║  TIMING                                                  ║
    var morphDelay: Double = 0.4        //  pause after typing before morph
    var tileStagger: Double = 0.1       //  delay between each tile appearing
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
    @State private var isHero = true
    @State private var skipped = false
    @State private var showTiles = false

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    // ── BODY ────────────────────────────────────────────────────
    var body: some View {
        ZStack {
            InteractiveBackground()

            VStack(spacing: 0) {

                if isHero { Spacer() }

                // ── TEXT AREA ──
                VStack(spacing: 8) {

                    // Header
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

                    // Subtext
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

                // Push tiles to vertical center of remaining space
                if !isHero && showControls { Spacer() }

                // ── TILES ──
                if showControls {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: tileSpacing),
                            GridItem(.flexible(), spacing: tileSpacing)
                        ],
                        spacing: tileSpacing
                    ) {
                        ForEach(Array(options.enumerated()), id: \.element) { index, option in
                            SelectionTile(
                                title: option,
                                icon: index < icons.count ? icons[index] : nil,
                                isSelected: selected == option,
                                onTap: { onSelect(option) }
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

                if !isHero { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { skipToControls() }
    }

    // ── MORPH LOGIC (don't touch) ───────────────────────────────

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showTiles = true
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
    SingleSelectTemplate(
        header: "Would you like quotes for professional movers?",
        subtext: nil,
        options: ["Yes", "No"],
        icons: ["hand.thumbsup.fill", "hand.thumbsdown.fill"],
        selected: "",
        onSelect: { print("Selected: \($0)") }
    )
}
