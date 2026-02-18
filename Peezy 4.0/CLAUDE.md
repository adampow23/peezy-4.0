# CLAUDE.md — Peezy iOS App

## What This Is

iOS moving concierge app. Swift/SwiftUI + Firebase backend (Cloud Functions, Node.js). Users complete an assessment, get personalized tasks, interact via card stack with button actions (complete, snooze, open chat), and chat with AI for help.

## Architecture

```
Auth → Assessment → Task Generation → Main App
                                        ├── Card Stack (home tab)
                                        ├── Timeline (tab 2)
                                        └── Profile (tab 3)
```

### Task Generation Pipeline (MEMORIZE THIS)

```
AssessmentCoordinator.completeAssessment()
  → AssessmentDataManager.computeDistanceAndInterstate()
  → AssessmentDataManager.getAllAssessmentData()
  → TaskGenerationService.generateTasksForUser(userId, assessmentData, moveDate)
    → Firestore db.collection("taskCatalog").getDocuments()
    → FOR EACH catalog task:
        TaskConditionParser.evaluateConditions(conditions, against: assessment)
        → nil/empty conditions = AUTO-PASS (task for everyone)
        → AND logic across keys, OR within value arrays
        → case-insensitive key lookup
    → batch.setData → users/{userId}/tasks/{docId}
```

### Key Files

| File | Purpose |
|------|---------|
| `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift` | Assessment flow controller, triggers task generation |
| `Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift` | Stores answers, builds assessment dict, computes derived fields |
| `Peezy 4.0/Assessment/AssessmentModels/TaskGenerationService.swift` | Reads catalog, evaluates conditions, writes user tasks |
| `Peezy 4.0/Assessment/AssessmentModels/TaskConditionerParser.swift` | Condition evaluation (NOTE: filename has typo, class name is correct) |
| `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift` | Home tab state machine, card stack logic |
| `Peezy 4.0/MainInterface/Models/WorkflowManager.swift` | Vendor workflow card progression |
| `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift` | Home tab UI |
| `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift` | Tab container, walkthrough host |
| `functions/seedTaskCatalog.js` | Wipes and reseeds Firestore taskCatalog |
| `functions/taskCatalogData.json` | 80 task definitions (source of truth for catalog) |

### Condition Format

Firestore stores conditions as maps with string array values:
```
conditions: { "hasVet": ["Yes"], "moveDistance": ["Long Distance"] }
```
Swift reads as `[String: Any]` where values are `[String]`. The parser casts with `as? [String]`.

IMPORTANT: If a condition value is NOT `[String]` (e.g., raw string, number), the parser SKIPS it (silent `continue`, not fail). This is a known bug — malformed conditions pass instead of blocking.

### View Model Ownership

- **PeezyHomeViewModel** drives the home card stack (primary)
- **PeezyStackViewModel** drives Timeline tab ONLY (legacy, demoted)
- PeezyStackView is DEAD CODE — not instantiated anywhere
- PeezyStackViewModel has hardcoded placeholder/intro cards — these do NOT appear in the home tab

## Build Commands

```bash
# Build iOS app (use available simulator — iPhone 17 Pro confirmed working)
xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build

# Seed task catalog to Firestore
cd functions && node seedTaskCatalog.js

# Deploy Cloud Functions
cd functions && firebase deploy --only functions --project peezy-1ecrdl
```

## Code Style

- Swift 5.9+, iOS 17+ minimum
- `@Observable` (Observation framework), NOT `ObservableObject`/`@Published` (Combine)
- `async/await` for all async operations
- SwiftUI views, no UIKit except PeezyWalkthrough overlay (legacy UIWindow)
- Firebase Firestore for all persistence
- Node.js for Cloud Functions (functions/ directory)

## DO NOT (CRITICAL — Read Before Every Session)

