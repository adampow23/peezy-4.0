# CLAUDE.md — Peezy iOS App

## What This Is

iOS moving concierge app. Swift/SwiftUI + Firebase backend (Cloud Functions, Node.js). Users complete an assessment, get personalized tasks, interact via card stack with button actions (complete, snooze), and complete vendor workflows to coordinate services.

## Architecture

```
Auth → Assessment → Task Generation → Main App
                                        ├── Card Stack (home tab)
                                        ├── Timeline (tab 2)
                                        └── Settings (tab 3)
```

### Assessment Flow (Template System)
- `AssessmentCoordinator` — sequence, branching, navigation, completion (`ObservableObject` — DO NOT convert)
- `AssessmentDataManager` — all answer storage (`ObservableObject` + `@Published` — DO NOT convert)
- `AssessmentFlowView` — routes to question views, owns progress bar. Background ignores keyboard; content VStack does NOT — this is intentional.
- Questions use self-contained templates: `SingleSelectTemplate`, `GridSelectTemplate`, `MultiSelectTemplate`, `TextEntryTemplate`, `DatePickerTemplate`, `ExplainerTemplate`
- Each template owns its full page: typewriter animation, morph transition, controls, layout
- `AssessmentInputWrapper` is DELETED — templates replaced it entirely
- Address questions use `AddressAutocompleteView` with `AddressSearchManager` (MKLocalSearchCompleter)
- Detail pages (Financial/Healthcare/Fitness) use `SuggestiveTextField` with `BusinessSearchManager` for autocomplete

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

### Task Type System

Every task has a `taskType` field in `taskCatalogData.json` (catalog source of truth). **Note: PeezyCard.swift does NOT parse `taskType` yet — only `actionType`. Adding `taskType` to the Swift model is a pending Phase 3 task.**

| Type | Count | Meaning |
|------|-------|---------|
| `research` | 25 | Peezy contacts someone on user's behalf |
| `survey` | 5 | Guided workflow questionnaire (existing workflows) |
| `transfer_cancel` | 11 | Update address vs cancel decision, then research |
| `provide_info` | 15 | Static guidance — user handles it themselves |

### Timeline Sub-Tabs (PeezyTaskStream)

The Tasks tab has 4 sub-tabs defined in `TaskTab` enum in `PeezyTimelineView.swift`:
- **To-Do** — upcoming tasks, sorted by urgency
- **In Progress** — tasks with status `.inProgress` or `.userInProgress`
- **Later** — snoozed tasks with return dates
- **Done** — completed tasks

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
| `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift` | Tab container (3 tabs: Home, Tasks, Settings) |
| `Peezy 4.0/PeezyTimeline/PeezyTimelineView.swift` | Task list with 4 sub-tabs (To-Do, In Progress, Later, Done) |
| `Peezy 4.0/Menu/PeezySettingsView.swift` | Settings with account deletion, privacy/terms links |
| `functions/seedTaskCatalog.js` | Wipes and reseeds Firestore taskCatalog |
| `functions/taskCatalogData.json` | 56 task definitions with taskType field (source of truth for catalog) |

### Condition Format

Firestore stores conditions as maps with string array values:
```
conditions: { "hasVet": ["Yes"], "moveDistance": ["Long Distance"] }
```
Swift reads as `[String: Any]` where values are `[String]`. The parser casts with `as? [String]`.
If a condition value is NOT `[String]` (e.g., raw string, number), the parser returns `false` — the task does NOT generate.

### View Model Ownership

- **PeezyHomeViewModel** drives the home card stack (primary)
- **PeezyStackViewModel** drives Timeline tab ONLY (legacy, demoted)
- PeezyStackView is DEAD CODE — not instantiated anywhere
- ChatView is DEAD CODE — chat removed from v1.0 launch

## Build Commands

```bash
# Build (use --quiet to prevent context overflow)
xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" \
  -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  build --quiet

# Seed task catalog to Firestore
cd functions && node seedTaskCatalog.js && cd ..

# Deploy Cloud Functions
cd functions && firebase deploy --only functions --project peezy-1ecrdl && cd ..
```

## Active Skills

- **peezy-dev** — Build protocol with mandatory verification steps, Read-Verify-Fix-Verify workflow
- **swiftui-pro** — SwiftUI best practices, deprecated API detection, performance and accessibility guidance

## MCP Servers (Active)

- **XcodeBuildMCP** — Build, test, run simulators, screenshots, LLDB debugging directly from Claude. Use `mcp__XcodeBuildMCP__*` tools.
- **Context7** — Live documentation lookup for Firebase iOS SDK, SwiftUI, Swift concurrency, etc. Invoke with "use context7" or Claude will auto-use it when referencing libraries.

