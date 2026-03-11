//
//  GridSelectTemplate.swift
//  Peezy
//
//  Template for 3+ option grid-select assessment questions.
//  Same typewriter + morph as SingleSelectTemplate but supports
//  variable column count and auto-advance on tap.
//

import SwiftUI

struct GridSelectTemplate: View {

    // ═══════════════════════════════════════════
    //  CONTENT
    // ═══════════════════════════════════════════
    let header: String
    let subtext: String?
    let options: [String]
    let icons: [String]
    let subtitles: [String]
    let speed: Double
    let columns: Int
    let selected: String
    let onSelect: (String) -> Void

    init(
        header: String,
        subtext: String? = nil,
        options: [String],
        icons: [String] = [],
        subtitles: [String] = [],
        speed: Double = 0.04,
        columns: Int = 2,
        selected: String,
        onSelect: @escaping (String) -> Void
    ) {
        self.header = header
        self.subtext = subtext
        self.options = options
        self.icons = icons
        self.subtitles = subtitles
        self.speed = speed
        self.columns = columns
        self.selected = selected
        self.onSelect = onSelect
    }

    // ═══════════════════════════════════════════
    //  LAYOUT
    // ═══════════════════════════════════════════
    private let heroFontSize: CGFloat = 32
    private let morphedFontSize: CGFloat = 22
    private let horizontalPadding: CGFloat = 24
    private let tileGridSpacing: CGFloat = 16
    private let tilePadding: CGFloat = 20
    private let morphTopPadding: CGFloat = 24
    private let morphBottomPadding: CGFloat = 40

    // ═══════════════════════════════════════════
    //  STATE
    // ═══════════════════════════════════════════
    @State private var headerDone = false
    @State private var subtextDone = false
    @State private var showControls = false
    @State private var isHero = true
    @State private var skipped = false
    @State private var showTiles = false

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: tileGridSpacing), count: columns)
    }

    // ═══════════════════════════════════════════
    //  BODY
    // ═══════════════════════════════════════════
    var body: some View {
        ZStack {
            InteractiveBackground()

            VStack(spacing: 0) {
                if isHero { Spacer() }

                // Text area
                VStack(spacing: 8) {
                    Group {
                        if skipped {
                            Text(header)
                        } else {
                            TypingText(fullText: header, speed: speed, visibleColor: PeezyTheme.Colors.deepInk, onComplete: {
                                headerDone = true
                                if subtext == nil { triggerMorph() }
                            })
                        }
                    }
                    .font(.system(size: isHero ? heroFontSize : morphedFontSize, weight: .semibold))
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .lineSpacing(4)
                    .multilineTextAlignment(isHero ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: isHero ? .center : .leading)

                    if let sub = subtext {
                        if headerDone || skipped {
                            Group {
                                if skipped {
                                    Text(sub)
                                } else {
                                    TypingText(fullText: sub, speed: speed, visibleColor: PeezyTheme.Colors.deepInk.opacity(0.5), onComplete: {
                                        subtextDone = true
                                        triggerMorph()
                                    })
                                }
                            }
                            .font(.system(size: isHero ? 16 : 14))
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .lineSpacing(3)
                            .multilineTextAlignment(isHero ? .center : .leading)
                            .frame(maxWidth: .infinity, alignment: isHero ? .center : .leading)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, isHero ? 0 : morphTopPadding)
                .padding(.bottom, isHero ? 0 : morphBottomPadding)

                if isHero { Spacer() }

                // Tiles
                if showControls {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: gridColumns, spacing: tileGridSpacing) {
                            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                                SelectionTile(
                                    title: option,
                                    subtitle: index < subtitles.count ? subtitles[index] : nil,
                                    icon: index < icons.count ? icons[index] : nil,
                                    isSelected: selected == option,
                                    onTap: { onSelect(option) }
                                )
                                .opacity(showTiles ? 1 : 0)
                                .offset(y: showTiles ? 0 : 30)
                                .animation(.easeOut(duration: 0.5).delay(0.1 + Double(index) * 0.08), value: showTiles)
                            }
                        }
                        .padding(.horizontal, tilePadding)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if !isHero { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { skipToControls() }
    }

    // ═══════════════════════════════════════════
    //  MORPH
    // ═══════════════════════════════════════════
    private func triggerMorph() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard isHero else { return }
            performMorph()
        }
    }

    private func performMorph() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { isHero = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.35)) { showControls = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showTiles = true }
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

#Preview {
    GridSelectTemplate(
        header: "What kind of place are you in now?",
        options: ["House", "Apartment", "Condo", "Townhouse"],
        icons: ["house.fill", "building.2.fill", "building.fill", "house.and.flag.fill"],
        selected: "",
        onSelect: { print($0) }
    )
}
