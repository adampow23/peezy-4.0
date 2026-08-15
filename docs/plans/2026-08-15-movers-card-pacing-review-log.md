# Plan Review Log: Movers education + equip card pacing

MAX_ROUNDS=3, BUDGET=6 chain rounds, strict=false (blocks on HIGH+),
reviewer model=gpt-5.6-sol, codex-cli 0.147.0.

Plan: `2026-08-15-movers-card-pacing.md` (scratchpad — repo `docs/plans/` is
blocked by the PHASE_MANIFEST PreToolUse hook).

| Round | Verdict | Findings |
|---|---|---|
| 1 | ITERATE | 9 (1 CRITICAL, 6 HIGH, 2 MEDIUM) |
| 2 | ITERATE | 10 (6 HIGH, 4 MEDIUM) — all new; convergence check passed |
| 3 | ITERATE | 4 (2 HIGH, 2 MEDIUM) — all new, all accepted in Rev 4; round cap hit |
| 4 | **APPROVE** | 0 — user-approved extension round |

---
## Round 1 — Codex (thread 01a0046c-9dd2-75b2-a86c-19813c0bf2b0)

1. **CRITICAL — The enum-change inventory is incomplete and contradictory.** Removing `.protectionEducation` requires changing `initialStage()` in [MoversFlowViewModel.swift](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/MoversFlowViewModel.swift:112>), despite declaring it unchanged. The exhaustive `stageContent` switch in [FindMoversFlow.swift](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Tasks/Task Cards/FindMoversFlow.swift:74>) is also omitted. Conversely, `advanceEducation` and `goBack` are not exhaustive because they have `default` arms. `persistedTaskStage` must be edited to compile, even if its mapping semantics remain unchanged.  
   **Fix:** List and sequence all required edits explicitly: enum cases → `initialStage` → `stageContent` → `stackIndex`/`persistedTaskStage` → forward/back transitions.

2. **HIGH — The proposed stack counter cannot work with the stated state ownership.** [TaskFlowStack.swift](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Tasks/Task Card Components/TaskFlowStack.swift:17>) receives only `model.stage.stackIndex`, so an index local to `MoversEquipView` cannot affect its identity or remaining-card count. A single `.confirmation` index also cannot represent both the dynamic get-quotes route and the shorter compare route. The claimed “up to 8” is false once chunking is dynamic, and the current catalog has eight preparation cards plus confirmation.  
   **Fix:** Lift the preparation-page index and derived page count into `FindMoversFlow` as the single source of truth, with role-specific global index/remaining calculations.

3. **HIGH — The code-verified layout claim is wrong.** [PeezyCardChrome.swift](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Assessment/PeezyTheme/PeezyCardChrome.swift:28>) fixes width but only caps height with `maxHeight`; it is not a fixed 340×500 frame and does not clip overflowing children. Education text gets roughly 260 points after outer and `taskContentCard()` padding, not 340. The reported body counts are also wrong: 96/99/142/221, not 108/99/146/232.  
   **Fix:** Replace character arithmetic with rendered measurements/screenshots for every page at the actual 260-point text width and smallest supported portrait viewport.

4. **HIGH — “Four items per chunk” does not guarantee fit.** One arbitrarily long catalog item can overflow by itself; `TaskCallSheet` also permits `[""]` or whitespace-only items, producing visually blank cards. The plan’s “ask is tallest” claim is unsupported: `ask` totals 219 characters, while `say` totals 256 and contains a 140-character bullet; only one BOOK_MOVERS item exceeds 100 characters, not “several.” An unbounded `actionError` can also overflow the final card.  
   **Fix:** Normalize blank entries and partition using a tested rendered-line/height budget, with a bounded or separately presented error surface.

5. **HIGH — Removing every `ScrollView` creates a Dynamic Type accessibility regression.** The acceptance rule forbids scrolling only at default Dynamic Type; the education views use scaling text, so longer pages can exceed 500 points at accessibility sizes and become unreachable. The plan’s grep asserting no `ScrollView` is therefore the wrong invariant.  
   **Fix:** Require no scrolling at default size while providing a conditional accessibility-size scroll/reflow fallback, verified at the largest supported Dynamic Type size.

