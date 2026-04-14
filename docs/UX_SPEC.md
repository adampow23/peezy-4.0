# UI/UX Specification: Peezy

**Version**: 1.0.0  
**Last Updated**: 2026-04-14  
**Status**: Draft  
**Platform**: iOS 17+  
**Primary Audience**: Product, design, engineering, and any LLM being asked to reason about or extend Peezy

---

## 0. What This System Is

Peezy is an assessment-driven moving concierge app. The product asks a short sequence of move-specific questions, turns those answers into a personalized task plan, then helps the user work through the move one calm decision at a time.

The system is intentionally not a generic productivity app.

- The assessment is the intake engine.
- Firestore task generation is the planning engine.
- Home is the daily coaching surface.
- Tasks is the full operational backlog.
- Chat is the human safety net.
- Settings is the control center for move details, subscription, inventory, and account management.

## 0.1 Why The Product Works

Peezy works because it reduces a high-stress, multi-week move into a narrow series of simple decisions.

1. It front-loads complexity into the assessment so the app can feel simple later.
2. It shows one primary action at a time on Home instead of overwhelming the user with an entire project plan.
3. It keeps the full backlog available in Tasks for control and confidence.
4. It uses warm, non-technical copy to lower anxiety during a stressful life event.
5. It gives users human backup through chat when automation is not enough.

## 0.2 Source Of Truth Used For This Spec

This repo does not currently contain canonical `docs/PRD.md` and `docs/ARCHITECTURE.md`, so this spec is synthesized from the live product and project documents:

- `CLAUDE.md`
- `INVENTORY_SPEC.md`
- `BUILD2_ASSESSMENT_OVERHAUL_SPEC.md`
- `E2E_TEST_SPEC.md`
- Current SwiftUI implementation in `Peezy 4.0/`

If an LLM finds a conflict between this doc and the live code, the live code wins unless a human explicitly says otherwise.

---

## 1. Product Principles

### 1.1 Core Experience Principles

1. **Calm over clever**  
Every screen should help the user feel more in control of the move, not more impressed by the interface.

2. **One meaningful decision at a time**  
Assessment questions appear one per screen. Home surfaces one primary next step. Complex operations are broken into focused flows.

3. **Progressive disclosure**  
Peezy hides detail until it becomes useful. The user sees only the next question, the next batch of tasks, or the next relevant setting.

4. **Plan first, then execute**  
The product invests heavily in personalized task generation so the working app can remain simple.

5. **Human help is always nearby**  
Automation handles the repeatable work, but support chat exists to preserve trust when the user has edge cases or uncertainty.

### 1.2 Brand Personality

Peezy should feel:

- Warm
- Capable
- Unfussy
- Reassuring
- Light without becoming childish

### 1.3 Design Translation Of The Brand

- Light, airy background with slow-moving color orbs
- Frosted glass surfaces for key cards and grouped controls
- Strong dark-ink text for trust and legibility
- Yellow used as a friendly brand accent, not as a constant loud CTA
- Large editorial-style headlines paired with plainspoken helper copy

---

## 2. Information Architecture

## 2.1 App State Routing

```text
Launch
  |
  v
[App Loading]
  |
  v
{Authenticated?}
  | \
  |  \-- No --> [Auth]
  |
  +-- Yes --> {Assessment Exists?}
                | \
                |  \-- Yes --> [Main App Shell]
                |                 |   |   |   |
                |                 |   |   |   +--> Settings
                |                 |   |   +------> Chat
                |                 |   +----------> Tasks
                |                 +--------------> Home
                |
                +-- No --> [Assessment Intro]
                           -> [Assessment Flow]
                           -> [Generating -> Ready -> Summary]
                           -> [Paywall Value -> Paywall Gate]
                           -> [Main App Shell]
```

## 2.2 Main App Navigation Pattern

**Primary pattern**: 4-tab floating bottom navigation

- `Home`
- `Tasks`
- `Chat`
- `Settings`

**Why this pattern is correct**

- Home is curated and emotional.
- Tasks is operational and exhaustive.
- Chat is support-oriented and should always remain one tap away.
- Settings handles profile, move details, subscription, inventory, and destructive account actions.

Keeping these separated prevents Home from turning into a cluttered dashboard.