## Xcode Agent Environment

- **Shell is sandboxed.** Your `.zshrc`, Homebrew paths, nvm paths do NOT exist. Use absolute paths everywhere.
- **MCP config path:** `~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/.claude` — use fully qualified absolute paths.
- **Usage is shared** across claude.ai, Claude Code CLI, and Xcode. Budget accordingly.
- **Use SwiftUI Preview capture** to verify visual changes — iterate until the UI matches intent.
- **Use thinking levels** for complex tasks: "think" < "think hard" < "think harder" < "ultrathink"

## Code Style

- Swift 5.9+, iOS 17+ minimum
- `@Observable` for NEW classes. Do NOT convert existing `ObservableObject` classes.
- `.foregroundStyle()` not deprecated `.foregroundColor()`
- `async/await` for all async operations — no completion handlers, no GCD
- SwiftUI views, no UIKit (except camera wrapper)
- Firebase Firestore for all persistence
- Firebase numeric casting: `(as? NSNumber)?.intValue` not `as? Int`
- Task IDs: `UPPER_SNAKE_CASE` (e.g., `BOOK_MOVERS`)
- Cloud Functions: Node.js JavaScript, not TypeScript

## Assessment Data Keys (Current)

getAllAssessmentData() outputs these keys — this is the CONTRACT:

**Raw answers:** userName, moveDate, moveDateType, moveConcerns, currentRentOrOwn, currentDwellingType, currentAddress, currentFloorAccess, currentBedrooms, newRentOrOwn, newDwellingType, newAddress, newFloorAccess, newBedrooms, anyKids, childrenInSchool, childrenInDaycare, hasVet, hasStorage, storageSize, storageFullness, hireMovers, hirePackers, hireCleaners, wantsTruckRental, hasDeclutter, wantToSell, financialInstitutions, healthcareProviders, fitnessWellness, howHeard

**Computed/derived:** moveDistance ("Local"/"Long Distance"), isInterstate ("Yes"/"No"), hasVehicles ("Yes"/"No" mapped from "0"/"1"/"2"/"3+")

## Condition Keys Used in Catalog

hasVet, hasVehicles, hireMovers, hireCleaners, wantsTruckRental, hasDeclutter, wantToSell, currentDwellingType, newDwellingType, currentRentOrOwn, newRentOrOwn, currentFloorAccess, newFloorAccess, moveDistance, isInterstate, childrenInSchool, childrenInDaycare, financialInstitutions, healthcareProviders, fitnessWellness

## Multi-Select Exact Labels (must match catalog)

**financialInstitutions:** "Bank / Credit Union", "Credit Card", "Investment Account", "Student Loans"
**healthcareProviders:** "Doctor", "Dentist", "Specialists", "Pharmacy"
**fitnessWellness:** "Gym / CrossFit", "Yoga / Pilates", "Spin / Cycling", "Massage / Spa", "Country Club / Golf"

## DO NOT (CRITICAL — Read Before Every Session)

1. **DO NOT modify .pbxproj files.** Create files on disk; add to Xcode manually.
2. **DO NOT create tasks outside TaskGenerationService.** All tasks come from `taskCatalog` Firestore collection.
3. **DO NOT use lowercase task IDs.** Catalog uses `UPPER_SNAKE_CASE`.
4. **DO NOT write conditions as raw strings.** Must be `[String: [String]]` maps.
5. **DO NOT store business names as condition values.** Conditions use categories; details go in separate fields.
6. **DO NOT add mock/test data in production files.** Tests go in `/Tests/`. Demo data guarded by `isDemoWorkflow`.
7. **DO NOT assume file contents.** Read the file first. If you haven't read it this session, you don't know what's in it.
8. **DO NOT make changes to files you weren't asked to change.** No drive-by refactors.
9. **DO NOT use deprecated APIs.** `.foregroundStyle()` not `.foregroundColor()`. `@Observable` not `ObservableObject` for new code. `async/await` not GCD.
10. **DO NOT add manual keyboard padding.** SwiftUI handles keyboard avoidance natively. Background ignores keyboard; content VStack shrinks naturally.
11. **DO NOT wrap AssessmentInputWrapper around template questions.** Templates own their full page. AssessmentInputWrapper is deleted.
12. **DO NOT skip xcodebuild verification after changes.** Build after every set of changes.
13. **DO NOT mark a task complete without proving it works.** Run tests, check logs, demonstrate correctness.

## DANGER ZONE FILES — Verify Unchanged After Every Change

