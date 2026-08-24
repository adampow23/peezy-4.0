# Peezy Execution Protocol
Governs every v1 build spec, starting with Spec 01. Distilled from Anthropic's internal Claude Code practices, GitHub Spec Kit / AWS Kiro spec-driven development, and independent-validator research. This is the layer that delivers speed AND quality simultaneously instead of alternating between them.

## 1. Acceptance criteria are the contract (per phase, non-negotiable)

Every phase carries testable Given/When/Then criteria written BEFORE the build. Not "verify it works" — criteria a separate agent can pass/fail with evidence.

Example (Spec 01 Phase 1):
- GIVEN a fresh install and completed auth, WHEN the app foregrounds, THEN explainer card 1 renders (screenshot) and `explainer.next` is tappable.
- GIVEN card 5, WHEN "Let's go" is tapped, THEN assessment question 1 renders and `peezy.explainer.seen == true`.
- GIVEN a second launch, WHEN the app foregrounds, THEN the explainer never renders (screenshot of direct route).

Rule: if a criterion can't be phrased testably, the requirement is not understood yet — stop and clarify before building.

## 2. NEEDS-CLARIFICATION beats invention

Specs and agents use an explicit `[NEEDS CLARIFICATION: …]` marker. When the code contradicts the spec, an API doesn't match, or a requirement is ambiguous: mark it, pick the safest bounded interpretation ONLY if reversible, and surface the marker in the phase report. Inventing an unmarked assumption is a protocol violation. (Spec 01's "adaptation rule" is the template: declared flex, hard boundary.)

## 3. Writer/Validator split (fresh context, permission to fail)

The agent that wrote the code never grades it. After each phase build:
- A fresh-context validator subagent receives ONLY: the phase spec, the acceptance criteria, the diff, and simulator access.
- It executes each criterion, attaches evidence (screenshot/log/test output), and returns PASS or FAIL per criterion. It has explicit permission — and instruction — to fail the work. "Looks right" is not a verdict.
- Bounded retry: on FAIL, the writer gets the structured feedback and TWO attempts max. Still failing → phase halts, human reads the trail. No infinite patch/revert thrash.

## 4. Autonomy tiers (decided per phase, in the spec)

- **PERIPHERY** (new self-contained UI, config, docs, greenfield leaf code): full auto-accept, review at phase end. Explainer = periphery.
- **CORE** (identity, card model, router, anything COMPLIANCE or LESSON-tagged, Firestore schemas): auto-accept OFF conceptually — the agent still runs autonomously, but commits sub-steps separately, and the phase report must walk each hub-file diff. Identity = core. PeezyCard rewrite = core.
Expectation-setting: even Anthropic's RL team lands first-attempt autonomous success only about a third of the time. A failed first attempt is a normal cost, not a crisis.

## 5. Revert-and-restart doctrine

If a phase goes sideways — wrong direction, mushrooming diff, validator failing on fundamentals — do NOT wrestle it. `git reset` to the phase-start checkpoint, improve the SPEC with what the failure taught, rerun clean. The spec is the asset; the failed attempt is tuition. Wrestling a confused session is the single behavior that produced the old "breaking more than fixing" era.

## 6. The improvement loop (end of every session)

Last action of every session: the agent writes a `SESSION_NOTES` block — what the spec got wrong, what surprised it, which CLAUDE.md/conventions line was missing or misleading — and proposes concrete doc edits. Adam or Claude.ai folds accepted edits into conventions-v2/CLAUDE.md before the next spec. This is how the system gets faster every phase instead of re-paying the same tax.

## 7. Repeated workflows become slash commands

First candidates: `/verify-ui` (build → boot sim → screenshot named flow → attach), `/phase-close` (diff review → acceptance run → commit → SESSION_NOTES). Anything done three times by hand gets a command.

## Division of labor (unchanged, now named)

Claude.ai (this chat): strategy, architecture, spec authoring, acceptance criteria, doc reconciliation — the plan-in-chat-then-hand-structured-prompt pattern Anthropic teams use.
Fable 5 in Claude Code: execution against specs, under hooks, with validator subagents.
Adam: decisions marked DECISION, Xcode-only operations, deploys, and reading phase reports — the human gate between specify and implement that every SDD framework keeps.
