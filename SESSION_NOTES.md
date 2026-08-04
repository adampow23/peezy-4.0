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

## Measurement chip — completed after scoped project authorization (2026-07-27)

### What the spec got wrong or left ambiguous

- “Firebase's own modules (already in the project)” conflated a resolved Swift
  package with products linked to the app target. Both measurement products,
  the Crashlytics run phase, `-ObjC`, and Debug dSYM output required a protected
  `project.pbxproj` change before Phase A could compile.
- The original protected-file stop condition had no machine close path. Adam's
  retry supplied the missing contract: a clean tracked tree, recorded revert
  point, Ruby `xcodeproj` mutation, isolated commit, full build, and immediate
  rollback on any failure.
- “Update PrivacyInfo.xcprivacy if analytics collection requires a declaration”
  did not distinguish SDK privacy manifests, the app's collected-data manifest,
  and App Store privacy answers. The existing L11/L12 gate forbids guessing the
  complete data-use matrix, so this chip does not close those rows.

### What surprised us

- Xcode/File Provider coordination could deadlock the workspace after the
  external Xcode-project update even though the project was valid. Builds from a
  physical mirror containing the exact committed project and current source were
  reliable and used the same scheme, destination, and DerivedData output.
- Crashlytics acknowledged the forced outside-debugger simulator crash as one
  unprocessed crash before console symbol processing completed. The local dSYM
  UUID and Firebase receipt UUID matched, and the relaunch emitted the upload POST.
- Firebase 12.7.0's Crashlytics resource already declares crash data and other
  diagnostic data with tracking disabled. That supports leaving Peezy's own
  manifest unchanged until Adam approves the broader L11 collection matrix.

### Missing or misleading conventions

- No ground-truth section defined the custom event vocabulary, allowed property,
  PII boundary, or service-boundary placement rule.
- The protected-project convention did not explain that existing-package product
  linkage is still an Xcode project mutation requiring an explicit exception.
- The launch checklist had privacy rows but no measurement-readiness row, so a
  shipped Crashlytics/Analytics layer could not be marked independently complete.

### Concrete documentation edits made

- Added the exact 13-event Analytics vocabulary to conventions, prohibited PII
  and stable identifiers, limited custom properties to `has_subscription`, and
  required guarded service/state-change boundary logging.
- Added VERIFIED launch row L15 with the Crashlytics console receipt, logged
  13-event journey, exact build proof, and explicit no-deployment scope.
- Kept L11 OPEN and L12 BLOCKED; `PrivacyInfo.xcprivacy` remains valid and
  unchanged because the approved app-wide collected-data matrix is still absent.

### Validation and commit ledger

- Initial tracked tree was clean and the recorded revert point was
  `6f17b857cf3d6a21e39468892a135a7981c5a293`.
- Project prerequisite commit `bf3af26` contains only the Xcode project wiring;
  its required full build passed, so rollback was not needed.
- Phase A commit `9123df2` passed fresh validation A1-A6, including the received
  forced-crash receipt and hook-free final build.
- Phase B commit `3425abc` passed fresh validation B1-B6; its DEBUG journey dump
  contains all 13 custom events exactly once with no PII parameter keys.
- Phase C documentation checks matched conventions to the source event list and
  validated the unchanged app privacy manifest. No backend or production
  deployment occurred anywhere in the chip.

## Estimate Integrity chip — Phase A complete; protocol STOP before Phase B (2026-07-27)

### What the spec got wrong or left ambiguous

- Phase B does not define the room-name normalization contract, the
  dwelling-to-garage/basement mapping, or the numeric meaning of “one confidence
  notch.” Fresh users also reach inventory capture without `currentBedrooms`;
  identity has no bedroom or dwelling fields, so the required expectation has
  no authoritative source for that path.
- Phase D names a LOCKED-pending-calibration `storageStopLoadHours` constant but
  supplies no starting value. It also leaves the no-stop storage-cube behavior
  and exact +30-minute fallback disclosure unspecified.
- Phase E does not say whether room floors apply to the aggregate room, each
  kitchen branch, or each generated session. “Kitchen always ≥2 sessions” also
  conflicts with the existing short-timeline merge unless it means before
  compression.
- Phase F names the `estimateCalibration` document shape but not its Firestore
  path. The smallest reversible backend-owned choice would be
  `estimateCalibration/{reviewId}`, written transactionally with the review.
- Phase G requires regression-gating an existing byte-identical moving fixture
  if duplicates appear, but the repo contains no processInventory fixture,
  per-vertical config, or suitable room images. The deployed inline prompt
  already contains a cross-frame dedup instruction.

### What surprised us

- The hidden-goods disclosure already had a durable home in
  `PriceEstimate.disclosures`, but the comparison adapter discarded every
  disclosure and rendered only specialty notes. Phase A now carries both into
  the visible comparison card.
- Xcode blocked in `NSFileCoordinator` while reading the Desktop-backed project
  package. A tar mirror containing byte-identical Phase A source avoided the
  File Provider deadlock and produced reliable simulator test evidence.
- The 1,300-cu-ft Phase C gate alone cannot prove the six-hour why-line
  invariant: the current four-person throughput crosses six hours at 1,230 cu
  ft before access, specialty, or storage-stop labor. Phase C therefore needs a
  scope-level physical-hours viability guard in addition to the cube boundary.

### Phase A implementation and validation ledger

- Added the exact 1BR/2BR/3BR/4BR+ hidden-goods factors only to scan-derived
  cube; the bedroom fallback remains unchanged and documents why it already
  includes hidden goods.
