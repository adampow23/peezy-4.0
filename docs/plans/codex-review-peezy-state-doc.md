# Plan: Generate PEEZY_STATE.md — canonical state document (rev 4 — APPROVED)

Consensus: APPROVED by GPT-5.6-sol adversarial review, round 4 of 4, 2026-08-23. Full transcript: codex-review-peezy-state-doc-review-log.md.

## Objective

Read-only audit of ~/Desktop/Peezy 4.0 producing exactly three final outputs — the sole permanent write locations:

1. `PEEZY_STATE.md` at the project root — the single canonical state document for all future AI-assisted work.
2. `ARCHIVE_MANIFEST.md` at the project root.
3. `~/Downloads/peezy-reports/STATE_GEN.md` — report containing verifiable copies of both.

Drafting uses a private staging directory (the session scratchpad), removed or emptied at the end; nothing else on disk is written. `PHASE_MANIFEST` is preserved baseline state, not an output.

## Baseline snapshot (taken FIRST, before any writes)

- Record: audit date, branch, commit SHA, the **full** `git status --porcelain` output, and a **path-framed per-file SHA-256 list** of every in-scope dirty/untracked file (not just a combined digest).
- Freeze the manifest candidate **filename set** (see ARCHIVE_MANIFEST.md below) and record it verbatim, before any output exists.
- At audit close, recompute the per-file hashes: any mismatch means input drift — re-verify every claim citing a drifted file and record the drift in STATE_GEN.md.
- The doc's snapshot header carries date/branch/SHA and a one-line baseline summary; full baseline, hash list, and candidate set go in STATE_GEN.md.

## Evidence discipline (governs every claim)

- Claims come only from code and checked-in data read during this audit. Prior documentation (CLAUDE.md, peezy-conventions-v2.md, old specs/audits/reports/launch plans) is NEVER evidence for sections 1–3; it may be opened only during the manifest classification pass. **This spec is not evidence either** — every topic it names is a hypothesis in the closed register below (H1–H43); the register is the complete list.
- **Scope boundary (what counts as "the code")**: active app code = files under the app target resolved via the project's `PBXFileSystemSynchronizedRootGroup` structure — synchronized root directories minus membership exceptions (the source build-phase lists are empty, so literal build-phase inspection finds zero files; do not use it) — with call-graph reachability applied separately on top. Active backend = functions reachable from `functions/index.js` exports, plus ALL deployment surfaces `firebase.json` declares (functions source bundle, Hosting `public/**` including any admin surface, `storage.rules`, Firestore rules/indexes). Active data = files the seeder/loaders actually reference. Everything else is classified `test`, `tooling`, `dead`, or `unscoped`.
- **Precedence**: only active reachable evidence may SUPPORT or CONTRADICT a runtime-architecture claim. Out-of-scope material (tests, tooling, dead trees) can never contradict reachable behavior by merely existing; it supports only test/tooling/dead-code annotations (e.g. H40) or TEST_ASSERTED_UNVERIFIED rows.
- Evidence classes:
  - `LOCAL_OBSERVED` — provable from in-scope code/data (file:line required).
  - `DEPLOY_CONFIGURED` — what firebase.json / exports say WOULD deploy (file:line required).
  - `LOCAL_METADATA` — existence/size only, content never read (the only class permitted for secret files).
  - `LOCAL_TOOLCHAIN_OBSERVED` — behavior read from the locally installed toolchain source (e.g. firebase-tools packaging code), always recorded with the toolchain version.
  - `TEST_ASSERTED_UNVERIFIED` — a claim whose only evidence is an unexecuted test's assertion; cannot alone make a decision SUPPORTED without matching reachable implementation or active data.
  - `UNKNOWN` — live/remote state or anything the repo cannot answer; must state what was searched and what was missing.
- Every SUPPORTED/CONTRADICTED disposition requires BOTH an evidence class AND concrete evidence (file:line, or for counts/set claims the exact deterministic command). Hypotheses bundling independently answerable components (e.g. H12, H14, H19, H26, H30, H41) get component-level sub-dispositions (H12a, H12b, …); overall SUPPORTED only if every component is supported, otherwise report per-component.
- No live reads or calls: anything only a deployed environment can answer is UNKNOWN, flagged for a separate human-run live check.

## Hypothesis register (closed; every ID — and sub-ID where bundled — gets a disposition)

