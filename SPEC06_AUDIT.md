# Spec 06 Phase 0 — Read-Only Audit

Audit target: repository HEAD `dd8cb5ef46bf77677c65ab331854f0643886d1f0` (`dd8cb5e`, `release: build 21`).

Pre-flight result: `/Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0.xcodeproj` exists. The source spec was read from `/Users/adampowell/Desktop/Peezy 4.0/PEEZY_SPEC_06_CATALOG_RESTRUCTURE.md`; no copy was made.

Overall gate result: **STOP — multiple HEAD facts contradict the spec assumptions. Phase 1 must not run from this spec without revision.**

## Git anchors cited by the spec

Read-only `git show -s` evidence:

```text
dd8cb5ef46bf77677c65ab331854f0643886d1f0
dd8cb5e 2026-08-06T02:26:16-05:00 release: build 21
da1916e28101a70020765fcaa400daf06ec43a1b
da1916e 2026-07-23T11:20:31-05:00 Add dead-code removal confirmation report (no source changes)
eab4193784786d8bfdab4660d9994b931b1206c1
eab4193 2026-04-10T17:35:47-05:00 Cleanup complete.
```

`eab4193` does support the deletion-doctrine lesson. Its name-status output includes these deletions:

```text
D	Peezy 4.0/Assessment/AssessmentModels/ConversationalInterestitialView.swift
D	Peezy 4.0/Assessment/AssessmentViews/Questions/CurrentBedrooms.swift
D	Peezy 4.0/Assessment/AssessmentViews/Questions/HasStorage.swift
D	Peezy 4.0/Assessment/AssessmentViews/Questions/HasVehicles.swift
D	Peezy 4.0/Assessment/AssessmentViews/Questions/MoveConcerns.swift
D	Peezy 4.0/Assessment/AssessmentViews/Questions/NewBedrooms.swift
D	Peezy 4.0/Assessment/AssessmentViews/Questions/StorageFullness.swift
D	Peezy 4.0/Assessment/AssessmentViews/Questions/StorageSize.swift
D	Peezy 4.0/Assessment/AssessmentViews/Questions/WantToSell.swift
D	Peezy 4.0/MainInterface/Views/TaskCard/PeezyTaskCardStackView.swift
D	Peezy 4.0/MainInterface/Views/TaskCard/PeezyTaskCardView.swift
```

At that same commit, `git grep` still finds the deleted questions' persisted fields and catalog conditions, for example:

```text
eab4193:Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift:45:    @Published var hasVehicles: String = ""
eab4193:Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift:46:    @Published var hasStorage: String = ""
eab4193:Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift:55:    @Published var wantToSell: String = ""
eab4193:Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift:147:        data["hasStorage"] = hasStorage
eab4193:Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift:161:        data["wantToSell"] = wantToSell
eab4193:Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift:192:        data["hasVehicles"] = (hasVehicles.isEmpty || hasVehicles == "No" || hasVehicles == "None" || hasVehicles == "0") ? "No" : "Yes"
eab4193:functions/taskCatalogData.json:172:      "wantToSell": [
eab4193:functions/taskCatalogData.json:546:      "hasVehicles": [
```

That commit lesson is valid. The `da1916e` state is not a valid proxy for current HEAD; Items 1, 2, 5, 7, and 9 below show later architectural changes.

## 1. Catalog row schema and seeder behavior

### Answer

`functions/taskCatalogData.json` contains 47 rows at HEAD. The union of declared row fields is:

```text
actionCategory              47/47
actionType                  47/47
category                    47/47
conditions                  47/47
desc                        47/47
estHours                    47/47
estPeezy                    47/47
researchPrefs                6/47
researchScope               47/47
rowGeneration                6/47
selfServiceOnly             15/47
surfaceAfterDaysPastMove     2/47
taskId                      47/47
taskType                    47/47
tips                        47/47
title                       47/47
urgencyPercentage           47/47
whyNeeded                   47/47
workflowId                  35/47
```

The seeder uses a fixed projection/allowlist; it does not spread arbitrary fields from each JSON row. Unknown future fields are dropped by `doc = { ... }` unless explicitly copied afterward. The verifier then compares every JSON-declared field to Firestore and throws if the projection dropped one.

`estPeezy` is **not** dropped at HEAD. It is explicitly projected. `git blame` attributes that line to `51031a9` (`feat: add post-move check-in flow`, after `da1916e`).

### Evidence

Full sample row, verbatim from `functions/taskCatalogData.json:2-51`:

```json
{
  "taskId": "BOOK_MOVERS",
  "title": "Book your movers",
  "actionCategory": "book-schedule",
  "category": "moving",
  "actionType": "workflow",
  "taskType": "survey",
  "researchScope": "web",
  "researchPrefs": [
    {
      "id": "top_priority",
      "question": "What matters most when you choose a mover?",
      "options": [
        "Lowest total cost",
        "Soonest confirmed date",
        "Careful handling"
      ]
    },
    {
      "id": "date_flexibility",
      "question": "How flexible is your move date?",
      "options": [
        "The date is fixed",
        "A few days flexible",
        "A week or more flexible"
      ]
    },
    {
      "id": "handling_priority",
      "question": "Which items need the most attention?",
      "options": [
        "Standard household items",
        "Fragile or high-value items",
        "Heavy or oversized items"
      ]
    }
  ],
  "workflowId": "book_movers",
  "conditions": {
    "hireMovers": [
      "Yes"
    ]
  },
  "desc": "Get binding estimates from three USDOT-licensed movers. Book 8-12 weeks out for summer moves, 4-6 weeks off-season.",
  "estHours": 3,
  "estPeezy": "90 secs",
  "tips": "Get a binding estimate — federal law caps your final bill at 110%.",
  "urgencyPercentage": 94,
  "whyNeeded": "Booking late means leftover dates, leftover crews, and leftover quality."
}
```

Fixed projection, verbatim from `functions/seedTaskCatalog.js:96-140`:

```js
for (const task of chunk) {
  const docId = task.taskId;
  const docRef = db.collection(COLLECTION).doc(docId);

  // Build the Firestore document
  const doc = {
    taskId: task.taskId,
    title: task.title,
    actionCategory: task.actionCategory,
    category: task.category,
    actionType: task.actionType,
    taskType: task.taskType || "provide_info",
    researchScope: task.researchScope,
    conditions: task.conditions, // stored as map: { key: [values] }
    desc: task.desc,
    estHours: task.estHours,
    estPeezy: task.estPeezy,
    tips: task.tips,
    urgencyPercentage: task.urgencyPercentage,
    whyNeeded: task.whyNeeded,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Only include workflowId if present (workflow tasks only)
  if (task.workflowId) {
    doc.workflowId = task.workflowId;
  }

  if (task.researchPrefs) {
    doc.researchPrefs = task.researchPrefs;
  }

  // Include selfServiceOnly flag (defaults to false if absent)
  doc.selfServiceOnly = task.selfServiceOnly || false;

  // Row-generation config (Spec 04 catalog v2) — consumed by the client's
  // TaskGenerationService to stamp per-user flowRows on task docs
  if (task.rowGeneration) {
    doc.rowGeneration = task.rowGeneration;
  }
  if (Number.isInteger(task.surfaceAfterDaysPastMove)) {
    doc.surfaceAfterDaysPastMove = task.surfaceAfterDaysPastMove;
  }

  batch.set(docRef, doc);
}
```

