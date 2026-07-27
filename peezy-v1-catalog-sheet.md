# Peezy v1 Catalog Sheet — for Adam's row-by-row review
Source: taskCatalogData.json (45 live catalog rows in the locally validated source). This sheet preserves the original review verdicts, with later implementation state called out explicitly.

Execution models: **SPINE** (vendor workflow: capture→compare→book) · **RESOLVER** (universal provider flow — user names company, LLM resolves the path, confidence-tiered, concierge floor) · **DRAFT** (Peezy pre-writes the letter/email/form; tap = approve/send) · **LINK** (deep-link + identity prefill) · **PHYSICAL** (honest off-app work; completion moves the readiness picture) · **CONCIERGE** (n8n human execution)

⚠ = broken in production today (condition key never populated — task never generates)

## 1. Transactional spine (revenue)

| Task | Verdict | Model | v1 depth | Notes |
|---|---|---|---|---|
| SCAN_INVENTORY (99) | CORE | in-app | Full | The root. Unchanged |
| BOOK_MOVERS (94) | CORE | SPINE | Full | Vertical #1. Pricing engine + rate cards |
| SETUP_INTERNET (81) | CORE | SPINE-lite | Full | Five Firestore-backed KC-area plan cards; pending affiliate links fall back to official provider URLs. Address-level serviceability remains v1.1 |
| RENT_TRUCK (91) | KEEP | LINK | Thin | U-Haul deep link + prefill; affiliate API v1.1 |
| BOOK_CLEANERS (25) | KEEP | SPINE | Full when vendors sign | **Urgency 25 is wrong** — cleaning happens late but *booking* needs lead time. Reweight to ~55 |
| REMOVE_ITEMS (70) ⚠ | KEEP | SPINE | Full when vendors sign | Dead: wantToSell always empty. Fix key + recondition to hasDeclutter=Yes (donation/junk path regardless of sell intent) |
| SELL_ITEMS (75) ⚠ | KEEP, low | LINK | Thin | Dead: same key. Recondition; marketplace deep-links |
| BUY_PACKING_SUPPLIES (85) | TRANSFORM | → Kit offer | Full | Becomes one-tap kit order at packing-plan creation. Revenue |
| **ADD: STORAGE_UNIT** | NEW | SPINE | Thin (concierge floor) | Storage-as-vertical (user NEEDS a unit). Note: existing hasStorage/size/fullness keys are ESTIMATE INPUTS (extra cube for mover pricing, Spec 05) — not this task's trigger. Vertical gets its own signal via a dose card in Spec 04/05 |

## 2. Deadline + identity (the trust engine)

| Task | Verdict | Model | v1 depth | Notes |
|---|---|---|---|---|
| FORWARD_MAIL_USPS (79) | CORE | LINK | Full | USPS flow, identity-prefilled. DRAFT-mode v1.1 |
| SETUP/CANCEL/TRANSFER_UTILITIES (80/75/72) | CORE ×3 | RESOLVER | Full | Conditions already route the right one. Resolver handles any local utility co |
| Insurance ×9 (77–76) | KEEP all | RESOLVER | Full | Conditions ARE the merge — each user sees exactly their 1–2. No task changes |
| UPDATE_AUTO_INSURANCE (82) ⚠ | KEEP | RESOLVER | Full | Dead: hasVehicles bug. Fix key |
| REGISTER_VEHICLE (82) ⚠ | MERGE→DMV | see below | — | Dead: same bug |
| UPDATE_DRIVERS_LICENSE (84) + NEW_DRIVERS_LICENSE (84) + REGISTER_VEHICLE | **MERGE 3→2**: HANDLE_DMV_LOCAL / HANDLE_DMV_INTERSTATE | DRAFT-adjacent (county office, hours, doc checklist, appt link prefilled) | Full | One DMV trip, everything for it. Interstate version includes registration rows when hasVehicles |
| SCHEDULE_TIME_OFF_WORK (92) | KEEP | DRAFT | Full | PTO request email pre-written |
| UPDATE_EMPLOYER_RECORDS (68) | KEEP | DRAFT | Full | HR email pre-written (W-2 protection) |
| TRANSFER_PHARMACY_RECORDS (55) | CORE | RESOLVER | Full | **Reweight to ~75** — medication gap is the highest-pain miss in the catalog. Also drop the Long-Distance-only gate? Local pharmacy changes are rarer but real — Adam's call |
| ARRANGE_PARKING_OLD/NEW (73/72) + RESERVE_ELEVATORS_OLD/NEW (71/70) | **MERGE 4→2**: RESERVE_ACCESS_OLD / RESERVE_ACCESS_NEW | RESOLVER (building mgmt) or CONCIERGE | Full | One card per address: parking + elevator rows appear per conditions. Feeds readiness gate |
| PHOTOGRAPH_RENTAL_CONDITION (4) + RETURN_KEY_FOBS_REMOTES (1) | **MERGE 2→1**: PROTECT_DEPOSIT | PHYSICAL + photo capture | Full | Photos, keys, condition record — one deposit-protection flow at move-out. Urgencies stay last (timing is correct) |