H1 entry point + startup order · H2 tab structure · H3 task pipeline (catalog → generation → task docs → rendering) · H4 "two loaders" (verify by call graph; name any unreachable legacy loader as dead) · H5 status vocabulary + terminal statuses, per consuming surface if surfaces differ · H6 flow engine step kinds incl. spawn/skipIfKnown + where definitions load from · H7 spawn system (callable, idempotency as implemented — note if token check is outside a transaction, anchors) · H8 nudge tier mechanics (dismissal durability as implemented, incl. swallowed write errors) · H9 post-flow fork · H10 research module · H11 paywall gating map (per gate: file:line, enforcing side, which flows covered; note TaskFlowRouter bespoke routes shadowing flowDefinitions) · H12 support system (a: thread, b: receipts, c: admin callables, d: push) · H13 scanner pipeline (hosting modes, processInventory contract) · H14 movers chain (a: the three-task chain/matrix/expert review; b: any legacy reachable path with its routing predicate) · H15 StoreKit product ids · H16 local vs server entitlement ("split-brain") · H17 entitlement-validation auth posture — confirm presence/absence of caller authentication, App Check, and Apple verification with file:line; **if all three are confirmed absent on a path that grants entitlement, the H17 row in section 3 is mandatorily CRITICAL with `blocks: deploy/release` and an urgent human live-deployment check flagged**; "hardened" banned absent verified code · H18 Stage-2 Apple verification pending · H19 backend function inventory (a: callables, b: HTTP, c: triggers — one line each) · H20 Firestore collections read/write map · H21 rules posture as EFFECTIVE permissions (allows are additive; resolve whether recursive owner-write also matches `moveAnswers`) · H22 env var NAMES in use (from source refs only) · H23 resetInventory orphan · H24 catalog row count + schema fields · H25 flow definition count · H26 seeder behavior (a: projection, b: round-trip verifier, c: delete-rewrite) · H27 reseedable vs binary-bound · H28 tier model (task/conversation/nudge) · H29 fork model (flows free, help paid — scoped to where code shows the gate) · H30 Move Pass pricing (a: local StoreKit config, b: App Store production = UNKNOWN, c: server entitlement, d: gift path — as a source-of-truth table) · H31 gift codes (mechanics only, no literal codes) · H32 one-card-one-idea where test-enforced · H33 insider-voice content model · H34 manual-release posture · H35 restore doesn't repair server doc · H36 expired pass blocks gift fallback · H37 `termMonths` ignored at redemption · H38 identifier/test issues · H39 iCloud-Desktop project location risk · H40 dead code worth noting · H41 Firebase deployment surfaces per firebase.json (a: functions bundle, b: Hosting incl. admin surface, c: storage.rules, d: Firestore rules/indexes) · H42 Storage usage (client upload paths, e.g. inventory, and effective storage rules) · H43 functions packaging risk — what the firebase.json ignore list excludes and does NOT exclude; evidence is "exclusions absent (file:line)" plus optionally LOCAL_TOOLCHAIN_OBSERVED packaging behavior; if packaging inclusion is unverified, report "not explicitly excluded; package inclusion unverified" — the section-3 deploy block stands either way, and the row must include a non-printing filename inventory of every bundle-eligible sensitive file (env files, key files, seed/diagnostic files containing literal entitlement codes or credentials), each requiring exclusion/relocation and rotation assessment before deploy.

Catalog/flow data additionally requires a provenance statement: every data source file path with row/flow counts (command shown), which file the seeder reads, seeder write behavior, and any divergence between sources stated explicitly. Seeding is described as "deterministically reproducible from <path>; live seeding is human-run and must follow: project-ID confirmation → backup/export → dry-run count/hash diff → approval → post-seed verification" (the seeder delete-rewrites collections).

## Safety boundary

- **No execution**: no tests, seeds, deploys, emulators, simulators, or network calls. Test-suite health is reported statically; runtime pass/fail is UNKNOWN. The repo's UI tests write to live Firebase and invoke restore; they must not run.
- **Secrets**: never open `functions/.env`, `functions/serviceAccountKey.json`, or `GoogleService-Info.plist` for values (LOCAL_METADATA only); never quote literal gift/promo codes, keys, or credentials; env vars by NAME from `process.env.X` references only.
- **Redaction (executable, non-printing)**: draft outputs in staging. Derive the gift-code pattern(s) from the redemption validator's own format check (read the validating code; do not guess a prefix). Scan drafts QUIETLY (`grep -qE` / match counts only — never print matched content) for: credential-assignment patterns (`password|secret|token|apiKey|client_secret` followed by a literal value), `-----BEGIN`, `AIza[0-9A-Za-z_-]{20,}`, `sk-[A-Za-z0-9]{20,}`, every derived gift-code format, and the repo's known test-credential literals. Lines that are labeled checksum/commit fields (`sha256:`, `commit:`) are exempt from long-hex/base64 heuristics — audit-generated hashes are not secrets. Zero matches required; then install drafts and record each file's SHA-256.