6. **HIGH — An unchanged spawn method does not prove an unchanged spawn contract.** Moving the CTA changes the call site that gates `completeGetQuotes()`. The plan lacks proof that intermediate Continue buttons never invoke it, the final CTA invokes it exactly once, and failed completion remains on the final page. Back also remains usable during `isCompleting`, allowing the user to leave the error/retry surface while the edge is in flight.  
   **Fix:** Disable preparation navigation during completion and add a closure-spy/UI test covering zero pre-final calls, one final call, failure/retry, and success-to-confirmation.

7. **HIGH — Acceptance criteria are missing for most deliverables.** Build, grep, diff, and unspecified screenshots do not test exact copy, section ordering, nil/partial/oversized call sheets, stable back/forward behavior, counter monotonicity, preserved identifiers, final-action placement, or chain behavior. A grep cannot prove that every `View` has a meaningful unique identifier.  
   **Fix:** Add an explicit fixture matrix and expected page/order/button/back/index results, plus per-page snapshot checks and the existing chain regression suite.

8. **MEDIUM — Card 1 still violates “one card = one idea.”** It combines the “Get three quotes” lesson with a distinct “Share your inventory” card/action, even though the plan identifies those as separate current-screen components.  
   **Fix:** Make inventory sharing its own page, including the not-scanned state, and update dynamic totals accordingly.

9. **MEDIUM — The simpler alternative is not fairly evaluated.** The plan rejects local paging because the stage would not identify the visible card, then immediately places multiple dynamic pages behind one `.equip` stage. Since these preparation stages are not persisted, a single pure `[MoversPreparationPage]` sequence owned by `FindMoversFlow` would reduce enum and switch churn while solving back navigation and stack counting coherently.  
   **Fix:** Compare the proposed hybrid against one flow-owned preparation-page array and adopt it unless an actual external consumer requires per-education-stage identity.

VERDICT: ITERATE
### Response (rev 2)

- F1 (CRITICAL, incomplete enum inventory): ACCEPTED — plan now lists every
  edit site in a table (enum, initialStage, stageContent, persistedTaskStage,
  transitions) and corrects the "exhaustive" mischaracterization.
- F2 (stack counter): ACCEPTED — resolved by adopting F9's architecture;
  model owns preparationIndex and computes currentCardIndex/cardsRemaining.
- F3 (layout claim wrong): ACCEPTED — verified independently: maxHeight cap
  not fixed frame, no clipping, 260pt text width, corrected counts
  96/99/142/221. Character arithmetic abandoned as a fit proof.
- F4 (chunk-by-count insufficient): PARTIAL — blank/whitespace filtering,
  lineLimit(3) on actionError, ViewThatFits degradation, screenshot proof of
  real content. Full rendered-height partitioning rejected (repo boundary:
  no machinery for hypothetical future content).
- F5 (Dynamic Type regression): ACCEPTED — ViewThatFits(in: .vertical) with
  ScrollView fallback branch; grep invariant restated as "only ScrollView is
  the fallback branch"; accessibility5 screenshot added.
- F6 (spawn contract proof): PARTIAL — advance/back are pure index
  arithmetic (structurally cannot reach the chain), primary binds only at
  pages.count-1 (fixture-asserted), Back hidden while isCompleting (closes
  an existing hole). New UI-test harness rejected as exceeding footprint.
- F7 (acceptance criteria): ACCEPTED — fixture matrix + behavioral criteria
  table added.
- F8 (intro+share = two ideas): REJECTED — the product brief explicitly
  composes card 1 this way; share button is the intro idea's affordance.
- F9 (simpler alternative): ACCEPTED — flow-owned page array adopted as the
  architecture; per-beat enum cases dropped.

## Round 2 — Codex (same thread)

1. **HIGH — The stack formula is still inconsistent.** Rev 2 assigns `.matrix` and `.confirmation` the same index while claiming strict monotonic increments. It also says compare starts with three remaining, but current [MoversFlowStage.swift](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/MoversFlowStage.swift:20>) reports two. Finally, `total(role)` cannot distinguish non-legacy `.getQuotes` from the legacy-inline `.getQuotes` route.  
   **Fix:** Specify and unit-test an exact `(role, isLegacyInline, stage, preparationIndex) → (currentIndex, remaining)` truth table, deciding explicitly whether compare’s current 2→1→1 behavior changes.

2. **HIGH — The accessibility fallback does not clearly cover education cards.** The edit inventory says [MoversEducationView.swift](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Tasks/Task Cards/MoversEducationView.swift:14>) only changes `callout`, while only `MoversEquipView` receives `ViewThatFits`; therefore the longest scaling education page can still overflow at accessibility sizes.  
   **Fix:** Apply one shared `ViewThatFits` card-layout wrapper to both education and equip pages and list that change explicitly.

