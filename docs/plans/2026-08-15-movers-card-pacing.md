# Plan: Movers education + equip card pacing (one idea per card) — Rev 4

Status: **APPROVED** — consensus reached round 4 (gpt-5.6-sol, thread 01a0046c-9dd2-75b2-a86c-19813c0bf2b0, 2026-08-15)
Repo: `~/Desktop/Peezy 4.0`
Scope: `BOOK_MOVERS` get-quotes role only (`MoversFlowRole.getQuotes`, non-legacy).
Owner: builder = Claude; reviewer = gpt-5.6-sol (read-only).

## Design rule (the acceptance bar)

One card = one idea, sized to fit the screen with **no internal scrolling at
default Dynamic Type**. If content doesn't fit, it becomes another card in the
sequence. Plain sentences, third-grader clear, no jargon-as-headline.

## Current state (code-verified; corrected per round 1)

| Fact | Evidence |
|---|---|
| Two education stages, then equip | `MoversFlowStage.swift:8-18` |
| Education copy passed in by the flow | `FindMoversFlow.swift:83-106` |
| Equip wraps content in a `ScrollView` | `MoversEquipView.swift:17-73` — violates the rule today |
| Card chrome: **width fixed 340, height only capped at 500, no clipping** — overflow spills visually | `PeezyCardChrome.swift:28-29`; applied by `TaskFlowStack.swift:51` |
| Effective text width ≈ **260pt**: 340 − 2×20 outer (`MoversEducationView.swift:57`) − 2×20 `taskContentCard()` (`TaskContentSections.swift:500`, `peezyTheme.swift:94`) | measured |
| Education body lengths: **96 / 99 / 142 / 221** chars | measured (rev-1 counts were wrong) |
| BOOK_MOVERS call sheet: say=3 (256 chars, max item 140), ask=4 (219, max 78), **get=2 (130)** — `say` is the tallest section, exactly one item >100 chars | `functions/taskCatalogData.json:62-78`, measured |
| `callSheet` may be nil; individual arrays may be `[]` on a non-nil sheet | `TaskContentSections.swift:51-62`; `SETUP_DAYCARE` ships `"say": []` |
| `MoversFlowStage` raw `Int` is never persisted; durable stage is a separate `String` enum | `MoversFlowViewModel.swift:39` (in-memory), `TaskStage.swift:7` |
| `TaskFlowStack` receives only `model.stage.stackIndex` — a view-local index cannot drive the stack counter | `FindMoversFlow.swift:45-48` |
| `advanceEducation`/`goBack` have `default:` arms (NOT exhaustive); the exhaustive switches are `stageContent` (`FindMoversFlow.swift:74-138`), `stackIndex`+`persistedTaskStage` (`MoversFlowStage.swift:20-43`), `initialStage()` returns `.protectionEducation` (`MoversFlowViewModel.swift:120`) | corrected inventory |
| FindMoversFlow does NOT use `resumableFlowProgress`; resume is `persistedResumeStage` (quotes/matrix only) | grep + `MoversFlowViewModel.swift:112-127` |
| **Non-legacy get-quotes route never visits `.quotes`/`.matrix`**: preparation → `completeGetQuotes` → `.confirmation`. Quotes/matrix occur only on legacy-inline and compare routes | `MoversFlowViewModel.swift:112-127,160-172` |
| `PeezyTheme.Typography.body` is a **fixed 17pt font** (`Font.system(size: 17)`); `TaskContentBullet` uses it, so `CallSheetSection` bullets do NOT scale with Dynamic Type | `peezyTheme.swift:68`, `TaskContentSections.swift:462` |
| Compare role today: quotes → remaining 2, matrix → remaining 1 (`max(5−stackIndex,1)`) | `MoversFlowStage.swift:20-32` |

## Architecture (rev 2 — adopts round-1 finding 9)

Replace the three preparation stage cases with **one `.preparation` stage**
plus a **model-owned page array**. This is the simpler design round 1 asked
to be steelmanned; it wins because the preparation stages were never
persisted and had no external consumer requiring per-stage identity.

### `MoversFlowStage` (8 → 6 cases)

```
loading, preparation, quotes, matrix, confirmation, failure
```

- `persistedTaskStage` unchanged in meaning: `.quotes → .compare`,
  `.matrix → .verify`, all else nil.
- `stackIndex`/`cardsRemaining` are **removed from the enum** — a static
  property cannot represent a dynamic page count. The model computes both
  (below).