## PEEZY_STATE.md structure

Hard cap **300 lines**, exactly four sections, dense fact-table style encouraged.

### 1. Architecture facts (verified today) — dispositions for H1–H27, H41–H43.

### 2. Product decisions in force — dispositions for H28–H34; each decision cites the enforcing code, test (TEST_ASSERTED_UNVERIFIED unless implementation matches), or data row.

### 3. In flight / known gaps — schema per row: `severity (CRITICAL/HIGH/MEDIUM/LOW) | impact | evidence | safe next action | blocks (seed/deploy/release/none) | sign_off (PENDING or owner/date/scope/reference)`. CRITICAL rows block the named operation until sign_off is filled by the owner. Expected entries if confirmed: H17 (mandatory CRITICAL if auth absent, see register), H43 packaging risk, additive-rules overlap, spawn idempotency race, nudge durability, catalog source divergence, H35–H40.

### 4. Working protocol — the six bullets below VERBATIM, unmodified, followed by the addendum:

> - Every session: read this file first; it outranks memory and any older doc.
> - Audit-first: read-only pass with file:line evidence before any spec.
> - Scoped changes: spec → Codex executes → report to ~/Downloads/peezy-reports/[NAME].md.
> - Cross-cutting changes: spec → codex-consensus adversarial review → execute converged plan → report.
> - No live seeds/deploys from inside a task; human runs them.
> - Session close-out: regenerate (not append) this file's sections 1–3 if anything changed; note the date.

Addendum (added per adversarial review 2026-08-23; **binding by default** — the owner may amend or strike it): no live-service or billing operations from inside a task — production-connected UI/integration tests, callable invocations, remote Firestore/Storage writes, StoreKit purchase/restore — except against an explicitly enumerated non-production target or with exact human authorization naming the target and action. Regenerating sections 1–3 requires a full evidence-and-acceptance pass against a fresh snapshot, never a partial-knowledge overwrite; refresh ARCHIVE_MANIFEST.md if the root document set changed.

## ARCHIVE_MANIFEST.md

- Candidate set frozen at baseline: every `*.md` and `*.txt` file at the project root, listed NUL-safe from a single `find -maxdepth 1` invocation; the exact filename set recorded. `PEEZY_STATE.md` and `ARCHIVE_MANIFEST.md` are excluded **by name** regardless of whether prior copies exist (reruns), and excluded from inbound-reference greps.
- Classification pass: each candidate may be opened only enough to classify (title / first ~20 lines); sole permitted contact with retired docs; contributes nothing to PEEZY_STATE.md.
- Each row: `filename — ARCHIVE | KEEP | UNKNOWN — one-line reason`. KEEP anything operational or referenced by code/tooling (inbound-reference grep before any ARCHIVE). The manifest lists; the human moves.

## STATE_GEN.md report format

Header: audit date, branch, SHA, full porcelain baseline, per-file baseline hash list (+ close-time recomputation result), frozen candidate set, redaction-scan result. Then, for each of the two root files: exact byte count and SHA-256, followed by its full content between unambiguous delimiters.

## Acceptance criteria (all binary)

