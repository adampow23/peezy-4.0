# Peezy v1 Build — Spec 07: Non-Service Layer
Prereqs: Spec 06 complete. Read repo peezy-conventions-v2.md, peezy-v1-architecture.md §8, peezy-execution-protocol.md, peezy-v1-catalog-sheet.md. Model: Fable 5 or Sol, xhigh. Autonomy: A PERIPHERY, B CORE (new server surface + one gated rules deploy), C PERIPHERY.

## Scope statement
The long-tail engine: any company a user names gets a resolved path — deep link, drafted call, or concierge — powered by a curated directory with an LLM resolver behind it. Plus the ISP cards (revenue path #2) and the userKnowledge schema finally adopted. v1.1 items (Gmail/Plaid detection) remain out.

## Phase A: userKnowledge schema adoption (PERIPHERY)
**READ FIRST:** functions/contextBuilder.js:40-47, the four client write sites (AssessmentDataManager + three in PeezySettingsView).
Client writes convert to `{entries: {key: {value, source: "assessment"|"settings", updatedAt}}}` matching flattenUserKnowledge. Merge-write (setData merge:true) so sources coexist. Verify contextBuilder returns non-empty context for the test bot post-write (node harness evidence). Conventions: userKnowledge greenfield note → resolved.
**Acceptance:** write → read-back in entries shape; contextBuilder harness returns the entries; all four sites migrated (citations).

## Phase B: Provider directory + resolver (CORE)
1. **Firestore `providerDirectory`** {providerId, name, aliases[], category, addressChangeURL?, cancellationURL?, phone?, method: link|call|concierge, verified: bool, source: seeded|resolved, resolvedAt?}. Seed functions/providerDirectoryData.json with ~40 REAL researched entries (agent web-researches current URLs; verified:true only when the URL is confirmed live this session): major banks/cards (Chase, BofA, Wells Fargo, Citi, Capital One, US Bank, Amex, Discover), insurers (State Farm, Geico, Progressive, Allstate), KC utilities (Evergy, Spire, KC Water), national gyms (Planet Fitness, LA Fitness, Lifetime), streaming/subscriptions (Netflix, Spotify, Amazon, Hulu), carriers (Verizon, AT&T, T-Mobile), USPS-adjacent already handled. Dead/uncertain URL → method: concierge, verified:false.
2. **Rules (ADAM GATE):** one match block — providerDirectory authed read, no client write. Present diff, STOP for approval, deploy on approval. (Same protocol as vendors.)
3. **`resolveProvider` callable** (new function, deploy sanctioned): input {name, category} → checks directory (aliases included) → on miss, calls the Anthropic API with web search (key already in env for inventory) with a tight prompt: find the official address-change/cancellation path; return {url?, phone?, method, confidence: high|medium|low} + citations. high → write-through cache to directory (source: resolved, verified:false) and return self-serve payload; medium/low → return method: concierge. Timeout/failure → concierge. NEVER invent a URL: the prompt requires a fetched citation for any returned link, else concierge.
4. **Client integration:** in the row flows (FINANCIAL_ACCOUNTS, MEMBERSHIPS, MEDICAL_RECORDS, utilities, insurance), when a provider is named via businessSearch: directory/resolver lookup → link rows render "Open {name}'s address change" (SFSafariViewController) with a copy-identity affordance (one tap copies formatted name/new address/phone for pasting); call rows render the number + a drafted call script line; concierge rows render the existing concierge submission. Confidence and method are invisible to the user — every row just works (LOCKED principle: user never learns which tier they're in).
**Acceptance:** seeded lookup renders a live link row (screenshot, URL opens); an unseeded real brand (validator picks one) resolves via the callable with citation evidence and caches into the directory (read-back); a gibberish provider routes to concierge; function never returns an uncited URL (test with a fake brand).

## Phase C: ISP curated cards (PERIPHERY)
1. functions/ispPlansData.json → Firestore ispPlans (rules: reuse an existing authed-read pattern — if a new block is needed, fold into Phase B's single gated diff up front): KC-serviceable providers (Google Fiber, AT&T Fiber, Xfinity, Spectrum, T-Mobile Home Internet) with hand-curated tiers {speed, price, promo, contract, affiliateURL?}. Affiliate URLs read from the JSON; where Adam's CJ/Impact links are absent, placeholder "#AFFILIATE_PENDING" renders the card with a plain provider link and logs — open item, not a blocker.
2. SETUP_INTERNET flow upgrade: ComparisonCardView reuse (provider cards: speed/price/promo/contract/one why-line) → tap → SFSafariViewController to the affiliate/provider URL. Address shown atop ("Plans for {newAddress city/zip}") — serviceability API remains v1.1; curation note in JSON header explains per-provider coverage assumptions.
**Acceptance:** flow renders the cards from Firestore (screenshot); tap opens the URL; pending-affiliate card degrades gracefully; catalog untouched (SETUP_INTERNET already routes custom).

## Phase D: Doc sync per protocol §6. Open items: affiliate URLs (Adam), directory grows via resolver cache + admin review of source:resolved entries.

## Files Summary
Created: providerDirectoryData.json, seedProviderDirectory.js, functions/resolveProvider.js, ispPlansData.json, seedIspPlans.js, ProviderDirectoryService.swift, row-flow link/call/concierge row views. Modified: firestore.rules (one approved diff), row flow definitions/views, SetupInternetFlow, contextBuilder write sites (Phase A), functions/index.js exports. Deployed (sanctioned): approved rules diff, resolveProvider, seeds.

## Delegation Prompt
```
cd ~/Desktop/Peezy 4.0/. Read peezy-conventions-v2.md, peezy-v1-architecture.md,
peezy-execution-protocol.md, peezy-v1-catalog-sheet.md, then peezy-build-spec-07.md.
Execute Phases A→D. Phase B is CORE and contains the ONE rules deploy of this
run: present the diff and WAIT for my explicit approval before deploying.
resolveProvider must never return an uncited URL. Validators per phase.
Sanctioned deploys only: the approved rules diff, resolveProvider, and the two
seeds. STOP on anything not covered. Investigate and execute.
```
(Codex variant: prepend the standard no-hooks self-enforcement block; read CLAUDE.md.)
