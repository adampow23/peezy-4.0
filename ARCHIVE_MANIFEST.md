# ARCHIVE_MANIFEST

Snapshot: 2026-08-23 09:30:45 CDT (-0500) | branch: `main` | commit: `7215cf2af503bd88cd888b70fcd0566609e14097`.

Regeneration update: 2026-08-26 10:02:53 CDT (-0500) | branch: `main` | commit: `e5a40e87a4666bcf0c69cd331b86dba98aac1ab1`. Added the three current Phase 0/state-regeneration documents below. `PHASE0_BUILD.md` is required as a root document by the regeneration spec but is absent at the root; the available report copy is under `~/Downloads/peezy-reports/`.

Regeneration update: 2026-08-31 21:50:35 CDT (-0500) | branch: `main` | commit: `e8d6133dace44c37275d9fffd02f79380ced771f`. The frozen root candidate set added `PHASE1_BUILD.md` and `PHASE1_PLAN.md`; both are current retained Phase 1 records and are referenced by retained repository material.

This is a classification manifest only; the human moves files. The candidate set was frozen before outputs existed with one NUL-safe root-level `find` invocation, excluding `PEEZY_STATE.md` and `ARCHIVE_MANIFEST.md` by name. Classification reads were limited to enough content to identify each document. Before any ARCHIVE decision, fixed-string inbound filename searches covered active app/test source, Xcode project/scheme, `functions` excluding `node_modules` and protected files, `Tests`, root shell/JS/JSON/config/rules/plists/`PHASE_MANIFEST`, `.claude`, `.agents`, and every final KEEP or UNKNOWN candidate document. Generated outputs were excluded. Transitive retained-document closure reached stability after four rounds; no final KEEP/UNKNOWN document references any ARCHIVE row.

