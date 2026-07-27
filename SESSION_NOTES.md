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

## Spec 07 — Non-service layer (2026-07-27)

### What the spec got wrong or left ambiguous

- “~40” provider records needed a concrete validation bound and an exact closeout count. The seed now has 46 entries: 28 cited links, one cited call, and 17 concierge records.
- “Return citations” did not itself make a URL safe. The implementation requires the returned URL to equal one cleaned HTTPS citation URL and centralizes every outbound payload through that check; any mismatch becomes URL-free concierge.
- Provider-name matching without category compatibility could return a valid but wrong-vertical record. Exact name/alias lookup is therefore also constrained to the requested category family.
- The ISP spec named plan fields but not the evidence metadata needed to maintain them. Each plan records `researchedAt`, a curation note, and an official source URL/title; the seed validator requires them.
- “Plans for {city/zip}” was bounded to the canonical destination city/state/ZIP. The flow explicitly states that the curated cards are not address-level availability results.

### What surprised us

- **Remote evidence (Phase B acceptance):** the originally configured Anthropic default model had retired. The first sanctioned function deployment therefore degraded safely to concierge, but live unseeded acceptance could not pass until the same function target was corrected to the current pinned `claude-sonnet-4-6` and redeployed.
- A provider page could present different current promotional prices in separate official sections during the same research session. The seed records the dated, locally targeted KC offer and retains the exact official source for later review.
- **Remote evidence (Phase C acceptance):** the booted simulator retained an older installed app after the current source had built successfully. Live UI validation required explicitly installing the new build before judging the flow.
- **Remote evidence (Phase C acceptance):** testing a catalog-routed custom flow required a temporary per-user task fixture. It was created only for the test bot, then deleted; independent cleanup verification confirmed the fixture absent and the pre-existing `BOOK_MOVERS` task intact.

### Missing or misleading conventions

- The userKnowledge contract still said clients wrote a flat dictionary and the collection was greenfield after the shared entry-envelope writer and live read-back existed.
- Rules guidance mentioned authenticated reads only for `flowDefinitions` and `vendors`; it omitted the new backend-owned `providerDirectory` and `ispPlans` collections.
- No durable convention stated the resolver's exact-citation URL invariant, its unverified write-through cache boundary, or the admin-review requirement for `source: resolved` records.
- The Spec 06 accessibility count and deployment examples were stale after adding the provider and ISP surfaces.

### Concrete documentation edits made

- Updated architecture section 8 with the 46-entry directory, citation-gated resolver, cache/review lifecycle, five-plan Firestore ISP feed, provider fallback, and v1.1 serviceability boundary.
- Updated the catalog sheet to the verified 45 live rows and described `SETUP_INTERNET` as five Firestore-backed cards with pending-affiliate provider fallback.
- Updated conventions and CLAUDE.md with the entries-shaped userKnowledge contract, backend ownership/rules, resolver safety invariant, seed counts, exact sanctioned remote scope, current accessibility count, and model-availability lesson.
- Added the two required operational open items below.

### Open items

- ISP affiliate URLs (Adam): replace all five `#AFFILIATE_PENDING` values with approved CJ/Impact HTTPS links.
- Provider directory operations: review `source: resolved` entries and promote vetted records into the seeded, verified set.
