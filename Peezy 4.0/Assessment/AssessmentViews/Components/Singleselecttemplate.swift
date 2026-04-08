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
    // ║  CONTENT — passed from the question file                  ║
    // ╚═══════════════════════════════════════════════════════════╝
    let header: String
    let subtext: String?
    let options: [String]
    let icons: [String]
    let selected: String
    let onSelect: (String) -> Void

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
    var morphBottomPad: CGFloat = 40    //  space between text and tiles
    // ║                                                           ║
    // ║  TILES                                                    ║
    var tilePadH: CGFloat = 24          // UX Fix: Standardized 20 -> 24pt for grid alignment
    var tileSpacing: CGFloat = 16       //  space between tiles
    // ║                                                           ║
    // ║  TIMING                                                   ║
    var morphDelay: Double = 0.4        //  pause after typing before morph
    var tileStagger: Double = 0.1       //  delay between each tile appearing
    // ║                                                           ║
    // ║  TEXT                                                     ║
    var textSidePad: CGFloat = 24       //  text left/right padding
    var lineSpacing: CGFloat = 4        //  space between lines of header
    var subtextLineSpacing: CGFloat = 3 //  space between lines of subtext
    // ║                                                           ║
    // ╚═══════════════════════════════════════════════════════════╝

    // ── ANIMATION STATE (don't touch) ───────────────────────────
    @State private var headerDone = false
    @State private var subtextDone = false
    @State private var showControls = false
    @State private var skipped = false
    @State private var showTiles = false

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    // ── BODY ────────────────────────────────────────────────────
    var body: some View {
        ZStack {
            InteractiveBackground()

            VStack(spacing: 0) {

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
                    // UX Fix: Swapped .semibold to .heavy to match primary app typography
                    .font(.system(size: morphedFontSize, weight: .heavy))
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .lineSpacing(lineSpacing)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

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

                // Push tiles to vertical center of remaining space
                if showControls { Spacer() }

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
                            .animation(
                                .easeOut(duration: 0.5).delay(tileStagger + Double(index) * tileStagger),
                                value: showTiles
                            )
                        }
                    }
                    .padding(.horizontal, tilePadH)
                    .transition(.opacity)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { skipToControls() }
    }

    // ── MORPH LOGIC (don't touch) ───────────────────────────────

    private func triggerMorph() {
        Task {
            try? await Task.sleep(for: .seconds(0.2))
            withAnimation(.easeOut(duration: 0.35)) {
                showControls = true
                showTiles = true
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
            showTiles = true
        }
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