3. **HIGH — `ViewThatFits` needs a non-compressible first candidate.** A flexible `VStack` may report that it fits by compressing children, preventing selection of the scroll fallback even when content truncates or spills. The plan does not specify branch structure or measurement semantics.  
   **Fix:** Make the plain candidate vertically intrinsic with `.fixedSize(horizontal: false, vertical: true)`, keep header/action outside the body fallback where practical, and add branch-specific test identifiers.

4. **HIGH — The accessibility test assumes call-sheet typography scales, but current bullets do not use relative fonts.** [TaskContentBullet](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Tasks/Views/TaskContentSections.swift:450>) uses `PeezyTheme.Typography.body`, which is a fixed 17-point font in [peezyTheme.swift](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Assessment/PeezyTheme/peezyTheme.swift:63>). A screenshot also cannot prove that a view scrolls or that its bottom content is reachable.  
   **Fix:** Require relative `.body`/`.headline` fonts for the new pages and verify the fallback with an actual swipe-to-bottom check, not a static screenshot.

5. **HIGH — Preparation index invariants are underspecified.** `advancePreparation()` is described as unconditional `index += 1`, `backPreparation()` likewise decrements, and `prepare()` does not explicitly reset the index. Repeated actions or retry/reprepare can make `preparationPages[preparationIndex]` invalid.  
   **Fix:** Guard both bounds, reset the index whenever pages are rebuilt, and unit-test repeated advance/back calls at both ends.

6. **HIGH — The fixture matrix misses the cases that can move the final CTA.** Testing `say: []` covers only a leading omission; it does not cover `get: []`, only-say, only-ask, only-get, or multiple blank trailing sections. Also, asserting that the last index is last cannot prove that `onGetQuotes` is actually bound there.  
   **Fix:** Add every single-surviving-section/trailing-empty fixture and either encode `.continue`/`.complete` in the page model or test the rendered action with a closure spy.

7. **MEDIUM — “Trimmed” conflicts with “verbatim.”** Trimming every nonblank item changes catalog strings, while the acceptance test requires exact source equality.  
   **Fix:** Use trimming only as the blank predicate, but retain the original nonblank string unchanged.

8. **MEDIUM — The identifier acceptance criterion cannot pass as written.** Existing `movers.education.protection.*` and `.callout` identifiers disappear when the prefix changes and callouts are removed, despite the criterion requiring every pre-existing education identifier to remain.  
   **Fix:** Document the intentional identifier removals and assert an explicit expected identifier set rather than using a preservation grep.

9. **MEDIUM — `.lineLimit(3)` silently weakens the existing error contract.** It can hide recovery information and contradicts the stated accessibility goal that all content remain reachable.  
   **Fix:** Keep the complete error inside the scroll fallback or present a bounded friendly alert instead of truncating arbitrary error text.

10. **MEDIUM — The smallest supported layout remains unverified.** A 375×667 SE-class viewport can be tested without an installed simulator using a fixed-size preview or snapshot; merely recording it as residual leaves the primary fit requirement open.  
   **Fix:** Add a deterministic 375×667 preview/snapshot fixture at default and accessibility Dynamic Type.

VERDICT: ITERATE
### Response (rev 3)

Convergence check: all 10 findings are new (attack rev-2 specifics, none
restate round 1) — loop is progressing, round 3 justified.

- F1 (stack formula): ACCEPTED — exact per-route truth table added
  (non-legacy get-quotes never visits quotes/matrix — route discovered and
  documented); compare/legacy 2→1→1 explicitly preserved; unit-tested.
- F2 (education not covered by fallback): ACCEPTED — shared
  fitOrScrollCard applied to BOTH views; listed in edit inventory.
- F3 (ViewThatFits semantics): ACCEPTED — intrinsic-height first candidate
  via fixedSize, header/button outside wrapper, .fit/.scroll branch ids.
- F4 (fixed fonts): ACCEPTED — verified Typography.body = fixed 17pt;
  call-sheet items re-rendered with relative fonts instead of
  TaskContentBullet; reachability via programmatic scroll-to-bottom in
  hosted tests, not static screenshots.
- F5 (index invariants): ACCEPTED — clamped advance/back, reset on rebuild,
  end-repetition unit tests.
