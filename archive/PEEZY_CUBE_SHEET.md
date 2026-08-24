# Peezy Cube Sheet + Truck Table — DRAFT FOR ADAM'S REDLINE

Built from consensus across published industry cube sheets (the standard mover
Table of Measurements lineage — the same base table virtually every van line and
inventory system descends from, cross-checked against multiple current published
catalogs). Values are RANGES, not points: the deterministic sheet owns the
bounds, the model places each item within its range using visual anchors. The
server rejects any model cube outside the sheet's bounds.

**Redline instructions:** correct any range that fights your nine years. Add
rows the scanner will meet that are missing. Delete rows that never occur.
The "typical" column is the fallback when the model has no anchor confidence.

---

## Part 1 — Anchor Reference Objects (known standard dimensions)

The model's first pass identifies these before sizing anything. They are
manufactured to standard dimensions and appear in nearly every scan:

| Anchor | Standard dimension |
|---|---|
| Interior door | 80" tall (6'8"), 30-32" wide |
| Electrical outlet / switch plate | 4.5" tall, mounted ~12-48" from floor |
| Kitchen countertop | 36" from floor, 25" deep |
| Refrigerator (standard) | 36" wide, ~70" tall |
| Dishwasher / washer / dryer | 24-27" wide (built to fit standard openings) |
| Queen mattress | 60" x 80" |
| King mattress | 76" x 80" |
| Twin mattress | 38" x 75" |
| Ceiling height (most rooms) | 96" (8') |
| Standard bath tub | 60" long |
| Toilet | ~28-30" tall at tank |

---

## Part 2 — Cube Sheet (cubic feet, [low – typical – high])

### Living Room
| Item | Low | Typical | High |
|---|---|---|---|
| Sofa, 4-seat | 55 | 65 | 75 |
| Sofa, 3-seat | 40 | 50 | 60 |
| Loveseat | 28 | 35 | 42 |
| Sleeper sofa | 50 | 60 | 75 |
| Sectional, 4-piece | 120 | 150 | 175 |
| Sectional, 5-piece | 155 | 185 | 215 |
| Futon | 40 | 50 | 65 |
| Recliner | 15 | 25 | 35 |
| Armchair / club chair | 10 | 15 | 20 |
| Overstuffed chair | 20 | 25 | 30 |
| Rocker / glider | 15 | 20 | 30 |
| Chaise lounge | 35 | 45 | 55 |
| Ottoman | 4 | 6 | 10 |
| Coffee table | 15 | 22 | 28 |
| End / side table | 4 | 5 | 8 |
| Console / sofa table | 12 | 18 | 25 |
| TV, 55-65" | 12 | 15 | 18 |
| TV, under 50" | 5 | 10 | 13 |
| TV, over 65" | 15 | 20 | 30 |
| TV stand | 8 | 10 | 15 |
| Entertainment center | 20 | 40 | 60 |
| Wall unit (per piece) | 30 | 40 | 55 |
| Bookcase / bookshelf | 10 | 20 | 35 |
| Shelving unit | 10 | 25 | 50 |
| Curio / display cabinet | 15 | 22 | 30 |
| Floor lamp | 8 | 10 | 12 |
| Table lamp | 3 | 5 | 8 |
| Area rug, large (8x10+) | 12 | 18 | 22 |
| Area rug, small | 4 | 6 | 10 |
| Mirror / large picture | 5 | 7 | 12 |
| Grandfather clock | 18 | 22 | 28 |
| Piano, upright | 50 | 60 | 70 |
| Piano, baby grand | 60 | 70 | 80 |
| Piano, grand | 75 | 85 | 100 |
| Large plant | 5 | 10 | 15 |