## 2.3 Secondary Navigation Patterns

- Assessment uses a linear `NavigationStack`-like step sequence with a custom progress bar.
- Task flows open as full-screen covers from Home.
- Inventory scanning opens as a full-screen flow from Settings or from eligible tasks.
- Edit flows in Settings open as sheets.
- Paywall is staged as a post-assessment sequence, not a random interrupt.

---

## 3. Screen Inventory

| Screen / Flow | Purpose | Entry Point | Priority |
|---|---|---|---|
| App Loading | Determine auth and assessment state | App launch | P0 |
| Auth Landing | Offer Apple, Google, or Email auth | Unauthenticated state | P0 |
| Login Sheet | Existing user email login | Auth landing | P0 |
| Sign Up Sheet | New user email signup | Auth landing | P0 |
| Assessment Intro | Reassure user before intake | Authenticated without assessment | P0 |
| Assessment Flow | Capture move context | Assessment intro | P0 |
| Completion: Generating | Show plan generation progress | Assessment completion | P0 |
| Completion: Ready | Confirm plan exists | After generating | P0 |
| Completion: Summary | Celebrate and frame task count | After ready | P0 |
| Paywall Value | Sell value before asking for purchase | After summary | P0 |
| Paywall Gate | Plan selection and purchase | After paywall value | P0 |
| Main Shell | Primary app container | Authenticated + assessed | P0 |
| Home: First-Time Welcome | Teach how Peezy works | First main app visit | P0 |
| Home: Daily Greeting | Start the day’s work | New day with tasks | P0 |
| Home: Returning Mid-Day | Resume daily batch | Same day return | P0 |
| Home: Daily Complete | Celebrate finishing today’s batch | Daily target reached | P0 |
| Home: All Complete | Show total plan completion | No active tasks remain | P0 |
| Tasks Stream | Full backlog with status tabs | Main shell | P0 |
| Support Chat | Async human help | Main shell | P1 |
| Settings | Profile, move details, subscription, inventory, support, account | Main shell | P1 |
| Inventory Flow | Scan rooms and review items | Settings or task flow | P1 |

---

## 4. Core User Journeys

## 4.1 New User Journey

```text
Auth
  -> Assessment Intro
  -> Short branched assessment
  -> Task generation
  -> Task count celebration
  -> Premium value framing
  -> Main app
  -> First-time welcome
  -> First daily task
```

**Why this works**

- The user gets emotional reassurance before data entry.
- The assessment feels short because only relevant questions appear.
- The completion flow converts invisible backend work into perceived value.
- The paywall comes after value is demonstrated, not before.

## 4.2 Returning Daily User Journey

```text
Open app
  -> Home greeting or resume state
  -> Start task
  -> Complete / mark in progress / snooze
  -> Return to next state
  -> End on Daily Complete or All Complete
```

**Why this works**

- Returning users do not need to re-parse the whole plan.
- The product creates momentum through batching and state-based messaging.

## 4.3 “I Need Control” Journey

```text
Open Tasks tab
  -> Switch between To-Do / In Progress / Done
  -> Expand a row
  -> Start or complete a task
  -> Navigate back to Home if needed
```

**Why this works**

- Users can override the “daily coach” layer without losing the emotional simplicity Home provides.

## 4.4 “I Need Help” Journey

```text
Open Chat
  -> Read prior support messages
  -> Send question
  -> Return later for reply
```

**Why this works**

- Chat is async and low-pressure, matching a moving concierge model better than a fake real-time support promise.

---

## 5. Experience Architecture

## 5.1 Structural Model

Peezy is not one continuous interface. It has three distinct modes:

1. **Intake mode**  
Assessment flow collects move details.

2. **Plan mode**  
Completion + paywall frames the output and value.

3. **Execution mode**  
Home, Tasks, Chat, and Settings help the user carry out the move.

## 5.2 Home Vs Tasks

This is the most important UX distinction in the app.

- `Home` is the curated, emotionally intelligent view.
- `Tasks` is the complete operational ledger.

An LLM should not collapse these into one screen unless a human explicitly wants a major product change.

## 5.3 Daily Dose Model

The app computes a daily task target based on remaining tasks and days until move date.

