# Peezy Launch Checklist

Single source of truth for launch and submission work as of 2026-07-27. This
reconciles `peezy-conventions-v2.md`, `CLAUDE.md`, `tasks/todo.md`,
`SESSION_NOTES.md`, the architecture's pre-user requirements, App Store notes,
repository shipping markers, and read-only production checks.

Status meanings:

- **BLOCKED** — an external value, partner, or human decision is missing.
- **OPEN** — the close path is known and can be executed by the named owner.
- **VERIFIED** — complete; the close-path column gives the repeatable proof.
- **DEFERRED** — intentionally post-launch or non-blocking maintenance.

Commands below are verification/close recipes, not authorization to deploy.
Any future backend mutation still requires an explicit sanctioned scope.

## Launch and App Store gates

| ID | Item and evidence | Owner | Status | Exact close path |
|---|---|---|---|---|
| L01 | Twilio destination + one live SMS. Presence-only audit: `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, and `TWILIO_FROM_NUMBER` are present in `functions/.env`; `ADAM_NOTIFY_NUMBER` is absent. Phase A proved the exact fallback log `SMS notify not configured`. | Adam | **BLOCKED** | Add `ADAM_NOTIFY_NUMBER` to the protected `functions/.env`, then run `firebase deploy --only functions:submitCheckIn --project peezy-1ecrdl`. Submit one flagged check-in from the authenticated app, confirm the phone receives `PEEZY FLAG: {vendor} — {flag}.`, and verify `firebase functions:log --only submitCheckIn --project peezy-1ecrdl \| rg 'Check-in flag SMS sent'`. |
| L02 | Five ISP affiliate URLs. Local validation and live Firestore both report five `#AFFILIATE_PENDING` values: `google_fiber_core_1_gig`, `att_fiber_300`, `xfinity_300`, `spectrum_internet_premier`, `tmobile_rely_home_internet`. The app safely falls back to official provider URLs, but attribution is not launch-ready. | Adam | **BLOCKED** | Obtain approved CJ/Impact HTTPS destinations, replace the five `affiliateURL` values in `functions/ispPlansData.json`, run `cd functions && node seedIspPlans.js --validate-only`, then—only in a separately sanctioned release operation—run `cd functions && node seedIspPlans.js`. Verify in Firebase Console → project `peezy-1ecrdl` → Build → Firestore Database → Data → `ispPlans` that all five documents have HTTPS `affiliateURL` values. |
| L03 | Resolver admin review. Read-only live query found exactly one `source: resolved` document: `resolved_regionsbank` (Regions Bank), `verified:false`, method `link`, one citation. | Adam | **OPEN** | Firebase Console → project `peezy-1ecrdl` → Build → Firestore Database → Data → `providerDirectory` → `resolved_regionsbank`. Confirm `addressChangeURL` exactly matches an official URL in `citations`; if approved, copy the complete row into `functions/providerDirectoryData.json` with `source:"seeded"` and `verified:true`, run `cd functions && node seedProviderDirectory.js --validate-only`, then use a separately sanctioned `cd functions && node seedProviderDirectory.js`. If rejected, delete the resolved document in that same console path. Re-run the read-only query documented under “Repeatable audit commands” until the result is zero. |
| L04 | Real mover agreements/rate cards. Local source and live Firestore both contain three active placeholders: `test_mover_a`, `test_mover_b`, `test_mover_c`. Architecture requires 3–5 KC movers and the vendor standards/rate-card contract is ready. | Adam | **BLOCKED** | Sign 3–5 KC movers against `docs/vendor-standards.md` and collect every field in `functions/vendorsData.json`'s `rateCard`, `serviceRadius`, and `accountability` shapes. Record real stable vendor IDs and written approval for their published rates before L05. |
| L05 | Replace Test Movers in source and production. This is blocked on L04; the existing seeder is upsert-only, so changing IDs alone would leave the three placeholders live. | machine | **BLOCKED** | Replace all three placeholder objects in `functions/vendorsData.json`; run `cd functions && node seedVendors.js` only in a separately sanctioned vendor-data operation. Then Firebase Console → project `peezy-1ecrdl` → Build → Firestore Database → Data → `vendors` → each of `test_mover_a`, `test_mover_b`, `test_mover_c` → set `active` to `false`. Verify the live collection has 3–5 real `active:true` movers and no active `Test Mover` name. |
| L06 | Pricing field calibration inputs. `PricingConstants.swift` remains explicitly `LOCKED-pending-calibration`; architecture requires five recent real KC moves before users see numbers. | Adam | **BLOCKED** | Enter five anonymized recent KC moves into the scenario inputs described in `tasks/todo.md` under “Pricing calibration output”, compare predicted hours/ranges with actual crew-hours and invoices, and provide a written approval containing the exact revised constant values for L07. Do not expose mover prices publicly until all five comparisons are signed off. |
| L07 | Apply Adam-approved pricing constants and prove the engine. Blocked on L06. | machine | **BLOCKED** | Apply only the approved values in `Peezy 4.0/MainInterface/Models/PricingConstants.swift`; run `swiftc -D DEBUG 'Peezy 4.0/MainInterface/Models/PricingConstants.swift' 'Peezy 4.0/MainInterface/Models/PricingEngine.swift' Tests/PricingEngineTests.swift -o /tmp/peezy_pricing_tests && /tmp/peezy_pricing_tests`, regenerate the five-scenario report, and run the exact iPhone 17 Pro build. |
| L08 | Kit supplier agreement and integration contract. `supplies_kit` still uses concierge fulfillment and placeholder retail assumptions; no supplier target exists. | Adam | **BLOCKED** | Sign a KC supplier and provide its accepted bundle SKUs, prices, delivery SLA, order transport/sandbox credentials, and pickup policy as the complete input contract for L09. |
| L09 | Replace concierge kit fulfillment with the signed supplier path. Blocked on L08; estimator tuning remains separately data-driven. | machine | **BLOCKED** | Open a scoped implementation spec and replace `WorkflowService.submitAnswers(taskId:"PACKING_SUPPLIES_KIT", workflowId:"supplies_kit", …)` in `Peezy 4.0/Tasks/Task Cards/SuppliesKitView.swift`; close only after `rg -n 'workflowId: \"supplies_kit\"' 'Peezy 4.0/Tasks/Task Cards/SuppliesKitView.swift'` shows the concierge order path removed/reframed, the exact iPhone 17 Pro build passes, and one supplier sandbox order round-trips. |
| L10 | StoreKit subscribed pass-through. The shared `Peezy 4.0` scheme already references `../../Configuration.storekit`; simctl validation could not create the subscribed state. | Adam | **OPEN** | Xcode → Product → Scheme → Edit Scheme… → Run → Options → StoreKit Configuration = `Configuration.storekit`; Run the `Peezy 4.0` scheme, purchase the test subscription through Xcode → Debug → StoreKit → Manage Transactions, then verify an already-subscribed user passes BOOK_MOVERS booking, the supplies-kit order, and a concierge submission without `PaywallGateView`. Capture one screenshot or test note per path. |
| L11 | Privacy data-use inventory. `Peezy 4.0/PrivacyInfo.xcprivacy` contains only the UserDefaults required-reason API and no `NSPrivacyCollectedDataTypes`, while the app stores account/contact/address/user content and sends inventory frames to Anthropic. | Adam | **OPEN** | App Store Connect → My Apps → Peezy → App Privacy → Edit. Reconcile every collected data type, purpose, identity linkage, tracking answer, retention, and third-party transfer against Firebase, Anthropic, Twilio, and support-chat behavior; give the approved matrix to the machine for L12. |
| L12 | Privacy manifest nutrition-label entries. Blocked on Adam's approved L11 matrix; no data types should be guessed. | machine | **BLOCKED** | Add `NSPrivacyCollectedDataTypes` (and the explicit tracking key/value required by the approved matrix) to `Peezy 4.0/PrivacyInfo.xcprivacy`; run `plutil -lint 'Peezy 4.0/PrivacyInfo.xcprivacy'` and `plutil -p 'Peezy 4.0/PrivacyInfo.xcprivacy' \| rg 'NSPrivacyCollectedDataTypes'`; archive in Xcode and review Organizer → Privacy Report before submission. |
| L13 | Auth-screen legal acknowledgement. Privacy/Terms links exist in Settings and the paywall, but `AuthView.swift` and `SignUpView.swift` contain neither link. | machine | **OPEN** | Add visible `Link` controls for `https://peezy-1ecrdl.web.app/privacy.html` and `https://peezy-1ecrdl.web.app/terms.html` beside account creation/sign-in consent, with stable accessibility IDs. Run `rg -n 'privacy.html\|terms.html' 'Peezy 4.0/Auth'`, add focused UI assertions, then run the exact iPhone 17 Pro build. |
| L14 | App Store screenshots + metadata. No App Store screenshot assets are in the repo, and the existing 10-slot plan predates mover comparison/booking, inventory-driven packing + kit/readiness, ISP cards, post-move check-in, and box return. Title/subtitle/keywords/category/current listing remain unverified. | Adam | **OPEN** | Capture clean production-data-free iPhone screenshots for the new surfaces, then App Store Connect → My Apps → Peezy → App Store → iOS App → current version → App Previews and Screenshots: replace the default set. In the same version page update Promotional Text, Description, Keywords, Support URL, and Marketing URL; then App Information → Primary/Secondary Category and confirm Lifestyle vs Productivity. Reconcile the copy/sequence against `docs/APP_STORE_CONVERSION_PLAN.md`, validate the final keyword set with an actual ASO tool, and save a dated submission screenshot/export. |

