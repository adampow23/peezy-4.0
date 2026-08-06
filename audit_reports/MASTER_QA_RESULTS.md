# Master QA Results

Execution date: August 4, 2026  
Simulator: iPhone 17 Pro Max, iOS 26.4.1  
Accounts: two newly created synthetic email/password accounts (`GiftQA` and `PurchaseQA`)  
Source policy: read-only; no source file was edited and no fix was attempted.

## Checkpoint results

| Checkpoint | Result | Evidence | Checklist failure route for non-pass |
|---|---|---|---|
| P1 | FAIL | Anthropic Billing showed **$19.83** credit, but **Auto reload off**. It was not changed during this read-only QA session. | No explicit failure route; checklist states that A7–A9 depend on this prerequisite. |
| P2 | BLOCKED | `firebase functions:list` showed the required callable functions active, including `researchTask`, `peezyChat`, and `redeemGiftCode`. The checklist's mutating `firebase deploy --only firestore:rules,functions` command was not rerun, so this checkpoint was not executed exactly. | No failure route specified in the checklist. |
| P3 | BLOCKED | `appConfig/cubeSheet` existed and was usable, but the mutating `functions/seedCubeSheet.js` seeder was not rerun, so this checkpoint was not executed exactly. | No failure route specified in the checklist. |
| P4 | PASS | `appConfig/supplyRates` and `appConfig/packing` existed. An unredeemed six-month test code was found in `giftCodes` and reserved for A4. | — |
| P5 | FAIL | The scheme still pointed to `Configuration.storekit`. Deleting Peezy from the first simulator did not clear Keychain/StoreKit state; the run had to move to a pristine iPhone 17 Pro Max simulator for a clean install. | No failure route specified in the checklist. Direct prerequisite for A1/A3. |
| A1 | FAIL | Fresh account assessment completed and created 17 tasks, but the app did **not** land directly on the task list. It showed “Your task list is ready,” a personalized-plan loading step, a three-card welcome flow, then Home. No paywall interrupted assessment. | `Day 2 Phase 6 gate files.` |
| A2 | PASS | Task-list rows showed only task title and timing (for example, “Transfer your utilities” / timing); no description subtitles appeared. | — |
| A3 | PASS | A gated task showed the value screen, then a StoreKit price screen with **$49.99**, “Founding price — locked for early users,” “One-time payment · 6 months of access,” and no strikethrough. | — |
| A4 | PASS | Redeeming the previously unredeemed test code succeeded, dismissed the paywall, and opened the gated task. | — |
| A5 | PASS | After Xcode Stop and relaunch, gated content opened without the paywall; Settings showed access through **Feb 4, 2027**. | — |
| A6 | BLOCKED | After gift access was active, every gated entry bypassed the paywall and the app exposed no other redeem-code UI. The same code therefore could not be submitted a second time to observe “This code was already used.” | `redeemGiftCode transaction.` |
| A7 | PASS | Utilities/web: generating state appeared, the typewriter brief rendered, and all five source buttons opened real pages on `evergy.com`, `kansasgasservice.com`, `opkansas.gov`, `getvibrato.com`, and `outandinmoving.com`. Movers/prefs: all three preference questions appeared before generation; the brief contained questions-to-ask, red flags, and what-could-go-wrong (it briefly showed an error, then auto-recovered to the completed brief). Packing/reasoning: the packing-category “Defrost your freezer” brief rendered with no Sources section. Reopening Utilities rendered the cached brief in about 1.2 seconds with no generating state. Full Utilities text is recorded verbatim below. | — |
| A8 | PASS | Utilities task chat answered “What should I do first for my utility transfer?” using the user's two addresses and Aug 19/Aug 21 dates; the disclaimer was visible and the reply contained no URL. | — |
| A9 | PASS | Support chat answered that the Move Pass is a one-time payment, supplies six months of access, and does not renew; it directed the user to the in-app Move Pass screen for the current price, showed the disclaimer, and included no URL. | — |
| A10 | PASS | Synthetic inventory fixture produced a ~628 cu ft move. All three tiers rendered a recommendation and “comfortable choice”: Packed tight = 15′/20′; Pretty good = 20′/26′; Just get it in = 20′/26′. Recommendations shifted sensibly. | — |
| A11 | PASS | Supplies rendered quantities and a **$446.50** total: 16 small, 15 medium, 8 large, 3 wardrobe, 1 dish pack, 4 tape, 4 paper, 10 wrap, and 2 mattress bags. Exact disclaimer: “Estimated at typical retail — prices vary.” | — |
| A12 | FAIL | Packing sessions generated and rendered, but not in chronological sequence: the list showed Bedroom parts for Aug 10–14, then **First-night bag Aug 19**, then Kitchen essentials parts for **Aug 15–16**. | `PackingPlanEngine / appConfig/packing.` |
| A13 | PASS | Box Return used a 43-box kit fixture, recorded 1 returned/recycled box, and ended with local reuse/donation plus flattening/recycling guidance. It made no pickup promise. | — |
| B1 | FAIL | In the exact ordered run, the newly created PurchaseQA account inherited the gift account's active Move Pass in memory and opened gated content without showing a purchase sheet. A diagnostic relaunch cleared that state; a retry then showed the localized **$49.99** one-time/six-month language, the Xcode test purchase confirmed successfully, and the utilities task unlocked. The initial required path still failed. | No failure route specified in the checklist. |
| B2 | PASS | After the successful StoreKit diagnostic purchase, Xcode Stop/relaunch preserved access; the account returned signed in with an active Move Pass. | — |
| B3 | PASS | Post-purchase, post-relaunch Settings showed “Peezy Move Pass” and “Access through Feb 4, 2027”; Restore purchases was present and Manage Subscription was absent. | — |

