# Master QA — One Simulator Pass (Tonight)

One clean run, two accounts, ~30 minutes. Every step lists PASS criteria and
where a failure routes, so any red becomes a scoped fix prompt, not
archaeology. Walk it in order — state builds on itself.

## Prerequisites (no simulator — do these first, in order)
- [ ] P1. Anthropic credit topped up + auto-reload ON (console.anthropic.com →
  Billing). Nothing in steps A7-A9 works without this.
- [ ] P2. `firebase deploy --only firestore:rules,functions`
- [ ] P3. `cd functions && node seedCubeSheet.js && cd ..`
- [ ] P4. Console: `appConfig/supplyRates` and `appConfig/packing` exist;
  `giftCodes` has ≥1 unredeemed test code (note it down).
- [ ] P5. Simulator: delete the Peezy app. Scheme still points at
  Configuration.storekit.

## Pass A — Gift account (the long walk)
- [ ] A1. Fresh install → create NEW account → assessment runs → completes →
  lands directly on the task list, no paywall interruption.
  (Fail → Day 2 Phase 6 gate files.)
- [ ] A2. List rows show title + timing only — no description subtitles.
  (Fail → TaskRowHeader / mapper.)
- [ ] A3. Tap any task → value screen → price screen: live price from
  StoreKit (not "—"), founding-price line, no strikethrough, one-time
  disclosure. (Fail → PaywallValueView / PaywallGateView.)
- [ ] A4. Redeem the unredeemed code → success → paywall dismisses → the
  task opens. (Fail → GiftCodeRedeemSheet / redeemGiftCode.)
- [ ] A5. KILL the app. Relaunch. Gated content still open. ← the ISO-date
  fix proving itself. (Fail → SubscriptionManager gift decoding.)
- [ ] A6. Redeem the SAME code again → clean "This code was already used."
  (Fail → redeemGiftCode transaction.)
- [ ] A7. RESEARCH, three modes:
  - Utilities task (web): generating state → brief renders with typewriter →
    every source link opens a real page → **copy the full brief text out for
    Claude**. (Fail → researchTask / prompt.)
  - Movers task (prefs): preference questions appear BEFORE generation →
    brief includes questions-to-ask + red flags + what-could-go-wrong.
  - Packing task (reasoning): brief renders with no sources section.
  - Reopen the utilities task → brief appears instantly (cache, no
    regeneration).
- [ ] A8. Task chat (utilities): send one message → answer references the
  brief/their situation → disclaimer visible → zero URLs in the reply.
  (Fail → peezyChat task surface.)
- [ ] A9. Support chat: ask "what does the Move Pass cost and does it
  renew?" → correct one-time/6-month answer, no URL, disclaimer visible.
  (Fail → peezyChat support prompt.)
- [ ] A10. Truck view (fixture/test cube): three tiers render with a
  recommended truck each + "comfortable choice"; recommendations shift
  sensibly across tiers. (Fail → TruckSizeView / appConfig/trucks read.)
- [ ] A11. Supplies kit: quantities render + dollar total + "Estimated at
  typical retail — prices vary." (Fail → KitEstimator / supplyRates.)
- [ ] A12. Packing plan: generates and renders sessions in sequence.
  (Fail → PackingPlanEngine / appConfig/packing.)
- [ ] A13. Box Return (prerequisite data now exists): ending is
  donation/recycling guidance, no pickup promise. (Carried from Day 2.)

## Pass B — Purchase account (the short walk)
- [ ] B1. Sign out → NEW account → assessment → tap task → purchase sheet:
  localized price + one-time charge language → confirm → content unlocks.
- [ ] B2. Kill + relaunch → access persists (Transaction.latest path).
- [ ] B3. Settings: "Peezy Move Pass · Access through {~6 months out}", no
  Manage Subscription row, Restore Purchases present.

## Exit rule
Every box green → Day 4 closed; simulator retired until after submission.
Any red → one scoped fix session for that step's route, then re-run ONLY the
failed step and its direct dependents — never the whole pass.

## The two runs that remain after tonight
- Thursday: THURSDAY_CALIBRATION.md on a physical iPhone — judgment, not
  software. Corrections are Firestore edits.
- Friday: sandbox spot-check on device (real Apple servers: one purchase,
  one restore) + submission checklist. That's the last time anything gets
  tested before Apple tests it for you.
