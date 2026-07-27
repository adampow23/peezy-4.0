# SESSION_NOTES

## Spec 06 — Packing plan, supplies kit, and readiness gate (2026-07-26)

### What the spec got wrong or left ambiguous

- `users/{uid}/packingPlan` and `users/{uid}/readiness` were collection-shaped shorthand, not valid Firestore document paths. The implementation uses `packingPlan/current` and `readiness/current`, matching the existing `identity/identity` convention.
- The supplies-kit 12% headroom requirement needed a boundary: it applies to raw small/medium/large box demand before rounding, not to exact-fit mattress, wardrobe, or dish accessories.
- "At day's end" lacked a calendar boundary. The reversible interpretation is the start of move day, immediately after the T−1 calendar day ends.
- The protocol required a `SESSION_NOTES` block, but the repository had no destination file. This root append-only file now makes the closeout artifact explicit.

### What surprised us

- A Customize sheet could compile and present as a blank surface when backed by a transient Boolean while its draft data was still nil. Item-driven sheet presentation made the data and presentation lifetime identical.
- An omitted Swift interpolation marker rendered as literal-looking date text and still built cleanly; live accessibility/screenshot validation caught it.
- Concurrent Xcode runs share SwiftPM package locking even with separate DerivedData locations. Phase validation should serialize package-resolving builds or use distinct package caches.
- A clean authenticated validator user still needed a `user_assessments` marker to reach Home through the current root gate; root user flags alone were insufficient.

### Missing or misleading conventions

- Catalog counts still described the pre-Spec-06 46-row state and did not distinguish catalog rows from engine-generated per-user packing tasks.
- The deployment example widened to all functions even though this spec authorized only `functions:submitWorkflowAnswers`.
- Packing persistence, one-session dose behavior, T−1 ordering, completion preservation, kit fulfillment, and readiness evidence paths were absent from the key-file and contract summaries.

### Concrete documentation edits made

- Corrected catalog facts to 45 total: workflow 32, off-app 8, in-app 4, in-app-inventory 1; survey 32, provide_info 13; workflowId 33.
- Added Spec 06 key files and data contracts for `packingPlan/current`, generated `PACKING_*` task documents, `readiness/current`, reflow, dose ordering, kit submission, and the SMS fallback.
- Replaced the broad deploy example with the exact scoped callable deploy and recorded that no rules or broad functions deploy occurred.
- Added the required open item: kit supplier: replace concierge fulfillment with local supplier handoff when signed.

### Open item

- kit supplier: replace concierge fulfillment with local supplier handoff when signed.
