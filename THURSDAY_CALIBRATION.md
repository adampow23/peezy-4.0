# Thursday Calibration — Physical iPhone, Real Room

Owner: Adam

Target: Thursday, August 6, 2026

Purpose: compare one real-room result with Adam's nine years of moving judgment, then make only traceable Firestore data corrections.

## Operating rule

This is a calibration session, not a feature or code session. Every accepted change must name one Firestore document and one field path from the mapping below. Record the before value, proposed value, reason, and rerun result. If an observation has no valid data field, stop that thread and log it as a scoped code or model defect; do not force it into an unrelated setting.

Move Pass access is non-renewing. Start with an active entitlement whose `expirationDate` is in the future, regardless of whether its source is a gift or StoreKit. Do not test or imply renewal.

## Preflight gate

Do not begin the room judgment until all of these are true:

- A physical iPhone runs the current signed build and can use the camera.
- The signed-in test account shows active Move Pass access after an app relaunch.
- The authenticated client can read `appConfig/anchors`, `appConfig/cubeSheet`, `appConfig/trucks`, `appConfig/supplyRates`, and `appConfig/packing`.
- The deployed inventory callable accepts the entitled account and returns a completed room.
- The test move has usable origin, destination, move date, home size, and access details.
- Current values from every config document below are saved as the baseline. No source file or seeder is edited during the session.

If any gate fails, record the failure and stop. A partially configured run cannot support calibration decisions.

## Room setup and ground truth

Choose one furnished room that includes several object sizes, at least one partially obscured item, and a closet or cabinet that can be opened safely. Keep the room unchanged through the baseline and rerun.

Before scanning:

1. Walk the room with Adam and make a ground-truth inventory. Give each physical item a stable label; record quantity and Adam's plausible cube estimate.
2. Mark items that should count as one unit, grouped units, or separate units. Note mirrors, repeated objects, and items visible from multiple angles.
3. Record the relevant whole-move context used by truck, cost, packing, and supplies outputs. Do not invent missing move details.
4. Save the app-config baseline and the time of the run.

## Scan pass

Use the first-scan coaching screen as written:

1. Start at the doorway only to establish the room.
2. Walk close to furniture instead of panning from one spot.
3. Show a second angle around large or occluded pieces.
4. Open closets and show their contents.
5. Make one continuous walkthrough and submit once.
6. Save the submitted item list, per-item cubes, total cube, truck results for all three tiers, cost guidance, packing plan, supplies quantities, and supplies total.

Do not correct the generated list before capturing the baseline output. The comparison needs the unedited result.

## Judgment sheet

For each section, write `PASS`, `DATA CORRECTION`, or `BLOCKED — NO DATA FIELD`, followed by the evidence and Adam's judgment.

### A. Item list versus reality

Compare output to the ground-truth labels and count:

- Missed items: present in the room, absent from output.
- Ghost items: absent from the room, present in output.
- Duplicates: one physical item represented more than once.
- Quantity errors: correct item type with the wrong count.
- Unknown or misclassified items: present once, but mapped to the wrong type.

For every discrepancy, cite the item label and the frames or viewpoints that support the judgment. Do not treat a cube adjustment as a fix for a detection error.

### B. Cubes per item

For every output item, compare the assigned cube with Adam's plausible cube and with its configured low, typical, and high values. Review unknown items first. Note whether the error comes from the type mapping, size class, missing scale reference, or a poor range.

Judge both individual items and the room total. A reasonable total cannot hide implausible item-level cubes.

### C. Truck recommendation

Review the same whole-move cube at each selectable tier:

- `tier1`: packed tight.
- `tier2`: pretty good.
- `tier3`: just get it in.

For each tier, record Peezy's recommended truck, the comfortable next size, Adam's recommendation, and why. If the load is above the largest truck, review both options and whether distance makes the displayed recommendation useful while leaving the decision with the user.

Tier corrections must keep the rule internally consistent: compare scan cube multiplied by the tier multiplier with truck capacity. When a multiplier changes, recompute every corresponding `fitsUpTo` threshold rather than tuning one threshold in isolation.

### D. Cost estimate

Compare the displayed estimate or guidance with Adam's judgment for the same cube, route, crew, access, services, and date. Record which input explains the difference. Long-distance output should remain deliberately wide and quote-dependent; do not replace uncertainty with a precise unsupported number.

### E. Packing plan

Read the plan in execution order and ask:

- Is each session humane for a person doing the work?
- Are room minimums and time estimates plausible?
- Are seasonal, storage, decor, guest, garage, bedrooms, bathrooms, and kitchen work sequenced sensibly?
- Are essentials protected until late enough?
- Do delivery and move-day buffers leave practical recovery time?
- Does a behind-pace plan ask for a sustainable amount of work?

Record the first step where the plan becomes unrealistic and the specific input or setting responsible.

### F. Supplies

Compare each suggested supply quantity with what Adam would send for this room, then judge the combined whole-move kit. Separate quantity judgment from retail-rate judgment. Confirm that the total is labeled as an estimate at typical retail and that price variability remains explicit.

## Data-correction map