Round-trip enforcement, verbatim from `functions/seedTaskCatalog.js:168-186`:

```js
const documentsById = new Map(snapshot.docs.map((document) => [document.id, document.data()]));
const roundTripFailures = [];
for (const task of tasks) {
  const stored = documentsById.get(task.taskId);
  if (!stored) {
    roundTripFailures.push(`${task.taskId}: missing document`);
    continue;
  }
  const mismatchedFields = Object.entries(task)
    .filter(([key, value]) => !isDeepStrictEqual(stored[key], value))
    .map(([key]) => key);
  if (mismatchedFields.length > 0) {
    roundTripFailures.push(`${task.taskId}: ${mismatchedFields.join(", ")}`);
  }
}
if (roundTripFailures.length > 0) {
  throw new Error(`Catalog round-trip failed — ${roundTripFailures.join("; ")}`);
}
console.log("   ✓ Every JSON-declared catalog field round-tripped exactly");
```

The spec's cited `da1916e` baseline was internally accurate at that commit but has since drifted. Read-only historical inspection produced:

```text
DA1916E_CATALOG_ROWS:56
DA1916E_ESTPEEZY_DECLARED:56
```

`git show da1916e:functions/seedTaskCatalog.js | rg -n 'estPeezy|const doc =|batch.set'` produced no `estPeezy` hit:

```text
100:      const doc = {
124:      batch.set(docRef, doc);
145:    const doc = await db.collection(COLLECTION).doc(id).get();
```

At HEAD, `git blame functions/seedTaskCatalog.js:112` attributes the explicit `estPeezy` projection to post-baseline commit `51031a9` (2026-07-27).

**VERDICT: CONTRADICTS: `estPeezy` is explicitly written at HEAD, not known-dropped; the catalog has 47 rows rather than the spec baseline's 56. The fixed-projection mechanism still exists and every new Phase 1 field must be added to it or verification will fail.**

## 2. Firestore task decoding, unknown fields, and parity marker

### Answer

Unknown fields on a task document pass harmlessly because the mapper reads selected dictionary keys and ignores all others.

There are not two independent decode blocks at HEAD. `PeezyHomeViewModel.loadTasks()` and `TasksStore` both call the single `PeezyCardFirestoreMapper.card()` decoder. The LE-025/031 parity/single-decoder marker exists in the mapper and at the Home call site.

### Evidence

Complete decoder, verbatim from `Peezy 4.0/Tasks/Store/PeezyCardFirestoreMapper.swift:9-78`:

```swift
static func card(from document: QueryDocumentSnapshot) -> PeezyCard? {
    let data = document.data()

    let statusString = data["status"] as? String ?? "Upcoming"
    let status = TaskStatus(rawValue: statusString) ?? .upcoming

    let priorityString = data["priority"] as? String ?? "Medium"
    let priority: PeezyCard.Priority
    switch priorityString.lowercased() {
    case "high", "urgent":
        priority = .high
    case "low":
        priority = .low
    default:
        priority = .normal
    }

    let dueDate = (data["dueDate"] as? Timestamp)?.dateValue()
    let snoozedUntil = (data["snoozedUntil"] as? Timestamp)?.dateValue()
    let lastSnoozedAt = (data["lastSnoozedAt"] as? Timestamp)?.dateValue()
    let completedAt = (data["completedAt"] as? Timestamp)?.dateValue()
    let urgencyPercentage = (data["urgencyPercentage"] as? NSNumber)?.intValue
    let surfaceAfterDaysPastMove = (data["surfaceAfterDaysPastMove"] as? NSNumber)?.intValue
    let userInProgressDate = (data["userInProgressDate"] as? Timestamp)?.dateValue()
    let userInProgressReturnDate = (data["userInProgressReturnDate"] as? Timestamp)?.dateValue()

    let categoryRaw = data["category"] as? String
    let isVendorTask = categoryRaw?.lowercased().contains("vendor") ?? false
    let cardType: PeezyCard.CardType = isVendorTask ? .vendor : .task
    let taskId = data["taskId"] as? String ?? data["id"] as? String ?? document.documentID
    let packingSession = packingSession(from: data, fallbackTaskId: taskId)
    let workflowId = data["workflowId"] as? String
        ?? (taskId.hasPrefix("PACKING_SESSION_") ? "packing_session" : nil)

    return PeezyCard(
        id: document.documentID,
        type: cardType,
        title: data["title"] as? String ?? "Untitled Task",
        // Retained for the gated task-detail renderer; free list rows do
        // not render this catalog description.
        subtitle: data["desc"] as? String ?? "",
        colorName: colorNameForPriority(priority),
        taskId: taskId,
        workflowId: workflowId,
        vendorCategory: isVendorTask ? categoryRaw : nil,
        vendorId: nil,
        priority: priority,
        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
        status: status,
        dueDate: dueDate,
        snoozedUntil: snoozedUntil,
        lastSnoozedAt: lastSnoozedAt,
        taskCategory: categoryRaw,
        urgencyPercentage: urgencyPercentage,
        surfaceAfterDaysPastMove: surfaceAfterDaysPastMove,
        userInProgressDate: userInProgressDate,
        userInProgressReturnDate: userInProgressReturnDate,
        completedAt: completedAt,
        selfServiceOnly: (data["selfServiceOnly"] as? Bool) ?? false,
        actionType: data["actionType"] as? String,
        taskType: data["taskType"] as? String,
        tips: data["tips"] as? String,
        whyNeeded: data["whyNeeded"] as? String,
        estPeezy: data["estPeezy"] as? String,
        estHours: (data["estHours"] as? NSNumber)?.doubleValue,
        // Nil-tolerant: absent/unknown stage = nil (notStarted for workflow tasks)
        stage: (data["stage"] as? String).flatMap(TaskStage.init(rawValue:)),
        payload: packingSession.map(CardPayload.packing)
    )
}
```

The mapper's parity marker is at `Peezy 4.0/Tasks/Store/PeezyCardFirestoreMapper.swift:5-8`:

```swift
/// THE single Firestore→PeezyCard decode path (successor to the LE-025/031
/// parity rule). Home (PeezyHomeViewModel.loadTasks) and the Tasks tab
/// (TasksStore listener) BOTH decode through this function — do not add a
/// second path or re-inline field decoding at a call site.
```

The Home loader's complete current decode/filter block, verbatim from `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:239-268`:

```swift
var cards: [PeezyCard] = []
var userInProgressBuffer: [PeezyCard] = []
let now = Date()

for document in snapshot.documents {
    // Single decode path: PeezyCardFirestoreMapper (LE-025/031 successor).
    // Do not re-inline field decoding here.
    guard var card = PeezyCardFirestoreMapper.card(from: document) else { continue }
    if card.status == .completed || card.status == .skipped { continue }

    if let snoozedUntil = card.snoozedUntil, snoozedUntil > now { continue }

    if card.status == .inProgress || card.status == .pending || card.status == .matchingInProgress {
        // Legacy human-handoff statuses are terminal. They stay
        // out of the actionable Home queue and render as complete
        // in the Tasks tab.
        continue
    } else if card.status == .userInProgress {
        if let returnDate = card.userInProgressReturnDate, returnDate <= now {
            card.status = .upcoming
            card.userInProgressDate = nil
            card.userInProgressReturnDate = nil
            cards.append(card)
        } else {
            userInProgressBuffer.append(card)
        }
    } else if card.shouldShow {
        cards.append(card)
    }
}
```

The Tasks-tab live decode call is `Peezy 4.0/Tasks/Store/TasksStore.swift:39-52`:

```swift
listener = db.collection("users").document(userId).collection("tasks")
    .addSnapshotListener(includeMetadataChanges: false) { [weak self] snap, err in
        Task { @MainActor [weak self] in
            guard let self else { return }

            if let err {
                self.loadState = .failed(err.localizedDescription)
                return
            }

            guard let snap else { return }

            self.tasks = snap.documents.compactMap { PeezyCardFirestoreMapper.card(from: $0) }
            self.loadState = .loaded
        }
    }
```

**VERDICT: CONTRADICTS: unknown fields are harmless and the parity marker exists, but the spec's “both decode blocks”/“both loaders add fields” premise is stale. HEAD has one shared decoder; Phase 3 should change the mapper once, not create or maintain two decode blocks.**

## 3. `TaskStatus` cases and fallback

### Answer

Current cases are `upcoming`, `inProgress`, `pending`, `matchingInProgress`, `userInProgress`, `completed`, `snoozed`, and `skipped`.

The exact fallback is `TaskStatus(rawValue: statusString) ?? .upcoming`.

Today, a task with Firestore status `"dismissed"` or `"converted"` behaves differently by loader:

- Home does not fetch it because the one-shot query does not include those strings.
- The Tasks listener fetches every task doc; the mapper decodes either unknown string as `.upcoming`, and `TaskGrouping` puts it in To-Do. Thus it reappears in the Tasks tab instead of being terminal.

### Evidence

Enum, verbatim from `Peezy 4.0/MainInterface/Models/PeezyCard.swift:6-23`:

```swift
enum TaskStatus: String, Codable {
    case upcoming = "Upcoming"
    case inProgress = "InProgress"
    // Server-created tasks carry lowercase "pending" (functions/index.js). Rendered as
    // waiting — same treatment the removed MatchingInProgress case had (nothing ever
    // wrote that CamelCase string; verified Spec 03 Phase A).
    case pending = "pending"
    // submitWorkflowAnswers writes this snake-case string onto the task doc after a
    // vendor submission (functions/getWorkflowQualifying.js:~254). Same waiting
    // treatment as .pending. (Spec 04 named the workflowSubmissions-only string
    // "pending_matching" here — that one never lands on task docs; this is the
    // string that does. Cited in the Phase C report.)
    case matchingInProgress = "matching_in_progress"
    case userInProgress = "UserInProgress"
    case completed = "Completed"
    case snoozed = "Snoozed"
    case skipped = "Skipped"
}
```

Fallback, verbatim from `Peezy 4.0/Tasks/Store/PeezyCardFirestoreMapper.swift:12-13`:

```swift
let statusString = data["status"] as? String ?? "Upcoming"
let status = TaskStatus(rawValue: statusString) ?? .upcoming
```

Home query, verbatim from `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:232-237`:

```swift
let db = Firestore.firestore()
let snapshot = try await db.collection("users")
    .document(userId)
    .collection("tasks")
    .whereField("status", in: ["Upcoming", "pending", "matching_in_progress", "Snoozed", "InProgress", "UserInProgress"])
    .getDocuments()
```

Tasks grouping fallback destination, verbatim from `Peezy 4.0/Tasks/Store/TaskGrouping.swift:27-42`:

```swift
switch task.status {
case .completed:
    completed.append(task)
case .userInProgress:
    userInProgress.append(task)
case .inProgress, .pending, .matchingInProgress:
    // Retired human-handoff states are terminal. Normalize the
    // local presentation so old documents appear under Done.
    var completedTask = task
    completedTask.status = .completed
    completed.append(completedTask)
case .upcoming, .snoozed:
    todo.append(task)
case .skipped:
    continue
}
```

**VERDICT: MATCHES SPEC ASSUMPTION**

## 4. Flow engine paths, branches, `forEachRow`, and ending behavior

### Answer

Primary engine files are:

- `Peezy 4.0/Tasks/FlowEngine/FlowDefinition.swift` — Codable definition, branch, row-expansion, and definition store.
- `Peezy 4.0/Tasks/FlowEngine/FlowEngineView.swift` — rendering, navigation, persistence, and terminals.
- `Peezy 4.0/Tasks/FlowEngine/FlowExitControl.swift` and `FlowProgressSession.swift` — exit/persistence coordination.
- `functions/flowDefinitionsData.json` — seeded definition data.

There is no `endingAction` model or generic ending-action dispatcher at HEAD. A normal title/info/select step with no resolvable `next` reaches the guard in `advance` and does nothing. Existing flows avoid that by ending on one of two hard-coded terminal step kinds:

- `.summary` calls `submitAndComplete()`, submits answers through `WorkflowService`, clears flow state, then calls `onComplete()`.
- `.status` calls `concludeFlow`, clears flow state asynchronously, then calls the selected `onStatusAction` callback.

Branches are ordered `[FlowBranch]` entries with `value`, optional `when`, and `next`. `forEachRow` is a Boolean plus a `rowConfigs` dictionary keyed by row category; resolution clones the step once per matching stamped row and chains the clones.

### Evidence

Exact model structures, verbatim from `Peezy 4.0/Tasks/FlowEngine/FlowDefinition.swift:55-132`:

```swift
struct FlowStep: Codable, Equatable {
    var id: String
    let kind: FlowStepKind

    // Navigation. `next` is the default successor (also drives the depth-card
    // count walk); `branches` route by the answer just given, first match wins.
    var next: String?
    var branches: [FlowBranch]?

    /// TaskStage raw value written via TaskActionService.setStage on entry.
    var stage: String?

    // title
    var icon: String?

    // info
    var infoTitle: String?
    var body: String?          // also: summary default body
    var primaryLabel: String?

    // decision / select / businessSearch / confirmAddress / confirmDate
    var question: String?
    var timeSaved: String?     // decision only
    var options: [FlowOptionDef]?  // select only

    // businessSearch
    var placeholder: String?
    var searchHint: String?

    // confirmAddress
    var addressSource: String? // "current" | "new"
    var displayIcon: String?

    // summary
    var subtext: String?
    var bodyVariants: [FlowSummaryVariant]?

    // Row-generation (Spec 04 Phase B). Rows are stamped on the task doc as
    // `flowRows` by TaskGenerationService from the catalog's rowGeneration
    // config; definitions reference them three ways:
    /// Step included only when the task's rows contain this row id
    /// (e.g. the DMV registration section when hasVehicles).
    var requiresRow: String?
    /// Step expands into one chained instance per row (instance id
    /// "{rowId}.{stepId}" — also the answer key), config per row category.
    var forEachRow: Bool?
    var rowConfigs: [String: FlowRowConfig]?
    /// Summary-step labels for the {rowsList} substitution, keyed by row id.
    var rowLabels: [String: String]?
}

/// Per-category strings for a forEachRow step instance.
struct FlowRowConfig: Codable, Equatable {
    let question: String
    let placeholder: String
    let searchHint: String
}

/// One stamped row from the task doc's `flowRows` array.
struct FlowRow: Equatable {
    let id: String
    let category: String?

    init?(firestoreData: [String: Any]) {
        guard let id = firestoreData["id"] as? String else { return nil }
        self.id = id
        self.category = firestoreData["category"] as? String
    }
}

/// Branch taken when the step's answer equals `value` and every `when`
/// pair matches an already-recorded answer (first element). Ordered;
/// first satisfied branch wins.
struct FlowBranch: Codable, Equatable {
    let value: String
    var when: [String: String]?
    let next: String
}
```

Conditional branch data, verbatim from `functions/flowDefinitionsData.json:491-511`:

```json
{
  "id": "handling_find",
  "kind": "decision",
  "question": "Want current vet options near your new place, with sources?",
  "next": "find_summary",
  "branches": [
    {
      "value": "peezy",
      "next": "find_summary"
    },
    {
      "value": "self",
      "when": {
        "handling_cancel": "peezy"
      },
      "next": "find_summary"
    },
    {
      "value": "self",
      "next": "find_tip"
    }
  ]
}
```

`forEachRow` data, verbatim from `functions/flowDefinitionsData.json:970-992`:

```json
{
  "id": "provider",
  "kind": "businessSearch",
  "forEachRow": true,
  "rowConfigs": {
    "Doctor": {
      "question": "Who's your primary care doctor?",
      "placeholder": "Search for a doctor's office...",
      "searchHint": "doctor"
    },
    "Dentist": {
      "question": "Who's your dentist?",
      "placeholder": "Search for a dental office...",
      "searchHint": "dentist"
    },
    "Specialists": {
      "question": "Who's your specialist?",
      "placeholder": "Search for a specialist's office...",
      "searchHint": "medical specialist"
    }
  },
  "next": "summary"
}
```

`forEachRow` expansion, verbatim from `Peezy 4.0/Tasks/FlowEngine/FlowDefinition.swift:165-189`:

```swift
if step.forEachRow == true {
    var instances: [FlowStep] = rows.compactMap { row in
        guard let config = step.rowConfigs?[row.category ?? row.id] else { return nil }
        var instance = step
        instance.id = "\(row.id).\(step.id)"
        instance.question = config.question
        instance.placeholder = config.placeholder
        instance.searchHint = config.searchHint
        instance.forEachRow = nil
        instance.rowConfigs = nil
        return instance
    }
    guard !instances.isEmpty else {
        alias[step.id] = step.next ?? ""
        continue
    }
    for index in instances.indices {
        instances[index].next = index + 1 < instances.count
            ? instances[index + 1].id
            : step.next
    }
    alias[step.id] = instances[0].id
    result.append(contentsOf: instances)
    continue
}
```

Terminal rendering, verbatim from `Peezy 4.0/Tasks/FlowEngine/FlowEngineView.swift:262-283`:

```swift
case .summary:
    TaskFlowSummaryCard(
        taskTitle: definition.taskTitle,
        bodyText: actionSheetBody,
        primaryLabel: submissionError == nil ? "Done" : "Try again",
        subtext: submissionError ?? "Use this action sheet while you make the calls or complete the steps.",
        showBack: canGoBack,
        onPrimary: { submitAndComplete() },
        onBack: { goBack() }
    )
    .id("summary.\(submissionAttempt)")

case .status:
    TaskFlowStatusCard(
        taskTitle: definition.taskTitle,
        showBack: canGoBack,
        onLater: { concludeFlow { onStatusAction(.later) } },
        onInProgress: { concludeFlow { onStatusAction(.inProgress) } },
        onDone: { concludeFlow { onStatusAction(.done) } },
        onBack: { goBack() }
    )
```

Ordinary navigation end behavior, verbatim from `Peezy 4.0/Tasks/FlowEngine/FlowEngineView.swift:353-378`:

```swift
private func matchingBranch(for step: FlowStep, value: String) -> FlowBranch? {
    step.branches?.first { branch in
        branch.value == value && conditionsSatisfied(branch.when ?? [:])
    }
}

private func advance(from step: FlowStep, selected: String?) {
    let nextId: String?
    if let selected, let branch = matchingBranch(for: step, value: selected) {
        nextId = branch.next
    } else {
        nextId = step.next
    }
    guard let nextId, let nextStep = resolvedStep(withId: nextId) else { return }

    path.append(nextId)
    persistProgress()

    // Empty-taskId guard (Phase A validator finding): Firestore's
    // documentWithPath: raises an uncatchable ObjC exception on an empty
    // segment — the harness can run without a task doc.
    if !taskId.isEmpty, let stageRaw = nextStep.stage, let stage = TaskStage(rawValue: stageRaw) {
        let id = taskId
        Task { await actionService.setStage(taskId: id, stage: stage) }
    }
}
```

Ending handlers, verbatim from `Peezy 4.0/Tasks/FlowEngine/FlowEngineView.swift:490-496,541-581`:

```swift
/// Clears persisted flow state, then fires the terminal callback —
/// status-card exits (later / in progress / done).
private func concludeFlow(_ callback: @escaping () -> Void) {
    let id = taskId
    Task { await actionService.clearFlowState(taskId: id) }
    callback()
}

// MARK: - Submission (summary terminal)

private func submitAndComplete() {
    guard !isSubmitting else { return }
    isSubmitting = true
    submissionError = nil

    var workflowAnswers = WorkflowAnswers(workflowId: definition.workflowId)
    workflowAnswers.answers = answers

    let id = taskId
    Task {
        do {
            let service = WorkflowService()
            let response = try await service.submitAnswers(
                workflowId: definition.workflowId,
                answers: workflowAnswers,
                userId: userId
            )
            guard response.success else {
                await MainActor.run {
                    isSubmitting = false
                    submissionError = "Couldn't save your answers. Check your connection, then try again."
                    submissionAttempt += 1
                }
                return
            }
            await actionService.clearFlowState(taskId: id)
            await MainActor.run {
                isSubmitting = false
                onComplete()
            }
        } catch {
            await MainActor.run {
                isSubmitting = false
                submissionError = "Couldn't save your answers. Check your connection, then try again."
                submissionAttempt += 1
            }
        }
    }
}
```

