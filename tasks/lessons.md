# Lessons (Peezy 4.0)

## 2026-09-02 — v9 manifest / codex-review
- Execution-report sections (§14) must cite locations only; restating a phase mapping, gate value, or transition anywhere outside §8.9 is a P1 under "replace wins" — Sol flagged nine such sentences in the first v9 report.
- When two §8.9 subsections both touch an ordering (derive/handoff/publish), defer to the owning subsection instead of paraphrasing; the paraphrase created V9-04.
- "Pointer + leftover clause" (e.g., "retains durable state. See §8.9.1.") is not pointer-only; delete the clause or reclassify it as an event, never a consequence.
- Ledger keys shown in code font are parsed as keys by the reviewer; markers like "relocated" must be plain text.
- Prompt assertions about the worktree must match `git status` at session start; pre-existing untracked files caused a spurious scope finding.

## 2026-09-02 — stranded commits / cloud-vs-local handoff
- After any commit, mine or a block handed to Adam, verify `git show --stat HEAD` names every file the message claims. c9e14b9 and 6ac2ea4 both claimed files that never landed: one unmatched pathspec in `git add A B` stages nothing, and the commit goes through anyway.
- Shell blocks handed to Adam must not assume a `~/Downloads` file exists. Guard with `[ -f ... ] || { echo MISSING; exit 1; }` so the block fails loudly; the S1 brief copy failed silently and `briefs/` stayed empty.
- A Claude Code on the web session sees only what is pushed to GitHub. Before handing work to a cloud session, push first and confirm `git status -sb` shows no `ahead` count; main was 15 commits ahead of origin when the cloud session started.

## 2026-09-03 — emulator harness
- Never sign the simulator test host ad-hoc (`CODE_SIGN_IDENTITY=-`) or unsigned (`CODE_SIGNING_ALLOWED=NO`): both strip entitlements, so Firebase Auth's keychain write fails (-34018) and the XCTest runner cannot attach (launch denied, xcodebuild idles forever). The project's automatic signing produced the green runs.
- A named falsifier file must be executable before its slice starts: `functions/rules-tests/firestoreRules.test.js` needed `npm install` in functions/ for its declared dev dependency; nothing had ever run it.
- Foreground Bash caps at 10 minutes; a full app rebuild plus test run exceeds it. Warm the build first (`build-for-testing`), then run the emulator script, or run it in the background and wait with an `until` loop.

## 2026-09-06 — I6 registry
- Seed conflict fixtures as envelope bytes, not through `reserve`: the registry refuses to create a second same-UID row by design, so a fixture that goes through the API can only prove the refusal.
- The simulator reports no file-protection class; assert `.protectionKey` on device builds only and say so in the test.
- Inside `#expect`, `await` may only lead the expression; hoist any awaited operand that sits to the right of `&&` or `==`.
- When a slice must leave a user path identical, keep the legacy identity (here the UserDefaults operation id) as the server-facing one and let the new durable identity ride alongside; the spec forbids importing the legacy id as the new alias (v9:569).

## 2026-09-06 — S2 server implementation
- A reconciler fixture must advance its clock with each schedule boundary: the lease grammar requires `scheduled_at <= started_at`, so a fake clock left at the first boundary silently refuses every later acquisition and the run looks like it did nothing.
- A cursor that "advances to the selected row" revisits a single-row backlog only after a wrap; fixtures that expect the same row on consecutive runs are wrong, not the reducer.
- The in-memory Firestore must mirror Admin SDK value semantics or tests lie: `Date` values come back as `Timestamp`, `FieldValue.delete()`/`serverTimestamp()` are sentinel objects (never deep-cloned), and a concurrency probe must decrement when the response resolves, not on a timer.
- firebase-admin's package `exports` map blocks deep requires (`firebase-admin/lib/...`, even `package.json`); load SDK internals by filesystem path from `node_modules`.
- Never put a cron string inside a `/** */` comment: `*/5` closes the comment and breaks the module at parse time.
- Bash heredocs cannot carry raw control bytes (the tool rejects them); spell control characters in regexes with backslash-u escapes or use the Write tool.
- Real Firestore `set(..., {merge:true})` deep-merges nested maps, so a marker rewritten that way keeps every member the new projection dropped; replace whole fields with `update` (or a non-merge set) and make the in-memory fake deep-merge so the offline suite catches it.
- A fresh-context verification pass caught a test that had encoded the reducer's behavior instead of the contract sentence (enrollment during DELETING-guarding); write each falsifier's expectation from the contract line first, then watch it fail.