## A7 — full generated Utilities brief (verbatim)

The wording and punctuation below are reproduced verbatim from the generated brief. The app did not render empty Questions-to-ask or Red-flags sections for this brief.

```text
You're crossing a state line in 16 days — Evergy covers both sides, but gas and water are brand-new accounts in Kansas, so start all three calls this week before August 20 slots fill up.

Your Utility Map: KC → Overland Park

Electric — Evergy serves both 100 Main St, KC MO and 8200 W 71st St, Overland Park KS. This is the one utility where you're not starting from scratch. Call Evergy at 888-471-5275 (Kansas Metro / Missouri Metro line) and ask to stop service at the KC address the day after your move (August 21) and start service at the Overland Park address the day before (August 19). One call, one account.

Gas — Kansas Gas Service is your new provider at 8200 W 71st St. They're a separate company from anything you used in KC MO. Call 800-794-4780 (Mon–Fri, 7 AM–7 PM CST) to open a new account and schedule activation for August 19. This is a brand-new account, so have your SSN and new address ready — they may run a credit check or require a deposit.

Water/Sewer — Overland Park's residential water is handled through the city. The official utility info page is at . Call or visit that page to confirm which provider serves 8200 W 71st St specifically and schedule activation for August 19. Trash in Overland Park is handled by private companies — your landlord should tell you which one serves that address.

Internet — You're moving from an apartment to a house, so your current ISP contract may not transfer. Check whether your provider serves 66204 before move day; if not, order new service now since installs can take 1–2 weeks.

Your 16-Day Action Sequence

TODAY (Aug 4): Call Evergy at 888-471-5275. Schedule Overland Park start for Aug 19, KC shutoff for Aug 21. Confirm account number stays the same — no deposit, no credit check for an existing customer transferring service.

TODAY (Aug 4): Call Kansas Gas Service at 800-794-4780. Open new account for 8200 W 71st St, activation date Aug 19. Ask upfront if a deposit is required and what the amount is.

By Aug 6: Confirm water/sewer setup at for 8200 W 71st St. Schedule activation Aug 19. Ask your landlord about trash pickup — private haulers like WM, Republic Services, and KC Disposal all operate in Overland Park.

By Aug 7: Contact your internet provider. If they don't serve 66204, order a new provider immediately — installs in a new house can take 1–2 weeks to schedule.

Aug 19 (day before move): Confirm all services are live at 8200 W 71st St. Do not assume — call or check online accounts.

Aug 21 (day after move): Verify KC utilities are off and you have final bill amounts. Take meter photos at 100 Main St on move day as proof of your last reading.

The Interstate Wrinkle

Even though this is only 9 miles, it's MO → KS, which makes it legally interstate. Gas and water are entirely new accounts with new providers — not transfers. Budget time for identity verification and possible deposits on those two.

Evergy is the exception: they operate across both states, so your existing account history works in your favor. No new deposit, no credit check, no setup fee when you transfer within Evergy's service territory.

August is peak moving season. Utility activation slots — especially for gas, which may require an in-person technician visit — can book out. Call today, not next week.

Sources

Evergy: Contact Us - Evergy
https://www.evergy.com/contact-us

Kansas Gas Service: Kansas Gas Service - Natural Gas Distribution
https://www.kansasgasservice.com/

City of Overland Park: Utilities and WiFi | Overland Park, KS - Official Website
https://www.opkansas.gov/utilities-and-wifi

Vibrato: Overland Park, Kansas Utility Services & New Resident Guide
https://www.getvibrato.com/c/city-guides/overland-park-kansas

Out & In Moving LLC: Things to Know Before Moving to Overland Park, KS
https://outandinmoving.com/blog/things-to-know-before-moving-to-overland-park-ks/

What could go wrong

Gas activation requires a technician visit at 8200 W 71st St — if no adult is home during the appointment window, they leave a tag and reschedule, which could mean no heat or hot water for days after move-in. Book the appointment now and plan to be at the new house on Aug 19.

If you assume your KC internet provider covers 66204 without checking, you could arrive at the new house with no internet and a 1–2 week wait for an install appointment. Verify coverage and order service this week.

Your move date is flagged as flexible/pending. If you shift the date, every utility activation date shifts too — you'll need to call all three providers again to reschedule. Lock the date as soon as possible to avoid a cascade of rescheduling calls.

Not photographing the meter at 100 Main St on move day leaves you exposed if your KC landlord disputes your final bill. A timestamped photo takes 10 seconds and is your only proof of the reading you left behind.
```

## Session notes

- The synthetic inventory fixture covered Bedroom, Kitchen, Living Room, Office, and Garage and was submitted through the UI; it produced 13 unique item types / 159 units and the app normalized the move to approximately 628 cu ft.
- The A4 gift code changed from unredeemed to redeemed as part of the required test. Account, research, chat, inventory, and StoreKit test-purchase data are synthetic QA data.
- Xcode created an untracked `build/` artifact during simulator execution. It is generated output, not source, and was left untouched.