**VERDICT: CONTRADICTS: branches and `forEachRow` match, but HEAD has no generic ending-action field, handler, or existing “second action type” seam. Terminal behavior is hard-coded by step kind, and a last nonterminal content step currently does nothing. Phase 4 must define where the new ending schema is stored and invoke it from the no-next path (or add a terminal step kind).**

## 5. `getWorkflowQualifying.js` response and `knownAnswers`

### Answer

There are four current response routes:

1. Firestore definition hit: `{ flowDefinition: definitionDoc.data() }`.
2. Legacy vendor definition: returns `WORKFLOW_QUALIFYING[workflowId]` verbatim.
3. Mini assessment: returns the explicitly mapped object below.
4. Unknown workflow: returns the generic object below.

No route returns `knownAnswers` today.

For the callable route, the map belongs next to `flowDefinition` immediately before `functions/getWorkflowQualifying.js:43`, after authenticating with `request.auth.uid` and reading `users/{uid}/moveAnswers/answers`.

However, the normal client path at HEAD reads `flowDefinitions` directly from Firestore and never calls this callable. Even on callable fallback, `FlowDefinitionStore.definitionFromCallable` extracts only `data["flowDefinition"]` and returns only `FlowDefinition`, discarding sibling response fields. Therefore adding `knownAnswers` to the server response alone cannot reach the engine; the client definition-loading return type/path must also change.

### Evidence

Firestore and vendor routes, verbatim from `functions/getWorkflowQualifying.js:33-52`:

```js
// Firestore-first (Spec 04): the flowDefinitions collection is the
// definition source for the config-driven FlowEngine. Served through
// this callable because deployed rules grant no direct client read.
// Adding a vertical stays a Firestore write.
try {
  const definitionDoc = await admin.firestore()
    .collection('flowDefinitions')
    .doc(workflowId)
    .get();
  if (definitionDoc.exists) {
    return { flowDefinition: definitionDoc.data() };
  }
} catch (err) {
  console.error(`flowDefinitions lookup failed for ${workflowId}:`, err.message);
}

// Check vendor workflows first
if (WORKFLOW_QUALIFYING[workflowId]) {
  return WORKFLOW_QUALIFYING[workflowId];
}
```

Mini-assessment response, verbatim from `functions/getWorkflowQualifying.js:54-75`:

```js
// Check mini-assessment workflows
if (MINI_ASSESSMENT_WORKFLOWS[workflowId]) {
  const miniWorkflow = MINI_ASSESSMENT_WORKFLOWS[workflowId];

  // Convert to the standard format expected by iOS
  return {
    workflowId: miniWorkflow.id,
    title: miniWorkflow.title,
    intro: miniWorkflow.intro,
    questions: miniWorkflow.questions.map(q => ({
      id: q.id,
      question: q.question,
      icon: q.icon,
      options: null,  // Mini-assessments use yes/no, not multi-choice
      textEntryPrompt: q.textEntryPrompt || null,
      textEntryPlaceholder: q.textEntryPlaceholder || null,
      allowMultiple: q.allowMultiple || false
    })),
    recap: null,  // Mini-assessments don't use recap
    review: miniWorkflow.review,
    taskTemplate: miniWorkflow.taskTemplate
  };
}
```

Generic response, verbatim from `functions/getWorkflowQualifying.js:117-130`:

```js
return {
  workflowId,
  intro: {
    title: "Quick questions",
    subtitle: "Just a few things to help us get started."
  },
  questions: genericQuestions,
  questionCount: genericQuestions.length,
  recap: {
    title: "Got it.",
    closing: "We'll be in touch shortly.",
    button: "Submit"
  }
};
```

Direct-read primary path and callable fallback, verbatim from `Peezy 4.0/Tasks/FlowEngine/FlowDefinition.swift:240-279`:

```swift
/// Returns the cached definition or reads it directly from Firestore.
/// Returns nil when the server has no definition for this workflowId —
/// the router renders the coming-right-up card in that case.
func definition(for workflowId: String) async -> FlowDefinition? {
    if let hit = cache[workflowId] { return hit }
    guard !workflowId.isEmpty else { return nil }

    do {
        let snapshot = try await Firestore.firestore()
            .collection("flowDefinitions")
            .document(workflowId)
            .getDocument()
        guard snapshot.exists else {
            print("⚠️ Flow definition missing from Firestore; using callable fallback: \(workflowId)")
            return await definitionFromCallable(workflowId: workflowId)
        }
        let definition = try snapshot.data(as: FlowDefinition.self)
        cache[workflowId] = definition
        print("✅ Flow definition direct Firestore read: \(workflowId)")
        return definition
    } catch {
        print("⚠️ Flow definition direct read failed; using callable fallback for \(workflowId): \(error.localizedDescription)")
    }

    return await definitionFromCallable(workflowId: workflowId)
}

private func definitionFromCallable(workflowId: String) async -> FlowDefinition? {
    do {
        let callable = Functions.functions().httpsCallable("getWorkflowQualifying")
        let result = try await callable.call(["workflowId": workflowId])
        guard let data = result.data as? [String: Any],
              let definitionDict = data["flowDefinition"] as? [String: Any] else {
            return nil
        }
        let json = try JSONSerialization.data(withJSONObject: definitionDict)
        let definition = try JSONDecoder().decode(FlowDefinition.self, from: json)
        cache[workflowId] = definition
        print("⚠️ Flow definition callable fallback used: \(workflowId)")
        return definition
```

**VERDICT: CONTRADICTS: the spec says conversation entry receives definition plus `knownAnswers` from `getWorkflowQualifying`, but HEAD's primary path is a direct Firestore read, and the fallback parser discards every sibling field. Server-only response modification will not deliver answer memory to the engine.**

## 6. `TaskActionService` completion path and post-complete hook

### Answer

The service method is `markTaskCompleted(_:)`. The safe sequential insertion point for `onCompleteSpawns` is after the awaited `updateData` succeeds and before the method returns, at `TaskActionService.swift:85`. Putting the hook after a Home call site would be racy because Home launches `markTaskCompleted` in an un-awaited `Task`.

There is also a separate Tasks-tab completion write in `TasksStore.dispatch(.markComplete)`. It does not use `TaskActionService`, so a hook added only to `markTaskCompleted` would be skipped when a user marks a task complete from the Tasks tab.

### Evidence

Complete service path, verbatim from `Peezy 4.0/MainInterface/Models/TaskActionService.swift:79-88`:

```swift
func markTaskCompleted(_ task: PeezyCard) async {
    guard let userId = Auth.auth().currentUser?.uid else { return }
    let db = Firestore.firestore()
    do {
        try await db.collection("users").document(userId).collection("tasks")
            .document(task.id).updateData(["status": "Completed", "completedAt": FieldValue.serverTimestamp()])
    } catch {
        print("⚠️ Failed to mark task completed: \(error.localizedDescription)")
    }
}
```

Home simple-task call site, verbatim from `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:366-378`:

```swift
// MARK: - Complete Simple Task

func completeCurrentTask() {
    guard let task = currentTask else { return }
    Task { await actionService.markTaskCompleted(task) }
    PeezyHaptics.taskComplete()
    completedThisSession += 1
    recordDoseProgress(completedTask: true)
    allActiveTasks.removeAll { $0.id == task.id }
    currentTask = nil
    isFocusedTask = false
    advanceAfterTask()
}
```

Home flow completion call site, verbatim from `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:405-421`:

```swift
// MARK: - Complete Task Flow

func completeTaskFlow() {
    guard let task = currentTask else {
        showTaskFlow = false
        return
    }

    Task { await actionService.markTaskCompleted(task) }

    PeezyHaptics.taskComplete()
    completedThisSession += 1
    recordDoseProgress(completedTask: true)
    allActiveTasks.removeAll { $0.id == task.id }

    finishFlowAndDeferAdvance()
}
```

Independent Tasks-tab completion path, verbatim from `Peezy 4.0/Tasks/Store/TasksStore.swift:73-90`:

```swift
case .markComplete(let card):
    await performWrite(
        taskId: card.id,
        optimistic: { $0.status = .completed; $0.completedAt = Date() },
        revertStatus: card.status,
        revertCompletedAt: card.completedAt,
        firestoreUpdate: [
            "status": "Completed",
            "completedAt": FieldValue.serverTimestamp()
        ],
        onSuccess: {
            ConfettiBus.shared.fire()
            PeezyHaptics.success()
        },
        onFailure: {
            ToastManager.shared.show("Couldn't mark complete", style: .error)
        }
    )
```

**VERDICT: CONTRADICTS: completion is not centralized in `TaskActionService`; the Tasks tab writes completion directly. A post-complete spawn hook added only to `markTaskCompleted` would miss that live path.**

## 7. Card rendering switch and nudge substitution points

### Answer

The deleted `PeezyTaskCardStackView`/`PeezyTaskCardView` referenced by the `eab4193` history no longer exists. There is no current generic card renderer that switches `PeezyCard.CardType` from greeting to task.

Home switches on `PeezyHomeViewModel.HomeState`: greetings render inline card properties, while `.activeTask` renders a loading placeholder and the real task UI is presented through `TaskFlowRouter` in a `fullScreenCover`. `startNextTask()` sets the flow id and immediately opens that cover.

The Tasks tab separately renders every item through `TasksList.row`, which unconditionally creates `TaskRow`. A nudge visible in both surfaces therefore needs two explicit routing/substitution decisions:

1. Home: branch on `currentTask.tier` before the automatic `fullScreenCover` flow launch, and render `NudgeCardView` for the nudge case.
2. Tasks list: branch in `TasksList.row(task:section:)` between `NudgeCardView` and `TaskRow`, or explicitly decide that list rows remain `TaskRow` and only Home receives the new card.

Named style reuse points:

- Home/flow card container: `PeezyCardChrome` / `.peezyCardChrome()` (`PeezyCardChrome.swift:7-35`).
- Existing Yes/No card composition: `TaskFlowDecisionCard` (`TaskFlowDecisionCard.swift:15-103`), including its deep-ink primary button and muted plain secondary button.
- Shared primary CTA: `PeezyAssessmentButton` with `PeezyPressButtonStyle` (`PeezyAssessmentButton.swift:5-82`).
- Tasks-list row container, if the nudge is rendered inline there: `TaskRow` and its `rowBackground` modifier chain (`TaskRow.swift:14-50`).

### Evidence

Home state switch, verbatim from `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift:69-95`:

```swift
VStack {
    Spacer()

    Group {
        switch viewModel.state {
        case .loading:
            LoadingView()
        case .firstTimeWelcome:
            firstTimeWelcomeCard
        case .dailyGreeting:
            dailyGreetingCard
        case .returningMidDay:
            returningMidDayCard
        case .activeTask:
            activeTaskContent
        case .dailyComplete, .allComplete:
            dailyCompleteEmptyState
        }
    }
    // Card-exit feel (Spec 03 Phase D): completed card slides out,
    // next state fades in. Existing transitions only — no new deps.
    .id(viewModel.state)
    .transition(reduceMotion ? .opacity : .asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.97)),
        removal: .move(edge: .leading).combined(with: .opacity)
    ))
    .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85), value: viewModel.state)

    Spacer()
}
```

Task presentation, verbatim from `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift:134-159`:

```swift
.fullScreenCover(isPresented: showTaskFlowBinding, onDismiss: {
    viewModel.cleanupTaskFlow()
    onTaskFlowDismissed()
}) {
    if let flowId = viewModel.taskFlowWorkflowId {
        TaskFlowRouter.flow(
            for: flowId,
            userId: Auth.auth().currentUser?.uid ?? "",
            taskId: viewModel.currentTask?.id,
            userState: viewModel.userState,
            onComplete: { viewModel.completeTaskFlow() },
            onDismiss: {
                viewModel.dismissTaskFlow()
            },
            onStatusAction: { action in
                switch action {
                case .done: viewModel.statusActionDone()
                case .inProgress: viewModel.statusActionInProgress()
                case .later: viewModel.statusActionLater()
                case .dismissedPermanently: viewModel.statusActionDismissedPermanently()
                case .submittedToPeezy: viewModel.statusActionSubmittedToPeezy()
                }
            }
        )
    }
}
```

Automatic launch, verbatim from `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:310-323`:

```swift
func startNextTask() {
    guard !taskQueue.isEmpty else {
        if allActiveTasks.isEmpty { state = .allComplete }
        else { state = .dailyComplete }
        return
    }

    let task = taskQueue.removeFirst()
    currentTask = task

    taskFlowWorkflowId = flowId(for: task)
    showTaskFlow = true
    state = .activeTask
}
```

Tasks-list row substitution point, verbatim from `Peezy 4.0/Tasks/Views/TasksList.swift:70-81`:

```swift
private func row(task: PeezyCard, section: TaskSection) -> some View {
    // The .id(rowIdentity) workaround for the old id-only PeezyCard
    // Equatable is gone (Spec 04 Phase C) — memberwise == (Spec 03 Phase A)
    // repaints rows on field changes without forced re-identity.
    TaskRow(
        task: task,
        section: section,
        isExpanded: expandedTaskId == task.id,
        onExpandToggle: { toggle(task.id) },
        onAction: onAction
    )
}
```