- F6 (fixture coverage + CTA binding proof): ACCEPTED — PrimaryAction
  encoded in the page model; fixtures expanded to get:[], only-X,
  multi-trailing-empty, all-empty; exactly-one-.getQuotes-and-last asserted.
- F7 (trim vs verbatim): ACCEPTED — trimming is the drop predicate only;
  surviving strings byte-identical.
- F8 (identifier criterion): ACCEPTED — explicit expected-set with
  documented intentional removals replaces the preservation grep.
- F9 (lineLimit weakens error contract): ACCEPTED — lineLimit withdrawn;
  error presentation unchanged from today.
- F10 (SE-class unverified): ACCEPTED — hosted UIHostingController layout
  tests at 375×667 (default DT asserts .fit; accessibility5 asserts .scroll
  + reachable), running under xcodebuild test.

## Round 3 — Codex (same thread)

1. **HIGH — Compare/legacy presentation is not actually unchanged.** `TaskFlowStack` keys transitions with `.id(currentIndex)` in [TaskFlowStack.swift](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Tasks/Task Card Components/TaskFlowStack.swift:56>). Rev 3 changes loading→quotes from 0→3 to 0→0, matrix→confirmation from 4→4 to 1→2, and loading/failure depth from 5 remaining to 2; this removes one existing transition, adds another, and changes the decorative stack despite the out-of-scope claim.  
   **Fix:** Preserve the existing compare/legacy tuples exactly: loading/failure `(0,5)`, quotes `(3,2)`, matrix/confirmation `(4,1)`, and describe that route as nondecreasing rather than strictly increasing.

2. **HIGH — The hosted layout test can produce a false fit result unless it mounts the production card constraint.** A raw page in a 375×667 `UIHostingController` receives substantially more height than the 500-point cap imposed by [PeezyCardChrome.swift](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Assessment/PeezyTheme/PeezyCardChrome.swift:28>); Rev 3 does not explicitly say the harness includes `TaskFlowStack`/`peezyCardChrome()`.  
   **Fix:** Require every hosted fixture to render through `TaskFlowStack` or explicitly apply `.peezyCardChrome()`, then assert branch selection and geometry within that card.

3. **MEDIUM — The accessibility test asserts the wrong universal outcome.** At `.accessibility5`, a short page may legitimately still choose `.fit`; correctness is “plain if it fits, otherwise scroll and remain reachable,” not “all eight pages must scroll.”  
   **Fix:** Assert exactly one branch per page, test bottom reachability conditionally for `.scroll`, and require at least the known longest page to exercise the fallback.

4. **MEDIUM — The layout matrix omits the two materially different intro states.** The submitted-inventory branch renders a 44-point `ShareLink`, while the missing-inventory branch renders wrapping text in [MoversEquipView.swift](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Tasks/Task Cards/MoversEquipView.swift:43>); testing one intro configuration does not prove the preserved branch fits.  
   **Fix:** Host the intro page with `hasSubmittedInventory` both true and false at default and accessibility Dynamic Type.

VERDICT: ITERATE
### Response (rev 4)

Round cap (3) reached. All four findings ACCEPTED and applied to the plan
as Rev 4; none disputed:

- F1 (compare/legacy presentation): ACCEPTED — verified .id(currentIndex)
  keys transitions; truth table now preserves today's tuples bit-for-bit
  (0,5)(3,2)(4,1)(4,1); monotonicity restated as nondecreasing on that route.
- F2 (hosted test must mount production constraint): ACCEPTED — fixtures
  render through TaskFlowStack/peezyCardChrome; raw-window false-fit noted.
- F3 (wrong universal a11y assertion): ACCEPTED — exactly-one-branch per
  page; conditional reachability; longest page must exercise .scroll.
- F4 (two intro states): ACCEPTED — intro hosted with hasSubmittedInventory
  true and false; fixture count 9.

Disposition: cap hit without APPROVE. User asked: accept as-is / one more
round (budget remaining: 3) / abandon.

## Round 4 — Codex (same thread; user-approved extension)

No material findings. Rev 4 addresses all prior issues, preserves compare/legacy presentation identity, and provides testable fit, accessibility, navigation, and chain-edge acceptance criteria.

VERDICT: APPROVE
### Final summary

Consensus reached round 4. Rounds: 1 ITERATE(9) -> 2 ITERATE(10) -> 3 ITERATE(4) -> 4 APPROVE(0).
Chain budget spent: 4 of 6 (2 remaining for codex-execute).