## 2026-09-06 — S3 brief
- Registry membership comes from the contract's C6 lists, not from ledger prose: the S2 close-out called `notifySupport.js` a fence writer and the S3 brief inherited it; C6.1 never lists it (it is a C6.2 provider with no Firestore write). Check each file against the registry before assigning it a call.
- A fixture family goes to the file the contract names for it: §12.3 gives every client decoder to `DurableStoreRecoveryTests`, so decoder mirrors do not belong in `TaskPlanDispositionTests` just because earlier slices extended that file.

## 2026-09-06 — S3 execution (contract-complete increments)
- Read-only test files pin implementation shapes, not just behavior: `processInventoryMerge.test.js` pinned the literal `sessionRef.update({` form and `TaskSupersessionTests.swift` pins the pre-S3 coordinator initializer. Before briefing a slice, grep the read-only tests for every symbol the slice must change; each hit is an owner decision, not a surprise at implementation time.
- Offline Firestore fakes in read-only suites implement different surfaces (`db.doc` only, `collection().doc()` only); a shared helper must resolve the owner root through whichever exists instead of assuming the Admin SDK.
- A rules predicate that dereferences `resource.data` denies reads of absent documents (the D15 point-path read precedes creation); write `resource == null || …` and keep a rules case for the absent root.
- `@firebase/rules-unit-testing`'s REST seeder matches `as Bool` before `as Int`, so NSNumbers from JSON fixtures are written as booleans; convert fixture numbers to Swift Ints before `adminSet`.
- Swift Testing rejects a `#require` nested inside another `#require` (and `try` inside its argument) with "recursive expansion"; hoist the inner expression.
- A background poller that greps for `xcodebuild` by command line matches itself; match the binary (`pgrep -x`) or run the build in the foreground.
- Freeze cross-language wire fixtures through the real handler on the fake Firestore and assert byte-equality from the Node side; the Swift decoder mirrors then read one committed file instead of restating shapes.

## 2026-09-06 — retro recommendations applied (PHASE2_RETRO_S1_S2, adopted as rules)
- Rec 1 (R12: C8 → C9 shapes + C10 ownership, then archive manifest v9 / spec v5): applied 2026-09-06; eight parallel ports, eight fresh-context verifiers, eight fixers; sources archived under docs/archive/phase2/ after the port.
- Rec 2 (one decision list per slice; never end on "result unknown"): applied — Decisions 10–11 raised in the ledger mid-slice and carried to the next report; in-flight runs are waited on before a turn ends.
- Rec 3 (warm project-signed build once per session; background runs with a single until-wait): applied — one `build-for-testing` per Swift change set; pollers match the xcodebuild binary, not their own command line.
- Rec 4 (drop process precision: preimage hashes → diff gate, C8 → PEEZY_STATE list, Reconciled → archive, no citations/Sources/restated hashes): applied in R12 (C7 diff gate, C1 spec row dropped, provenance archived, PEEZY_STATE §4 trail).
- Rec 5 (section reads only; PEEZY_STATE §4 + last ledger entry + brief at session start): applied from this point; recorded in PHASE2_WORKFLOW_v2 session rules.
- Rec 6 (RED = one named assertion fails; extend fakeFirestore.js once per slice before the first Node RED): applied — fakeFirestore.js gained field orderBy, forEach, range/in/array-contains operators, collection groups, snapshot cursors, count(); the I6 Swift families were re-run red under a deliberate break after the compile-only red.

