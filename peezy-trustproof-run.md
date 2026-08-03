# Trustproof Run — Full-App Exit-Risk Audit
Read first: peezy-trustproof skill (SKILL.md — Adam places it in the repo or Claude Code skills path before this run), repo peezy-conventions-v2.md, peezy-v1-architecture.md, peezy-execution-protocol.md. Model: Fable 5, xhigh. **READ-ONLY on all source: this run produces ONE findings document and zero code changes.** Simulator use is expected and encouraged.

## Objective (bounded, per Adam)
Find the moments that push a user to LEAVE — not every imperfection. A finding earns ledger space only if it plausibly ends a session or the relationship: dead ends, trapped states, silent failures, broken promises, surprise charges, wasted effort, "the app lied to me" moments. Cosmetic and preference items are out of scope; note them in one line in an appendix at most.

## Ground rules
1. **Chesterton fences (locked — never flag as findings):** the long assessment (tribe filter), boring-on-purpose plainness, buttons-not-swipes, the dose boundary ("done for today" is a feature), directed action (not offering choices is intentional), paywall placement per architecture §10 option (c). If a fence seems to cause a genuine exit risk, record it under "Fence tensions" with the tension stated — do not propose removing the fence.
2. **Free-tier ground truth is architecture doc §10** (soft post-assessment offer + hard gate at booking/kit/concierge). Older docs (business overview, product spec) are stale where they conflict.
3. **Concentration rule:** churn concentrates in (a) the first session and (b) the T-7-to-move-day window. Weight both; anything Trust-Collapse severity inside T-7 is automatically top-priority.
4. No fixes, no code, no "while I'm here." Findings only.

## Method
**Phase 1 — Moment inventory.** Enumerate every discrete user action/moment from the code and catalog: first launch, each explainer card, signup (email + SIWA, including SIWA failure/cancel), each assessment chapter + both escape hatches, plan generation wait, plan reveal, first dose card, task complete, snooze + snooze return, flow exit + resume, the scan (permission denial, mid-scan interruption, upload failure, bad video, coverage check), estimate reveal, comparison cards, paywall (view/dismiss/purchase/purchase-failure/restore), booking submit + its failure, kit offer/customize/order, packing session, behind-pace nudge, readiness gate, ISP cards + handoff return, provider rows (link/call/concierge) incl. resolver failure, settings edits, retake, sign out, delete account, day-2 return, dose-complete state, offline behavior at each network-dependent moment, post-move check-in, box return. Include Adam-known incidents: the pre-Spec-04 permanent spinner class, the paywall-moment findings from the skill's pilot run (import them into this ledger as F-001…F-005 rather than re-deriving).
**Phase 2 — Run the skill's loop per moment:** premortem narration → failure enumeration (including backend-fails-mid-action) → classify (Trust-Collapse / Friction / Filter) → tag (Severity / Silence / Clock) → proposed fix rung (Impossible / Constrained / Loud / Recovered) as a ONE-LINE direction, not a design. Verify live in the simulator wherever a failure can be induced cheaply (airplane mode, permission denial, force-quit mid-flow, expired session); attach screenshot or code citation per finding — a finding with no evidence is a hypothesis and is marked as such.
**Phase 3 — Ledger.** Write TRUSTPROOF_LEDGER.md: findings table (ID, moment, failure, class, tags, evidence, proposed rung + one-line direction), then three short sections: Stop-ship candidates (Trust-Collapse + high Severity or any T-7 Clock), Fence tensions, Accepted-as-is (Filter class, with rationale). Appendix: one-line cosmetics.
**Phase 4 — SESSION_NOTES last.** No commits to source; the ledger may be committed alone.

## What good looks like
A short stop-ship list Adam can read in five minutes, a defensible accepted-as-is list so nothing gets relitigated later, and evidence for every claim. If the stop-ship list is empty, say so plainly — an honest clean bill is a valid outcome and must not be padded.

## Delegation Prompt
```
cd ~/Desktop/Peezy 4.0/. Read the peezy-trustproof skill, peezy-conventions-v2.md,
peezy-v1-architecture.md, peezy-execution-protocol.md, then peezy-trustproof-run.md.
Execute Phases 1→4. READ-ONLY on all source; the only file you create is
TRUSTPROOF_LEDGER.md (+SESSION_NOTES). Simulator verification with evidence per
finding. Import the pilot paywall findings as F-001..F-005. STOP on anything
not covered. Investigate and execute.
```