### `MoversPreparationPage` (new type, declared in `MoversFlowStage.swift` — already in PHASE_MANIFEST)

```swift
struct MoversPreparationPage: Equatable {
    enum Kind: Equatable {
        case education                       // title + body, MoversEducationView
        case intro                           // get-three-quotes + share button
        case callSheetSection(items: [String]) // one say/ask/get section
    }
    enum PrimaryAction: Equatable {
        case advance      // "Continue" → advancePreparation()
        case getQuotes    // "I'm getting quotes" → completeGetQuotes()
    }
    let kind: Kind
    let title: String
    let body: String?          // education body or intro line
    let systemImage: String
    let accessibilityPrefix: String
    let primary: PrimaryAction // builder sets exactly one .getQuotes, on the last page
}
```

Finality is **encoded in the model**, not inferred at render time: fixtures
assert directly that exactly one page carries `.getQuotes` and that it is
last. The render switch maps `.advance → advancePreparation` and
`.getQuotes → completeGetQuotes` — the only site where the chain closure is
bound.

### Page builder (pure, unit-testable)

`static func MoversFlowViewModel.buildPreparationPages(callSheet: TaskCallSheet?) -> [MoversPreparationPage]`

1. Four education pages (copy verbatim below).
2. Intro page (always).
3. One page per **surviving** call-sheet section, in say → ask → get order.
   Blank predicate: an item is dropped iff its whitespace-trimmed form is
   empty; **surviving items keep their original untrimmed catalog string**
   (trimming is a predicate, never a transform — copy stays verbatim).
   A section with no surviving items emits no page; nil sheet → no section
   pages.
4. Builder stamps `primary: .getQuotes` on the final page and `.advance` on
   all others — positional, so no composition (nil sheet, `get: []`,
   trailing-empty sections, only-one-section) can strand the CTA.

Model state: `preparationPages: [MoversPreparationPage]`,
`preparationIndex: Int = 0`. Pages are built in `prepare()` after
`loadCallSheet()`, and **`preparationIndex` resets to 0 whenever pages are
rebuilt** (re-prepare after failure/retry included).

Transitions (bounds-guarded, round-2 F5):

```swift
func advancePreparation() { preparationIndex = min(preparationIndex + 1, preparationPages.count - 1) }
func backPreparation()    { preparationIndex = max(preparationIndex - 1, 0) }
```

Pure index arithmetic — structurally cannot reach the chain. Repeated calls
at either end are no-ops (unit-tested). First card hides Back
(`preparationIndex == 0`). `initialStage()` returns `.preparation` where it
returned `.protectionEducation` (`MoversFlowViewModel.swift:120`). Legacy
inline + compare-role paths untouched.

### Stack counter — exact truth table (round-2 F1)

The non-legacy get-quotes route is preparation → confirmation (no
quotes/matrix — see current-state table), so the routes are disjoint and
each gets an explicit row. `N = preparationPages.count`. Model exposes
`currentCardIndex` and `cardsRemaining`; both are unit-tested against this
table verbatim.