## 2026-09-06 — S3 close-out
- Ownership resolves from the contract's C10 test-file rows, not from code comments or ledger prose: an S1 comment put the legacy-migration transitions in S3, but C10.4 assigns that family to S4. Check the C10 row before scoping an increment that a comment or brief line seems to imply.
- There is no `npm test` in `functions/`; the offline envelope is the contract's C10.9 command restricted to the files that exist, plus `accountDeletionFence.test.js`. Record the exact command in the close-out so the next session does not rediscover it.
- Emulator runs share ports: chain node, rules, and swift in one nohup script that writes a `.done` marker, then wait once. The Swift Testing total is the `Test run with N tests in M suites passed` line; counting `✘` matches Firebase log noise.

## 2026-09-06 — S3 close-out review (Swift pass + Sol diff review)
- Named falsifiers can pin the implementation instead of the contract: three S3 tests asserted that a deleting owner's candidate produces a refusal row (a C6.1 violation), and the sizing oracle copied production's array double-count. Before a family goes GREEN, name the contract sentence each assertion would fail against; a fixture that manufactures a precondition (refusals via a deleting owner) must itself be contract-legal.
- A verifier that says "no contract row" must quote the section it searched: the part-1 disposition of the drive singleflight missed C9.5.8's `inflightResetOperation` and C9.5.12's Winner/Join rows; the second-model review found them. Grep the contract for the mechanism's own name (slot, singleflight, in-flight) before writing "no row".
- Deletion-slice reviews pay for themselves: Sol's 15 findings yielded 11 fixes with new RED tests, 1 refutation, and 5 contract gaps for the owner; verify each finding against the contract with a fresh-context reader before touching code, and fix in groups (scheduler, fence/intents, historical migration, Swift) with one RED/GREEN log per group.
- `codex exec resume` drops the thread's model unless `-m gpt-5.6-sol` is passed; the first round-2 attempt died with HTTP 400 on the config default. Check the first jsonl lines for `turn.failed` before waiting on a round.

## 2026-09-06 — S3 close-out, owner decisions
- A fresh-context verifier of a contract amendment catches wording drift the author cannot see (subject/object inversion, a paraphrased criterion missing a clause, undefined tokens, register rows without test files). Run one on every amendment before registering the hash; the five S3-CD5..CD9 sentences all needed a precision pass.
- "Zero writes" is a stronger claim than "fail-closed refusal": a durable refusal record is a write beneath the owner. When the owner asks for a zero-write proof, the interim behavior must be a settle, and the tests that used the old refusal as a fixture need a new, contract-legal cause (an injected commit failure with bytes and identity untouched).
- A scoped fourth review round on fixes no reviewer had seen found three more defects (basis shape, signed-out foreign caller, Firestore timestamp domain). Post-cap fixes are exactly where the next defect lives; budget the extra round for deletion slices.

## 2026-09-06 — S4 (recovery/privacy UI + deletion orchestration)
- A deliberate break must be observable by a named test, and "the end state looks right" is not observation: the dose copy-before-remove order and the same-UID retired listener token both passed under their breaks until a fixture observed the intermediate step (a failing-read `UserDefaults` subclass; a late callback from the first listener of the same UID). Write the observing case before declaring RED.
- When two contract rows disagree, the more specific literal wins and the correction is a ledger line: C9.5.18 fixes the `reset_epoch_conflict` digest formula, C9.7.12's generic map does not override it. Grep for the mechanism's own digest before deriving one from a general rule.
- Read-only pins decide accessor design: S5's nudge tests read the raw dose keys after view-model writes, so Home's accessor keeps the shipped key names behind one type; moving a pin is an owner decision, not a slice's.
- The simulator keychain outlives the app configuration: a plain `signOut()` leaves the real app ID's Firebase Auth user item beside the emulator app's, so "keychain item absent" needs a scrub of every `firebase_auth_*` service, and the test must seed a stale item to make the scrub observable.
- Swift Testing traps that cost a rebuild each: `await` right of `&&`/`||` in `#expect`; a `Result` failure type that is not an `Error`; an enum pattern with the wrong number of placeholders ("failed to produce diagnostic"); `id` as a nested helper's parameter name; a `@MainActor` model test must be `@MainActor`; a test-double callback stored after it is recorded can race the test's completion — retry after yields.
- The named skills a brief cites may not exist in the session (`/swiftui-pro`, `/swift-concurrency-pro`): run the equivalent pass as read-only subagents with the same scope and record the substitution in the ledger.

