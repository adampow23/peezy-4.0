# Phase C — One question per screen report

## Locked scrolling-form inventory

### Qualifies and must convert

| Surface | Existing fields/questions |
| --- | --- |
| Mover refinement | origin/destination bedrooms; storage inclusion, size, fullness, moving-day stop, optional address; origin/destination access and long carry; packing status; protection; arrival window |
| Moving-day check-in | four yes/no facts; optional note; optional final bill for booked moves |
| Box return | returned count; ran-out question; pickup preference |
| Packing-supplies Customize sheet | nine quantity steppers |
| Inventory review Add Item sheet | item name; tier; category; size |

### Inventoried and excluded

| Surface | Reason |
| --- | --- |
| Movers booking review | Review/confirmation with one optional notes input, not multi-field. |
| Movers comparison, ISP comparison, quote selection | Vertically scrolling comparison/selection lists; seeing options together is the task. |
| Packing readiness | A checklist whose items must be reviewed together, not a questionnaire/form. |
| Packing-supplies offer, inventory room hub/review, inventory locked, task list | Scrollable content/list/review surfaces, not multi-field forms. |
| Business search and confirm-address components | Keyboard accommodation around one logical search/address input. |
| Paywall and support chat | Not task-flow questionnaires; purchase/chat content. |

## Acceptance evidence

- **C1.1 — PASS.** `MoveRefinementView` now owns a conditional question sequence and renders only `currentQuestion`. All original fields remain, storage questions still branch on storage/stop choices, inventory-backed moves still skip bedroom fallbacks, and the last arrival-window screen retains `model.canCompare` as the comparison gate.
- **C1.2 — PASS.** Moving-day check-in, box return, packing-kit customization, and inventory Add Item each render one answer control per screen. Their prior `ScrollView`/`Form` wrappers are gone. Nested Customize/Add Item sheets retain Cancel plus Back-to-prior-question behavior; dismissal returns to the parent sheet owner.
- **C1.3 — PASS.** A fresh `ScrollView|Form` inventory leaves only the explicitly excluded list/review/comparison/checklist/single-input surfaces. Within the five qualifying files, the only remaining ScrollViews are the packing-kit offer content and the inventory item review list; neither contains the converted multi-field form. No `Form` remains in a qualifying surface.
- **C1.4 — PASS.** Converted controls still bind to the original `MoversFlowViewModel` and flow-local answer state. Movers, check-in, box-return, and kit answers continue through their existing `FlowProgressSnapshot`/`resumableFlowProgress` paths. The inventory Add Item surface commits to its existing review model only on Add; no presentation ownership changed.

Validation:

- `swiftc -frontend -parse` across all five edited Swift files — PASS.
- iPhone 17 Pro / iOS 26.5 Debug build — `** BUILD SUCCEEDED **`; log at `/tmp/peezy-phase-c-build.log`.
- Fresh targeted source inventory — PASS: zero qualifying `Form`/multi-field `ScrollView` paths remain.

Implementation note: these five surfaces are bespoke service/model flows rather than `FlowDefinition`-backed catalog questionnaires (the mover flow explicitly keeps capture/comparison outside `FlowDefinition`). They retain the existing `TaskFlowStack`/assessment-style step progression instead of introducing a second persistence or routing system.