- Added the exact locked scan disclosure and propagated estimate disclosures to
  comparison-card detail notes.
- Standalone PricingEngine tests passed 45 assertions. Targeted iPhone 17 Pro
  tests passed 4/4 on iOS 26.5; workspace and mirror hub-file SHA-256 values
  matched exactly. The fresh-context validator reported PASS for A1–A5.
- `project.pbxproj` remained byte-diff clean. No function, rules, catalog, flow,
  or other remote deployment occurred.

### Stop reason and proposed documentation edits

- Per the execution protocol and the chip’s “STOP on anything not covered”
  boundary, Phase B did not start. Adam must supply the missing Phase B contract
  before A→G can continue; downstream D/E/F choices should be locked in the
  same clarification to avoid a second stop.
- Once decided, add the canonical coverage-room mapping/confidence tiers,
  storage-stop calibration/copy, packing-floor semantics, and calibration path
  to conventions so later clients do not infer them again.

## Estimate Integrity chip — Phases B–G complete (2026-07-28)

### What the spec got wrong or left ambiguous

- Phase G originally assumed byte-stable vision output. Three identical-input
  runs proved the model has ordinary naming, category, quantity, and cube
  variance, so prompt changes must be judged against a measured same-prompt
  band rather than a byte-identical diff.
- The attempted identity-ledger prompt addressed one duplicated decorative
  heart-frame item under 1 cu ft but destabilized cube-material inventory:
  armchairs moved `4 → 5 → 5`, and the credenza disappeared in run 3. Requested
  material cube moved from 169 cu ft on the original prompt to 163/188/173 cu ft
  on the rejected prompt. The approach was rejected on cost and rolled back to
  the exact prompt at model-migration commit `4023ca3`; no second prompt attempt
  occurred.
- “Deduplication” needed two separate meanings. The accepted deterministic
  post-processor is exact-entry aggregation: NFKC/case/punctuation/whitespace
  normalized name plus exact category, stable first occurrence, and summed
  quantity. It performs no fuzzy or semantic identity matching and therefore
  does not claim to reduce a duplicated physical count when names differ.
- A useful cube-material variance report requires identity rows as well as
  totals. The rejected prompt's extra chair and missing credenza could otherwise
  cancel in aggregate. The controlled ground truth now includes the credenza
  and explicit aliases/category expectations.

### Phase B–F implementation ledger

- Phase B commits `f58a5a1` and `0d91619` added the normalized expected-room
  coverage model, missing-bedroom rows, dwelling garage/basement mapping,
  scanned extras, the capped high-side confidence notch, the Not seen strip,
  and the Nothing there resolution action.
- Phase C commits `adb064e` and `2f20594` replaced the cube threshold with the
  largest-active-crew physical-hours gate and routed scopes with no crew at or
  below six hours to the concierge quote card. The why-line invariant is now
  true by construction; `bigMoveCubicFeetGate` is gone.
- Phase D commits `e6905fd` and `0c27869` modeled storage as an optional moving-day
  stop, added the locked 0.75 load hours before ceiling, summed geocoded legs,
  retained cube-only storage when it is not a stop, and added the locked
  30-minute/address disclosure fallback.
- Phase E commit `568a7dc` applies room floors before session splitting and then
  runs existing approximately-40-minute chunking/compression; the kitchen
  two-session minimum is established before compression.
- Phase F commits `b2e78b9` and `2b4c4bb` write backend-owned
  `estimateCalibration/{autoId}` records transactionally from `submitCheckIn`,
  retain `kitCalibration` under the user, and reject Boolean values masquerading
  as numeric booking metrics. Fresh validation passed F1–F6, including the
  signed live write/readback/cleanup. Only `functions:submitCheckIn` deployed.

### Phase G final regression baselines

- No prior byte-identical `processInventory` baseline existed. The separately
  committed model migration `4023ca3` replaced the retired model with
  `claude-sonnet-4-6` and deployed only `functions:processInventory`.
- The controlled fixture is five overlapping generated camera views of one
  furnished room. Its three final runs used the same deployed source SHA-256
  `b7ac389f3288f60644f745a0ebc765a397bac21a5aed9ef9f5e409edc42d3141`.
  All nine ground-truth groups were present with no duplicate or missing group.
- Tracked cube-material identity counts were invariant: sofa `1/1/1`, armchairs
  `4/4/4`, coffee table `1/1/1`, side table `1/1/1`, and credenza `1/1/1`.
  The identity-count variance band is therefore width 0.
- For the requested material categories (`furniture`, `appliance`, `boxes`),
  entry counts were `5/5/6`, reported units `8/8/9`, and total cube
  `173/178/174` cu ft. The observed regression tolerance is: tracked identity
  count width 0; category-material entry/unit width 1; total material-cube width
  5 cu ft, or 2.89% of the 173-cu-ft minimum. Run 3's extra category-material
  row was an area-rug category drift, not an identity/count change.
- Supplemental all-item cube was `205.1/210.9/192.8` cu ft, an 18.1-cu-ft band.
  Future prompt work must report this separately and must not substitute it for
  the narrower requested-category band.
- The realistic multi-room baseline contains Living room 11 entries and Family
  room 29 entries: 40 combined entries, reported quantity 58, and 195.85 cu ft.
  Every one of its eight input frames is SHA-256 pinned, and the combined output
  is stored alongside the per-room output.
- Commit `8f02be0` contains the controlled and multi-room baselines, five-frame
  fixture, frame hashes, diagnostic/variance harness, rollback proof, exact-entry
  aggregation, and unit tests.