| Route | Stage | currentCardIndex | cardsRemaining |
|---|---|---|---|
| getQuotes, non-legacy | .loading / .failure | 0 | N + 1 (full deck behind, matches today's look) |
| getQuotes, non-legacy | .preparation (index i) | i | (N + 1) − i |
| getQuotes, non-legacy | .confirmation | N | 1 |
| getQuotes legacy-inline / compareQuotes | .loading / .failure | **0 / 0** | **5** |
| getQuotes legacy-inline / compareQuotes | .quotes | **3** | **2** |
| getQuotes legacy-inline / compareQuotes | .matrix | **4** | **1** |
| getQuotes legacy-inline / compareQuotes | .confirmation | **4** | **1** |

Compare/legacy tuples are **today's values bit-for-bit** (round-3 F1):
`TaskFlowStack` keys its slide transition on `.id(currentIndex)`
(`TaskFlowStack.swift:56`), so index values are presentation behavior, not
bookkeeping — loading→quotes must stay 0→3 (transition fires),
matrix→confirmation must stay 4→4 (no transition fires), and loading/failure
keep remaining 5 (same depth-card look). On the non-legacy route
currentCardIndex is strictly monotonic per advance; on compare/legacy it is
**nondecreasing** (matrix→confirmation repeats 4), exactly as today.
`FindMoversFlow.swift:45-48` passes these model values instead of the enum
statics.

### Complete list of edit sites (round-1 finding 1)

| File | Edit |
|---|---|
| `MoversFlowStage.swift` | 6-case enum; delete `stackIndex`/`cardsRemaining`; keep `persistedTaskStage`; add `MoversPreparationPage` |
| `MoversFlowViewModel.swift` | `buildPreparationPages` + state (index reset on rebuild); bounds-guarded `advancePreparation`/`backPreparation` replacing education arms; `initialStage()` `.preparation`; truth-table `currentCardIndex`/`cardsRemaining` |
| `FindMoversFlow.swift` | `stageContent` switch: `.preparation` renders by page kind; primary binding maps `.advance`/`.getQuotes`; stack params from model |
| `MoversEducationView.swift` | `callout` → `String?` (nil hides the box); body content wrapped in the shared fit-or-scroll wrapper (round-2 F2 — education pages scale too) |
| `MoversEquipView.swift` | Remove `ScrollView`; render ONE page (intro or call-sheet section) per instantiation; shared fit-or-scroll wrapper; call-sheet items rendered with **relative** SwiftUI fonts (round-2 F4), not `TaskContentBullet`'s fixed 17pt |
| `TaskContentSections.swift` | add the shared `fitOrScrollCard(idPrefix:)` wrapper (file already in PHASE_MANIFEST); `TaskCallSheet`/`CallSheetSection` themselves untouched |
| `PHASE_MANIFEST` | already lists every file above; add the new test file |
| `Peezy 4.0Tests/MoversPreparationPagesTests.swift` | new — page-builder fixtures, index-bounds tests, truth-table tests, 375×667 hosted layout tests |

Nothing else references the deleted cases (repo-wide grep, round 1 confirmed
no site was missed beyond these).

## Copy (verbatim from the brief)

| # | Title | Body |
|---|---|---|
| 1 | If something breaks | By law, moving companies only have to pay 60 cents per pound for anything damaged beyond repair. |
| 2 | What that means in real money | Say your $1,000 TV weighs 50 pounds and gets destroyed. They legally owe you $30. Not $1,000 — $30. |
| 3 | What to do about it | If that doesn't worry you, skip it. If it does, ask every company what additional coverage costs and exactly what it covers — before you book. |
| 4 | How quotes really work | A quote is a guess: their hourly rate × how long they think it'll take. A lower total usually just means a smaller guess — the job costs whatever it actually takes. Compare the hourly rates and crew sizes, not the totals. |

Icons: 1–3 `shield.lefthalf.filled`, 4 `clock.badge.questionmark`. No
callouts. Call-sheet pages reuse catalog copy verbatim (post blank-filter,
which is identity on current content).

Accessibility prefixes: `movers.education.valuationRule` / `.valuationMath`
/ `.valuationAction` / `.estimates`; equip pages keep every existing id
(`movers.equip.title`, `.intro`, `.shareInventory`, `.inventoryMissing`,
`.inventoryCard`, `.error`, `.getQuotes`, `.screen`) with additive per-page
ids (`movers.equip.say`, `.ask`, `.get`).

## Overflow + Dynamic Type (round-1 findings 3, 4, 5)

Character arithmetic is abandoned as a fit proof. The mechanism:

**Shared `fitOrScrollCard(idPrefix:)` wrapper** — applied to the card BODY
of **both** `MoversEducationView` and `MoversEquipView` (round-2 F2; the
221-char education card scales too). Semantics specified precisely
(round-2 F3):

- `ViewThatFits(in: .vertical)`; first candidate is the plain content with
  `.fixedSize(horizontal: false, vertical: true)` on the container so it
  reports its **intrinsic** height and cannot "fit" by compressing children;
  second candidate is `ScrollView { same content }`.
- Header (`TaskFlowHeader`) and the primary button stay **outside** the
  wrapper — matching today's structure — so the action is always visible
  even when the body scrolls.
- Branch-specific test identifiers: `"\(prefix).fit"` on the plain branch,
  `"\(prefix).scroll"` on the fallback — layout tests assert which branch
  was selected.
- Typography rule: every text inside wrapped bodies uses **relative** fonts
  (`.title`, `.body`, `.headline`). Education views already comply;
  call-sheet items are rendered with relative `.body` bullet rows in
  `MoversEquipView` instead of `TaskContentBullet` (fixed 17pt,
  `peezyTheme.swift:68`) so the fallback can actually engage (round-2 F4).

Verification of fit (round-2 F4/F10) — deterministic, not screenshots alone:

1. **Hosted layout tests** (new test file, runs under `xcodebuild test`):
   each page mounted in a `UIHostingController` sized **375×667**
   (SE-class floor; no SE simulator exists, so the window is pinned
   in-test) **rendered through `TaskFlowStack` so the production
   `peezyCardChrome()` 340-width/500-cap constraint applies** — a raw page
   in the full window would see ~667pt and could report a false fit
   (round-3 F2). Assertions:
   - Default Dynamic Type: `.fit` branch identifier present on every page
     (no scrolling, by construction).
   - `.accessibility5`: **exactly one branch present per page**; where
     `.scroll` is selected, the last element must be reachable by
     programmatic scroll-to-bottom; and the known-longest page (education
     card 4, 221 chars) must select `.scroll` so the fallback is proven to
     engage at least once. Short pages legitimately keeping `.fit` is a
     pass, not a failure (round-3 F3).
   - The intro page is hosted in **both** states — `hasSubmittedInventory`
     true (44pt ShareLink) and false (wrapping text,
     `MoversEquipView.swift:43-64`) — at both type sizes, since the two
     branches have different heights (round-3 F4). Fixture count: 9 hosted
     configurations (7 pages + intro ×2).
2. **Simulator screenshot pass** (human-checkable evidence): all pages on
   iPhone 16e (390×844) at default Dynamic Type — no spill, `.fit` branch.

No chunking machinery: current sections are 2–4 items and must be *proven*
to fit by the layout tests. Rendered-height partitioning for hypothetical
future catalog copy violates the repo boundary ("don't design for
hypothetical future requirements"); the fallback already makes that case
scroll instead of break. `actionError` keeps **exactly today's
presentation** (unbounded text between body and button,
`MoversEquipView.swift:75-83`) — no `lineLimit`, no truncation, no change
to the error contract (round-2 F9); real chain errors are single sentences
and the region sits outside the wrapper, same as today's footer.

## Chain-edge protection (round-1 finding 6)

- `advancePreparation()`/`backPreparation()` are pure index arithmetic on
  the model — structurally incapable of invoking `completeGetQuotes()`.
  Wiring: only the final page's primary button binds `onGetQuotes`; the
  binding site is one switch arm in `FindMoversFlow`.
- Final page while `isCompleting`: primary disabled (existing) **and Back
  hidden** (`showBack: !isCompleting`) so the user cannot leave the
  error/retry surface mid-flight. (Today Back is live during in-flight —
  this closes that hole rather than widening it.)
- `completeGetQuotes()` body, `chain.runEdge`, exit-lock, and
  `.confirmation` routing: zero diff (checked by `git diff` at the end).
- Unit tests (new test file): builder fixtures below + "final-page index is
  last for every fixture."

## Acceptance criteria (round-1 finding 7)

Fixture matrix for `buildPreparationPages` (round-2 F6 — every composition
that can move the final CTA):

| Fixture | Expected pages | Final (`primary == .getQuotes`) |
|---|---|---|
| Full BOOK_MOVERS sheet | 4 edu + intro + say + ask + get = 8 | get |
| Nil sheet | 4 edu + intro = 5 | intro |
| `say: []` (leading empty) | 7 | get |
| `get: []` (trailing empty) | 4 edu + intro + say + ask = 7 | **ask** |
| `ask: []` + `get: []` (multiple trailing empty) | 6 | **say** |
| only-say / only-ask / only-get | 6 each | that section |
| all three empty arrays | 5 | intro |
| whitespace-only items in a section | that section's page absent; CTA repositions accordingly |
| Every fixture | exactly ONE page has `.getQuotes` and it is last; all other pages `.advance` |
| Every fixture | surviving titles/bodies/items are byte-identical to source strings (verbatim check — trimming is only the drop predicate, round-2 F7) |

Behavioral criteria:

| Criterion | Check |
|---|---|
| Build succeeds | `xcodebuild … -destination "platform=iOS Simulator,name=iPhone 17 Pro" build` |
| Unit + layout tests pass | `xcodebuild test` on the new test file (fixtures, index bounds, truth table, 375×667 hosted layout) |
| Exact education copy | builder fixtures compare against the brief's strings verbatim |
| No default-DT scrolling at the SE-class floor | hosted layout test, 375×667 **through TaskFlowStack/card chrome**, 9 configurations (7 pages + intro ×2 inventory states): `.fit` branch asserted |
| Accessibility reachability | hosted layout test at `.accessibility5`: exactly one branch per page; scroll-to-bottom reaches last element wherever `.scroll` selected; longest page (education 4) must select `.scroll` |
| Counter presentation parity | truth-table test: compare/legacy tuples (0,5)(3,2)(4,1)(4,1) bit-for-bit today's values; transition identity preserved (`.id(currentIndex)`) |
| Human-checkable fit evidence | screenshot pass, all 8 pages, iPhone 16e, default DT |
| Back/forward stability | index-bounds unit tests (repeated advance/back at both ends are no-ops); manual 1→8→1→8 sequence lands on identical pages; card-1 Back hidden |
| Counter monotonicity + route preservation | unit test asserts the full truth table, incl. compare/legacy 2→1→1 unchanged |
| Identifier set explicit (round-2 F8) | assert against an expected-set list, not a preservation grep. **Kept:** all `movers.equip.*` ids, `movers.education.estimates.*` (minus `.callout`). **Intentionally removed:** `movers.education.protection.*` (page replaced by three `valuation*` prefixes), all `movers.education.*.callout` (callouts dropped by design). **Added:** `movers.education.valuationRule/.valuationMath/.valuationAction.*`, `movers.equip.say/.ask/.get.*`, per-card `.fit`/`.scroll` branch ids |
| Final-action placement | fixture assertion on `primary`: exactly one `.getQuotes`, always last; render switch is the single chain-closure binding site (code review) |
| Chain untouched | `git diff` shows no hunk in `completeGetQuotes`, `MoversChainCoordinator`, `persistedTaskStage` semantics; existing `MoversChainCoordinatorTests` still pass |

## ADR

- **Decision:** One `.preparation` stage + model-owned page array; pure page
  builder with blank-predicate filtering, verbatim strings, and
  model-encoded final action; shared intrinsic-height `ViewThatFits`
  fallback on both views with relative fonts; truth-table stack counter
  computed by the model; hosted 375×667 layout tests as the fit proof.
- **Drivers:** one-idea-per-card; no default-DT scrolling; verbatim catalog
  copy; spawn/persistence edges frozen; accessibility must not regress.
- **Alternatives considered:**
  1. *Per-beat enum cases (rev 1).* Rejected — three exhaustive-switch edit
     sites and a static `stackIndex` that cannot express a dynamic page
     count; round 1 showed the view-local equip index could not drive
     `TaskFlowStack` at all.
  2. *Keep ScrollView, shorten copy.* Rejected — copy is fixed verbatim and
     scrolling is what's being removed.
  3. *Rendered-height partitioning of sections.* Rejected — machinery for
     content that doesn't exist; fallback already degrades safely.
  4. *Blanket ScrollView removal.* Rejected — unreachable content at
     accessibility sizes (round-1 finding 5).
- **Consequences:** flow length 3 → 8 cards for get-quotes; enum shrinks;
  stack-depth logic centralizes in the model; new unit-test file added to
  PHASE_MANIFEST.
- **Follow-ups:** none — no migration, reseed, or deploy.

## Reviewer pushback (deliberate rejections, with rationale)

- **R1-F8 (intro + share = two ideas):** Rejected. The brief explicitly
  composes card 1 as "'Get three quotes' intro + Share-your-inventory
  button." The share button is the action affordance of the intro's single
  idea ("give every company the same facts"), not a second idea. Splitting
  it contradicts the product owner's stated sequence.
- **R1-F4 (full rendered-height partitioning):** Adopted only as
  blank-predicate filtering + fit-or-scroll degradation + hosted layout
  tests over real content. Measurement-driven chunking is rejected per the
  repo's boundary constraint against hypothetical-future engineering. (The
  `lineLimit(3)` proposed in rev 2 was itself withdrawn per R2-F9 — the
  error surface now changes not at all.)
- **R1-F6 / R2-F6 (closure-spy/UI test):** Adopted as model-encoded
  `PrimaryAction` fixtures (stronger than positional inference) +
  structural argument (advance/back are bounds-guarded index arithmetic
  that cannot reach the chain) + existing chain tests. A full UI-test
  harness for one switch-arm binding still exceeds the change's footprint;
  the binding site is unique and code-reviewed.

## Out of scope

No commit. No Firestore writes. No catalog reseed. No changes to
`COMPARE_MOVING_QUOTES`, `BOOK_YOUR_MOVERS`, legacy inline resume, or any
`onStatusAction` destination.
