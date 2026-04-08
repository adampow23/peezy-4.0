//
//  ExplainerTemplate.swift
//  Peezy
//
//  Full-page template for transition/explainer screens.
//  Shows an icon, typewriter header + subtext, and Continue button.
//  No morph — everything stays centered. Button appears after typing.
//  ALL layout values are in the CONTROL BOARD below.
//

import SwiftUI

struct ExplainerTemplate: View {

    // ╔═══════════════════════════════════════════════════════════╗
    // ║  CONTENT — passed from the question file                  ║
    // ╚═══════════════════════════════════════════════════════════╝
    let icon: String
    let header: String
    let subtext: String?
    let buttonText: String
    let onContinue: () -> Void

    // ╔═══════════════════════════════════════════════════════════╗
    // ║  CONTROL BOARD — change any number, see it in preview     ║
    // ╠═══════════════════════════════════════════════════════════╣
    // ║                                                           ║
    // ║  TYPEWRITER                                               ║
    var speed: Double = 0.04            //  seconds per character
    // ║                                                           ║
    // ║  ICON                                                     ║
    var iconSize: CGFloat = 72          // UX Fix: Standardized to 72pt to match SubmittedView hero icons
    var iconColor: Color = PeezyTheme.Colors.deepInk.opacity(0.3)
    var iconBottomPad: CGFloat = 24     //  space between icon and header
    // ║                                                           ║
    // ║  TEXT                                                     ║
    var headerFontSize: CGFloat = 34    // UX Fix: Standardized to 34pt Large Title
    var subtextFontSize: CGFloat = 16   //  subtext size (Already correct at 16pt!)
    var textSidePad: CGFloat = 24       //  text left/right padding (Already correct at 24pt!)
    var lineSpacing: CGFloat = 4        //  header line spacing
    var subtextLineSpacing: CGFloat = 3 //  subtext line spacing
    var subtextTopPad: CGFloat = 12     //  space between header and subtext
    // ║                                                           ║
    // ║  BUTTON                                                   ║
    var buttonPadH: CGFloat = 24        //  button side padding
    var buttonPadBottom: CGFloat = 24   // UX Fix: Standardized to 24pt bottom margin
    // ║                                                           ║
    // ╚═══════════════════════════════════════════════════════════╝

    // ── STATE ───────────────────────────────────────────────────
    @State private var showIcon = false
    @State private var headerDone = false
    @State private var subtextDone = false
    @State private var showButton = false
    @State private var skipped = false

    // ── BODY ────────────────────────────────────────────────────
    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea(.keyboard)

            VStack(spacing: 0) {

                Spacer()

                // ── ICON ──
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(iconColor)
                    .opacity(showIcon ? 1 : 0)
                    .scaleEffect(showIcon ? 1 : 0.5)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showIcon)
                    .padding(.bottom, iconBottomPad)

                // ── HEADER ──
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
                                if subtext == nil { revealButton() }
                            }
                        )
                    }
                }
                // UX Fix: Standardized to .heavy weight to match all primary titles
                .font(.system(size: headerFontSize, weight: .heavy))
                .foregroundColor(PeezyTheme.Colors.deepInk)
                .lineSpacing(lineSpacing)
                .multilineTextAlignment(.center)
                .padding(.horizontal, textSidePad)

                // ── SUBTEXT ──
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
                                        revealButton()
                                    }
                                )
                            }
                        }
                        // UX Fix: Added .medium weight to match 16pt body text standard
                        .font(.system(size: subtextFontSize, weight: .medium))
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .lineSpacing(subtextLineSpacing)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, textSidePad)
                        .padding(.top, subtextTopPad)
                    }
                }

                Spacer()

                // ── CONTINUE BUTTON ──
                if showButton || skipped {
                    PeezyAssessmentButton(buttonText) {
                        onContinue()
                    }
                    .padding(.horizontal, buttonPadH)
                    .padding(.bottom, buttonPadBottom)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .onAppear {
            withAnimation { showIcon = true }
        }
    }

    // ── HELPERS ─────────────────────────────────────────────────

    private func revealButton() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.35)) {
                showButton = true
            }
        }
    }

    private func skip() {
        guard !skipped else { return }
        skipped = true
        headerDone = true
        subtextDone = true
        showButton = true
    }
}

// ── PREVIEW ─────────────────────────────────────────────────
#Preview {
    ExplainerTemplate(
        icon: "hammer.fill",
        header: "Let's Start with Common Moving Services",
        subtext: "When moving, there are countless services you might need, but we'll begin by discussing the most common ones—movers, packers, cleaners, and more.",
        buttonText: "Continue",
        onContinue: { print("Continue") }
    )
}