Standard Tasks row modifier chain, verbatim from `Peezy 4.0/Tasks/Views/TaskRow.swift:14-50`:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 0) {
        TaskRowHeader(
            task: task,
            isExpanded: isExpanded,
            section: section,
            onTap: onExpandToggle
        )

        if isExpanded {
            TaskRowButtons(
                layout: TaskRowButtons.layout(for: task, section: section),
                onAction: onAction
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
    .background(rowBackground)
    .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 4)
    .opacity(section == .done ? 0.7 : 1.0)
    .padding(.vertical, 8)
}

private var rowBackground: some View {
    ZStack {
        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusLarge, style: .continuous)
            .fill(.regularMaterial)
        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusLarge, style: .continuous)
            .fill(Color.white.opacity(0.15))
    }
    .overlay(
        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusLarge, style: .continuous)
            .stroke(Color.black.opacity(0.05), lineWidth: 1)
    )
}
```

Unified Home card chrome, verbatim from `Peezy 4.0/Assessment/PeezyTheme/PeezyCardChrome.swift:7-35`:

```swift
struct PeezyCardChrome: ViewModifier {
    var width: CGFloat = 340
    var maxHeight: CGFloat = 500

    func body(content: Content) -> some View {
        ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .foregroundStyle(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.white.opacity(0.7))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    .padding(1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 15)

            content
        }
        .frame(width: width)
        .frame(maxHeight: maxHeight)
    }
}

extension View {
    func peezyCardChrome(width: CGFloat = 340, maxHeight: CGFloat = 500) -> some View {
        modifier(PeezyCardChrome(width: width, maxHeight: maxHeight))
    }
}
```

**VERDICT: CONTRADICTS: the assumed live greeting-vs-task card-stack switch was deleted in `eab4193`. HEAD has a Home state switch plus full-screen flow routing and a separate Tasks-list `TaskRow` path, so Phase 3 needs explicit substitution points for both surfaces rather than one “stack switch.”**

## 8. `TaskGenerationService` due-date computation

### Answer

Due date is computed inside each catalog-row loop immediately after conditions pass. It currently uses `urgencyPercentage` and `calculateDueDate(moveDate:urgencyPercentage:)`, not a row `dateRule`.

There are two generation paths and therefore two insertion sites:

1. Initial generation: `TaskGenerationService.swift:78-85`.
2. Add-only incremental generation: `TaskGenerationService.swift:204-214`.

A per-row `dateRule` can slot in by replacing the urgency-based call with a helper that reads the current row's `dateRule`. For a nudge whose due date depends on its spawn target's original rule, the catalog snapshot must first be indexed by task/catalog id so the nudge row can resolve `nudge.spawnsId`, compute the target date, and subtract `leadDays`. The identical logic must be used in both loops.

### Evidence

Initial-generation seam, verbatim from `Peezy 4.0/Assessment/AssessmentModels/TaskGenerationService.swift:75-85`:

```swift
// Evaluate conditions against user's assessment
let conditionPassed = TaskConditionParser.evaluateConditions(conditions, against: assessment)

