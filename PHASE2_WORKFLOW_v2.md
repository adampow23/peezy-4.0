# PHASE 2 WORKFLOW v2

Source of truth: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5
Supersedes the v6–v9 manifest loop. The manifest is a decision record now, not an instruction set.

## Five rules

1. Specify what must be true, not how to make it true. Contracts, state machines, registries, and named tests are the spec. Prose byte-shapes are not.
2. One brief per slice: job, why, boundaries with reasons, done. One page. If it needs a second page, the contract is missing something; fix the contract.
3. Tests are the reviewer. A slice is done when its named falsifiers were red, then green, on the emulator. No spec reviews.
4. Second-model diff review only on deletion slices (S3, S4). Everywhere else, skip it.
5. You get pulled in for three things only: a destructive action, a real scope change, or input only you have.

## Standard preamble (paste at the top of every Claude Code session)

```
Context: Peezy is an iOS moving-concierge app. The brand promise is "someone in your corner," and the Phase 2 work makes account deletion provably complete so that promise is true and legally defensible. PHASE2_CONTRACT.md is the authority for what must be true. PEEZY_STATE.md is the authority for project state.

How to work:
- When you have enough information to act, act. Don't re-derive established facts or re-litigate decisions already in the contract. If you're weighing a choice, give me one recommendation, not a menu.
- Do the simplest thing that satisfies the contract. No refactors, abstractions, feature flags, or defensive handling for cases the contract says can't happen. Validate only at system boundaries.
- Before reporting progress, check every claim against a tool result from this session. Only report what you can point to. If a test failed, show the output. If you skipped something, say so.
- Pause only for a destructive or irreversible action, a real scope change, or input only I can provide. Ask, then end the turn. Everything reversible that follows from the brief: just do it.
- Verification: every [interval] dispatch a fresh-context subagent to check the work so far against PHASE2_CONTRACT.md. Its findings are yours to fix, not to argue with.
- Destructive tests run only on the Firebase emulator or an enumerated non-prod target. Never production.
- Record lessons in LESSONS.md: one per entry, one-line summary on top, why it mattered. Don't record what the repo already shows. Delete entries that turn out wrong.
- Final message: outcome first, in complete sentences, for a reader who saw none of the work. Then what you need from me, if anything.
```

## Brief template (one per slice)

```
# SLICE S<n> — <name>

Job: <one paragraph: what exists when this is done>

Why: <two sentences: what it enables, who it's for>

Boundaries:
- <constraint> — because <reason>
- <constraint> — because <reason>
(Files you own for this slice: <list>. Everything else is read-only — because two writers on shared deletion state is how we got 36 defects.)

Done:
- These tests exist, were run red against a deliberately broken build, then green: <named falsifiers from PHASE2_CONTRACT.md>
- These contract rows are closed: <§11.5 row names>
- No new writes outside the fence-writer registry (static check passes)
- LESSONS.md updated
```

## Sequence

1. `PHASE2_CONTRACT.md` extracted from manifest v8 (+ v9 decisions). Once. Hash it, register in PEEZY_STATE.
2. S1 seams/reset stamps/runtime consumers + TaskPlanService transport
3. S2 workflow/server implementation
4. S3 scheduler/migration/deletion/outbound integration  ← second-model diff review
5. S4 recovery/privacy UI + deletion orchestration  ← second-model diff review
6. S5 identity
7. S7 close-out, whole-contract verification pass, PEEZY_STATE regen

## Housekeeping (once, not now)

- Rewrite `peezy-dev` and `peezy-autopilot` skills. They are prior-model skills and the guide says they degrade output. Job/why/boundaries/done, nothing else.
- Archive v6–v9 manifests and the amendment files under `docs/archive/phase2/`.