## Release hygiene and non-blocking follow-up

| ID | Item and evidence | Owner | Status | Exact close path |
|---|---|---|---|---|
| H01 | Verification-only source marker. `Tests/ConditionVerification.swift` says `DELETE BEFORE SHIPPING`; it is tracked but has no Xcode project reference, so it cannot enter the app archive. | machine | **OPEN** | Run `rg -n 'ConditionVerification.swift' 'Peezy 4.0.xcodeproj/project.pbxproj'` (expect no match), then `git rm Tests/ConditionVerification.swift` in a scoped cleanup commit and run the exact iPhone 17 Pro build. |
| H02 | Flow-definition callable compatibility fallback. Direct Firestore reads are live; `getWorkflowQualifying` remains an intentional one-release client fallback. | machine | **DEFERRED** | After the minimum supported app version is beyond the direct-read release, remove the callable fallback in `Peezy 4.0/Tasks/FlowEngine/FlowDefinition.swift`; verify with `rg -n 'getWorkflowQualifying' 'Peezy 4.0/Tasks/FlowEngine/FlowDefinition.swift'` (expect no match) and run the exact iPhone 17 Pro build. Do not delete the backend function while it has other duties/callers. |
| H03 | Legacy Home handling path. `markCurrentTaskPeezyHandling`, `HomeState.activeTask`, and `activeTaskContent` remain after universal routing. | machine | **DEFERRED** | In a scoped cleanup, use `rg -n 'markCurrentTaskPeezyHandling\|activeTaskContent\|case activeTask' 'Peezy 4.0/MainInterface'`, remove only the unreachable path with characterization coverage, and run the exact iPhone 17 Pro build. |
| H04 | Dead-code list. Seven file candidates and `peezyLayout.swift` are already absent; `PeezyStackViewModel.swift` is definition-only and `TaskFlowSelect5Card` has only its definition remaining. | machine | **DEFERRED** | Re-run the symbol commands in `DEAD_CODE_REMOVAL_LIST.md`; delete `Peezy 4.0/MainInterface/Models/PeezyStackViewModel.swift`, remove the `TaskFlowSelect5Card` definition from `Peezy 4.0/Tasks/Task Card Components/TaskFlowTileVariants.swift`, and run the exact iPhone 17 Pro build in a dedicated cleanup commit. |
| H05 | `backup/friend-changes-2026-04-28` still exists locally; no deletion decision is recorded. | Adam | **DEFERRED** | Review `git log --oneline main..backup/friend-changes-2026-04-28` and `git diff --stat main...backup/friend-changes-2026-04-28`; if nothing must be retained, run `git branch -d backup/friend-changes-2026-04-28`. |
| H06 | `PeezyClient`/`PeezyResponse` fate remains tied to the v1.1 chat decision; `PeezyConfig` is still live through receipt sync. | machine | **DEFERRED** | After the v1.1 chat decision, run `rg -n 'PeezyClient\|PeezyResponse\|PeezyConfig' 'Peezy 4.0' --glob '*.swift'`; extract the live `PeezyConfig` receipt-sync values before deleting unused client/response code, then run the exact iPhone 17 Pro build. |
| H07 | Assessment contract cleanup. Several unused fields remain in `getAllAssessmentData()`, but the earlier warning that `hasVehicles`/`wantToSell` were always wrong is stale: both questions are collected and their current catalog conditions are reachable. This is payload hygiene, not a launch blocker. | machine | **DEFERRED** | Inventory `getAllAssessmentData()` keys against `functions/taskCatalogData.json`, `functions/contextBuilder.js`, and Firestore consumers; remove only zero-consumer fields and their reset properties in one scoped pass. Run `swift Tests/ConditionParserV2Test.swift`, assessment generation tests, and the exact iPhone 17 Pro build. |