### Bedroom
| Item | Low | Typical | High |
|---|---|---|---|
| Bed, king (frame + mattress) | 105 | 125 | 140 |
| Bed, queen (frame + mattress) | 80 | 95 | 110 |
| Bed, full (frame + mattress) | 65 | 80 | 90 |
| Bed, twin (frame + mattress) | 50 | 60 | 70 |
| Bed, bunk | 55 | 70 | 85 |
| Bed, toddler / crib | 15 | 20 | 45 |
| Mattress only, king | 35 | 40 | 45 |
| Mattress only, queen/full | 25 | 30 | 35 |
| Mattress only, twin | 15 | 20 | 25 |
| Headboard | 10 | 18 | 25 |
| Dresser, triple | 45 | 50 | 60 |
| Dresser, double | 32 | 40 | 48 |
| Dresser, single / chest | 20 | 25 | 32 |
| Chest of drawers, small | 12 | 18 | 25 |
| Armoire / wardrobe | 30 | 50 | 65 |
| Nightstand | 4 | 5 | 8 |
| Vanity table | 15 | 20 | 28 |
| Cedar / storage chest | 10 | 15 | 20 |
| Toy chest | 8 | 10 | 15 |
| Changing table | 18 | 22 | 28 |
| Full-length standing mirror | 15 | 22 | 28 |

### Dining Room / Kitchen
| Item | Low | Typical | High |
|---|---|---|---|
| Dining table | 28 | 35 | 48 |
| Kitchen table | 15 | 20 | 25 |
| Bistro / pub table | 10 | 20 | 26 |
| Dining/kitchen chair (each) | 4 | 5 | 7 |
| Bar stool (each) | 5 | 7 | 9 |
| China cabinet / hutch | 40 | 50 | 60 |
| Buffet / sideboard | 35 | 45 | 58 |
| Credenza | 30 | 40 | 50 |
| Baker's rack | 18 | 25 | 30 |
| Kitchen island, freestanding | 30 | 45 | 55 |
| Wine rack | 8 | 15 | 25 |
| Microwave | 4 | 7 | 10 |
| Microwave cart | 8 | 10 | 14 |
| High chair | 7 | 10 | 12 |

### Appliances
| Item | Low | Typical | High |
|---|---|---|---|
| Refrigerator, side-by-side / French door | 50 | 60 | 70 |
| Refrigerator, standard top-freezer | 32 | 40 | 48 |
| Refrigerator, mini | 6 | 10 | 14 |
| Freezer, chest | 25 | 35 | 45 |
| Freezer, upright | 35 | 45 | 60 |
| Range / stove | 20 | 25 | 30 |
| Washer | 22 | 25 | 28 |
| Dryer | 22 | 25 | 28 |
| Washer/dryer stacked combo | 42 | 50 | 55 |
| Dishwasher (portable) | 16 | 20 | 24 |
| Window A/C unit | 4 | 7 | 12 |

### Office
| Item | Low | Typical | High |
|---|---|---|---|
| Desk, standard | 18 | 22 | 30 |
| Desk, executive / L-shaped | 40 | 48 | 58 |
| Desk, computer / small | 12 | 15 | 20 |
| Office chair | 6 | 9 | 13 |
| File cabinet, 2-drawer | 8 | 10 | 15 |
| File cabinet, 4-5 drawer | 18 | 25 | 50 |
| Bookcase, tall (7-8 ft) | 25 | 30 | 38 |
| Computer / monitor setup | 8 | 12 | 18 |
| Printer, home | 3 | 5 | 8 |
| Safe, small | 10 | 15 | 22 |
| Safe, large / gun safe | 30 | 45 | 60 |

### Exercise / Garage / Outdoor
| Item | Low | Typical | High |
|---|---|---|---|
| Treadmill | 40 | 45 | 60 |
| Elliptical | 25 | 40 | 50 |
| Exercise bike | 12 | 15 | 20 |
| Weight bench + weights | 15 | 25 | 40 |
| Bicycle, adult | 8 | 10 | 13 |
| Bicycle, child | 4 | 5 | 7 |
| Kayak / canoe | 40 | 50 | 60 |
| Workbench | 15 | 22 | 30 |
| Tool chest, mechanic | 25 | 32 | 50 |
| Toolbox, hand-carry | 3 | 5 | 8 |
| Lawnmower, push | 20 | 28 | 35 |
| Lawnmower, riding | 85 | 100 | 120 |
| Snow blower / leaf blower | 10 | 15 | 20 |
| Ladder | 5 | 12 | 45 |
| Grill, small | 12 | 17 | 25 |
| Grill, large / 4-burner | 35 | 45 | 58 |
| Patio table | 18 | 25 | 32 |
| Patio chair (each) | 5 | 8 | 12 |
| Patio set, 5-piece | 55 | 70 | 85 |
| Outdoor chaise / swing | 40 | 55 | 65 |
| Fire pit | 18 | 25 | 32 |
| Trampoline | 20 | 25 | 35 |
| Garbage can, large | 10 | 15 | 20 |
| Storage tote / bin (each) | 3 | 5 | 8 |
| Pool table | 280 | 350 | 400 |
| Air hockey / foosball table | 40 | 50 | 60 |

