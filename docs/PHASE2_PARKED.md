# Phase 2 is parked (8 September 2026)

Phase 2 was a large piece of behind-the-scenes work on Peezy. Four of its seven stages were finished. **None of it is switched on.** The app today runs exactly as it did before Phase 2 started, and stopping here changes nothing that a user can see.

This page explains what was built, why it is invisible, and what someone would need to do to finish it.

## The problem Phase 2 set out to solve

When the app asks the server to do something important — delete your account, reset your plan, submit a form to a mover — three things can go wrong. The phone can lose signal halfway through. The app can be closed mid-request. Or you can sign out and back in while it is still running.

In each case the app cannot currently tell the difference between "it never happened" and "it happened but I never heard back". That matters most for account deletion, because the app tells you your data is gone, and it should only say that when it can prove it.

Phase 2's job was to make those operations survivable: write down what you are about to do *before* you do it, and on the next launch look at what you wrote and finish or safely abandon it.

## What was actually built (stages 1–4)

- **Stage 1** put in the connection points — the places where the real Google, Apple, notification and storage pieces will eventually plug in. For now each one has a stand-in used only by the tests.
- **Stage 2** built the server side: cloud functions that record each request and its outcome, so the phone can later ask "did this actually go through?" and get a truthful answer.
- **Stage 3** added the scheduling rules, the conversion of older saved data into the newer format, and the server half of account deletion.
- **Stage 4** built the account-deletion machine that runs on the phone. It writes a small file describing the deletion in progress, steps through it in a fixed order, and can pick up from any interruption. Alongside it sits the privacy clean-up that removes local traces, and a recovery system that repairs or quarantines any of these files if they are damaged.

Roughly 8,800 lines of reviewed code, with about 600 tests written against it.

## Why none of it is visible

Nothing creates these objects when the app launches. The final stage — the one that would have connected them to the running app and deployed the server pieces — was never done.

Think of it as a new engine that has been built and bench-tested but never bolted into the car. The car still runs on its old engine. The new one sits in the corner of the workshop, complete and tested, connected to nothing.

This was deliberate. The plan built and proved each piece in isolation first, and left the switch-on to the very end so it could be done once, deliberately, rather than piecemeal.

## What stages 5–7 would have done

- **Stage 5** would have replaced every test stand-in with the real thing — real Google sign-in, real Apple account checks, real notification removal, real secure-storage access — and added the last piece of storage the others depend on. It was started and stopped: one small unit of it (a set of data definitions with 14 tests) is committed, and like everything else it is connected to nothing.
- **Stage 6** would have added the remaining server actions and the scheduling behaviour that depends on them.
- **Stage 7** was the switch-on: wire everything into app startup, deploy the server functions and security rules, and run the final pre-release checks.

## Three questions that were never settled

Anyone resuming this should know these are open, because work stopped on them rather than guessing:

1. **The mover-form submission path does not currently work end to end.** The part that writes the record and the part that reads it back disagree in six specific ways — different naming, different identifiers, different version numbers. This was found during review, confirmed independently, and never repaired, because the files involved belong to already-finished stages.
2. **Resuming an interrupted handoff between two devices has no defined next step.** Four review rounds could not find one in the specification, and the mechanism proposed to close it turned out not to work.
3. **Who performs the final "apply the result locally" step** was reassigned to stage 6 but the paperwork was never fully squared, and two related items still point at the wrong stage.

All three are written up in the project ledger with the exact evidence.

## The state of things right now

- **The app builds.** Confirmed on 8 September 2026 against the iPhone 17 Pro simulator: `BUILD SUCCEEDED`.
- **The tests pass.** With all of this work dormant:
  - Server tests, run offline: **365 tests, 360 pass, 0 failures** (5 are skipped because they need the local test server running).
  - Server tests, run against the local test server: **191 of 191 pass.**
  - Security-rule tests: **25 of 25 pass.**
  - App tests, the Phase 2 set: **216 tests across 12 groups pass**, plus 15 older-style tests with 1 skipped and no failures.

One caveat worth recording honestly: running the *entire* app test suite in one go does not work in this project and never has. Several tests need a local Firebase test server, and without it the test process crashes rather than failing cleanly. The suites listed above are run through `scripts/test-emulator.sh`, which starts that server first. That is the project's normal way of running tests, not a workaround introduced here.

## If someone picks this up later

Read these four things, in this order. Together they are the complete handover.

1. `PEEZY_STATE.md`, section 4 — the current version numbers and file fingerprints.
2. `STATUS.md` — a one-page snapshot of where each stage stands.
3. `HANDOFF.md` — how to run the builds and tests, and the traps that cost the most time.
4. `tasks/todo.md` — the running ledger. The last few entries explain exactly why work stopped.

The specification everything is built against is `docs/plans/PHASE2_CONTRACT.md`. It is the single source of truth; older planning documents were archived in September 2026 and should not be read.

Two practical notes. Nothing has been deployed — no server function, no security rule, no configuration change is live. And picking up at stage 5 means starting with the three open questions above, because two of them block work that comes later.