## 3. People clusters (conditional)

| Task | Verdict | Model | v1 depth | Notes |
|---|---|---|---|---|
| BEGIN_SCHOOL_TRANSFER (82) + NEW_SCHOOL_ENROLLMENT (90) | **MERGE 2→1**: SCHOOL_TRANSFER (LD) | DRAFT | Full | Records-request letter pre-written + enrollment checklist. One parental job, one card |
| COA_SCHOOLS (90) | KEEP | DRAFT | Full | Local variant, address-update letter |
| SETUP_DAYCARE (88) / TRANSFER_DAYCARE (75) | KEEP both | RESOLVER | Full | Conditions already split LD/local |
| MANAGE_DOCTOR (68) + MANAGE_DENTIST (59) + TRANSFER_SPECIALISTS_RECORDS (69) | **MERGE 3→1**: MEDICAL_RECORDS | RESOLVER | Full | Rows per healthcareProviders selection. Pharmacy stays separate (urgency class) |
| MANAGE_VET (63) | KEEP | RESOLVER | Full | Records transfer, concierge-friendly |
| MANAGE_BANK (84) + UPDATE_CREDIT_CARD (62) + UPDATE_INVESTMENT (61) + UPDATE_STUDENT_LOANS (60) | **MERGE 4→1**: FINANCIAL_ACCOUNTS | RESOLVER | Full | Rows from multi-select (count fix honors the "each tap = a task" promise as rows). Urgency = 84 (bank timing governs) |
| MANAGE_GYM (86) + MANAGE_YOGA (87) + MANAGE_GOLF (85) + MANAGE_SPIN (82) + MANAGE_MASSAGE (82) | **MERGE 5→1**: MEMBERSHIPS | RESOLVER (concierge floor — gym cancellation is the showcase) | Full | Rows per fitnessWellness selection. High urgency is CORRECT (30-day cancellation notices) — keep ~86 |

## 4. Physical / advice tier

| Task | Verdict | Model | v1 depth | Notes |
|---|---|---|---|---|
| DEFROST_FREEZER (8) | KEEP | PHYSICAL | Full | The model advice card. Low urgency = late surfacing = correct T-2 timing |
| DIY_DEEP_CLEANING (5) + BUY_CLEANING_SUPPLIES (10) | **MERGE 2→1**: DIY_DEEP_CLEANING | PHYSICAL | Full | Supply list folds into the cleaning card as a section |
| DIY_FINAL_CLEANING (2) | KEEP | PHYSICAL | Full | Different moment than deep clean; stays separate |
| **ADD: PACKING SESSIONS** | NEW | engine-generated | Full | Not catalog rows — the packing plan emits them from inventory |
| **ADD: READINESS_GATE** | NEW | PHYSICAL checklist | Full | T-1 gate; evidence layer for vendor accountability |
| **ADD: BOX_RETURN** | NEW | scheduled pickup | Thin | Post-move; calibration loop |

## 5. Escape-hatch adds (from assessment fixes)

| Task | Model | Notes |
|---|---|---|
| **ADD: ADD_NEW_ADDRESS** | in-app | Generated when newAddressPending; unblocks downstream on completion |
| **ADD: CONFIRM_MOVE_DATE** | in-app | Generated when date marked flexible |

## Urgency system — verified intent, two flags
The urgency scale doubles as reverse chronology (high = do early, low = do near move day) — RETURN_KEYS at 1 and DEFROST at 8 prove it's deliberate and correct. Only two reweights: BOOK_CLEANERS 25→~55, TRANSFER_PHARMACY 55→~75.

## Net result
Original Spec 02 projection: 56 tasks → **~40 catalog rows** after consolidation. Current implementation: **45 live catalog rows** after Spec 06; engine-generated packing work remains catalog-external. RESOLVER now covers provider rows with a cited self-service path or concierge floor.

## Spec 02 consequences (locked once you sign off)
1. Persistence fixes now include hasVehicles + wantToSell/hasDeclutter + hasStorage (4 dead tasks + 1 missing vertical hang on them)
2. Merges implemented as catalog config (new taskIds, row-generation from multi-selects) — no App Store cycle
3. Two urgency reweights
4. RESOLVER engine is the biggest new build in the non-service layer — one flow definition, provider resolved per company, confidence-tiered, concierge floor