This creates:

- A realistic sense of pace
- Better habit formation
- Less overwhelm
- A reason for Home to exist as a separate experience from Tasks

---

## 6. Detailed Screen Specifications

## 6.1 App Loading

**Purpose**: Resolve auth state and assessment-complete state before showing the correct root.

**Wireframe**

```text
┌─────────────────────────────────────┐
│                                     │
│                                     │
│              [Glass Orb]            │
│            [ProgressView]           │
│                                     │
│              Loading...             │
│                                     │
│                                     │
└─────────────────────────────────────┘
```

**Key behaviors**

- Full-screen background with soft moving orbs
- Centered glass container
- No user choice here
- Routes immediately once state is known

## 6.2 Auth Landing

**Purpose**: Let users sign in with the least friction possible.

**Wireframe**

```text
┌─────────────────────────────────────┐
│                                     │
│          Moving made peezy.         │
│       Your move, on autopilot.      │
│                                     │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Continue with Apple           │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ Continue with Google          │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ Continue with Email           │  │
│  └───────────────────────────────┘  │
│                                     │
│      Already have an account?       │
│              Log in                 │
└─────────────────────────────────────┘
```

**Components**

- Typewriter-style rotating headline
- Bottom glass tray with auth actions
- Apple = native first-party trust signal
- Google = high-convenience fallback
- Email = universal fallback

**Why it works**

- The screen frames the brand promise before asking for commitment.
- The action stack is simple and familiar.
- The glass tray visually anchors interaction without turning the whole screen into a form.

## 6.3 Login / Sign Up Sheets

**Purpose**: Handle email-based auth without cluttering the primary auth landing screen.

**Wireframe**

```text
┌─────────────────────────────────────┐
│  X                        Log In    │
├─────────────────────────────────────┤
│                                     │
│          Welcome back               │
│     Log in to continue your move    │
│                                     │
│  Email                              │
│  ┌───────────────────────────────┐  │
│  │ your@email.com                │  │
│  └───────────────────────────────┘  │
│  Password                           │
│  ┌───────────────────────────────┐  │
│  │ •••••••••                     │  │
│  └───────────────────────────────┘  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Log in                        │  │
│  └───────────────────────────────┘  │
│                                     │
│          Forgot password?           │
└─────────────────────────────────────┘
```

**Notes**

- `Sign Up` uses the same visual structure but adds confirm password.
- Validation is inline where possible.
- Modal presentation keeps the primary auth landing emotionally clean.

## 6.4 Assessment Intro

**Purpose**: Shift the user from account setup into a guided intake experience.

**Wireframe**

```text
┌─────────────────────────────────────┐
│                                     │
│          [wand.and.stars]           │
│                                     │
│      Welcome to the easy part       │
│                                     │
│  You're in. We just need a few      │
│  quick details to build your move   │
│  plan.                              │
│                                     │
│     [clock] 90 second setup         │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Take the first step           │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Why it works**

- It re-frames form filling as plan building.
- The copy reduces intimidation before the first question.
- The time estimate lowers uncertainty.

## 6.5 Assessment Flow Shell

**Purpose**: Collect the minimum information needed to generate relevant tasks.

**Shared shell wireframe**

```text
┌─────────────────────────────────────┐
│  <         7 of current total       │
│  ─────────────── progress ───────── │
├─────────────────────────────────────┤
│                                     │
│  [Question header]                  │
│  [Optional helper copy]             │
│                                     │
│              [Input]                │
│                                     │
│                                     │
│        [Continue when needed]       │
│                                     │
└─────────────────────────────────────┘
```

### 6.5.1 Assessment Template System

Peezy uses a small set of repeatable question templates rather than inventing a new layout for every question.

| Template | Used For | Why |
|---|---|---|
| Text Entry | Name, address-like inputs | Fast typing with clear focus |
| Date Picker | Move date | Native confidence and low error rate |
| Single Select (2-option) | Yes/No decisions | Fast low-cognitive-load input |
| Grid Select | Multi-option single choice | Clear comparison across options |
| Multi Select | Accounts and memberships | Supports many selections and counts |
| Explainer | Section transitions | Prevents abrupt context switching |

### 6.5.2 Template: Text Entry

```text
┌─────────────────────────────────────┐
│  <         1 of current total       │
│  ───────────── progress ─────────── │
│                                     │
│  Let's get to know each other.      │
│  What's your first name?            │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ First name                    │  │
│  └───────────────────────────────┘  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Continue                      │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Behavior**

