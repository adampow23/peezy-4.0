# Design System: Peezy

**Version**: 1.0.0  
**Last Updated**: 2026-04-14  
**Status**: Draft  
**Platform**: iOS 17+ / SwiftUI  
**Audience**: Designers, engineers, and LLMs generating or editing Peezy UI

---

## 0. Design System Summary

Peezy’s UI is built around one core contrast:

- **Soft environment**
- **Strong direction**

The environment is light, airy, and forgiving. The direction is confident, dark-ink typography and clear CTAs. The result should feel reassuring, not noisy.

This system is already partially encoded in `PeezyTheme`, `PeezyCardChrome`, `PeezyAssessmentButton`, and the assessment templates. This document explains the visual logic behind those primitives so an LLM can extend them consistently.

## 0.1 Non-Negotiable Identity Rules

1. Peezy is light-mode first.
2. Glass surfaces are a core motif.
3. Primary text is dark ink, not flat black.
4. The UI should feel premium and gentle, not gamified.
5. Yellow is a friendly accent, not a default background for every CTA.

---

## 1. Brand Identity

## 1.1 Brand Personality

Peezy should feel:

- Calm
- Helpful
- Modern
- Human
- Competent

## 1.2 Visual Thesis

The visual system should communicate:

- “You are safe here.”
- “This is organized.”
- “You don’t need to figure everything out at once.”

That is why the interface favors:

- Large headlines
- Breathing room
- Rounded geometry
- Soft glass backgrounds
- Low-friction transitions

## 1.3 Copy Tone

Use copy that is:

- Plainspoken
- Warm
- Encouraging
- Specific

Avoid copy that is:

- Robotic
- Overly corporate
- Joke-heavy
- Overwritten

Examples:

- Good: “Just 3 tasks to knock out today.”
- Good: “We typically respond within a few hours.”
- Avoid: “Optimize your relocation workflow.”

---

## 2. Color System

## 2.1 Core Brand Palette

These values are grounded in `PeezyTheme.Colors`.

| Token | Value | Role |
|---|---|---|
| `brandYellow` | `#FFE36B` approx | Friendly brand accent |
| `brandYellowLight` | `#FFF0A1` approx | Gradient pair / highlight |
| `deepInk` | `#0D1A33` approx | Primary text, dark controls, authority |
| `lightBase` | `#F5F7FA` approx | App background |
| `iceBlue` | light cool blue | Background orb 1 |
| `softLavender` | light lavender | Background orb 2 |

## 2.2 Semantic Colors

| Token | Approx Value | Use |
|---|---|---|
| `emotionalRed` | muted coral red | Destructive actions, error moments |
| `infoBlue` | aqua-mint | Informational accents |
| `supportPurple` | muted violet | Secondary accent / category differentiation |
| `successGreen` | medium green | Success states |
| `warningOrange` | warm orange | Snoozed / caution / retry |
| `accentBlue` | strong blue | Focus rings, links, subscription, utility accents |

## 2.3 Neutral / System-Surface Colors

| Token | Use |
|---|---|
| `backgroundPrimary` | Standard grouped backgrounds |
| `backgroundSecondary` | Secondary grouped surfaces |
| `backgroundTertiary` | Nested surfaces |
| `textPrimary` | System label fallback |
| `textSecondary` | Secondary label fallback |
| `textTertiary` | Tertiary label fallback |

## 2.4 Usage Rules

### Use `deepInk` for

- Primary text
- Primary pill buttons
- Strong selected states
- Key iconography

### Use `brandYellow` for

- Brand moments
- Loading highlights
- Emphasis, not bulk UI fill

### Use semantic colors for state, not decoration

- Green = success / done
- Red = destructive / delete / failure
- Orange = snoozed / caution
- Blue = focus / links / informational utility

### Avoid

- Random new accent colors
- Saturated rainbow palettes
- Purple-led visual direction
- Dark mode-only thinking for new components

---

## 3. Background System

## 3.1 App Background

The primary app backdrop is an animated two-orb field on top of `lightBase`.

**Construction**

- Full-screen `lightBase`
- Large blurred `iceBlue` orb
- Large blurred `softLavender` orb
- Slow oscillating motion unless Reduce Motion is enabled

**Why**