### Validation, deployment, and close ledger

- The exact-entry aggregator passed 4/4 focused tests. The final Functions suite
  passed 23/23; the final diagnostic/baseline suite passed 9/9; syntax and walked
  diff checks passed. Fresh source and artifact validators passed G1–G5 and G7.
- The rejected prompt was deployed only after its diagnostic found the decorative
  duplicate. The final sanctioned deployment again targeted only
  `functions:processInventory` and combined the exact `4023ca3` prompt rollback
  with deterministic exact-entry aggregation. No rules, broad-functions,
  catalog, or flow deployment/reseed occurred.
- Exact live-fixture cleanup was independently verified at zero remaining
  Phase-G Firestore session documents and zero Storage objects. Source sessions
  were never mutated.
- `peezyBrain` and `.env.example` now pin `claude-sonnet-4-6` in commit
  `fa2a324`; focused 3/3 and full-suite validation passed. No deployment was
  needed because `peezyRespond` is orphaned from the current iOS client and
  `healthCheck` never invokes Anthropic. The intentional negative guard and
  archival inventory spec/build logs remain untouched.
- Remote mutations across B–G were limited to the sanctioned
  `functions:submitCheckIn` and scoped `functions:processInventory` deployments.
  Flow/catalog data did not change, so no reseed ran. This SESSION_NOTES block
  is the final repository edit/action of the session.

## Post-Test Cleanup chip — Phase A halted at final retry gate (2026-08-01)

### What the spec/protocol left ambiguous

- A1.6 said to report every `try?` or swallowed `catch` encountered in flow
  answer-persistence paths, but did not define the transitive call-graph
  boundary. Validation progressively extended that boundary from the new
  progress writer and flow terminals into identity migration, payload
  serialization, persisted-answer decoding, and finally add-address geocoding.
- A future audit criterion should lock its closure before implementation: name
  the root entry points, state whether readback/context derivation is included,
  and require a preflight `try?`/`catch` inventory over that exact closure.
  This avoids spending bounded functional retry budget on an expanding
  reporting-only perimeter.

### What surprised us

- Generic flow-progress writes and nested domain writes formed two persistence
  timelines. Without generation invalidation, an older generic completion could
  clear a newer readiness-write error and falsely produce the saved-answer
  dialog. External pending/failure/success now supersedes and cancels the older
  generic chain head.
- Mover confirmation restoration needed to rebuild vendor comparisons and
  resolve the saved quote ID, not merely restore the outer enum stage; otherwise
  confirmation lost the vendor name.
- Sixty-seven Swift sources had been evicted by iCloud. Xcode frontends blocked
  at zero CPU until those dataless files were hydrated; the same candidate then
  built successfully without a code change.

### Implementation and validation ledger

- The session began with the requested `git checkout -- .`; tracked state was
  verified clean before the fresh Phase A implementation. The user-owned
  untracked chip documents were preserved.
- Functional validation passes A1.1–A1.5 and A2–A4. The simulator exercised all
  21 routed flow families with exactly one outer `flow.exit`, native nested
  dismissal, immediate known-empty exit, exact saved/unsaved dialogs, Keep
  going, full teardown, originating-tab restoration, and onboarding routing.
- The final candidate prevents stale generic persistence completions from
  overwriting newer external failure state, restores mover vendor booking and
  confirmation dependencies, removes the `.allComplete` card render path, and
  classifies future-dated snoozes before visible status buckets.
- The iPhone 17 Pro / iOS 26.5 simulator build completed with
  `** BUILD SUCCEEDED **`. `project.pbxproj` remained diff-clean. No commit and
  no remote deployment were made.

### Stop reason and proposed documentation edit

- The final validator failed only A1.6 because the report omitted
  `IdentityService.swift:178`, where add-address persistence encounters a
  swallowed geocoding failure and continues without derived distance/interstate
  data. Under the two-attempt rule, Phase A halts here even though all functional
  acceptance lines pass.
- Phase A remains uncommitted for human review; Phases B–F did not start, and
  `functions:resolveProvider` was not deployed.
- Add an execution-protocol template for audit acceptance lines containing:
  `ROOT ENTRY POINTS`, `TRANSITIVE DEPENDENCY DEPTH`, `INCLUDED READBACKS`, and
  `EXCLUDED NON-PERSISTENCE FALLBACKS`. Require that manifest before writer work
  begins. This SESSION_NOTES block is the final repository edit/action of the
  halted session.

## Post-Test Cleanup chip — Phases A–F completed (2026-08-01)

This completion block supersedes the preceding halted-state block.

### A1.6 correction and final validation

- `PHASE_A_REPORT.md` now includes the swallowed geocoding failure at
  `IdentityService.swift:178` in the bounded flow-persistence/identity audit.
- Only A1.6 was rerun after that report correction. The fresh validator
  reconciled all 77 `try?`/`catch` hits across the report's three categories,
  with no unmatched or misclassified hit, and returned PASS.
- Phase A's launch-blocking exit behavior remained functionally green across
  all 21 routed flow families: one outer exit, native nested dismissal,
  whole-flow answer-state evaluation, persistence-honest saved/unsaved dialog,
  full nested teardown, and outermost-step resume.

### Phase and commit ledger

- Phase A — `63576e61db8c27608c1acb99a0229e254d9d4539` — post-test cleanup,
  including the deleted `.allComplete` card render path.
- Phase B — `b267f676dda3b7b82e4b25f0b215db8767343f3c` — resolver intent and
  validation. The only deployment was the sanctioned `functions:resolveProvider`.