- Field autofocuses on reveal
- Continue stays disabled until valid input exists
- Tapping background dismisses keyboard

### 6.5.3 Template: Date Picker

```text
┌─────────────────────────────────────┐
│  <         2 of current total       │
│  ───────────── progress ─────────── │
│                                     │
│  When are we moving?                │
│  Best guess is okay.                │
│                                     │
│   ┌─────────────────────────────┐   │
│   │  Native graphical calendar  │   │
│   └─────────────────────────────┘   │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Continue                      │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Why**

- Native calendar reduces date ambiguity.
- The interface feels trustworthy during a high-stakes input.

### 6.5.4 Template: Grid Select

```text
┌─────────────────────────────────────┐
│  What kind of place is it?          │
│                                     │
│  ┌────────────┐  ┌────────────┐     │
│  │ House      │  │ Apartment  │     │
│  └────────────┘  └────────────┘     │
│  ┌────────────┐  ┌────────────┐     │
│  │ Condo      │  │ Townhouse  │     │
│  └────────────┘  └────────────┘     │
└─────────────────────────────────────┘
```

**Behavior**

- Tile tap selects immediately
- Branching can change future steps
- Tiles use bold icon + title structure for fast scanning

### 6.5.5 Template: Multi Select

```text
┌─────────────────────────────────────┐
│  Let's start with finance related   │
│  accounts you might have.           │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ [bank icon] Bank Account   +  │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ [card icon] Credit Card    2  │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ [chart icon] Investments      │  │
│  └───────────────────────────────┘  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Continue                      │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Why**

- Users often have multiple institutions in the same category.
- Count-based interaction lets one question generate multiple tasks without asking separate screens.

### 6.5.6 Template: Explainer

```text
┌─────────────────────────────────────┐
│                                     │
│            [hammer.fill]            │
│                                     │
│  Now let's talk about any           │
│  professional help you might need.  │
│                                     │
│  We'll ask about movers, cleaners,  │
│  and other services.                │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Continue                      │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Why**

- Section explainer screens prevent the assessment from feeling like a random list.
- They help the user understand why a new cluster of questions is appearing.

### 6.5.7 Actual Assessment Step Map

| Step | Template | Data Captured | Branching / Notes | Why It Exists |
|---|---|---|---|---|
| `userName` | Text Entry | First name | No branching | Personalizes the rest of the experience |
| `moveDate` | Date Picker | Move date | No branching | Powers urgency and daily target |
| `currentRentOrOwn` | Single Select | Current ownership | No branching | Determines task relevance |
| `currentDwellingType` | Grid Select | Current home type | Branches to floor access when apt/condo | Captures moving logistics |
| `currentAddress` | Text Entry | Current address | No branching | Needed for utilities, mail, location logic |
| `currentFloorAccess` | Grid Select | Elevator/stairs/etc. | Only shown for apt/condo | Needed for mover/logistics tasks |
| `newRentOrOwn` | Single Select | Destination ownership | No branching | Drives task relevance |
| `newDwellingType` | Grid Select | New home type | Branches to floor access when apt/condo | Logistics and services relevance |
| `newAddress` | Text Entry | Destination address | No branching | Needed for setup tasks and geocoding |
| `newFloorAccess` | Grid Select | Elevator/stairs/etc. | Only shown for apt/condo | Logistics relevance |
| `anyKids` | Single Select | Kids yes/no | Branches school/daycare | Prevents asking irrelevant family questions |
| `childrenInSchool` | Single Select | School transfer yes/no | Only if kids | Education-related tasks |
| `childrenInDaycare` | Single Select | Daycare transfer yes/no | Only if kids | Daycare tasks |
| `hasVet` | Single Select | Pets with vet yes/no | No branching | Pet-related tasks |
| `servicesIntro` | Explainer | None | Transitional only | Frames services cluster |
| `hireMovers` | Single Select | Movers yes/no | If “No”, ask truck rental | Distinguishes full-service vs DIY path |
| `truckRental` | Single Select | Truck rental yes/no | Only if not hiring movers | Handles DIY move path |
| `hasDeclutter` | Single Select | Declutter yes/no | No branching | Powers sell/remove tasks |
| `hireCleaners` | Single Select | Cleaners yes/no | No branching | End-of-home tasks |
| `addressChangeIntro` | Explainer | None | Transitional only | Frames accounts/update cluster |
| `financialInstitutions` | Multi Select | Banking/credit/investment categories + counts | No branching | Generates multiple admin tasks efficiently |
| `healthcareProviders` | Multi Select | Health categories + counts | No branching | Generates transfer/update tasks |
| `fitnessWellness` | Multi Select | Membership categories + counts | No branching | Generates cancellation/transfer tasks |
| `howHeard` | Grid Select | Acquisition source | Final step | Marketing attribution |

## 6.6 Completion Flow

### 6.6.1 Generating

```text
┌─────────────────────────────────────┐
│                                     │
│          [rotating ring]            │
│                                     │
│  Building your personalized task    │
│  list...                            │
│                                     │
└─────────────────────────────────────┘
```

**Behavior**

- Rotating visual spinner
- Cycling progress copy
- Minimum dwell time so task generation feels intentional, not glitchy

### 6.6.2 Ready

```text
┌─────────────────────────────────────┐
│                                     │
│         [animated checkmark]        │
│                                     │
│      Your task list is ready        │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ See Your Custom Plan          │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