### Boxes (standard — used by packing plan + supplies kit, same sheet)
| Item | Cube (fixed) |
|---|---|
| Small box (1.5 cf) | 1.5 |
| Medium box (3.0 cf) | 3 |
| Large box (4.5 cf) | 4.5 |
| Extra-large box (6.0 cf) | 6 |
| Dish pack / china box | 6 |
| Wardrobe box | 13 |
| Picture/mirror carton | 3 |

### Specialty (flat-fee items in the pricing engine — cube still counts)
| Item | Low | Typical | High |
|---|---|---|---|
| Piano (any) | see Living Room | — | — |
| Gun safe / large safe | 30 | 45 | 60 |
| Pool table | 280 | 350 | 400 |
| Aquarium + stand | 10 | 25 | 65 |
| Hot tub (rare, flag for review) | 300 | 375 | 450 |

---

## Part 3 — Truck Table (three load-quality tiers)

Rated usable capacities (consumer rental standard): pickup ~75 cf, cargo van
~245 cf, 10' ~400 cf, 15' ~760 cf, 20' ~1,015 cf, 26' ~1,680 cf.

The user self-selects their tier from three photos of a loaded truck:

- **Tier 1 — "Packed tight"** (+15%): floor-to-ceiling, tiered like a pro load
- **Tier 2 — "Pretty good"** (+30%): solid load to about three-quarter height
- **Tier 3 — "Just get it in"** (+45%): flat-loaded to roughly head height

Recommendation = smallest truck whose tier threshold covers the scan cube.

| Truck | Tier 1 fits up to | Tier 2 fits up to | Tier 3 fits up to |
|---|---|---|---|
| Pickup | 65 cf | 55 cf | 50 cf |
| Cargo van | 210 cf | 185 cf | 170 cf |
| 10' truck | 345 cf | 305 cf | 275 cf |
| 15' truck | 660 cf | 585 cf | 520 cf |
| 20' truck | 880 cf | 780 cf | 700 cf |
| 26' truck | 1,460 cf | 1,290 cf | 1,155 cf |
| Above 26' threshold | LOCKED: educate + both options with a recommendation. "This won't fit in one 26' truck." Present second trip vs. second truck, with Peezy's recommendation driven by drive time between addresses: under ~2 hours → second trip; over → second truck. User chooses; the app explains the tradeoff (time and fuel vs. rental cost) either way. |

**Open for redline:** the tier percentages (15/30/45) are yours from the voice
note; the thresholds are pure math from them. Correct the truck capacities if
your field numbers differ from rental-rated figures, and decide whether the
recommendation should also display the next size up as "the comfortable choice"
(one line of copy, big regret-insurance value).

---

## Part 4 — How the pipeline consumes this sheet

1. Model pass 1: identify anchor objects (Part 1) in the frames.
2. Model pass 2: identify every item ONCE across all frames (cross-frame
   tracking), assign item type from this sheet's rows, size it relative to
   anchors, and output a cube WITHIN the row's [low, high] range plus a
   confidence score.
3. Server validation: any cube outside its row's range is clamped to the range
   and flagged; unknown item types fall back to the nearest category row and
   are surfaced uncertain-first in review.
4. This sheet lives in Firestore config — every number editable forever without
   an App Store release. Adam's redlines land as config writes.