if conditionPassed {
    // Calculate due date based on urgency
    let urgencyPercentage = (taskData["urgencyPercentage"] as? NSNumber)?.intValue ?? 50

    let dueDate = calculateDueDate(
        moveDate: moveDate,
        urgencyPercentage: urgencyPercentage
    )
```

The computed date is written into each user task at `TaskGenerationService.swift:93-112`:

```swift
// Build user task document
var userTask: [String: Any] = [
    "id": document.documentID,              // e.g., "BOOK_MOVERS"
    "taskId": taskData["taskId"] ?? document.documentID,
    "title": taskData["title"] ?? "",
    "desc": taskData["desc"] ?? "",
    "category": taskData["category"] ?? "custom",
    "actionCategory": taskData["actionCategory"] ?? "",
    "actionType": taskData["actionType"] ?? "off-app",
    "taskType": taskData["taskType"] as? String ?? "provide_info",
    "urgencyPercentage": urgencyPercentage,
    "estHours": taskData["estHours"] ?? 0,
    "tips": taskData["tips"] ?? "",
    "whyNeeded": taskData["whyNeeded"] ?? "",
    "conditions": taskData["conditions"] ?? [:],
    "dueDate": Timestamp(date: dueDate),
    "status": "Upcoming",
    "userId": userId,
    "createdAt": Timestamp(date: Date()),
]
```

Incremental-generation seam, verbatim from `Peezy 4.0/Assessment/AssessmentModels/TaskGenerationService.swift:204-214`:

```swift
for document in catalogSnapshot.documents {
    guard !existingIds.contains(document.documentID) else { continue }
    if document.documentID == "BOX_RETURN", !hasSuppliesKitSubmission {
        continue
    }
    let taskData = document.data()
    let conditions = taskData["conditions"] as? [String: Any]
    guard TaskConditionParser.evaluateConditions(conditions, against: assessment) else { continue }

    let urgencyPercentage = (taskData["urgencyPercentage"] as? NSNumber)?.intValue ?? 50
    let dueDate = calculateDueDate(moveDate: moveDate, urgencyPercentage: urgencyPercentage)
```

Current helper, verbatim from `Peezy 4.0/Assessment/AssessmentModels/TaskGenerationService.swift:329-360`:

```swift
// MARK: - Due Date Calculation

/// Calculates task due date based on urgency percentage
/// Higher percentage (90+) = MORE urgent = do it EARLY (within first 10% of timeline)
/// Lower percentage (10) = LESS urgent = can wait (90% into timeline)
/// - Parameters:
///   - moveDate: User's move date
///   - urgencyPercentage: Task urgency (1-99)
/// - Returns: Calculated due date
private func calculateDueDate(
    moveDate: Date,
    urgencyPercentage: Int
) -> Date {
    let today = Calendar.current.startOfDay(for: DateProvider.shared.now)
    let moveDateStart = Calendar.current.startOfDay(for: moveDate)
    let totalDays = Calendar.current.dateComponents([.day], from: today, to: moveDateStart).day ?? 0

    // Guard against past/same-day moves
    guard totalDays > 0 else { return today }

    // HIGH urgency (90+) = do it EARLY (within first 10% of timeline)
    // LOW urgency (10) = can wait (90% into timeline)
    let daysFromNow = Double(totalDays) * (1.0 - Double(urgencyPercentage) / 100.0)
    var dueDate = Calendar.current.date(byAdding: .day, value: Int(daysFromNow), to: today) ?? moveDate

    // Never schedule in the past
    if dueDate < today {
        dueDate = today
    }

    return dueDate
}
```

**VERDICT: MATCHES SPEC ASSUMPTION**

## 9. Conventions-v2 facts at HEAD

### Answer

- **Two live task loaders only: confirmed.** Home uses the one-shot query and shared mapper. `TasksStore` owns the live listener and shared mapper. `PeezyStackViewModel` still exists as orphan source, but exhaustive symbol search finds no construction/use outside itself and one stale comment in `PeezyMainContainer`; it is not a live path.
- **No `TimelineService`: confirmed.** No file named `TimelineService.swift` exists and no Swift symbol use exists; only stale comments/docs mention it.
- **Four app tabs: confirmed.** `PeezyTab` has Home, Tasks, Chat, Settings.
- **Deployed-rules default-deny posture unchanged since `da1916e`: false.** Five commits after `da1916e` changed `firestore.rules`. The live ruleset was fetched read-only through the Firebase Rules REST API and was created `2026-08-04T19:18:22.557215Z`; it includes authenticated reads for `flowDefinitions`, `appConfig`, `vendors`, `providerDirectory`, and `ispPlans`. In particular, `flowDefinitions` is no longer default-denied.

The current conventions file itself records the correction: Spec 04 closed with default-deny, then Spec 05 reconciled/deployed authenticated `flowDefinitions` read and moved the client to direct reads.

### Evidence

Live loader wiring, verbatim from `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift:21-22,91-102`:

```swift
// Tasks tab listener-backed store — lifecycle owned here so it spans tab switches
private let tasksStore = TasksStore.shared

.onAppear {
    chatService.startListening()
    if let uid = userState?.userId {
        tasksStore.start(userId: uid)
    }
}
.onChange(of: userState?.userId) { _, newId in
    if let newId {
        tasksStore.start(userId: newId)
    } else {
        tasksStore.stop()
    }
}
```

The two loader implementations are evidenced in Item 2 at:

- `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:209-306`
- `Peezy 4.0/Tasks/Store/TasksStore.swift:31-55`
- `Peezy 4.0/Tasks/Store/PeezyCardFirestoreMapper.swift:5-78`

Exhaustive live-symbol search result for the orphan stack model:

```text
Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift:18:    // Timeline still uses PeezyStackViewModel for its data loading
Peezy 4.0/MainInterface/Models/PeezyStackViewModel.swift:6:// MARK: - PeezyStackViewModel
Peezy 4.0/MainInterface/Models/PeezyStackViewModel.swift:8:final class PeezyStackViewModel {
```

No source file matched `TimelineService.swift`; Swift-tree matches are comments only:

```text
Peezy 4.0/MainInterface/Models/PeezyStackViewModel.swift:71:    // MARK: - Direct Firestore Loading (matches TimelineService)
Peezy 4.0/MainInterface/Models/PeezyStackViewModel.swift:88:            // Query active tasks - same filter as TimelineService
Peezy 4.0/MainInterface/Models/PeezyStackViewModel.swift:112:                // Parse priority (same logic as TimelineService)
Peezy 4.0/MainInterface/Models/PeezyStackViewModel.swift:198:    /// Color name for priority (matches TimelineService)
```

Four tabs, verbatim from `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift:122-128`:

```swift
// MARK: - Tab Enum

enum PeezyTab: String, CaseIterable {
    case home
    case tasks
    case chat
    case settings
```

Rules changes after `da1916e`, from read-only `git log da1916e..HEAD -- firestore.rules`:

```text
4baf203 2026-08-04T13:50:21-05:00 day4: fix — gift date decoding, appConfig rules, resolver copy
fe1d37d 2026-07-27T03:39:56-05:00 Add citation-safe provider resolver
51f6932 2026-07-25T18:01:07-05:00 Spec 05 Phase A: add mover vendor rate cards
5b06b5a 2026-07-25T16:55:14-05:00 Spec 05 Phase 0: reconcile rules and housekeeping
e57e562 2026-07-25T04:15:01-05:00 Spec 01 Phase 2b: identity write path + firestore.rules
```

Current checked-in rule, verbatim from `firestore.rules:66-70`:

```text
// Config-driven workflows are readable by signed-in clients only.
// Definitions remain backend-owned: no client writes.
match /flowDefinitions/{document=**} {
  allow read: if request.auth != null;
}
```

Read-only Firebase Rules REST result:

```text
RELEASE_NAME:projects/peezy-1ecrdl/releases/cloud.firestore
RULESET_NAME:projects/peezy-1ecrdl/rulesets/b7a1659a-5800-4e60-a635-ac0dbba1a015
RULESET_CREATE_TIME:2026-08-04T19:18:22.557215Z
```

The live fetched ruleset contains the same `flowDefinitions` block verbatim:

```text
// Config-driven workflows are readable by signed-in clients only.
// Definitions remain backend-owned: no client writes.
match /flowDefinitions/{document=**} {
  allow read: if request.auth != null;
}
```

The repository's current ground-truth correction is `peezy-conventions-v2.md:157-159,168-171`:

```text
## Corrections from Spec 05 run (2026-07-25)

- **Flow definitions now load directly.** Signed-in clients read `flowDefinitions` from Firestore first; the getWorkflowQualifying callable is retained as a one-release fallback.

## Corrections from Spec 04 run (2026-07-25)

- **At the Spec 04 close, deployed rules were default-deny for new collections.** flowDefinitions therefore used the getWorkflowQualifying callable. Spec 05 Phase 0 subsequently reconciled the waitlist rule, added the authenticated read, and moved the client to direct reads with a callable fallback.
```

Current catalog/loader correction, verbatim from `peezy-conventions-v2.md:9-21`:

~~~~text
2. **Four tabs, not three:** Home / Tasks / Chat / Settings. Chat = SupportChatView (live, T06-tested, Firestore-backed support chat). The *AI* chat was removed; support chat was not.
3. **Catalog v2 is 47 tasks (Spec 08).** actionType: workflow=32, off-app=8, in-app=6, in-app-inventory=1. taskType: survey=34, provide_info=13. 35 rows carry a workflowId, including scan_inventory. `MOVE_CHECKIN` and `BOX_RETURN` are the two post-move additions. `BUY_PACKING_SUPPLIES` remains retired; the Spec 06 `PACKING_*` tasks are generated per-user and catalog-external. Flow content lives in 25 Firestore `flowDefinitions` documents.
4. **WorkflowManager.swift does not exist.** TimelineService is dead (zero callers, deleted in cleanup). The live loading paths are exactly two: PeezyHomeViewModel.loadTasks() (Home, one-shot) and TasksStore listener → PeezyCardFirestoreMapper.card() (Tasks tab).

## Live data paths (the only two)

```
Home:      PeezyHomeViewModel.loadTasks() :219 → mapper :257  (one-shot query)
Tasks tab: TasksStore listener :51 → PeezyCardFirestoreMapper.card() :4  (snapshot)
```
Single-decoder rule (LE-025/LE-031 successor): both loaders call
`PeezyCardFirestoreMapper.card()`. Never add or re-inline a second
Firestore→PeezyCard decoder.
~~~~

**VERDICT: CONTRADICTS: two loaders, no `TimelineService`, and four tabs still hold, but the deployed-rules posture did change after `da1916e`; authenticated `flowDefinitions` reads are live. The spec's 56-row current-state baseline is also stale at the 47-row HEAD.**

## Gate summary

Items 1, 2, 4, 5, 6, 7, and 9 contradict at least one operative spec assumption. Per Phase 0's gate language, stop before Phase 1 and revise the spec against HEAD.