- Adds atmosphere without using heavy illustrations
- Keeps the app from feeling blank or utilitarian
- Supports the glass-surface motif

## 3.2 When To Use A Plain Background

Use a simpler or flatter background only when:

- The user needs higher visual focus for input
- A modal sheet is already providing depth
- Motion would be distracting

---

## 4. Typography

## 4.1 Primary Type Approach

Peezy uses SF-based typography but leans on weight, spacing, and composition to create personality. It does not rely on custom fonts.

## 4.2 Defined Type Tokens

From `PeezyTheme.Typography`:

| Token | Size / Weight | Primary Use |
|---|---|---|
| `largeTitle` | 28 / bold | Major sheet or auth headers |
| `title` | 22 / bold | Section leaders |
| `title2` | 20 / bold | Settings header, list header |
| `headline` | 17 / semibold | Buttons, strong text |
| `body` | 17 / regular | Standard body text |
| `bodyMedium` | 17 / medium | Slightly emphasized body |
| `callout` | 15 / regular | Secondary text |
| `calloutMedium` | 15 / medium | More assertive secondary text |
| `calloutSemibold` | 15 / semibold | Labels needing stronger presence |
| `footnote` | 13 / regular | Metadata |
| `footnoteMedium` | 13 / medium | Small emphasis |
| `caption` | 11 / regular | Support labels |
| `captionMedium` | 11 / medium | Section labels / tiny badges |

## 4.3 Real-World Typography Patterns

### Home / high-emotion cards

- Use oversized custom headlines around `34pt` and `.heavy`
- Pair with a small divider line
- Use 16pt medium body copy beneath

### Settings / utility screens

- Use tokenized typography
- Keep hierarchy flatter and more operational

### Support chat

- Keep message text readable and plain
- Do not stylize bubble copy too aggressively

## 4.4 Typography Rules

1. Major headlines can be custom-sized when they are true hero statements.
2. Supporting copy should usually live in the 15–17pt range.
3. Avoid tiny text except for metadata and legal copy.
4. Preserve strong contrast between headline and helper copy.

---

## 5. Spacing And Layout

## 5.1 Layout Tokens

From `PeezyTheme.Layout`:

| Token | Value | Use |
|---|---|---|
| `cornerRadiusLarge` | 20 | Large cards / message bubbles |
| `cornerRadius` | 16 | Standard grouped glass blocks |
| `cornerRadiusMedium` | 14 | Mid-size components |
| `cornerRadiusSmall` | 12 | Tight controls |
| `cornerRadiusPill` | 25 | Pills |
| `cornerRadiusFixed` | 41 | Fixed-shape controls / tiles |
| `cardPadding` | 16 | Standard inner padding |
| `cardPaddingSmall` | 12 | Tighter cards |
| `horizontalPadding` | 20 | Standard screen edge padding |
| `horizontalPaddingSmall` | 16 | Compact edge padding |
| `verticalSpacing` | 12 | Default vertical separation |
| `verticalSpacingSmall` | 8 | Tight spacing |
| `sectionSpacing` | 32 | Major section gaps |
| `itemSpacing` | 16 | Medium component spacing |
| `buttonHeight` | 56 | Primary CTA height |
| `buttonHeightSmall` | 44 | Secondary compact control height |
| `iconSizeLarge` | 80 | Hero icon scale |
| `iconSizeMedium` | 36 | Standard icon emphasis |
| `iconSizeSmall` | 24 | Common icon size |

## 5.2 Layout Behavior

### Standard screen padding

- Horizontal: 20–24pt
- Bottom button margin: 24pt
- Top utility/header spacing: 16–24pt

### Assessment screens

- Large text block near top
- Input controls centered or lower in the remaining canvas
- Bottom CTA anchored consistently

### Home cards

- Fixed card width around 340pt
- Maximum height around 500pt
- Large internal padding
- Generous vertical spacing

## 5.3 Why The App Uses Big Margins

The product is about reducing stress. Dense spacing would make the app feel busy and administrative. Larger margins and roomy cards create psychological calm.

---

## 6. Surface System

## 6.1 Glass Surfaces

Peezy repeatedly uses layered material cards:

- Material base
- White tint overlay
- Low-contrast border
- Soft shadow

This appears in:

- Home cards
- Settings groups
- Chat input bar
- Support bubbles
- Paywall plan cards
- Completion cards

## 6.2 Primary Card Chrome

From `PeezyCardChrome`:

- Width: `340`
- Max height: `500`
- Radius: `36`
- Fill: `.ultraThinMaterial` + white tint
- Border: subtle `Color.primary.opacity(0.05)`
- Shadow: dark, soft, elevated

**Use this for**

- Hero cards
- Welcome cards
- Home state cards
- Task-flow intro/info cards

**Do not use this for**

- Small list rows
- Input fields
- Tight utility components

## 6.3 Grouped Utility Surface

Settings and paywall utilities use a lighter grouped glass block:

- Standard radius
- Regular material
- White tint
- Soft border

This surface is meant to feel calm and functional rather than theatrical.

---

## 7. Component Library

## 7.1 Primary CTA: `PeezyAssessmentButton`

**Visual properties**

- Capsule shape
- Height: `56`
- Background: `deepInk`
- Text: white, semibold rounded feel
- Strong shadow when enabled
- Press scale on touch

**Use for**

- Primary advancement
- “Continue”
- “Get started”
- “Let’s do this”
- Important completion actions

**Do not use for**

- Tiny inline actions
- Secondary text links
- Destructive utility rows

## 7.2 Auth Buttons

Auth landing uses a separate button family:

- Apple native button
- Custom capsule buttons for Google and Email
- Same height and interaction energy as `PeezyAssessmentButton`

This preserves consistency while respecting Apple’s auth requirements.

## 7.3 Selection Tile

Used by single-select and grid-select assessment questions.

**Characteristics**

- Large tile footprint
- Rounded rectangle
- Icon-led
- Selected state flips to dark fill with light text
- Strong shadow depth

**Why**

- Makes choice feel tactile and obvious
- Faster scanning than plain segmented controls for this emotional flow

## 7.4 Multi-Select Tile

Used for account categories.

**Characteristics**

- Horizontal row tile
- Icon left, label center, state affordance right
- Selected state uses dark fill
- Can show checkmark or `+/-` quantity controls

**Why**

- Supports repeated categories without adding extra screens

## 7.5 Task Row

Used in the Tasks tab.

**Characteristics**

- Glass row block
- Leading circular icon container
- Title + subtitle + optional status badge
- Expandable
- Button appears only when expanded

**Status badges**

- “You’re on it” = informational blue
- “Peezy is on it” = accent blue
- “Snoozed” = orange

## 7.6 Chat Bubble

**User bubble**

- Solid `deepInk`
- Light text

**Support bubble**

- Glass material
- Dark ink text

This clear split helps orientation without requiring avatars.

## 7.7 Floating Tab Bar

**Characteristics**

- Capsule shell
- Material fill
- Icon-only labels
- Selected icon uses darker contrast
- Unread badge dot for chat

**Why**

- Feels lighter than a standard opaque tab bar
- Matches the rest of the glass language

## 7.8 Settings Row

**Characteristics**

- Full-width button row
- Leading icon
- Label
- Chevron
- Grouped by glass container

**Why**

- Familiar iOS behavior
- Fast scan
- Operational clarity

---

## 8. Input System

## 8.1 Form Fields

Email/login/settings fields use:

- Soft tinted background
- Rounded corners
- Fine border
- Dark-ink text
- Accent blue tint when focused

## 8.2 Text Entry In Assessment

Assessment text entry is more centered and expressive than utility forms.

Why:

- Intake mode is more emotional and guided
- Utility forms in settings should feel more standard and operational

## 8.3 Date Input

Use the native graphical date picker for move date.

Do not replace it with a custom calendar unless there is a strong product reason.

---

## 9. Motion System

## 9.1 Timing Tokens

From `PeezyTheme.Animation`:

| Token | Value | Use |
|---|---|---|
| `quickDuration` | `0.1` | Press feedback |
| `standardDuration` | `0.2` | Most transitions |
| `slowDuration` | `0.3` | Slightly calmer reveals |
| `springResponse` | `0.3` | Default spring |
| `springDamping` | `0.7` | Default spring balance |
| `springResponseSlow` | `0.6` | Slower transitions |
| `springDampingSlow` | `0.8` | Smoother slower spring |

