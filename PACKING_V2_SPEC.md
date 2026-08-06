# Packing Engine v1 — Build Spec (v2, supersedes all prior packing specs)

Adam's simulation design + accepted items from external review. The interactive
layer (taps, timers, pace learning, root-cause feedback) remains 1.1 against
the frozen contract in Appendix B.

## Session Protocol (unchanged from Days 2-4)
One phase per fresh session; read cited files fully first; `node --check` /
build verify; commit `packv2: phase N — <name>`; diff confined; tone rule
applies; every tuning number in config, never code.

## Design Rules (LOCKED)
1. Walkthrough order is sacred: room (by min first-seen frame), then item
   first-seen frame, ties broken by inventory doc ID. Never globally optimize.
2. THREE LANES, each with at most ONE open box at a time:
   dense (books, media, tools, canned) · fragileClean (glass, dishes, decor,
   electronics) · generalSoft (clothing, linens, general household).
   An item goes to its lane's open box if EVERY check passes: padded volume,
   box max gross weight, min/max box size, incompatibleTags, lane membership.
   Any failure → close that lane's box (log which constraint closed it), open
   the size its padded volume calls for. Specialty containers bypass lanes.
3. Volume terms: protectionFactor (≥1.0, wrapping/air) and compressionFactor
   (≤1.0, soft goods) are SEPARATE config fields. Effective volume =
   cube × protectionFactor × compressionFactor. Box capacity =
   usableCube × fillEfficiency. Weight = unit cube × lbPerCuFt(densityClass),
   summed against the box's maxGrossWeightLb.
4. Quantity semantics: every cube-sheet row gets packingUnit.behavior:
   "indivisible" (sofa) | "countable" (books qty 50 → 50 units) |
   "bulkDivisible" (config maxChunkQty → chunks). The simulator packs UNITS,
   then re-aggregates adjacent same-name units for display.
5. Routing precedence, strict order: transportPolicy → packingState →
   row specialtyRoute → row notBoxable → category fallback → lane simulation.
   Row-level rules ALWAYS beat category rules.
6. No hidden blends. plannedBySize = the literal plan. reserveBySize comes
   from a second deterministic STRESS run (high-band cubes for ambiguous
   items, per-coverageDebt allowances by container type, lower fill for
   uncertain fragile) minus planned, floored at 0. purchaseBySize = planned +
   reserve, each reserve line carrying its named reason. The old
   reconciliation blend is DELETED; divergence logs a diagnostic only.
7. Messy-home truth: the vision model emits packingState per item
   (loose | alreadyPackedSealed | alreadyPackedOpen | emptyContainer |
   visibleContentsStayInside | closedContentsUnknown | builtInOrStays).
   Sealed boxes are existing containers, never re-boxed, contents never
   double-counted. Closed storage (dresser, cabinet, opaque bin, closed
   closet) creates a coverageDebt record — never invented contents. Built-ins
   excluded unless user-marked. Debts feed reserve (Rule 6) and disclosure
   (Rule 9).
8. Transport policy runs FIRST: rows/keywords flagged carrierRestricted
   (fuels, compressed cylinders, paint/chemicals, some batteries,
   perishables) or carrySeparately (medications, documents, valuables) exit
   the simulation with copy: "Set this aside before packing. It may be
   restricted by a mover or carrier — rules vary by provider." Never a
   universal legal claim. Garage/utility scans surface the restricted list
   prominently.
