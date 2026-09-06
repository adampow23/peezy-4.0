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