## 9.2 Motion Rules

1. Motion should reinforce clarity, not show off.
2. Reveals should feel soft and immediate.
3. Press states should be tactile.
4. Confetti and celebratory motion should be reserved for meaningful milestones.
5. Background motion should stay slow and atmospheric.

## 9.3 Common Motion Patterns

- Fade + slight slide for screen content
- Spring scale for icon reveals
- Spring press on buttons
- Rotating spinner for generation/loading
- Chevron rotation for expandable rows

## 9.4 Reduced Motion

When Reduce Motion is on:

- Disable background orb animation
- Prefer opacity changes over spring movement
- Keep transitions brief and functional

---

## 10. Haptics

## 10.1 Haptic Strategy

Haptics are used to make important choices feel grounded.

Use them for:

- Button confirmation
- Tab switches
- Success completion
- Errors
- Key taps in assessment choices

Avoid overusing haptics for:

- Passive scrolling
- Every list interaction
- Continuous or decorative motion

---

## 11. Accessibility

## 11.1 Contrast

- Primary text should always hit strong readable contrast against glass surfaces.
- Helper copy can soften, but must remain legible.

## 11.2 Dynamic Type

- Hero headlines may scale down slightly, but should not truncate important meaning.
- Body text should wrap naturally.
- Tile and row layouts must remain readable at larger sizes.

## 11.3 VoiceOver

- Buttons need action-based labels.
- Tab bar items should expose selected state.
- Badges cannot be color-only signals.

## 11.4 Touch Targets

- Primary buttons already meet comfortable hit sizes.
- Row tap areas should span the whole row.
- Tiny icon actions should be avoided unless wrapped with sufficient padding.

---

## 12. Dark Mode Guidance

The current product is visually optimized for the light-mode system. If dark mode support is expanded:

1. Preserve the “soft glass” feeling.
2. Do not simply invert the entire palette.
3. Replace some shadow-based separation with stroke-based separation.
4. Keep `deepInk`’s role conceptually, but adapt for contrast.

Until that work is intentionally done, new components should prioritize consistency with the current light-first system.

---

## 13. Implementation Guidance For LLMs

## 13.1 Preferred Reuse Order

When building UI in this codebase:

1. Reuse `PeezyTheme`
2. Reuse `PeezyAssessmentButton`
3. Reuse `peezyCardChrome()` for hero cards
4. Reuse existing tiles and grouped row patterns
5. Extend tokens only if the existing ones clearly do not cover the use case

## 13.2 Do Not Introduce

- Generic purple SaaS gradients
- Heavy black dark themes by default
- Square, sharp enterprise geometry
- Unrelated font systems
- Busy dashboard grids on Home
- Random micro-animations on every element

## 13.3 When Adding A New Screen

Ask:

1. Is this screen intake, plan, or execution?
2. Should it feel emotional or operational?
3. Does it need hero-card treatment or grouped utility treatment?
4. Does it deserve a primary CTA, or is a secondary action enough?

---

## 14. Quick Reference

## 14.1 Use This Surface

| Situation | Surface |
|---|---|
| Hero state card | `peezyCardChrome()` |
| Settings group | standard grouped glass background |
| Chat input | rounded material container |
| Task row | medium glass row block |
| Paywall plan choice | bordered glass plan card |

## 14.2 Use This Button

| Situation | Component |
|---|---|
| Main forward action | `PeezyAssessmentButton` |
| Auth provider button | auth button family |
| Small utility text action | plain text button / underlined link |
| List row action | settings row / task row expansion button |

## 14.3 Use This Tone

| Situation | Tone |
|---|---|
| Onboarding / intro | Reassuring |
| Daily tasking | Encouraging and direct |
| Errors | Calm and specific |
| Celebration | Warm and earned |
| Settings | Straightforward |

---

## 15. LLM Handoff Prompt Fragment

If you need to brief another model quickly, this summary is safe to paste:

> Peezy is a light-first, glass-surface moving concierge app. It collects move data through a short branched assessment, generates personalized tasks, then guides the user through a daily-dose Home experience while keeping a full task ledger in Tasks. The UI should feel calm, premium, and helpful, with dark-ink typography, soft animated orb backgrounds, capsule CTAs, rounded glass cards, and plain-language copy.