## Reconciled historical chips and stale boxes

These remain listed because `tasks/todo.md` is an append-only execution log. They
are not launch work.

| ID | Historical item | Owner | Status | Exact close path / repeatable proof |
|---|---|---|---|---|
| C01 | Spec 04 Phase A `PHASE_MANIFEST` checkbox | machine | **VERIFIED** | `git show a6c04cb:PHASE_MANIFEST \| head` |
| C02 | Spec 04 `FlowDefinition.swift` model checkbox | machine | **VERIFIED** | `git show --stat a6c04cb -- 'Peezy 4.0/Tasks/FlowEngine/FlowDefinition.swift'` |
| C03 | Spec 04 `flowDefinitionsData.json` checkbox | machine | **VERIFIED** | `git show --stat a6c04cb -- functions/flowDefinitionsData.json` |
| C04 | Spec 04 `FlowEngineView.swift` checkbox | machine | **VERIFIED** | `git show --stat a6c04cb -- 'Peezy 4.0/Tasks/FlowEngine/FlowEngineView.swift'` |
| C05 | Spec 04 `TaskActionService` flow persistence checkbox | machine | **VERIFIED** | `git show a6c04cb -- 'Peezy 4.0/MainInterface/Models/TaskActionService.swift' \| rg 'writeFlowProgress\|clearFlowState'` |
| C06 | Spec 04 DEBUG `FlowEngineHarness.swift` checkbox | machine | **VERIFIED** | `git show --stat a6c04cb -- 'Peezy 4.0/Tasks/FlowEngine/FlowEngineHarness.swift'` |
| C07 | businessSearch invisible-results chip | machine | **VERIFIED** | Fixed in `5b06b5a`; prove the height/layout priority and AX marker with `git show 5b06b5a -- 'Peezy 4.0/Tasks/Task Card Components/TaskFlowBusinessSearchCard.swift'`. |
| C08 | assessment-retake daily-dose residue chip | machine | **VERIFIED** | Fixed in `5b06b5a`; prove the Firestore + UserDefaults reset with `git show 5b06b5a -- 'Peezy 4.0/MainInterface/Models/DailyDoseEngine.swift' 'Peezy 4.0/Menu/PeezySettingsView.swift'`. |
| C09 | Firestore rules reconciliation chip | machine | **VERIFIED** | `git show --stat 5b06b5a -- firestore.rules`; the Spec 07 live authenticated provider/ISP read and client-write-denial evidence is recorded as remote evidence in `peezy-conventions-v2.md`. |
| C10 | orphaned remote `resetInventory` deletion chip | machine | **VERIFIED** | `firebase functions:list --project peezy-1ecrdl \| rg 'resetInventory'` returns no match; the same inventory lists the sanctioned `submitCheckIn`. |
| C11 | catalog `estPeezy` omission | machine | **VERIFIED** | Fixed in `51031a9`; `rg -n 'estPeezy\|Every JSON-declared catalog field' functions/seedTaskCatalog.js`, and the live 47-document reseed round-tripped every JSON-declared field. |
| C12 | Spec 04 subscribed-pass-through environment limitation | Adam | **OPEN** | Consolidated into L10; close only through the Xcode scheme path stated there. |
| C13 | Spec 05 Twilio launch chip | Adam | **BLOCKED** | Consolidated into L01; `ADAM_NOTIFY_NUMBER` remains absent. |

## Repeatable audit commands

Run from the repository root. These are read-only except the explicitly labeled
future seed/deploy commands in the tables above.

```bash
# Local launch markers
rg -n -i 'before launch|before submission|before shipping|delete before shipping|#AFFILIATE_PENDING|LOCKED-pending-calibration' \
  --glob '!node_modules/**' --glob '!functions/node_modules/**' --glob '!peezy-build-spec-*.md' .

# Stale unchecked todo boxes
rg -n '^- \[ \]' tasks/todo.md

# ISP source validation
node functions/seedIspPlans.js --validate-only

# Deployed function inventory (resetInventory must remain absent)
firebase functions:list --project peezy-1ecrdl
```

For the live resolver review, use Firebase Console → project `peezy-1ecrdl` →
Build → Firestore Database → Data → `providerDirectory`, filter field `source`
equal to `resolved`. For live vendor readiness, use the same Data screen →
`vendors`, filter `active` equal to `true`, and reject any result whose `name`
starts with `Test Mover`.

Exact build used by every machine-owned close path:

```bash
xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" \
  -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
```
