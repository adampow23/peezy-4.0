# Day 4 Build Spec — Scanner, Cube Sheet, Truck, Gift Codes

Inputs: AUDIT_A (defect evidence — authoritative for every fix here),
PEEZY_CUBE_SHEET.md (MUST be in the project root before Phase 2 — it is the
seed source), PEEZY_LAUNCH_PLAN_AUG2026.md, Day 2-3 commits.

## Session Protocol (unchanged)
One phase per fresh session; read spec phase + cited audit rows + every named
file fully first; build / `node --check` verify; commit `day4: phase N —
<name>`; diff confined to named files; tone rule + architect ruling apply; no
hardcoded prices or model strings anywhere new — and Phase 1 removes the last
existing ones.

## Locked Rulings (context for copy and behavior)
- Truck output: three load-quality tiers the user self-selects (Tier 1
  "Packed tight" ×1.15, Tier 2 "Pretty good" ×1.30, Tier 3 "Just get it in"
  ×1.45). Recommendation = smallest truck whose capacity covers scan cube ×
  tier multiplier. Also surface the next size up as "the comfortable choice."
- Above 26': never a hard answer. Educate both options (second trip vs.
  second truck), recommend by distance — under ~120 miles ("about two hours'
  drive") → second trip; over → second truck. User chooses.
- Long-distance (>100 mi) cost estimate: wide honest range + research
  guidance, never a fake-precise number, never a concierge reference.
- Supplies dollar total ships from draft market rates in config; label it
  "Estimated at typical retail — prices vary." Adam corrects rates in config.
- All tuning numbers (cube ranges, anchors, trucks, tiers, supply rates,
  packing constants) live in Firestore config. Thursday's calibration edits
  data, never code.

---

## Phase 1 — Scanner defects + config migration + usage logging (functions + client touchpoint)
READ FIRST: AUDIT_A rows on frame handoff, finalization ordering, and the
model literal + its locking test; then processInventory.js and the capture/
upload client code the audit cites, fully.

1. **Frame atomicity (server-authoritative fix):** processInventory stops
   assuming frames 0..N-1 from a count. It lists the actual files under the
   session's Storage prefix and processes exactly what exists, in name order.
   The count param becomes a logged sanity check (mismatch → log warning,
   proceed with listed files). Client: add one retry per failed frame upload;
   if a frame still fails, continue — the server no longer breaks on gaps.
2. **Finalization ordering:** reorder so ALL outputs (inventory finalize +
   packing plan + estimates) persist BEFORE the scan is marked submitted/
   locked. Any failure leaves status "processing" with the client's existing
   retry surface reachable — a user can never be stranded with a locked scan
   and no outputs. Read the audit's exact sequence before touching it.
3. **Model literals → config:** processInventory reads `inventoryModel`,
   resolveProvider reads `resolverModel`, via aiConfig.js. Update
   seedAppConfig.js to add `resolverModel: "claude-sonnet-4-6"` (merge, not
   overwrite). Update the test that currently LOCKS the hardcoded literal so
   it asserts config usage instead — the test must protect the new rule, not
   the old bug.
4. **Usage logging:** researchTask, peezyChat, processInventory log input/
   output token counts from each API response (one structured log line each).
VERIFY: `node --check` all touched; build (client retry change); the model
grep from Day 3's sweep now returns zero literals outside seeders.

## Phase 2 — Anchor prompt + cube sheet (server)
READ FIRST: PEEZY_CUBE_SHEET.md in full; processInventory.js prompt and
parse/merge sections; AUDIT_A's pipeline map.

1. **Seeder:** new `functions/seedCubeSheet.js` transcribing the cube sheet
   verbatim into config docs: `appConfig/anchors` (Part 1), `appConfig/
   cubeSheet` (Part 2 — every row: { key, category, low, typical, high };
   boxes keep fixed cubes), `appConfig/trucks` (Part 3 — capacities, tier
   multipliers 1.15/1.30/1.45, tier labels and descriptions, the above-26'
   ruling constants including the 120-mile threshold). Transcribe exactly;
   invent nothing.
2. **New inventory system prompt** (replaces the freehand-cube prompt):
   - Pass 1: identify anchor reference objects (from `appConfig/anchors`,
     injected into the prompt) visible in the frames.
   - Pass 2: identify every physical item EXACTLY ONCE across all frames —
     the frames are one continuous walkthrough of one room; track items
     across frames; note which frames each item appears in.
   - For each item: `type` (must be a key from the injected cube sheet rows;
     if nothing fits, `type: "unknown"` + free-text name), size class,
     `cubicFeet` WITHIN the row's [low, high] placed using anchor-relative
     size judgment, quantity, fragile, highValue, confidence.
   - Output JSON only, existing field names preserved for downstream
     compatibility (read the current parse code and match it — extend, don't
     break).
3. **Server validation:** every returned cube clamps to its row's range
   (clamps logged + item flagged `adjusted`); `unknown` types get the size-
   class typical (small 5 / medium 15 / large 30 / oversized 50) and
   `uncertain: true` so review sorts them first. Existing name-merge dedup
   stays as a safety net only.
VERIFY: `node --check`; Adam deploys and runs `node seedCubeSheet.js` +
`node seedAppConfig.js` after commit; one live scan in the simulator (camera
feeds a sample video in sim — if capture is device-only per the audit, defer
the live scan to Thursday's device calibration and say so in the commit
message).

## Phase 3 — Truck size + supplies rates + packing constants
READ FIRST: AUDIT_A rows for the estimate/results surfaces, KitEstimator (or
the supplies computation the audit names), the packing plan generator.

1. **Truck size (net-new, client):** `TruckSizeView` on the scan-results/
   estimate surface: reads `appConfig/trucks` + the user's total cube; three
   tier options (text descriptions at launch, photos post-launch); shows the
   recommended truck per selected tier + "comfortable choice" next size up;
   above-26' state renders both options with the distance-based
   recommendation and one-line tradeoffs. Persist the user's tier choice.
2. **Supplies rates:** new `appConfig/supplyRates` seeded (extend
   seedCubeSheet.js): smallBox 1.75, mediumBox 2.20, largeBox 4.75→NO — use:
   largeBox 2.75, xlBox 3.60, dishPack 9.50, wardrobe 14.00, pictureCarton
   8.00, packingPaper10lb 14.00, bubbleRoll 22.00, tapeRoll 4.00, mattressBag
   10.00, stretchWrap 16.00, marker 2.00. (Current mid-market retail, Aug
   2026 — drafts for Adam's config corrections.) Supplies computation swaps
   its placeholder constants for these rates; UI shows the total with
   "Estimated at typical retail — prices vary."
3. **Packing constants → config:** extract the generator's tuning numbers
   (session length, cubic-feet-per-hour, buffer days, sequencing weights)
   into `appConfig/packing` with their CURRENT values — behavior-preserving
   refactor; Thursday tunes the data.
4. **Long-distance estimate:** where the audit found the dead concierge
   branch (>100 mi / >6 hr), render the locked ruling: a wide labeled range +
   "Research this" pointer for long-distance movers. No hard number, no
   concierge remnant.
VERIFY: build; simulator: truck view renders all three tiers with sane
recommendations at a test cube (e.g. 900 cf → 20' at Tier 1-2, 26' at Tier
3); supplies total renders with the label; packing plan output unchanged
before/after the constants refactor (compare one generated plan).

## Phase 4 — Gift codes + server entitlement enforcement (functions)
READ FIRST: Day 2 Phase 3's GiftCodeRedeemSheet (the client caller — match
its callable name and payload exactly), validateSubscription.js (the
subscription doc shape it writes — match it).

1. `functions/mintGiftCodes.js` (admin script, not deployed): args `--count N
   --batch <name>`; generates codes `PEEZY-XXXX-XXXX` (no 0/O/1/I), writes
   `giftCodes/{code}` docs `{ status: "unredeemed", batchId, createdAt,
   termMonths: 6 }`, prints the list.
2. `redeemGiftCode` callable: auth required. Firestore transaction: code doc
   must exist with status "unredeemed" → set `{ status: "redeemed",
   redeemedBy: uid, redeemedAt }` and set `users/{uid}.subscription` to the
   SAME SHAPE validateSubscription writes, with `{ productId: "peezy.plus.
   move", source: "giftCode", expirationDate: now + 6 months (ISO) }`.
   Critical writes inside the transaction; clean HttpsErrors: not-found
   ("That code doesn't exist"), failed-precondition ("This code was already
   used"). Return the expiration date.
3. `functions/entitlement.js`: `requireMovePass(uid)` — reads
   `users/{uid}.subscription`; active if `expirationDate` parses and is
   future (any source). Throws `HttpsError('permission-denied', 'Move Pass
   required')` otherwise. Apply as the first check (after auth) in
   researchTask, peezyChat, and processInventory. (Simulator test purchases
   pass: the client's syncToServer writes the doc.)
VERIFY: `node --check`; Adam deploys; mint a `--count 3 --batch test` run;
redeem one code on a CLEAN simulator account → gated task opens without
purchase → relaunch → access persists; redeem the same code again → clean
"already used" error; call research from a no-entitlement account → clean
denial in the UI.

## Phase 5 — FaceTime coaching screen (client)
New pre-scan screen, shown before the user's first scan and re-openable from
an info affordance on the scanner. Copy (verbatim, Adam's design):

Headline: "Scan it like you'd show a friend"
Body: "Imagine you're on FaceTime showing a friend everything you own.
You wouldn't spin in a circle — you'd walk up to the bookshelf, angle around
the desk, open the closet. Do that. Peezy sees what you show it."
Three tips: "Walk close to furniture — don't pan from the doorway" / "Show a
second angle around big pieces" / "Open closets and show what's inside"
CTA: "Start scanning"
Match PeezyTheme; one screen, no carousel.
VERIFY: build; screen appears before first scan on a clean account, info
affordance reopens it, never blocks repeat scans.

## Phase 6 — Verification sweep + Thursday calibration protocol
1. Greps into SESSION_NOTES: zero model literals outside seeders; entitlement
   guard present in all three callables; no concierge/"we'll" strings in any
   file Day 4 touched.
2. Build + simulator pass: gift redeem e2e (from Phase 4), truck tiers,
   supplies total, research + chat still green post-enforcement.
3. Write `THURSDAY_CALIBRATION.md` into the repo root — Adam's device
   protocol: real-room scan on a physical iPhone → judge against nine years:
   (a) item list vs. reality — missed / ghost / duplicate counts; (b) cubes
   plausible per item; (c) truck recommendation vs. professional judgment at
   each tier; (d) cost estimate vs. judgment; (e) packing plan humane and
   correctly sequenced; (f) supplies counts sane for the room. Every
   correction maps to a named config doc + field so the fix session is pure
   data edits.

## Explicitly Deferred
Blur/sharpest-frame filtering (post-launch). Truck tier photos (post-launch;
text ships). Listing, screenshots, IAP creation, review notes, sandbox
device QA (Friday). Website/Allconnect (Track 1). Thumbs QC. Chat web access.