- Phase C — `24310c4b6d82356d48bcb7733c758ae1ceb36c26` — scrolling flow forms
  converted to stepped questions.
- Phase D — `0814f680578a4e1e235009a90988c45583901055` — chaptered Lucide
  assessment visuals.
- Phase E — `66ca63c247a3f632ee3ba0c7a46e807408f232f0` — compact ISP plan
  comparison.
- Phase F — `bb56324dc143c3d7e6490a08403787ec38d919d2` — copy inventory dump.

### Validation and close ledger

- Phase A's fresh A1.6 validator passed; the simulator/build evidence remained
  green. Phase B's live validator passed after deploying only
  `functions:resolveProvider`.
- Phase D passed D1.1–D1.6 independently with 27 simulator screenshots. Phase E
  passed E1.1–E1.5 independently; its Release build ended `BUILD SUCCEEDED`,
  and the iPhone 17 Pro screenshot showed all three compact cards plus the top
  of the additional-provider affordance.
- Phase F passed F1.1–F1.5 independently. `COPY_INVENTORY.md` contains 1,968
  entries across 153 sections: 1,281 Swift literals from 138 files and 687
  runtime-data literals from 15 files. The inventory has clean five-field
  source rows, no duplicate exact entries, no named LOCKED-block hits, and no
  runtime-source modification.
- Phase F stopped after the inventory dump. No copy rewrite was undertaken.
  This completion block is the final repository edit/action of the session and
  remains outside the Phase F commit.

## Peezy copy rewrite — G1–G4 close-out (2026-08-02)

### Application and data changes

- Applied G1–G4 and every targeted table replacement verbatim. Coordinator/view
  duplicates were changed together, including two live duplicates discovered
  during simulator verification (`AnyKids` and `HasVehicles`). No neighboring
  copy was rewritten.
- Removed the approved referral question from the coordinator, flow view,
  question view, assessment data model/reset, visual map, and test profile.
  Production grep now returns zero `howHeard`/`HowHeard` references.
- Repaired the disk-full-corrupted Functions dependency tree with the approved
  quarantine + `npm ci` path. `firebase-functions@7.0.3` is installed, the
  Functions entry point and mini-assessment module load cleanly, and
  `flowDefinitionsData.json` parses cleanly.
- Deployed `functions:getWorkflowQualifying`, reseeded 47 catalog tasks and 25
  flow definitions, and deployed `functions:peezyRespond` for the final G1
  fallback corrections. The post-reseed read-back reports 47 deployed tasks,
  zero ghosts, and zero missing tasks.

### Build and simulator verification

- The final iPhone 17 Pro / iOS 26.3 simulator `xcodebuild` completed with exit
  code 0 while Xcode.app remained closed. The only warning was the existing
  Crashlytics build phase lacking declared outputs.
- Completed the full assessment on the corrected build. The Accounts chapter
  ended at question 4 of 4 and advanced directly to generation; the referral
  screen is gone and the chapter count dropped by one. The generated plan
  contained 14 personalized tasks.
- Completed one managed-provider path for a bank account through its summary;
  the live screen rendered `Expect word back within 24–48 hours.`
- Ran the mover path from capture through ten refinement questions and three-way
  price comparison. The changed capture screen rendered the exact new copy. A
  subscription gate appeared only after selecting a mover; no purchase was made.
- G4 finding: the live mini-assessment interaction is tap-based. Account rows
  expose tappable add/remove controls and Continue; no swipe gesture rendered,
  so there is no live swipe-design bug to report.
- Twenty-one simulator screenshots are committed under
  `artifacts/copy-rewrite-screenshots/`, including assessment, no-referral count,
  generation/ready, mover, and managed-provider evidence.

### Final verification ledger

- Local production audit: 266 Swift/JavaScript/JSON files scanned, zero exact
  OLD-string hits, zero old G4 swipe-pattern hits, zero referral identifiers,
  and zero active first-person-singular narrator fallbacks.
- Deployed read-back: 25 Firestore flow definitions and all six callable
  mini-assessment workflows contain zero exact OLD strings and zero old G4
  swipe patterns. The six callable instructions read back with the required
  `Tap yes...` wording.
- `git diff --check` passed. This SESSION_NOTES block is the final file edit of
  the session before staging it and creating the requested all-worktree commit.

---

## Session: Trustproof Run — Full-App Exit-Risk Audit (2026-08-03)

Scope executed: peezy-trustproof-run.md Phases 1–4. READ-ONLY honored — zero
source changes; outputs are TRUSTPROOF_LEDGER.md, this block, and an updated
PHASE_MANIFEST. Six parallel read-only subsystem audits + a live simulator pass
(fresh build of 64aa5b2, test account at T-2) + independent re-verification of
every stop-ship-level claim before it entered the ledger.

### What the run doc got wrong / left ambiguous

1. **The pilot paywall findings (F-001..F-005) do not exist anywhere findable.**
   Not in any repo file, not in any prior Claude Code session transcript. Per
   execution-protocol §2 the slots were re-derived from code and marked
   `[NEEDS CLARIFICATION]` in the ledger header. Doc fix: either commit the
   pilot output as a file next to the skill, or drop the import instruction.
2. **"Induce failures cheaply (airplane mode)" conflicts with autonomous runs.**
   Cutting the host network kills the session driving the test. Offline findings
   are code-cited and flagged conservative in the ledger. Doc fix: note that
   network-loss induction needs an attended session or a proxy harness.