- (S4 close-out) zsh does not word-split an unquoted `$LIST` of file paths; use `${=LIST}` (or bash) when building a `node --test` argument list, or the runner reports "Could not find" the whole string. A review-round fix that changes a contract-derived formula (the `rso1_` canonical ID) legitimately moves S4's own fixtures off their placeholders; read-only pins of other slices stay where they are and become owner decisions.
- (S4 close-out, rounds 6–7) When a client validator mirrors a server sanitizer, parity runs both ways. Round 6 caught the client accepting a `subject.kind` outside the server's closed set — including in the test's own positive fixture, which had been proving a row the server would reject. Round 7 caught the correction over-shooting: a 1,024-byte cap on `resumeDestination` that `cleanDescriptor` never imposes, a false negative that would drop a real server-written cycle out of its precedence row. Read the writer and copy *its* bounds: every constraint it has, and none it does not. A positive fixture must be byte-shaped like the writer's output, or it silently pins the wrong grammar.
- (S4 close-out, round 8) Cross-runtime string parity is not a detail. Foundation's `.whitespacesAndNewlines` is not ECMAScript's `String.prototype.trim` set: Foundation trims U+0085 and keeps U+FEFF, JavaScript does the opposite of both. A Swift client mirroring a Node sanitizer must build the exact set (`CharacterSet.whitespaces`, which is Zs ∪ U+0009, unioned with VT, FF, ZWNBSP, LF, CR, LS, PS) — and verify it by running the scalars through `node` before writing the Swift, not after.
- (S4 close-out, round 9) The first attempt at that set still derived from `CharacterSet.whitespaces`, which on Apple platforms contains U+200B even though U+200B left general category Zs in Unicode 4.0.1 — Foundation's documentation says "Zs plus tab" and its table disagrees. Never derive a cross-runtime set from a platform set whose membership you have not enumerated: build it scalar by scalar and check it exhaustively in both directions (`for v in 0..0x10FFF`) against the runtime you are mirroring. A set that is right for fifteen scalars and wrong for the sixteenth still picks the wrong branch.
- (S5 brief gate) "Mirror, don't invent" is only executable where the contract actually states the shape. The S5 brief asserted the contract fixed the handoff record grammar and the workflow store's schema; it fixes neither — only the empty payload, the recovery keys and a one-line phase summary for one, and only the fileKind, cap and counted universe for the other. Before writing "the contract states every shape" in a brief, grep for each named type and read what comes back; an absent schema is a mandatory amendment at I0, not a detail to settle while coding.
- (S5 brief gate) A six-lens verification with adversarial refutation caught 19 real defects and still missed a misassigned owner, two absent schemas, four uncovered register rows and a write to an excluded file. Independent passes are complements, not substitutes: the lens pass was told what to look for and found those things well; the gate read the brief as an implementer would and asked what it would be unable to build. Keep both.

## 2026-09-08 — S5 amendment re-gate (Astra): a table you call exhaustive is a claim, and it needs a falsifier like any other

The Astra re-gate found the same defect three times in amendments that two fresh-context passes and a nine-finding Sol round had already been over: **a table written as exhaustive that was not.**

