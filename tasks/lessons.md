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