These files are fragile and interconnected. After ANY code change, verify these were NOT modified unless your prompt explicitly targeted them:

```
TaskGenerationService.swift        — task generation pipeline
TaskConditionerParser.swift        — condition evaluation logic
AssessmentCoordinator.swift        — assessment flow and completion
AssessmentDataManager.swift        — answer storage and data contracts
PeezyHomeViewModel.swift           — home card stack state machine
PeezyMainContainer.swift           — tab navigation (3 tabs: Home, Tasks, Settings)
PeezyTimelineView.swift            — task list sub-tabs and filtering logic
WorkflowManager.swift              — vendor workflow progression
functions/taskCatalogData.json     — task catalog source of truth
functions/seedTaskCatalog.js       — catalog seeding script
GoogleService-Info.plist           — Firebase configuration
functions/.env                     — API keys and secrets
```

If ANY of these files show up in your git diff and they weren't in the prompt's change list, you have a problem. Revert and investigate before proceeding.

## NEVER MODIFY (absolute restrictions)

These files must NEVER be touched by Claude Code under any circumstances:

```
Peezy 4.0.xcodeproj/project.pbxproj
*.xcworkspace files
GoogleService-Info.plist
functions/.env
```

## Task Catalog Entry Format

```json
{
    "taskId": "UPPER_SNAKE_CASE",
    "title": "Human readable title",
    "actionCategory": "book-schedule|prepare-plan|document-record|contact-notify",
    "category": "moving|services|packing|admin|home",
    "actionType": "off-app|workflow|in-app-inventory",
    "taskType": "research|survey|transfer_cancel|provide_info",
    "workflowId": "only_if_actionType_is_workflow",
    "conditions": {
        "conditionKey": ["AcceptableValue1", "AcceptableValue2"]
    },
    "desc": "Description shown to user",
    "estHours": 1.5,
    "tips": "Helpful tips for the user",
    "urgencyPercentage": 75,
    "whyNeeded": "Why this task matters"
}
```

## When Builds Fail (CRITICAL)

Follow this escalation ladder IN ORDER. Do not skip steps.

### Level 1: Fix YOUR code
Read the error. Fix only the lines YOU changed in this session. If you changed a function signature, fix YOUR call site — not the function someone else wrote. Build again.

### Level 2: Fix the INTEGRATION
Read the file that's erroring. Understand what it expects. Adapt YOUR code to match what the existing code expects — not the other way around. The existing code that was compiling before you started is CORRECT. Your new code is WRONG. Build again.

### Level 3: STOP and report
If you've tried Level 1 and Level 2 twice each and it still fails, STOP. Do NOT start changing files you didn't originally plan to change. Do NOT rename existing functions, change existing signatures, or delete existing code to make your new code compile. Do NOT "simplify" working code to avoid the error. Report: "Build fails. Here's the error. Here's what I tried. I need guidance before changing [file] because it was working before I started."

**The Rule: Code that compiled before you started is innocent until proven guilty.** If your change broke the build, your change is the problem. You have ZERO authorization to modify files outside your task scope just to make the build pass. A build that passes because you gutted working code is worse than a build that fails.

## Workflow

1. State what you're changing, which files, and why
2. Read every file you plan to modify BEFORE making changes
3. Make changes — one feature at a time
4. Build with `--quiet` flag to verify
5. If build fails, follow "When Builds Fail" ladder above
6. Check danger zone files are unchanged (git diff)
7. Git commit after each successful change
8. If you hit Level 3, stop and ask — do not freelance

## Self-Improvement Loop

- After ANY correction: update `tasks/lessons.md` with the pattern
- Review `tasks/lessons.md` at session start before doing any work
- Write prevention rules, not just fixes

## When Unsure

If you're not sure what a file contains, what a method does, or how two systems connect: **read the file first, then explain what you found.** Do not guess. Do not say "this likely does X." Read it and know.

## v1.0 Launch State

- **Chat is removed.** No AI chat in v1.0. ChatView exists as dead code but is not reachable from any navigation path.
- **3 tabs only:** Home, Tasks, Settings. The chat tab was removed from PeezyMainContainer.
- **Privacy/Terms hosted:** https://peezy-1ecrdl.web.app/privacy.html and /terms.html
- **Account deletion:** Available in Settings via "Delete Account" button
- **Privacy manifest:** PrivacyInfo.xcprivacy with UserDefaults CA92.1
- **Bundle ID:** peezy.Peezy-4-0 (matches App Store Connect and Firebase)
- **Note:** `peezy-conventions.md` still references chat in its navigation structure — it is outdated. This CLAUDE.md takes precedence for current app state.