- The handoff and workflow transition tables were indexed **by phase**. So `PREPARED → DISPATCHED → RECEIPT → APPLYING → (removed)` plus "no other edge exists" *forbade* the edge C9.7.8 L3730 requires — a loaded RECEIPT or APPLYING row is a `receipt_mismatch`, and on `absent` it goes back to DISPATCHED. A phase-indexed table cannot express a backward edge that belongs to one event and not another. An earlier fresh-context pass had looked straight at this area and "fixed" it in the wrong direction, which is the tell: when two passes disagree about the same edge, the *shape* of the statement is wrong, not the direction.
- **Rule: state a transition table as event × source phase, never phase → phase.** Then "exhaustive" is checkable: enumerate the events the contract can produce, and for each one list every source phase. The rewritten amendment says a phase-only statement of the table is unlawful, so the next writer cannot regress it.
- The same shape twice more: a member defined as a *map* in the grammar block and an opaque *string* in the opacity rule, so the digest had two preimages and "the sha256 hashes exactly this" was not a specification; and a sort declared "the frozen store order" without saying it is *serialization* order, which silently collided with a different rule's mismatch-selection order. **A representation and an ordering each need to say what they are for, or two rules will claim them.**

## 2026-09-08 — S5 amendment re-gate: never write a bound the authority does not have

Two of the four blockers were invented authority: a "frozen retry bound" that appears nowhere in the contract, and a retirement code that would have deleted the only receipt-bearing record without completing its application — against a rule that says those bytes are never dropped and always rerun. Both read as *completions* while drafting; both were amendments quietly changing a guarantee they had no authority to change.

**Rule: when an amendment adds a limit, a retirement, or a failure exit, find the existing rule that governs that state and quote it first.** If no rule bounds it, the contract's answer is "unbounded" — write that, and raise the bound as a decision. This is the same failure as inventing a byte cap the server does not impose, one level up: there it was a validator inventing a server constraint, here an amendment inventing a contract one.

## 2026-09-08 — S5 amendment re-gate: a falsifier that passes with the defect present is not a falsifier

S5-CD7 named `AppRootAuthRaceTests`'s guard test as its falsifier. That test exercises a pure predicate, `completionIsCurrent(...)`, and never invokes the helper the row changes — it passes with the defect fully present. The real pin was in a different file and required the literal `_ = await geocodeTask.value`, which the fix necessarily deletes; so the row was simultaneously unfalsifiable and unimplementable under its own "nothing else" clause.

**Rule: before naming a falsifier in a row, grep the named test for the symbol the row changes.** If the symbol does not appear, the test cannot fail on the change. And check the other direction too: grep every test file for the literal shape the fix removes, because the pin that must move is usually not the pin you were thinking of.

## 2026-09-08 — S5 amendment review: a state machine restated is a state machine that will disagree

Four review rounds on two new contract sections, and the defect count went **up** on the fourth. The cause was not drafting care; it was the choice to restate.

The contract expresses handoff and workflow records as recovery *classifications* and *named actions* spread over C9.7.3, C9.7.4, C9.7.6, C9.7.7, C9.7.9 and C9.7.11 — C9.7.4 L3569 says it outright: live rows are "never removed/changed except named reconciliation replacement". Writing a self-contained phase table for the same records created a second expression of one machine, and every pass found more edges the second expression contradicted or branded corruption.

**Rule: before writing a table that claims to be exhaustive over an existing system, find where the system already expresses those transitions.** If the answer is "in six other sections", the amendment's job is to state the *new* facts — member sets, immutability, ordering, uniqueness, caps, and the phase each already-named action lands on — and defer every existing edge by reference to the rule that owns it. A closing clause ("an edge in neither this table nor those named rules is corruption") keeps it closed without re-deriving anything.

Two corollaries the same review produced:

- **Check the happy path first.** My table had `apply`, `applied` and `applicationId` and no edge that stored a receipt outside recovery — so a normal successful dispatch had nowhere to put its response, RECEIPT was unreachable, and four rules were dead text. I had been so focused on the recovery edges a reviewer would attack that the ordinary one was never written. Enumerate the success path before the failure paths.
- **When a fix needs a new member, suspect the fix.** I added a durable watermark to allocate a generation, and it was wrong twice over: the premise was false (the server document is keyed on the submission token, so a reused generation addresses a different document) and the member introduced a permanent-wedge failure the previous design did not have. The real producer already existed one layer up, in the flow attempt's CAS. **A new member that exists to protect an invariant is worth checking against whoever already owns that invariant.**
