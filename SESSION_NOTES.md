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

## Spec 08 — Verify layer and launch audit (2026-07-27)

### What the spec got wrong or left ambiguous

- A Firestore Console status edit cannot invoke the pure accountability function
  or `submitCheckIn`. The sanctioned MVP therefore has two parts: Adam changes
  `accountability.strikes[].status` and, when that confirmed state is removal,
  sets sibling `active=false` in the same vendor document. `submitCheckIn`
  transactionally reconciles any confirmed state the next time it touches that
  vendor, but there is no hidden trigger.
- `users/{uid}/kitCalibration` was collection-shaped shorthand without a document
  ID. The bounded implementation is the `kitCalibration` map on `users/{uid}`,
  immediately read back before success.
- “Kit purchasers” could not be expressed by the catalog's assessment-condition
  map. Initial and add-only task generation instead check the durable
  `users/{uid}/workflowResponses/supplies_kit` document; placing the kit triggers
  that refresh.
- Negative check-in answers and strikes are different contracts. All four
  negative facts become review flags and SMS messages; only price-overage and
  damage flags deterministically create pending high strikes.
- Console confirmation of a day-of price change needs a stable severity value.
  The reversible encoded value is `dayOfPriceChange`; it is tested as immediate
  removal.
- `tasks/todo.md` is an append-only historical execution log. Its six unchecked
  Spec 04 boxes are already implemented, so Phase D reconciles them as verified
  rows rather than rewriting history.

### What surprised us

- The first Phase A validator found that `estPeezy` existed in catalog JSON but
  was silently omitted by the seeder. Adding that field alone was insufficient
  protection, so the reseed verifier now compares every JSON-declared field
  exactly. The corrected 47-row live catalog has no mismatches or ghosts.
- The shared Xcode scheme already references `Configuration.storekit`. The open
  StoreKit item is strictly the Xcode-launched subscribed-pass-through walk, not
  a scheme repair.
- Read-only launch state was concrete: one unreviewed resolved provider
  (`resolved_regionsbank`), three active Test Movers, five pending ISP affiliate
  URLs, and three present Twilio credentials with `ADAM_NOTIFY_NUMBER` absent.
- Firebase CLI authentication now succeeds; a fresh deployed-function inventory
  independently verified the old `resetInventory` orphan absent.
- The privacy manifest parses but declares only the UserDefaults required-reason
  API. Settings and the paywall have legal links, while the authentication and
  account-creation surface has neither.
- A live box-pickup validator call would also invoke existing webhook/admin-SMS
  side effects. Phase C therefore validated the exact callable and payload path
  without creating an external concierge request.

### Missing or misleading conventions

- Catalog counts and the catalog sheet still stopped at the 45-row Spec 06
  state, and the sheet described already-restored assessment keys and completed
  urgency reweights as broken/pending.
- The two task-loading paths were still documented as separate decoders even
  though both now use `PeezyCardFirestoreMapper`.
- No ground-truth contract covered post-move date gates, `vendorReviews`, the
  strikes array/legacy decode, console confirmation, `kitCalibration`, or box
  pickup.
- Scattered open-item lists mixed real launch blockers with completed chips and
  deferred cleanup, allowing closed work such as the retake reset, dropdown,
  rules reconciliation, resetInventory deletion, and seeder omission to look
  open.

### Concrete documentation edits made

- Added `LAUNCH_CHECKLIST.md` as the single owner/status/close-path ledger: 14
  launch/App Store rows, seven deferred or release-hygiene rows, and 13
  reconciled historical rows. Live backend evidence is recorded without
  exposing secrets.
- Updated `peezy-conventions-v2.md` and `CLAUDE.md` to 47 catalog rows
  (workflow 32, off-app 8, in-app 6, in-app-inventory 1; survey 34,
  provide_info 13; 35 workflow IDs), added the verify/accountability/return
  contracts, corrected the shared decoder path, and pointed all future launch
  work to the canonical checklist.
- Updated `peezy-v1-architecture.md` with the implemented VERIFY and return-loop
  boundaries and corrected its stale assessment-key claim.
- Updated `peezy-v1-catalog-sheet.md` with `MOVE_CHECKIN`, the implemented
  `BOX_RETURN`, reachable vehicle/declutter conditions, and completed 55/75
  urgency reweights.

### Validation and deployment ledger

- Phase A commit `51031a9`: initial validator failed only the `estPeezy`
  round-trip, bounded retry 1 passed A1–A5 after the seeder fix and sanctioned
  catalog reseed.
- Phase B commit `a478c8d`: initial validator failed only the exact console-path
  documentation, bounded retry 1 passed B1–B5 after the manifest correction.
- Phase C commit `5b3fd9a`: validator passed C1–C5 without a retry.
- Phase D: initial validator found checklist ownership/evidence defects and stale
  catalog/architecture claims; bounded retry 1 passed D1–D5. The exact iPhone
  17 Pro build, 11 Node ladder/check-in tests, focused post-move/box-return/vendor
  Swift tests, seed validators, and documentation checks all passed.
- Remote mutations for the complete spec were limited to
  `functions:submitCheckIn` and the sanctioned 47-row catalog reseed. Phase B
  redeployed only that same callable; Phases C/D deployed nothing. The SMS
  family did not change, so `submitWorkflowAnswers` was not deployed.

All remaining launch and maintenance work is tracked only in
`LAUNCH_CHECKLIST.md`; do not duplicate an open-item list here.

## Measurement chip — blocked before Phase A implementation (2026-07-27)

### What the spec got wrong or left ambiguous

- The existing Firebase Swift package reference does not make all Firebase
  products importable by the app target. `FirebaseCrashlytics` and
  `FirebaseAnalytics` are separate products and neither is currently linked.
- Crashlytics setup also requires an Xcode-managed symbol-upload build phase and
  Debug dSYM generation; both changes persist in the protected project file.

### What surprised us

- The resolved Firebase 12.7.0 checkout already contains both requested products
  and the Crashlytics scripts, but the target links only Auth, Firestore,
  Functions, and Storage.
- Release already emits dSYMs, while Debug uses plain DWARF. A Debug forced-crash
  acceptance run therefore needs the Xcode Debug Information Format changed.

### Missing or misleading conventions

- “No new SDK beyond Firebase's own modules (already in the project)” should
  distinguish a resolved package from products explicitly linked to a target.
- Future measurement specs should list required Xcode product dependencies,
  Crashlytics input files, and dSYM settings as a human prerequisite when
  `project.pbxproj` remains protected.

### Closeout

- Wrote the Phase A acceptance contract in `PHASE_MANIFEST` before implementation.
- A fresh-context validator confirmed A1 FAIL and A2-A5 BLOCKED.
- Per the chip's explicit stop condition, no Swift implementation, build,
  deployment, remote mutation, Phase B work, Phase C doc sync, or launch-checklist
  status change occurred. Adam must add the two Firebase products and Crashlytics
  Xcode configuration before execution resumes.