### 6.6.3 Summary

```text
┌─────────────────────────────────────┐
│                                     │
│    Adam's Personalized Moving Plan  │
│   Here's what we built for you      │
│                                     │
│               47                    │
│       personalized tasks            │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Let's Get Started             │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Why the 3-step completion sequence exists**

- Stage 1 explains the system is doing real work.
- Stage 2 confirms success.
- Stage 3 turns output into an emotionally meaningful artifact.

## 6.7 Paywall Sequence

### 6.7.1 Value Builder

```text
┌─────────────────────────────────────┐
│               PEEZY+                │
│                                     │
│  Can you really put a price on      │
│  peace of mind?                     │
│                                     │
│  25+ hours saved. Zero stress.      │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Try it free                   │  │
│  └───────────────────────────────┘  │
│      Free trial / price line        │
└─────────────────────────────────────┘
```

### 6.7.2 Paywall Gate

```text
┌─────────────────────────────────────┐
│               PEEZY+                │
│   Your easiest move ever.           │
│                                     │
│  ┌────────────┐  ┌────────────┐     │
│  │ YEARLY     │  │ WEEKLY     │     │
│  │ best value │  │ starter    │     │
│  └────────────┘  └────────────┘     │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Let's do this                 │  │
│  └───────────────────────────────┘  │
│                                     │
│   Not now   ·   Redeem   · Restore  │
│         Privacy · Terms             │
└─────────────────────────────────────┘
```

**Why the paywall is sequenced this way**

- `PaywallValueView` sells outcome.
- `PaywallGateView` asks for transaction.
- This separation keeps the purchase screen focused and easier to convert.

## 6.8 Main App Shell

**Purpose**: Provide persistent access to Home, Tasks, Chat, and Settings.

**Wireframe**

```text
┌─────────────────────────────────────┐
│                                     │
│          Active tab content         │
│                                     │
│                                     │
│                                     │
│        ╭────────────────────╮       │
│        │ home tasks chat ⚙ │       │
│        ╰────────────────────╯       │
└─────────────────────────────────────┘
```

**Key traits**

- Floating capsule tab bar
- Glass material background
- Compact icon-only navigation
- Optional unread dot on Chat

## 6.9 Home State Machine

Home is not a static dashboard. It is a state-driven card surface.

### 6.9.1 First-Time Welcome

```text
┌─────────────────────────────────────┐
│                                     │
│  Welcome, Adam!                     │
│  ─────                              │
│                                     │
│  We break your move into bite-      │
│  sized daily tasks based on your    │
│  timeline.                          │
│                                     │
│          ○  ●  ○                    │
│       Swipe to continue             │
│                                     │
│     [Let's do this] on final page   │
└─────────────────────────────────────┘
```

**Why**

- A 3-page welcome teaches the mental model before task execution begins.
- Swipe interaction makes education feel lightweight.

### 6.9.2 Daily Greeting

```text
┌─────────────────────────────────────┐
│                                     │
│  Good morning, Adam.                │
│  ─────                              │
│                                     │
│  Just 3 tasks to knock out today.   │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Get started                   │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

### 6.9.3 Returning Mid-Day

```text
┌─────────────────────────────────────┐
│                                     │
│  Welcome back, Adam.                │
│  ─────                              │
│                                     │
│  You've done 1 of 3 today.          │
│  2 tasks to go.                     │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Pick up where I left off      │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

### 6.9.4 Active Task Handoff

When a user starts a task, Home enters an `activeTask` state and immediately routes into:

- Inventory scanner if the task is an inventory task
- Full-screen task flow if the task has a mapped workflow
- Simple completion logic for basic tasks

Home itself intentionally does not try to render every possible task interaction inline.

### 6.9.5 Daily Complete

```text
┌─────────────────────────────────────┐
│                                     │
│  You're all done for today!         │
│  ─────                              │
│                                     │
│  Right on schedule. Enjoy the rest  │
│  of your day.                       │
│                                     │
│  [confetti behind card]             │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Want to get ahead?            │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

### 6.9.6 All Complete

```text
┌─────────────────────────────────────┐
│                                     │
│        [checkmark seal icon]        │
│                                     │
│    You're all set, Adam!            │
│    ─────                            │
│                                     │
│  Your move is on track. Peezy is    │
│  handling the rest.                 │
│                                     │
└─────────────────────────────────────┘
```

## 6.10 Tasks Stream

**Purpose**: Provide the full, filterable, status-based task ledger.

**Wireframe**

```text
┌─────────────────────────────────────┐
│  Adam's Task List            [Home] │
├─────────────────────────────────────┤
│  To-Do(8)  In Progress(2)  Done(4)  │
├─────────────────────────────────────┤
│  ┌───────────────────────────────┐  │
│  │ [icon] Book movers        >   │  │
│  │ Research and reserve...       │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ [icon] Transfer utilities >   │  │
│  │ Snoozed / In Progress badge   │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Interaction model**

- Tap row to expand
- Expanded rows show contextually appropriate CTA:
  - `Start task`
  - `Mark as completed`
  - `Undo completion`

**Why it works**

- Home stays emotionally simple
- Tasks provides operational confidence
- Status tabs reduce scanning cost

## 6.11 Support Chat

**Purpose**: Async human help for unclear or stressful moments.

**Wireframe**

```text
┌─────────────────────────────────────┐
│             Support                 │
│    We typically respond in hours    │
├─────────────────────────────────────┤
│                                     │
│   [Support bubble]                  │
│   Of course. What's going on?       │
│                                     │
│                    [User bubble]    │
│        I have a question...         │
│                                     │
├─────────────────────────────────────┤
│  ┌───────────────────────────────┐  │
│  │ What can we help with?        │  │
│  └───────────────────────────────┘  │
│                          [send]     │
└─────────────────────────────────────┘
```

**Design notes**

- User bubbles are solid dark ink
- Support bubbles are glass
- Header sets expectation that this is async, not instant live chat

## 6.12 Settings

**Purpose**: Central control surface for everything not part of the daily-task loop.

**Wireframe**

```text
┌─────────────────────────────────────┐
│ Settings                            │
│                                     │
│  [Profile card with initials]       │
│                                     │
│  EDIT MOVE DETAILS                  │
│  Move Date                  >       │
│  Current Address            >       │
│  New Address                >       │
│  Retake Assessment          >       │
│                                     │
│  SUBSCRIPTION                       │
│  Status                             │
│  Manage Subscription       >        │
│  Restore purchases         >        │
│                                     │
│  INVENTORY                          │
│  Scan Room Inventory      >         │
│                                     │
│  SUPPORT                            │
│  Contact Support          >         │
│  Privacy Policy           >         │
│  Terms of Service         >         │
│                                     │
│  Sign Out                 >         │
│  Delete account           >         │
└─────────────────────────────────────┘
```

**Why this works**

- It keeps Home emotionally clean.
- Related actions are grouped in glass blocks.
- Destructive actions are visually separated and colored red.

## 6.13 Inventory Flow

**Purpose**: Let users scan rooms and build an inventory with AI assistance.

**High-level flow**

```text
Intro card
  -> "Here's how it works"
  -> Room hub
  -> Camera capture per room
  -> Processing
  -> Item confirmation
  -> Room review
  -> Return to room hub
```

**Intro wireframe**

```text
┌─────────────────────────────────────┐
│  X                                  │
│                                     │
│         [camera.viewfinder]         │
│                                     │
│           Scan my home              │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Continue                      │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Why it works**

- The flow is intentionally separated from the main navigation.
- Users focus on one room at a time.
- AI handles recall, while the user remains the quality-control layer.

---

## 7. Shared States

## 7.1 Loading

- App loading uses centered glass + spinner
- Home loading uses task-specific copy
- Generating uses branded loading copy

## 7.2 Empty

- Tasks empty state: “No tasks yet”
- Chat empty state: prompt to ask questions
- Tab empty states use plain-language reassurance, not blame

## 7.3 Error

- Auth uses alert/toast patterns
- Home uses bottom error toast
- Settings uses toast or confirmation alerts
- Delete and retake actions use explicit confirmation

---

## 8. Interaction Patterns

## 8.1 Motion

- Background orbs move slowly and continuously
- Buttons use spring press scale
- Assessment controls fade/slide in after header reveal
- Confetti appears for celebration states
- Task row chevrons rotate on expand

## 8.2 Haptics

- Light impact for navigation and tab changes
- Medium impact for primary actions
- Error haptic for failures
- Success haptic for successful auth or task completion moments

## 8.3 Gesture Rules

- First-time welcome uses horizontal swipe
- Assessment is tap-first; back uses explicit chevron
- Task rows expand on tap
- Chat scroll dismisses keyboard interactively

---

## 9. Accessibility Requirements

1. Large type must not break core flows.
2. All primary actions need clear accessibility labels.
3. Color cannot be the only status signal.
4. Reduce Motion should disable unnecessary flourish while preserving clarity.
5. Tap targets should stay comfortably touchable, especially on card buttons and settings rows.

---

## 10. Design Rationale By Area

## 10.1 Why The App Is Light Mode First

Peezy’s emotional job is to reduce stress. The current light, airy background system communicates calm and openness better than a dense dark UI for this product.

## 10.2 Why Glass Is Used So Often

The glass surfaces create soft containment without visually boxing the user into a heavy enterprise UI. This makes the app feel lighter while still preserving hierarchy.

## 10.3 Why Home Avoids A Traditional Dashboard

Moving is already cognitively expensive. A multi-card dashboard would front-load anxiety. Home instead narrows attention to the right next action.

## 10.4 Why The Assessment Is Branched

Branching protects the user from irrelevant questions, keeps the flow feeling shorter, and improves downstream task relevance.

## 10.5 Why Settings Holds Inventory

Inventory is powerful but not the user’s primary daily action. Putting it in Settings keeps the main loop clean while still making the feature accessible.

---

## 11. Rules For LLMs Working On This Product

1. Do not redesign Peezy into a generic task manager.
2. Do not merge Home and Tasks unless explicitly instructed.
3. Keep assessment steps focused and sequential.
4. Prefer calm, plain-language copy over clever copy.
5. Preserve the glass-card + airy background visual identity unless the user asks for a rebrand.
6. Treat task generation and daily-dose pacing as core product logic, not incidental implementation details.
7. When adding screens, decide whether they belong to intake mode, plan mode, or execution mode before designing them.

---

## 12. Open Product Notes

- The current app shell is 4 tabs, even though some older project notes describe a 3-tab structure.
- Inventory is implemented as a secondary flow and should remain visually consistent with the rest of the product.
- Some legacy docs still reference older home task card behavior; the current app routes many active tasks into dedicated full-screen flows.

---

## 13. Next Recommended Documents

If another LLM needs to implement or refine the UI, provide:

1. This file: `docs/UX_SPEC.md`
2. `docs/DESIGN_SYSTEM.md`
3. `CLAUDE.md`
4. The relevant SwiftUI source files for the screen being changed