| filename | disposition | reason |
|---|---|---|
| BUGFIX_ASSESSMENT_SPEC.md | KEEP | Fixed-string input to `bugfix_assessment.sh:10` and its app Documents tooling copy. |
| BUILD1_ASSESSMENT_OVERHAUL_SPEC.md | KEEP | Fixed-string input to `build1_assessment_overhaul.sh:10` and its tooling copy. |
| BUILD24_AUDIT.md | ARCHIVE | Historical audit artifact (a PDF despite the extension); no inbound reference. |
| BUILD24_REPORT.md | ARCHIVE | Dated implementation report; no inbound reference. |
| BUILD2_ASSESSMENT_OVERHAUL_SPEC.md | KEEP | Fixed-string input to `build2_assessment_overhaul.sh:10` and its tooling copy. |
| CLAUDE.md | KEEP | Required by checked-in runners including `peezy_build.sh:135,204` and hook logic. |
| COPY_INVENTORY.md | KEEP | Referenced by retained `SESSION_NOTES.md`; retained-document closure forbids archiving it. |
| COPY_INVENTORY_TRIAGED.md | ARCHIVE | Historical triage derived from the copy inventory; no inbound reference. |
| DAY1_AUDITS_SPEC.md | KEEP | Fixed-string input to `day1_audits.sh:10`. |
| DAY2_BUILD_SPEC.md | KEEP | Referenced by retained `SESSION_NOTES.md`. |
| DAY3_BUILD_SPEC.md | ARCHIVE | Completed legacy build spec; no inbound reference. |
| DAY4_BUILD_SPEC.md | ARCHIVE | Completed legacy build spec; no inbound reference. |
| DEAD_CODE_REMOVAL_LIST.md | KEEP | Required by retained `LAUNCH_CHECKLIST.md:45`. |
| E2E_TEST_SPEC.md | KEEP | Fixed-string input to `peezy_e2e_build.sh:22` and its tooling copy. |
| File.txt | KEEP | Explicit app Resource in `Peezy 4.0.xcodeproj/project.pbxproj:10,41,109,261`. |
| INVENTORY_SPEC.md | KEEP | Fixed-string input to `inventory_build_stage1.sh:26` and its tooling copy. |
| INVENTORY_STAGE2_SPEC.md | KEEP | Fixed-string input to `inventory_build_stage2.sh:23` and its tooling copy. |
| LAUNCH_CHECKLIST.md | KEEP | Operational launch/submission gate runbook retained for human use. |
| MASTER_QA_CHECKLIST.md | UNKNOWN | Potential live-deploy/seed/simulator runbook, but its time-relative freshness and completion state cannot be established locally; owner decides. |
| PACKING_V2_SPEC.md | ARCHIVE | Legacy packing build spec; no inbound reference. |
| PEEZY_CUBE_SHEET.md | UNKNOWN | Unreferenced owner-redline draft may still be a calibration source; owner must resolve it against active seeded data. |
| PEEZY_LAUNCH_PLAN_AUG2026.md | KEEP | Required by `day1_audits.sh:27`. |
| PEEZY_SPEC_06_CATALOG_RESTRUCTURE.md | KEEP | Referenced by retained `SPEC06_AUDIT.md` and `PEEZY_SPEC_09_CATALOG_RESTRUCTURE.md`. |
| PEEZY_SPEC_09_CATALOG_RESTRUCTURE.md | KEEP | Fixed-string input to `peezy_build.sh:11`. |
| PEEZY_STATE_REGEN_SPEC.md | KEEP | Active directive for regenerating the canonical state document at `e8d6133`. |
| PHASE0_BUILD.md | KEEP | Required Phase 0 checkpoint input; root copy is absent and the available report copy is under `~/Downloads/peezy-reports/`. |
| PHASE0_VERIFICATION.md | KEEP | Current architect verification input named by the state-regeneration spec. |
| PHASE1_BUILD.md | KEEP | Current Phase 1 implementation checkpoint and the hypothesis source named by this regeneration. |
| PHASE1_PLAN.md | KEEP | Current Phase 1 plan, referenced by `PHASE1_BUILD.md` and the retained Phase 1 review plan. |
| PHASE_A_REPORT.md | KEEP | Referenced by retained `SESSION_NOTES.md`. |
| PHASE_B_REPORT.md | ARCHIVE | Completed phase acceptance report; no inbound reference. |
| PHASE_C_REPORT.md | ARCHIVE | Completed phase acceptance report; no inbound reference. |
| PHASE_D_REPORT.md | ARCHIVE | Completed phase acceptance report; no inbound reference. |
| PHASE_E_REPORT.md | ARCHIVE | Completed phase acceptance report; no inbound reference. |
| SESSION_NOTES.md | KEEP | Referenced by retained `LAUNCH_CHECKLIST.md`; its retained dependencies were closed transitively. |
| SPEC06_AUDIT.md | KEEP | Fixed-string audit input to `peezy_build.sh:12`. |
| THURSDAY_CALIBRATION.md | KEEP | Scheduled by retained `MASTER_QA_CHECKLIST.md:70` and referenced by retained `SESSION_NOTES.md`. |
| TRUSTPROOF_LEDGER.md | KEEP | Referenced by retained `SESSION_NOTES.md` and `peezy-trustproof-run.md`. |
| V1_ARCHITECTURE_MAP.md | KEEP | Referenced by retained `peezy-conventions-v2.md` and `peezy-v1-architecture.md`. |
| app-marketing-context.md | KEEP | Explicitly consumed by installed `.agents` marketing skills. |
| peezy-build-spec-01.md | ARCHIVE | Completed legacy build spec; no active code/tooling inbound reference. |
| peezy-build-spec-02.md | ARCHIVE | Completed legacy build spec; no active code/tooling inbound reference. |
| peezy-build-spec-03.md | ARCHIVE | Completed legacy build spec; no active code/tooling inbound reference. |
| peezy-build-spec-04.md | ARCHIVE | Completed legacy build spec; no active code/tooling inbound reference. |
| peezy-build-spec-05.md | ARCHIVE | Completed legacy build spec; no active code/tooling inbound reference. |
| peezy-build-spec-06.md | ARCHIVE | Completed legacy build spec; no active code/tooling inbound reference. |
| peezy-build-spec-07.md | ARCHIVE | Completed legacy build spec; no active code/tooling inbound reference. |
| peezy-build-spec-08.md | ARCHIVE | Completed legacy build spec; no active code/tooling inbound reference. |
| peezy-chip-estimate-integrity.md | ARCHIVE | Historical implementation chip; no inbound reference. |
| peezy-chip-measurement.md | ARCHIVE | Historical implementation chip; no inbound reference. |
| peezy-chip-post-test-cleanup.md | ARCHIVE | Historical cleanup chip paired with completed phase reports; no inbound reference. |
| peezy-chip-pricing-calibration.md | ARCHIVE | Historical calibration implementation chip; no inbound reference. |
| peezy-conventions-v2.md | KEEP | Fixed-string input to `peezy_build.sh:204` and compliance source named by `.claude/hooks/pre_tool_use.py:15`. |
| peezy-copy-rewrite.md | ARCHIVE | Historical rewrite directive; no inbound reference. |
| peezy-execution-protocol.md | KEEP | Referenced by retained `peezy-trustproof-run.md`. |
| peezy-trustproof-run.md | KEEP | Referenced by retained `SESSION_NOTES.md` and `TRUSTPROOF_LEDGER.md`. |
| peezy-ux-reference-sheet.md | UNKNOWN | Unreferenced durable UX reference may still be intentional; owner decides whether the canonical document replaces it. |
| peezy-v1-architecture.md | KEEP | Fixed-string contract references in active Swift at `ExplainerView.swift:4` and `PeezyIdentity.swift:7`. |
| peezy-v1-catalog-sheet.md | KEEP | Referenced by retained `SESSION_NOTES.md`; its stale data warning remains relevant to owner cleanup. |

Disposition totals: KEEP 33 | ARCHIVE 23 | UNKNOWN 3 | total 59.