9. Trust surfaces: beta label stays verbatim ("Packing engine · beta —
   estimates improve as movers like you use it") AND an evidence card renders
   with every plan: assigned + reserve counts, "based on items visible in
   your walkthrough and the inventory you confirmed," could-not-verify list
   (from coverageDebt), most-uncertain list (high-band + ambiguous), and
   not-included note. Coverage grades High/Medium/Limited — never fake
   percentages. All times render as ranges ("about 10–15 min") from a
   configured spread around the central estMinutes.
10. Privacy is a feature: pre-scan disclosure states the truth we already
    have — the video never leaves the phone; only still frames upload for
    processing; after inventory finalization the server deletes all frames
    except per-item evidence frames (retained for plan thumbnails until the
    move ends or the account deletes). Copy ships in Phase 5; cleanup in
    Phase 3.

## Phase 1 — Config: pack profiles, box catalog, validation (server/seed)
READ FIRST: seedCubeSheet.js, appConfig/cubeSheet shape, supplyRates.
1. Box catalog into appConfig/packingSim.boxes: per size —
   internalDimensionsIn, usableCube (existing box cubes), maxGrossWeightLb
   (small 50, medium 65, large 65, xl 70 — drafts), permitted lanes.
2. packProfile annotations for the ~30 highest-risk cube rows (books, media,
   dishes/glassware, tools, canned/pantry, framed art, mirrors, lamps,
   electronics, linens, hanging clothes, records, liquids/chemicals, meds/
   documents/valuables rows): lane, densityClass (light|medium|heavy →
   lbPerCuFt config 6|12|25 drafts), minBox, maxBox, incompatibleTags
   (liquid, sharp, dirty, heavy-on-fragile), protectionFactor,
   compressionFactor, specialtyRoute?, transportPolicy?, availabilityFlag?
   (packLast | openFirst | carrySeparately for ~15 obvious rows).
   Unannotated rows inherit category defaults (config map).
3. Seeder validation BEFORE any write: JSON schema, cross-refs (every lane/
   box/route/tag resolves), ranges (0<fillEfficiency≤1, positive weights),
   conflict check (boxable vs notBoxable needs explicit precedence). Fails
   loud, writes nothing. Stamp configVersion (content hash) into the doc.
VERIFY: node --check; validation rejects a deliberately broken fixture;
Adam deploys + reseeds after Phase 2 (single deploy for both).

## Phase 2 — The constrained packer (server)
READ FIRST: processInventory.js finalization section (Day 4 ordering:
outputs-before-lock), inventory item schema incl. frames + doc IDs.
1. functions/packSimulation.js, pure + unit-tested:
   `simulatePack(items, config) → { packResult, trace, closures }` per Design
   Rules 1-5. Unitization first, then transport/state/specialty routing, then
   lane simulation with bottom-to-top layering order recorded inside each box
   (heavy/rigid → general → fragile/light).
2. Specialty estimators, simple v1: mattress size→bag; TV band→kit; hanging
   clothes count→wardrobes (config itemsPerWardrobe); framedArt/mirrors→
   picture cartons (config itemsPerCarton by size band); dishes→dishPacks
   (config bundlesPerPack). Specialty units excluded from stress comparison.
3. STRESS run (Rule 6) as a second call with the stress config transform.
4. Trace (server-only, outside Appendix B): per box → [{inventoryItemId,
   cubeRowId, qtyPacked, effectiveCube, estWeightLb, evidenceFrames}], plus
   closures log [{boxRef, closedBy: "volume|weight|incompat|maxBox"}], plus
   coverageDebt[] and restrictedItems[].
5. GOLDEN FIXTURES (required, the suite fails if any regress):
   (a) lamp + 20 books + framed photos → MUST yield books in smalls (dense
   lane), frames routed to picture carton, lamp in fragileClean large — the
   old single-box answer is the failing case; (b) 50-book line → unitized,
   multiple smalls, none over weight; (c) sealed moving box with visible
   contents → one existing container, zero double-count; (d) closed dresser →
   coverageDebt, no invented contents; (e) garage with paint + tools →
   restricted list + dense lane; (f) notBoxable-only room → zero boxes +
   handling notes; (g) same inputs twice → byte-identical output; (h) open
   tote visibleContentsStayInside → excluded with assumption recorded.
VERIFY: node --check; all fixtures green.

## Phase 3 — Aggregates, integration, frame cleanup (server)
READ FIRST: processInventory finalization + room/move doc shapes; Storage
frame paths (Audit A).
1. Integration: after cube validation, before lock, per room: run simulation
   + stress; persist room packPlan (Appendix B) + packMeta {status:
   "complete", inventoryRevision, configVersion}. Failure → packMeta
   {status:"failed"} and finalization proceeds (legacy plan renders).
2. Move-level aggregate: RECOMPUTED from current room docs on every write —
   never incremented: {status: building|partial|complete, expectedRoomIds,
   includedRoomIds, plannedBySize, reserveBySize (with reasons),
   purchaseBySize, coverageDebt, restrictedItems, uncertainty metadata for
   the evidence card, configVersion}. status complete only when every
   expected room has a matching-revision complete packMeta.
3. Frame cleanup: on finalization, delete the session's uploaded frames from
   Storage EXCEPT frames referenced as evidence in the trace. Best-effort,
   independently guarded, after critical writes (doctrine).
VERIFY: node --check; retry-twice fixture produces identical aggregate (no
double count); one failed room → status partial and client-guard flag.

## Phase 4 — Additive prompt touch: packingState + transport flags
READ FIRST: processInventory prompt + parse (Day 4 two-pass version).
Append to the item schema in the prompt: packingState (enum, Rule 7) and
restrictedCandidate: bool (obvious fuels/chemicals/etc.). ADDITIVE ONLY — no
change to existing fields or the cube contract. Parse tolerantly: missing →
"loose"/false. Extend fixtures: sealed box, closed dresser, paint can.
VERIFY: node --check; existing 20+ tests still green; new fixtures green.
(Adam deploys + reseeds HERE — one deploy covers Phases 1-4.)

## Phase 5 — Client (binary-bound, modest)
READ FIRST: KitEstimator.swift, PackingPlanEngine.swift + session render,
SuppliesKitView.swift, InventoryScanCoachingView.swift.
1. Supplies: when move aggregate status=="complete" AND inventoryRevision
   matches current inventory → purchaseBySize REPLACES formula counts,
   rendered as "N assigned + M reserve" with reserve reasons one tap away;
   otherwise legacy formula unchanged.
2. Plan render: rooms with packPlan show box cards — "Box 3 · Medium — three
   folded sweaters, two handbags, jewelry organizer" with layer order —
   leftovers with handling notes, restricted items in their own flagged
   section at top, times as ranges. Legacy rooms render exactly as today.
3. Evidence card (Rule 9) above the plan; beta label on plan + supplies.
4. Open-first strip: rows flagged openFirst/carrySeparately render as a
   "Keep these out" list at the plan's end.
5. Coaching screen gains the privacy line (Rule 10 copy): "Your video never
   leaves your phone. Peezy uploads still frames only, and deletes them
   after your inventory is confirmed — keeping just the snapshots that show
   where your items are."
VERIFY: build; fixture account renders boxes/reserve/evidence card;
legacy account untouched; partial-status account falls back to formula.

## Phase 6 — Verification
Fixture end-to-end; greps (no hardcoded dims/weights/minutes/factors);
build; Appendix B byte-checked; SESSION_NOTES entry; THURSDAY_CALIBRATION
addendum: section E judges box believability + lane sanity + walkthrough
order; section F judges planned-vs-reserve honesty; corrections map to
appConfig/packingSim fields (list them).

## Appendix A — Beta + evidence copy (verbatim)
Label: "Packing engine · beta" / Line: "Estimates improve as movers like you
use it." Evidence card headline: "What this plan is based on."

## Appendix B — packPlan schema (FROZEN 1.1 contract)
{ "generatedAt": ISO, "engineVersion": "sim-v2", "configVersion": "...",
  "boxes": [ { "n": 1, "size": "medium", "lane": "generalSoft",
    "items": [ { "name": "Folded sweaters", "qty": 3 } ],
    "layers": ["handbags","sweaters","jewelry organizer"],
    "estMinutes": 9, "roomId": "bedroom-1",
    "startedAt": null, "packedAt": null,
    "fitFeedback": null } ],
  "leftovers": [ { "name": "Queen mattress", "handlingNote": "mattress bag" } ],
  "restricted": [ { "name": "Paint cans", "policy": "carrierRestricted" } ],
  "openFirst": [ "Coffee maker", "Medications" ],
  "totalsBySize": { }, "reservedFeedbackSchema": { "outcome":
    "easy|snug|failed", "failureReason": "tooFull|tooHeavy|awkwardShape|unsafeMix|inventoryMismatch",
    "actualSize": null, "activeSeconds": null, "crewCount": null } }

## Explicitly Deferred
1.1: Box Recipe Mode, tap/timer/pace learning, root-cause feedback capture,
availability phase-sorting, micro-zones, keyframe preprocessing, work-content
time model, calibration loop (#17 blueprint filed), model band-output
refactor (#8 — FIRST post-launch server change), full 130-row profiles,
confirmation cards for coverage debt. Later: box catalogs, user-owned
containers.