3. **The run doc's moment list omits the support-chat send moment** (only "who
   answers" is implied via manual-MVP). It produced a HIGH/SILENT finding
   (F-064). Worth adding explicitly to any rerun.

### What surprised (worth conventions-v2 lines)

- **`SMS notify not configured` is load-bearing on more paths than L01 implies.**
  L01 frames it as the check-in flag SMS; the same absent `ADAM_NOTIFY_NUMBER`
  silently no-ops booking, kit, and quote notifications in
  getWorkflowQualifying.js — with no adminNotifications fallback on those paths
  (unlike index.js's notifyAdmin callers). Conventions line suggestion: "The
  getWorkflowQualifying notify family writes no durable admin record; do not
  treat notifyAdmin's record-first behavior as universal."
- **FlowEngineView completes on submission error by design** (":537-545 — old
  screens completed on error too"). That inherited comment now guards the single
  worst trust path in the app (answers deleted + fake success behind a paywall).
  Any future spec touching the engine should treat that catch block as a bug,
  not a compatibility contract.
- **The Tasks tab shows date-gated post-move tasks pre-move** (sim-verified
  MOVE_CHECKIN in To-Do at T-2). `surfaceAfterDaysPastMove` gates only the dose.
  Conventions doc reads as if the gate is universal; it is not.
- **ToastOverlay is mounted below fullScreenCover flows**, so every in-flow
  error toast in the codebase is invisible. Multiple agents found "error
  handling" that exists but cannot render.

### Proposed doc edits

- CLAUDE.md / conventions-v2 "Contract facts": add the notify-family caveat and
  the dose-vs-Tasks-tab gating distinction above.
- LAUNCH_CHECKLIST: L01's blast radius should name booking/kit/quote paths, not
  only the flag SMS; consider a new gate for the FlowEngine error-completion
  behavior (ledger S3) since it invalidates the "durable Firestore record"
  contract claim from the client side (answers are deleted client-side on error
  before any record exists).
- peezy-trustproof.skill: pilot findings should ship inside the skill bundle as
  a data file so future runs can import rather than re-derive.

### Evidence trail

Ledger: TRUSTPROOF_LEDGER.md (6 stop-ship clusters, ~60 findings, fence
tensions, accepted-as-is, observability adds, cosmetics appendix). Simulator
screenshots live in the session transcript. Spot-check re-verifications:
FlowEngineView.swift:537-545, TasksStore.swift:31-32, functions/.env key names +
getWorkflowQualifying.js:317-326/347-351, PeezyHomeViewModel.swift:309-324.

---

## Day 2 — Phase 10: Verification sweep (2026-08-04)

Scope: Phase 10 only. No production source or explicitly deferred file was
changed. The exact launch-gate commands from `DAY2_BUILD_SPEC.md` were run from
the project root; their results follow.

### Launch-gate grep results

1. `grep -rn "NOTIFICATION_WEBHOOK_URL\|notifyAdmin" functions/*.js`

   Exit 0. Output was confined to the self-contained legacy module:

   ```text
   functions/notifyAdmin.js:2: * notifyAdmin — Central admin notification module
   functions/notifyAdmin.js:23:async function notifyAdmin({ type, userId, title, summary, details, urgency = 'normal' }) {
   functions/notifyAdmin.js:49:    console.error('[notifyAdmin] Failed to lookup user:', err.message);
   functions/notifyAdmin.js:76:    console.error('[notifyAdmin] CRITICAL — Failed to write adminNotification:', err.message);
   functions/notifyAdmin.js:89:      console.warn('[notifyAdmin] Twilio not configured — SMS skipped');
   functions/notifyAdmin.js:123:    console.error('[notifyAdmin] SMS failed:', err.message);
   functions/notifyAdmin.js:128:module.exports = { notifyAdmin };
   ```

   There are no matches in a live Functions entry point or call site. The local
   CommonJS export is not exported as a deployed callable/trigger by `index.js`.

2. `grep -rni "pinky\|money back\|money-back\|concierge" "Peezy 4.0" functions/*.json functions/index.js`

   Exit 0 with 89 raw matches, all `concierge` implementation identifiers,
   persisted enum values, comments, accessibility IDs, previews/harness code,
   provider-directory method values, or legacy `requestConcierge` server
   identifiers/comments in `functions/index.js`. There were zero
   `pinky`, `money back`, or `money-back` matches and zero rendered strings that
   contain any of the four forbidden terms. Result: zero user-visible hits.

3. `grep -rni "trial\|weekly\|annual\|renew" "Peezy 4.0/MainInterface/Views/Paywall" "Peezy 4.0/Menu/PeezySettingsView.swift"`

   Exit 0. Output:

   ```text
   Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:5://  Single-screen paywall for the six-month, non-renewing Peezy Move Pass.
   Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:118:                        Text("One-time payment charged to your Apple ID at confirmation of purchase. Includes 6 months of Peezy Move Pass access. This is not an auto-renewing subscription — access ends automatically and nothing renews.")
   Peezy 4.0/MainInterface/Views/Paywall/PaywallValueView.swift:59:                    Text("One-time payment · Nothing renews")
   Peezy 4.0/Menu/PeezySettingsView.swift:407:        case .trial:
   Peezy 4.0/Menu/PeezySettingsView.swift:408:            return "Free Trial Active"
   Peezy 4.0/Menu/PeezySettingsView.swift:422:        case .trial(let productId, let expires):
   Peezy 4.0/Menu/PeezySettingsView.swift:425:            return "\(planName) plan — trial ends in \(daysLeft) day\(daysLeft == 1 ? "" : "s")"
   Peezy 4.0/Menu/PeezySettingsView.swift:431:            return "\(planName) plan — renews \(formattedDate(expires))"
   Peezy 4.0/Menu/PeezySettingsView.swift:447:        case .weekly:
   Peezy 4.0/Menu/PeezySettingsView.swift:448:            return "Weekly"
   Peezy 4.0/Menu/PeezySettingsView.swift:449:        case .annual:
   Peezy 4.0/Menu/PeezySettingsView.swift:456:        case .trial(let productId, _), .subscribed(let productId, _):
   ```

   The paywall matches are explicit non-renewing disclosures. Settings matches
   are the grandfathered legacy receipt-state labels and enum cases; the live
   Move Pass path remained a one-time purchase with a fixed six-month access
   window and no renewal.

4. `grep -rn '\$[0-9]' --include='*.swift' "Peezy 4.0"`

   Exit 0 with 237 raw matching lines. Swift closure shorthand (`$0`) accounts
   for 232 of them, including lines that separately format dynamic values. The
   only five user-visible literal-dollar matches were the Audit D `KEEP`
   exceptions:

   ```text
   Peezy 4.0/Tasks/Task Cards/MoveCheckInView.swift:255:                    Text("Enter a final bill greater than $0, or leave it blank.")
   Peezy 4.0/Tasks/Task Cards/SellItemsFlow.swift:96:                option1: FlowOption(id: "under_500", label: "Under $500", icon: "dollarsign.circle"),
   Peezy 4.0/Tasks/Task Cards/SellItemsFlow.swift:97:                option2: FlowOption(id: "500_2000", label: "$500 – $2,000", icon: "dollarsign.circle.fill"),
   Peezy 4.0/Tasks/Task Cards/SellItemsFlow.swift:98:                option3: FlowOption(id: "2000_5000", label: "$2,000 – $5,000", icon: "banknote"),
   Peezy 4.0/Tasks/Task Cards/SellItemsFlow.swift:99:                option4: FlowOption(id: "over_5000", label: "$5,000+", icon: "banknote.fill"),
   ```

5. `grep -rn "We'll\|we'll" functions/flowDefinitionsData.json functions/taskCatalogData.json`

   Exit 1 with no output. Result: zero execution promises in either authoritative
   Functions data inventory.

### Build and clean-install simulator pass

- `xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build`
  completed with exit 0 and `** BUILD SUCCEEDED **` against iOS 26.5.
- Shut down the prior simulator, booted the exact iPhone 17 Pro / iOS 26.5
  destination, uninstalled `peezy.Peezy-4-0`, installed the new Debug build,
  and launched it. The simulator Keychain retained an earlier Firebase session
  across uninstall, so that session was signed out before creating a new
  synthetic account.
- The fresh account completed the full assessment and generated 14 personalized
  tasks. The free task list exposed titles and due dates; opening `Scan your
  home` presented the Move Pass value screen and purchase gate.
- Relaunched through the shared Xcode scheme so `Configuration.storekit` was
  attached. The localized StoreKit display price loaded, the system sheet
  identified a one-time charge and explicitly said the test purchase would not
  charge, and the Xcode-environment sandbox purchase succeeded.
- After purchase confirmation, the paywall dismissed directly into `Scan my
  home`. Result: clean-install assessment → list → locked task → sandbox
  purchase → task unlock **PASS**, with the entitlement behaving as a
  non-renewing six-month Move Pass.

### Launch-blocking copy observed during the required live pass

The simulator pass exposed three reachable copy violations that the prescribed
greps do not fully cover:

- Assessment services intro: `we'll line up the quotes` promises Peezy
  execution (`AssessmentCoordinator.swift:550`; duplicated in
  `Servicesintro.swift:11`).
- Paywall value screen: `The research done for you. Your home scanned. The
  right truck the first time. A packing plan built around your date.` promises
  execution/outcomes, while the wrong-sized-truck/cupholder comparison makes an
  unsupported reference-cost claim (`PaywallValueView.swift:39,45`).
- Purchase gate: `Six months of Peezy doing the work.` directly violates the
  equip-and-inform rule (`PaywallGateView.swift:56`).

Phase 10 is a verification-and-recording phase, and the assessment source files
are outside its named write scope, so none of these earlier-phase defects was
edited here. Overall launch-gate result: **BLOCKED on reachable copy** despite
the successful build, non-renewing purchase, and task unlock.

ARCHITECT RULING: copy tone rule clarified — banned: promises of action outside the app (contact/arrange/book/line up); allowed: accurate descriptions of in-app software behavior (research/scan/plan/recommend). Phase 10 violations 2 and 3 ruled false positives under this distinction; violation 1 fixed this session.

---

## Day 3 — Phase 7: Verification sweep (2026-08-04)

Scope: Phase 7 only. No production source or explicitly deferred file was
changed. Phase 7 cites no audit-report section. Static checks, a signed Debug
build, and the clean-install simulator sweep were run from the project root.

### Static verification

1. `grep -rn "claude-" functions/*.js "Peezy 4.0" | grep -v seedAppConfig`

   Exit 0, so the gate is **not clean**. The broad command also finds historical
   documents and build logs. Restricting the same check to executable Functions
   source leaves two literal-model matches: `functions/processInventory.js:184`
   and `functions/resolveProvider.js:283`. Both files are outside Phase 7; the
   inventory migration is explicitly deferred, so neither was edited.

2. `rg -n 'https?://|www\.|URL\(string:|web_search|request\.tools|\.tools\s*=' functions/peezyChat.js "Peezy 4.0/MainInterface/Views/SupportChatView.swift"`

   Exit 1 with no output. The chat callable and client path contain no URL
   construction, web-search tool, or request-tools configuration.

3. `grep -n -A3 -B2 'if (!request.auth)' functions/researchTask.js functions/peezyChat.js`

   Exit 0. `researchTask.js:587` and `peezyChat.js:363` both reject requests
   without `request.auth`.

4. `node --check functions/researchTask.js` and
   `node --check functions/peezyChat.js`

   Both completed with exit 0.

5. `firebase functions:list --json | jq -r '.result[].id' | sort | rg '^(peezyChat|researchTask)$'`

   Exit 0 with only `researchTask`. The Phase 6 `peezyChat` callable is not
   deployed, which blocks successful responses from either live chat surface.

### Build and clean-install simulator sweep

- A normally signed Debug simulator build for iPhone 17 Pro / iOS 26.4.1
  completed with exit 0 and `** BUILD SUCCEEDED **`. An initial diagnostic
  build with signing disabled produced a Firebase Keychain-access error during
  account creation; rebuilding with the standard simulator signing identity
  removed that error.
- Uninstalled `peezy.Peezy-4-0`, installed the signed build, launched it, and
  created a new synthetic Firebase account. The account completed the full
  assessment and generated 19 personalized tasks.
- Opening a locked task presented the Move Pass value screen and purchase gate.
  Relaunching from the shared Xcode scheme attached `Configuration.storekit`.
  The localized StoreKit price loaded, the system sheet identified a one-time
  charge and testing-only/no-charge confirmation, and the sandbox purchase
  succeeded. The paywall dismissed into the task. Result: assessment → gate →
  non-renewing Move Pass purchase **PASS**.
- Web generation: `SCHOOL_TRANSFER` produced a personalized brief with six
  visible source buttons and a `What could go wrong` section. **PASS**.
- Reasoning generation: `SCHEDULE_TIME_OFF_WORK` produced a personalized brief
  with no sources and a `What could go wrong` section. **PASS**.
- Preference generation: `BOOK_MOVERS` required and retained all three selected
  preferences (careful handling, a few days of date flexibility, and fragile or
  high-value items), then produced a cited brief with a `What could go wrong`
  section. **PASS**.
- Task-scoped chat and global chat both rendered, accepted a message, cleared
  the composer, and displayed the bounded retry error. Successful AI responses
  are **BLOCKED** because `peezyChat` is absent from the deployed callable
  inventory.
- Box Return used a controlled synthetic-account fixture matching the Day 2
  prerequisite contract: `workflowResponses/supplies_kit` contained a 15-box
  kit, and a due-now `BOX_RETURN` task was added because the clean account's
  move date had not reached the catalog's seven-days-past-move surface rule.
  The flow read `Your kit included 15 boxes`, accepted 1 returned box plus
  `did not run out`, saved successfully, and rendered `1 of 15 boxes recorded`.
  Firestore readback showed `kitCalibration.delivered = 15`, `returned = 1`,
  and `ranOut = false`. **PASS**.

### Cost sanity

`firebase functions:log --only researchTask --lines 500 | rg -i
'"usage"|input_tokens|output_tokens|inputTokens|outputTokens'` exited 1 with no
output after the three live generations. The deployed callable logs invocation
verification but no provider token-usage fields; the Phase 7 source review also
confirmed that `response.usage` is not logged. The requested web-brief token
count is therefore **NOT OBSERVABLE** without a change outside this verification
phase. No estimate was fabricated.

Overall Phase 7 result: build, clean-install assessment, gate, sandbox purchase,
three research modes, and Box Return pass. Launch verification remains
**BLOCKED** on the two out-of-phase model literals, missing `peezyChat`
deployment, and absent research token-usage logging.

---

## Day 4 — Phase 6: Verification sweep + Thursday calibration protocol (2026-08-04)

Scope: Phase 6 only. The only repository writes are this verification ledger
and `THURSDAY_CALIBRATION.md`. No production source or explicitly deferred file
was changed. Phase 6 cites no specific audit row; `audit_reports/AUDIT_A_REPORT.md`
was read in full before verification.

### Static verification

1. Model-literal sweep outside seeders:

   ```sh
   rg -n 'claude-[0-9A-Za-z.-]+' functions --glob '*.js' \
     --glob '!seed*.js' --glob '!peezy-brain-ralph/**'
   ```

   Exit 1 with zero matching lines. **PASS.** The only deployable Functions
   model values are read from config; the seeder remains the permitted source
   of pinned values.

2. Entitlement call-site sweep:

   ```sh
   rg -n 'await requireMovePass\(request\.auth\.uid\)' \
     functions/processInventory.js functions/peezyChat.js \
     functions/researchTask.js
   ```

   Exit 0 with exactly three call sites:

   ```text
   functions/researchTask.js:603
   functions/peezyChat.js:378
   functions/processInventory.js:179
   ```

   Each call follows the authentication rejection and precedes input parsing or
   task work. **PASS.**

3. Day 4 source-copy sweep. The retired service term is assembled from two
   fragments so this ledger does not add another source-string hit:

   ```sh
   retired_service_term='con''cierge'
   base=$(git rev-parse 436ad9c^)
   git diff --name-only -z "$base"..HEAD |
     while IFS= read -r -d '' file; do
       case "$file" in
         *.swift|*.js) test -f "$file" && printf '%s\0' "$file" ;;
       esac
     done |
     xargs -0 rg -n -i "${retired_service_term}|we['’]ll"
   ```

   Exit 0 with 23 lines in four Day 4-touched source/test files. The contraction
   arm has zero matches. The retired-service arm remains in compatibility
   aliases in `FindMoversFlow.swift`, an old enum assertion in
   `EstimateIntegrityPhaseCTests.swift`, legacy callable and collection names
   in `functions/index.js`, and provider fallback values and prompt text in
   `functions/resolveProvider.js`. **FAIL.** These files are outside Phase 6's
   write scope, so the raw-string gate was not rewritten or waived.

4. JavaScript checks and tests:

   ```sh
   node --check <each Day 4-touched top-level Functions JavaScript file>
   node --test functions/tests/*.test.js
   ```

   Syntax checks completed with exit 0. The test run passed 20 of 20 tests with
   zero failures. **PASS.**

5. Deployed callable inventory:

   ```sh
   firebase functions:list --json | jq -r '.result[].id' | sort |
     rg '^(peezyChat|processInventory|redeemGiftCode|researchTask)$'
   ```

   Exit 0 and all four required callables were present. **PASS.**

### Build

```sh
xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
```

The build log contains `** BUILD SUCCEEDED **` for the iPhone 17 Pro simulator
destination. **PASS.** The command wrapper's later attempt to assign zsh's
reserved `status` parameter exited nonzero; the underlying `xcodebuild` process
and log completed successfully.

### Production config and rules preflight

An Admin SDK read of the required config inventory returned:

```text
appConfig/ai: present
appConfig/anchors: present
appConfig/cubeSheet: present
appConfig/trucks: present
appConfig/supplyRates: MISSING
appConfig/packing: MISSING
```

The checked-in Firestore rules have authenticated read matches for user data,
task catalog, flow definitions, vendor cards, and provider directories, but no
authenticated read match for `appConfig/{document=**}`. The signed-in simulator
therefore received `Missing or insufficient permissions` when the client read
config. This blocks truck, supplies, and packing-plan acceptance even for the
config documents that exist. No seed or rules mutation was performed in this
verification-only phase.

### Simulator pass

Device: iPhone 17 Pro simulator, iOS 26.4.1. A clean synthetic account completed
the minimum assessment fixture needed for the Phase 6 surfaces. Test-only task,
inventory, and entitlement fixtures were written under that account; no
production user data was used.

#### Gift redemption and Move Pass reference model

- A newly minted gift code redeemed through the app. Server readback showed the
  code as redeemed by the test user and a future six-month subscription
  expiration using the same ISO-string shape as subscription validation.
  Server transaction: **PASS**.
- Reusing the same code rendered `This code was already used`. **PASS**.
- The app dismissed the paywall after a successful gift response, but scanner
  access remained gated; after relaunch the gift access was still absent.
  **FAIL.** `SubscriptionManager.swift:295-298` recognizes only a Firestore
  `Timestamp`, while both gift redemption and subscription validation persist
  `expirationDate` as an ISO string. This client file is outside Phase 6.
- The shared Xcode scheme's StoreKit test purchase rendered a dynamic localized
  price and one-time-charge disclosure, granted a future six-month Move Pass,
  unlocked the scanner, and remained visible after relaunch. **PASS.** No
  auto-renewable behavior was introduced or assumed.
- A separate clean no-entitlement account called `researchTask` and received
  HTTP 403 / `PERMISSION_DENIED` / `Move Pass required`. Server denial:
  **PASS**.

#### Truck, cost, packing, and supplies

- The mover scope loaded the scan-based two-bedroom total as approximately 900
  cubic feet. The wide, quote-dependent long-distance guidance rendered without
  a fixed dollar claim. **PASS** for the cost boundary presentation.
- Truck guidance rendered its bounded unavailable state because the signed-in
  client could not read `appConfig/trucks`. No tier recommendation could be
  judged. **BLOCKED** by Firestore config read permissions.
- The packing-supplies flow rendered `Couldn't load your kit` and `Missing or
  insufficient permissions.` No quantities or total rendered. **BLOCKED** by
  config read permissions and the absent `appConfig/supplyRates` document.
- A packing-plan before/after comparison could not run against the deployed
  config. **BLOCKED** by config read permissions and the absent
  `appConfig/packing` document.

#### Research and chat after enforcement

- The entitled research request passed authentication and the Move Pass guard,
  reached the provider, then rendered `Peezy couldn't finish this research.`
- The entitled task chat accepted and sent a message, passed the Move Pass
  guard, reached the provider, then rendered the bounded retry error.
- Function logs identify the common downstream cause as insufficient provider
  credit. The no-entitlement request was denied before provider work.

Entitlement enforcement behaves correctly, but successful research and chat
responses are **BLOCKED** by external provider credit and are not green for this
sweep.

### Thursday handoff

`THURSDAY_CALIBRATION.md` defines the physical-iPhone, real-room procedure for
item reality, per-item cubes, all truck tiers, cost guidance, packing-plan
sequencing, and supplies quantities. Its correction table maps every permitted
calibration to an exact `appConfig`, `vendors/{vendorId}.rateCard`, or nested
field. Observations without a valid data field are explicit stop conditions;
they cannot be hidden as unrelated config edits.

Overall Phase 6 result: build, syntax/tests, model-config sweep, entitlement
call sites, deployed callable inventory, gift server transaction, duplicate
gift error, StoreKit non-renewing access, no-entitlement denial, and wide cost
guidance pass. Launch verification remains **BLOCKED** on the raw retired-term
source sweep, gift ISO-date client decoding, missing config documents, absent
client read permission for `appConfig`, and insufficient provider credit.