1. PEEZY_STATE.md exists at root, ≤300 lines, exactly the four headed sections, snapshot header present.
2. Every ID H1–H43 (and every defined sub-ID) has an explicit SUPPORTED/CONTRADICTED/UNKNOWN disposition; no hypothesis exists outside the register.
3. Every SUPPORTED/CONTRADICTED claim carries evidence class + file:line (or the deterministic command for counts); every UNKNOWN states search scope; zero claims sourced from prior docs or this spec; runtime claims cite only active reachable evidence.
4. Function inventory, collection map, data-source provenance, deployment-surface inventory, and test-target list each reconcile against the discovered set (set-equality both directions; commands recorded in STATE_GEN.md).
5. Section 4's six protocol bullets are byte-identical to the block quoted in this plan; the addendum is present, labeled, and binding-by-default.
6. ARCHIVE_MANIFEST.md filename set is exactly equal (unique set equality, not count) to the frozen candidate set; every row has disposition + reason; no ARCHIVE row has unexamined inbound references.
7. Each embedded block in STATE_GEN.md, extracted by its delimiters, matches its recorded byte count and SHA-256, AND those equal a fresh re-hash of the corresponding installed root file.
8. Quiet redaction scan reports zero matches across all three outputs (checksum-labeled fields exempt), recorded in STATE_GEN.md.
9. Final `git status --porcelain` equals the recorded baseline plus exactly the two root outputs; close-time per-file hash recomputation matches baseline or drift is recorded with re-verification noted.
10. No test, seed, deploy, emulator, simulator, or live-service/network operation occurred during the audit.
11. Staging directory is removed or empty; the report directory's delta is exactly `STATE_GEN.md`.
12. Every CRITICAL section-3 row carries a `sign_off` field (PENDING until the owner fills it).

## Reviewer pushback (deliberately rejected, with rationale)

- **Threat model + negative entitlement tests / emulator rules tests (R1-F4, R1-F11):** follow-up work the doc points at; section-3 rows carry `blocks` + `sign_off` instead.
- **Appendix-ledger architecture (R1-F17):** the product is ONE canonical file; STATE_GEN.md carries verification detail outside the doc.
- **Exhaustive per-flow reachability matrix (R1-F8):** per-gate enforcement + router shadowing with file:line is required; a full matrix is a future dedicated audit.
- **Wholesale restart-on-drift (R1-F6):** superseded by per-file baseline hashes with close-time recomputation and targeted re-verification (R3-F2 adopted).
- **Rewriting the owner's six verbatim protocol bullets (R2-F6):** bullets stay byte-identical; the addendum is now binding-by-default with owner amendment rights (R3-F6 adopted in substance).
- *(Withdrawn rejections: R2-F10's envelope simplification — Sol was right that source hashes don't authenticate embedded blocks; embedded-block extraction verification adopted in criterion 7.)*

## ADR

- **Decision**: Generate the canonical state document via a strictly non-executing, evidence-classed audit against a closed hypothesis register (H1–H43), with per-file baseline hashing, a quiet redaction gate, and 12 binary acceptance criteria; ARCHIVE_MANIFEST.md built from a baseline-frozen candidate set; STATE_GEN.md carries all verification detail.
- **Drivers**: prior docs (CLAUDE.md, conventions, specs) drifted from code and are being retired; the checkout is dirty; secret-bearing local files (`functions/.env`, `functions/serviceAccountKey.json`) sit inside the Functions upload scope; repo tests reach live Firebase and StoreKit restore; a static audit cannot prove deployed state.
- **Alternatives considered**: matrix-plus-generated-appendices architecture (rejected — recreates doc sprawl); live Firebase read-only inventory (deferred — human-run per protocol); exhaustive per-flow reachability matrix (deferred — future dedicated audit); running test suites for pass/fail (rejected — live side effects).
- **Why chosen**: one readable file re-read every session, with an evidence discipline strict enough that a cold agent can execute it without touching production, guessing, or laundering stale docs into "facts".
- **Consequences**: deployed-state facts remain UNKNOWN until a human-run live check; regeneration requires a full evidence-and-acceptance pass; the section-4 addendum is binding by default until the owner amends it; CRITICAL gap rows block their named operations until `sign_off` is filled.
- **Follow-ups**: (a) round-4 non-blocking refinements, adopted as executor guidance — extend integrity hashing to all pre-existing porcelain paths plus this plan; define search roots/pattern families for Firestore + test discovery, computed paths → UNKNOWN; include `Configuration.storekit` and `.firebaserc` in the active-config boundary (H41 sub-ID for local project selection, live identity UNKNOWN); make the H43 sensitive-file set a quiet filename-only scan over the whole Functions bundle with exact reconciliation; add conditional acceptance checks enforcing H17/H43 mandatory severities; snapshot the report directory before writing and keep STATE_GEN's own hash external; state LOCAL_METADATA/LOCAL_TOOLCHAIN_OBSERVED as explicit narrow exceptions in the opening discipline rule; define inbound-reference search roots (active code + tooling/config, fixed-string filenames, candidates and outputs excluded). (b) Human actions outside the audit: rotate `functions/serviceAccountKey.json` and add firebase.json upload exclusions; run the live check on the entitlement endpoint; sign off or amend the protocol addendum.