| Observation | Allowed Firestore document and field | Calibration rule |
|---|---|---|
| A visible reference object has the wrong standard size | `appConfig/anchors.anchors[].standardDimension` for the named anchor | Correct only from a known physical standard or measured reference. |
| A useful scale reference is absent | `appConfig/anchors.anchors[]` using `name` and `standardDimension` | Add only a repeatable reference object with a defensible standard dimension. |
| An item type is missing or maps to the wrong taxonomy row | `appConfig/cubeSheet.rows[]` using `key` and `category` | Add or correct the named row; do not use an unrelated row to absorb the item. |
| A known item's cube range is implausible | `appConfig/cubeSheet.rows[].low`, `.typical`, `.high` for the named key | Keep `low <= typical <= high`; cite the real item and Adam's judgment. |
| An unknown size class is implausible | `appConfig/cubeSheet.unknownSizeTypical.small`, `.medium`, `.large`, or `.oversized` | Change only the judged size class and rerun unknown items first. |
| A truck's physical capacity is wrong | `appConfig/trucks.capacities[].cubicFeet` for the named truck | Correct the capacity, then recompute all tier thresholds for that truck. |
| A load-quality assumption is wrong | `appConfig/trucks.tiers[].multiplier` for the named tier | Preserve the locked smallest-fitting-truck calculation. |
| A tier recommends the wrong cutoff after multiplier review | `appConfig/trucks.capacities[].fitsUpTo.tier1`, `.tier2`, or `.tier3` | Derive cutoffs consistently from capacity and multiplier; do not hand-tune an isolated example. |
| The comfortable-choice wording is unclear | `appConfig/trucks.comfortableChoiceLabel` | Keep it informative and optional. |
| Above-largest distance guidance is wrong | `appConfig/trucks.above26.distanceThresholdMiles`, `.driveTimeDescription`, `.underThresholdRecommendation`, or `.overThresholdRecommendation` | Preserve both choices and user control. |
| Above-largest choice labels or tradeoffs are unclear | `appConfig/trucks.above26.message` or `.options[].label` / `.options[].tradeoff` | Equip the decision; do not claim an external action. |
| A local-move labor assumption is wrong | `vendors/{vendorId}.rateCard.hourlyByCrew`, `.minimumHours`, or `.tripChargeModel` | Change the identified vendor card only and cite the matching crew and trip basis. |
| A materials, valuation, access, date, or specialty cost input is wrong | `vendors/{vendorId}.rateCard.materials`, `.valuationTiers`, `.surcharges`, `.blackoutDates`, or `.specialtyFees` | Change the narrowest field supported by the observation. |
| The packing session duration is not humane | `appConfig/packing.targetSessionMinutes` or `.minimumSessionMinutes` | Adjust from the observed session burden, then regenerate the entire plan. |
| Packing time per cube is wrong | `appConfig/packing.cubicFeetPerHour` or `.boxEquivalentCubicFeet` | Change one rate per hypothesis and compare the regenerated duration. |
| A room minimum is wrong | `appConfig/packing.minimumRoomMinutesByType.kitchen`, `.garage`, `.bedroom`, or `.bathroom` | Change only the room type Adam judged. |
| The plan starts too early or late | `appConfig/packing.moveDayBufferDays` or `.suppliesDeliveryBufferDays` | Preserve the move date and regenerate instead of editing generated tasks. |
| A behind-pace recovery is too light or too harsh | `appConfig/packing.behindPaceSessionsPerDay` | Judge sustainability across the regenerated remaining schedule. |
| Rooms or item groups are sequenced badly | `appConfig/packing.sequencingWeights.storageSeasonal`, `.decorBooks`, `.guestSpare`, `.garage`, `.secondaryBedroom`, `.kitchenNonEssentials`, `.primaryBedroom`, `.bathrooms`, or `.kitchenEssentials` | Change relative order deliberately and verify essentials remain available. |
| A retail unit rate is wrong | The matching field in `appConfig/supplyRates`: `smallBox`, `mediumBox`, `largeBox`, `xlBox`, `dishPack`, `wardrobe`, `pictureCarton`, `packingPaper10lb`, `bubbleRoll`, `tapeRoll`, `mattressBag`, `stretchWrap`, or `marker` | Correct the unit rate; do not hardcode or rewrite the displayed total. |

## Stop conditions: no data correction

These observations do not have a valid calibration field in the current schema:

- A true missed, ghost, duplicate, or quantity error that remains after an adequate walkthrough and cannot be explained by a missing taxonomy row or scale anchor.
- A gift entitlement that is active on the server but absent in the client after relaunch.
- An authenticated client permission failure while reading a required config document.
- A truck calculation that ignores configured multipliers or thresholds.
- A cost presentation or calculation defect that remains after cube and vendor rate-card inputs are correct.
- A supplies quantity defect that remains after item types and cubes are correct. Retail-rate fields change totals, not quantity formulas.
- A packing-plan defect that cannot be expressed by one of the named `appConfig/packing` fields.

For a stop condition, capture the screen, input, output, account state, config snapshot, and exact reproduction steps. Label it `BLOCKED — NO DATA FIELD`; do not alter code, prompts, product identifiers, or unrelated configuration during calibration.

## Correction loop

For each `DATA CORRECTION`:

1. Record document, exact field path, before value, proposed value, evidence, and expected effect.
2. Change one hypothesis at a time in Firestore.
3. Confirm the client can read the updated document.
4. Reset only the generated room result needed for the rerun; leave the physical room unchanged.
5. Repeat the same coached scan path and capture all six judgment sections again.
6. Keep the change only if it improves the intended observation without degrading another section.
7. Record the accepted final value and a seed-parity follow-up. Seeder or source changes belong in a separately authorized code phase.

## Thursday closeout

The session is complete when Adam has signed off each section as `PASS`, accepted a mapped data correction with a clean rerun, or recorded a stop condition with evidence. The closeout must list:

- Physical device and build identifier.
- Test account and entitlement expiration, without credentials.
- Room and move-context summary.
- Baseline config snapshot time.
- Missed, ghost, duplicate, quantity, and unknown counts.
- Per-item cube judgments and total-cube judgment.
- All three truck-tier judgments.
- Cost, packing-plan, and supplies judgments.
- Every accepted document/field change with before and after values.
- Every blocked defect that needs a separately scoped fix.
