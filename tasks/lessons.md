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