- **DO NOT modify .pbxproj files.** Create files, add to Xcode manually.
- **DO NOT create tasks outside TaskGenerationService.** All user tasks come from the `taskCatalog` Firestore collection. No hardcoded task arrays, no manual Firestore writes to `users/{uid}/tasks/`.
- **DO NOT use lowercase task IDs.** Catalog uses UPPER_SNAKE_CASE (e.g., `BOOK_MOVERS`, `SETUP_INTERNET`). Never `book_movers` or `internet_setup`.
- **DO NOT write conditions as raw strings.** Conditions are `[String: [String]]` maps. WRONG: `{"hireMovers": "Yes"}`. RIGHT: `{"hireMovers": ["Yes"]}`.
- **DO NOT store assessment brand names as condition values.** Conditions check categories ("Bank Account", "Gym", "Doctor"), NOT specific names ("Chase", "Genesis", "Aetna"). Business names go in separate detail fields.
- **DO NOT add mock/test/sample data in production files.** Tests go in `/Tests/`. Demo data is guarded by `isDemoWorkflow` flag.
- **DO NOT assume file contents.** Read the file first. If you haven't read it this session, you don't know what's in it.
- **DO NOT make changes to files you weren't asked to change.** No drive-by refactors, no "improvements" to unrelated code.
- **DO NOT use `print()` for debugging in production code.** Use existing Logger/debug infrastructure or ask first.
- **DO NOT skip xcodebuild verification after changes.** Build after every set of changes to catch compile errors immediately.

## Known Bugs and Gotchas (Learn From Past Mistakes)

1. **Ghost tasks from stale Firestore data.** If `taskCatalog` collection has old documents not in `taskCatalogData.json`, they generate for users. Fix: re-run seed script.
2. **Assessment value mismatch.** `getAllAssessmentData()` must map hiring question labels to "Yes"/"No" for catalog conditions. Raw labels like "Hire Professional Movers" won't match.
3. **Multi-select fields must output categories, not brands.** `financialInstitutions` should contain `["Bank Account"]`, not `["Chase"]`. Business names stored separately in detail fields.
4. **`computeDistanceAndInterstate()` needs real addresses.** Test addresses like "11" and "12" can't be geocoded. ~40 catalog tasks depend on `moveDistance` and `isInterstate`.
5. **Walkthrough overlay (tag 1009) blocks touches.** The PeezyWalkthrough uses a separate UIWindow. If it doesn't dismiss properly, the entire app is unresponsive. Defensive cleanup exists in PeezyMainContainer `.onAppear`.
6. **`cancelWorkflow()` fires `onWorkflowDismissed` callback.** During demo workflows, this callback is nil (safe). But if a real workflow set it before demo triggered, it could cause state conflicts.
7. **Single-select auto-advance timing.** In workflow cards, single-select options auto-advance after 0.3s delay via `dismissLeft → onContinue → handleWorkflowContinue()`. Demo phase tracking depends on this call chain.
8. **Firestore numeric casting.** Use `(as? NSNumber)?.intValue` for integers from Firestore, not `as? Int`. Fixed in TaskGenerationService but watch for it elsewhere.
9. **iPhone 16 simulator does not exist.** Use iPhone 17 Pro for xcodebuild destination.

## Assessment Data Keys (Current)

getAllAssessmentData() outputs these keys — this is the CONTRACT that the condition parser evaluates against:

**Raw answers:** userName, moveDate, moveDateType, moveConcerns, currentRentOrOwn, currentDwellingType, currentAddress, currentFloorAccess, currentBedrooms, currentSquareFootage, currentFinishedSqFt, newRentOrOwn, newDwellingType, newAddress, newFloorAccess, newBedrooms, newSquareFootage, newFinishedSqFt, childrenInSchool, childrenInDaycare, hasVet, hireMoversDetail, hirePackersDetail, hireCleanersDetail, financialInstitutions, healthcareProviders, fitnessWellness, howHeard, referralCode

**Computed/derived:** moveDistance (String), isInterstate (String), hireMovers (String "Yes"/"No"), hirePackers (String "Yes"/"No"), hireCleaners (String "Yes"/"No")

## Condition Keys Used in Catalog

These keys are referenced in taskCatalogData.json conditions:
hasVet, hireMovers, hirePackers, hireCleaners, currentDwellingType, newDwellingType, currentRentOrOwn, newRentOrOwn, moveDistance, isInterstate, childrenInSchool, childrenInDaycare, financialInstitutions, healthcareProviders, fitnessWellness

## Workflow

1. Before coding: state what you're changing, which files, and why
2. Read every file you plan to modify BEFORE making changes
3. Make changes
4. Run xcodebuild to verify compilation
5. If build fails, fix before moving on — do not accumulate broken state
6. Report what changed with file paths and line numbers

## When Unsure

If you're not sure what a file contains, what a method does, or how two systems connect: **read the file first, then explain what you found.** Do not guess. Do not say "this likely does X." Read it and know.
