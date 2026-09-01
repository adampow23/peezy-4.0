import SwiftUI
import FirebaseFirestore

// MARK: - Task Status

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
    // Terminal — nudge lifecycle (Spec 09 Phase 3). A dismissed nudge never
    // resurfaces; a converted nudge is replaced by its spawned real task.
    case dismissed = "Dismissed"
    case converted = "Converted"
}

// MARK: - PeezyCard Model
/// Enhanced card model that connects to Firebase backend and task system
struct PeezyCard: Identifiable, Equatable, Codable {
    /// Firestore-safe recursive value used by disposition trigger payloads.
    /// Keeping this typed prevents UI code from depending on untyped SDK data.
    indirect enum FirestoreValue: Codable, Equatable {
        case null
        case bool(Bool)
        case int(Int64)
        case double(Double)
        case string(String)
        case date(Date)
        case array([FirestoreValue])
        case map([String: FirestoreValue])
    }

    struct DispositionContract: Codable, Equatable {
        enum Disposition: String, Codable {
            case completed = "COMPLETED"
            case notApplicable = "NOT_APPLICABLE"
            case userActionTracked = "USER_ACTION_TRACKED"
            case waitingOnExternal = "WAITING_ON_EXTERNAL"
            case deferred = "DEFERRED"
            case supportActive = "SUPPORT_ACTIVE"
        }

        enum TerminalKind: String, Codable {
            case notApplicable = "not_applicable"
            case retired
            case superseded
        }

        struct Trigger: Codable, Equatable {
            enum Kind: String, Codable { case date, event }

            var kind: Kind
            var at: Date?
            var eventName: String?
            var canonicalKey: String?
            var afterSourceVersion: Int?
            var payload: [String: FirestoreValue]?
            var fired: Bool

            enum CodingKeys: String, CodingKey {
                case kind, at, payload, fired
                case eventName = "event_name"
                case canonicalKey = "canonical_key"
                case afterSourceVersion = "after_source_version"
            }

            init(
                kind: Kind,
                at: Date? = nil,
                eventName: String? = nil,
                canonicalKey: String? = nil,
                afterSourceVersion: Int? = nil,
                payload: [String: FirestoreValue]? = nil,
                fired: Bool = false
            ) {
                self.kind = kind
                self.at = at
                self.eventName = eventName
                self.canonicalKey = canonicalKey
                self.afterSourceVersion = afterSourceVersion
                self.payload = payload
                self.fired = fired
            }
        }

        var disposition: Disposition?
        var terminalKind: TerminalKind?
        var owner: String?
        var nextAction: String?
        var nextTrigger: Trigger?
        var resumeDestination: String?
        var visibleStatusCopy: String?
        var profileVersion: Int?
        var externalSubmission: Bool
        var supersededBy: String?

        enum CodingKeys: String, CodingKey {
            case disposition, owner
            case terminalKind = "terminal_kind"
            case nextAction = "next_action"
            case nextTrigger = "next_trigger"
            case resumeDestination = "resume_destination"
            case visibleStatusCopy = "visible_status_copy"
            case profileVersion = "profile_version"
            case externalSubmission = "external_submission"
            case supersededBy = "superseded_by"
        }

        init(
            disposition: Disposition? = nil,
            terminalKind: TerminalKind? = nil,
            owner: String? = nil,
            nextAction: String? = nil,
            nextTrigger: Trigger? = nil,
            resumeDestination: String? = nil,
            visibleStatusCopy: String? = nil,
            profileVersion: Int? = nil,
            externalSubmission: Bool = false,
            supersededBy: String? = nil
        ) {
            self.disposition = disposition
            self.terminalKind = terminalKind
            self.owner = owner
            self.nextAction = nextAction
            self.nextTrigger = nextTrigger
            self.resumeDestination = resumeDestination
            self.visibleStatusCopy = visibleStatusCopy
            self.profileVersion = profileVersion
            self.externalSubmission = externalSubmission
            self.supersededBy = supersededBy
        }
    }

    let id: String
    let type: CardType
    let title: String
    let subtitle: String
    let colorName: String // Codable-friendly color storage

    // Task connection (optional - not all cards link to tasks)
    var taskId: String?
    var workflowId: String?

    // Vendor connection (for vendor recommendation cards)
    var vendorCategory: String?
    var vendorId: String?

    // Action tracking
    var createdAt: Date
    var priority: Priority

    // Task status and snooze support
    var status: TaskStatus
    var dueDate: Date?
    var snoozedUntil: Date?
    var lastSnoozedAt: Date?

    // UserInProgress support (user-initiated "I'm on it")
    var userInProgressDate: Date?
    var userInProgressReturnDate: Date?

    // Completion timestamp — set when task transitions to .completed
    var completedAt: Date?

    // Daily Dose — task urgency from catalog (0–99, higher = more urgent)
    var urgencyPercentage: Int?

    // Optional post-move dose gate from the catalog. The card stays in the
    // complete Tasks plan, but cannot join a frozen dose before moveDate + n.
    var surfaceAfterDaysPastMove: Int?

    // Intro card briefing message (warm, conversational summary)
    var briefingMessage: String?

    // Task category for icon mapping (e.g. "moving", "utilities", "packing")
    var taskCategory: String?

    // Self-service flag — user handles it themselves (no Peezy concierge option)
    var selfServiceOnly: Bool = false

    // Action type from catalog (e.g. "off-app", "in-app-inventory", "workflow")
    var actionType: String?

    // Task type from catalog (e.g. "provide_info", "schedule", "purchase")
    var taskType: String?

    // Catalog tips (actionable advice for self-service tasks)
    var tips: String?

    // Catalog whyNeeded (explains why this task matters)
    var whyNeeded: String?

    // Estimated effort: Peezy-handled time string and self-service hours
    var estPeezy: String?
    var estHours: Double?

    // Workflow spine stage (persisted; nil = notStarted for workflow tasks)
    var stage: TaskStage?

    // Per-type payload (shells until Specs 04–05; nil = no payload)
    var payload: CardPayload?

    // Catalog tier (Spec 09): "task" | "nudge" | "conversation". Nudge cards
    // are Home-only and carry their prompt + spawn target.
    var tier: String = "task"
    var nudgePrompt: String?
    var nudgeSpawnsId: String?

    // Spawn metadata (Spec 09): provenance + completion-spawn list.
    var spawnedFrom: SpawnedFrom?
    var onCompleteSpawns: [CompletionSpawn] = []

    // Task-surface flags from the catalog (Spec 09).
    var notesEnabled: Bool = false
    var quoteTracker: String = "none"

    /// Presence makes lifecycle state server-owned. UI projection deliberately
    /// keys off presence, including malformed maps, so malformed state fails
    /// safe instead of falling back to writable legacy controls.
    var dispositionContract: DispositionContract?

    // MARK: - Spawn Metadata Types (Spec 09)

    /// Provenance stamped by the spawnTasks callable — which nudge,
    /// conversation, or completion produced this task doc.
    struct SpawnedFrom: Codable, Equatable {
        let kind: String
        let id: String
    }

    /// Per-spawn date override: `{anchor:"moveDate", offsetDays:N}`.
    struct SpawnDateRule: Codable, Equatable {
        let anchor: String
        let offsetDays: Int
    }

    struct CompletionSpawn: Codable, Equatable {
        let id: String
        var dateRule: SpawnDateRule?

        init(id: String, dateRule: SpawnDateRule? = nil) {
            self.id = id
            self.dateRule = dateRule
        }
    }

    // MARK: - Card Types
    enum CardType: String, Codable {
        case intro          // "Good morning, 3 updates ready"
        case task           // Standard task decision
        case vendor         // Vendor recommendation
        case update         // Status update / notification
        case milestone      // Celebration / progress marker
        case question       // Peezy asking for info
    }
    
    enum Priority: Int, Codable, Comparable {
        case low = 0
        case normal = 1
        case high = 2
        case urgent = 3
        
        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    // MARK: - Computed Properties
    var color: Color {
        switch colorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .white
        }
    }
    
    var icon: String {
        switch type {
        case .intro: return "sparkles"
        case .task: return "circle.grid.2x2.fill"
        case .vendor: return "building.2.fill"
        case .update: return "bell.fill"
        case .milestone: return "star.fill"
        case .question: return "questionmark.circle.fill"
        }
    }
    
    var headerLabel: String {
        switch type {
        case .intro: return "UPDATES"
        case .task: return "DECISION"
        case .vendor: return "RECOMMENDATION"
        case .update: return "UPDATE"
        case .milestone: return "MILESTONE"
        case .question: return "QUESTION"
        }
    }
    
    // What happens on swipe right
    var doItLabel: String {
        switch type {
        case .intro: return "Start"
        case .task: return "Do It"
        case .vendor: return "Book"
        case .update: return "Got It"
        case .milestone: return "Nice!"
        case .question: return "Yes"
        }
    }
    
    // What happens on swipe left
    var laterLabel: String {
        switch type {
        case .intro: return "Skip"
        case .task: return "Later"
        case .vendor: return "Skip"
        case .update: return "Dismiss"
        case .milestone: return "Dismiss"
        case .question: return "No"
        }
    }
    
    // MARK: - Snooze Support

    /// Whether this card can be snoozed (must have taskId and be a task type)
    var canSnooze: Bool {
        guard dispositionContract == nil else { return false }
        guard taskId != nil else { return false }
        guard status != .completed else { return false }
        switch type {
        case .task, .vendor:
            return true
        case .intro, .milestone, .update, .question:
            return false
        }
    }

    /// Whether this card is currently snoozed
    var isSnoozed: Bool {
        guard let snoozedUntil = snoozedUntil else { return false }
        return snoozedUntil > DateProvider.shared.now
    }

    /// Capture modality for this card, if it opens a capture path
    /// (CaptureRegistry — Spec 04 Phase C shim).
    var captureRegistration: CaptureRegistration? {
        CaptureRegistry.registration(taskId: taskId)
    }

    /// True if this card represents the video-inventory capture task.
    /// Resolved through the capture registry so the next vertical attaches
    /// without touching TasksStore/TaskRowButtons.
    var isScanInventory: Bool {
        captureRegistration?.kind == .videoInventory
    }

    /// Engine-generated packing tasks are catalog-external and carry their
    /// complete session payload on the task doc.
    var packingSession: PackingSession? {
        guard case .packing(let session) = payload else { return nil }
        return session
    }

    var isPackingSession: Bool {
        packingSession != nil || (taskId ?? id).hasPrefix("PACKING_SESSION_")
    }

    var isPackingReadiness: Bool {
        (taskId ?? id) == ReadinessChecklist.taskId
    }

    /// Whether this card should be shown in the stack
    var shouldShow: Bool {
        if dispositionContract != nil { return false }
        // If snoozed, only show if snooze date has passed
        if isSnoozed {
            return false
        }
        // Don't show completed, skipped, in-progress, pending / matching (server
        // working), or user-in-progress tasks — none are actionable from the stack
        if status == .completed || status == .skipped || status == .inProgress || status == .userInProgress || status == .pending || status == .matchingInProgress {
            return false
        }
        return true
    }

    // MARK: - Initializers
    init(
        id: String = UUID().uuidString,
        type: CardType,
        title: String,
        subtitle: String,
        colorName: String = "white",
        taskId: String? = nil,
        workflowId: String? = nil,
        vendorCategory: String? = nil,
        vendorId: String? = nil,
        priority: Priority = .normal,
        createdAt: Date = Date(),
        status: TaskStatus = .upcoming,
        dueDate: Date? = nil,
        snoozedUntil: Date? = nil,
        lastSnoozedAt: Date? = nil,
        briefingMessage: String? = nil,
        taskCategory: String? = nil,
        urgencyPercentage: Int? = nil,
        surfaceAfterDaysPastMove: Int? = nil,
        userInProgressDate: Date? = nil,
        userInProgressReturnDate: Date? = nil,
        completedAt: Date? = nil,
        selfServiceOnly: Bool = false,
        actionType: String? = nil,
        taskType: String? = nil,
        tips: String? = nil,
        whyNeeded: String? = nil,
        estPeezy: String? = nil,
        estHours: Double? = nil,
        stage: TaskStage? = nil,
        payload: CardPayload? = nil,
        tier: String = "task",
        nudgePrompt: String? = nil,
        nudgeSpawnsId: String? = nil,
        spawnedFrom: SpawnedFrom? = nil,
        onCompleteSpawns: [CompletionSpawn] = [],
        notesEnabled: Bool = false,
        quoteTracker: String = "none",
        dispositionContract: DispositionContract? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.colorName = colorName
        self.taskId = taskId
        self.workflowId = workflowId
        self.vendorCategory = vendorCategory
        self.vendorId = vendorId
        self.priority = priority
        self.createdAt = createdAt
        self.status = status
        self.dueDate = dueDate
        self.snoozedUntil = snoozedUntil
        self.lastSnoozedAt = lastSnoozedAt
        self.briefingMessage = briefingMessage
        self.taskCategory = taskCategory
        self.urgencyPercentage = urgencyPercentage
        self.surfaceAfterDaysPastMove = surfaceAfterDaysPastMove
        self.userInProgressDate = userInProgressDate
        self.userInProgressReturnDate = userInProgressReturnDate
        self.completedAt = completedAt
        self.selfServiceOnly = selfServiceOnly
        self.actionType = actionType
        self.taskType = taskType
        self.tips = tips
        self.whyNeeded = whyNeeded
        self.estPeezy = estPeezy
        self.estHours = estHours
        self.stage = stage
        self.payload = payload
        self.tier = tier
        self.nudgePrompt = nudgePrompt
        self.nudgeSpawnsId = nudgeSpawnsId
        self.spawnedFrom = spawnedFrom
        self.onCompleteSpawns = onCompleteSpawns
        self.notesEnabled = notesEnabled
        self.quoteTracker = quoteTracker
        self.dispositionContract = dispositionContract
    }

    var visibleStatusCopy: String? {
        let trimmed = dispositionContract?.visibleStatusCopy?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Full UI-side coherence check. The server remains authoritative, but the
    /// client must never guess completion or expose legacy controls for bad data.
    var dispositionContractIsCoherent: Bool {
        guard let contract = dispositionContract else { return true }
        guard !(contract.visibleStatusCopy ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch status {
        case .completed:
            return contract.disposition == .completed && contract.terminalKind == nil
                && Self.hasNoNonterminalState(contract)
                && !contract.externalSubmission && contract.supersededBy == nil
        case .dismissed:
            guard Self.hasNoNonterminalState(contract), !contract.externalSubmission else { return false }
            if contract.terminalKind == .notApplicable {
                return contract.disposition == .notApplicable && contract.supersededBy == nil
            }
            if contract.terminalKind == .retired {
                return contract.disposition == nil && contract.supersededBy == nil
            }
            return contract.disposition == nil && contract.terminalKind == .superseded
        case .upcoming:
            return contract.disposition == nil && contract.terminalKind == nil
                && Self.hasNoNonterminalState(contract)
                && !contract.externalSubmission && contract.supersededBy == nil
        case .inProgress:
            return Self.validNonterminal(contract, disposition: .userActionTracked)
        case .matchingInProgress:
            return Self.validNonterminal(contract, disposition: .waitingOnExternal)
        case .snoozed:
            return Self.validNonterminal(contract, disposition: .deferred)
        case .pending:
            return Self.validNonterminal(contract, disposition: .supportActive)
        case .userInProgress, .skipped, .converted:
            return false
        }
    }

    private static func validNonterminal(
        _ contract: DispositionContract,
        disposition: DispositionContract.Disposition
    ) -> Bool {
        guard contract.disposition == disposition,
              contract.terminalKind == nil,
              !(contract.owner ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !(contract.nextAction ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !(contract.resumeDestination ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !(contract.visibleStatusCopy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              contract.supersededBy == nil,
              let trigger = contract.nextTrigger else { return false }
        switch trigger.kind {
        case .date:
            return trigger.at != nil && trigger.eventName == nil && trigger.canonicalKey == nil
        case .event:
            return trigger.at == nil
                && !(trigger.eventName ?? "").isEmpty
                && !(trigger.canonicalKey ?? "").isEmpty
                && trigger.afterSourceVersion != nil
        }
    }

    private static func hasNoNonterminalState(_ contract: DispositionContract) -> Bool {
        contract.owner == nil && contract.nextAction == nil
            && contract.nextTrigger == nil && contract.resumeDestination == nil
    }
    
    // MARK: - Factory Methods

    /// Create intro card for daily greeting with user name and contextual briefing
    static func intro(userName: String?, briefing: String? = nil) -> PeezyCard {
        let timeOfDay = TimeOfDay.current
        let greeting = timeOfDay.greeting
        let name = userName ?? ""

        // Title: "Good morning," or "Good morning" (without comma if no name)
        let title = name.isEmpty ? greeting : "\(greeting),"

        // Subtitle stores the user's name for display
        // briefingMessage stores the warm, conversational summary
        return PeezyCard(
            type: .intro,
            title: title,
            subtitle: name,
            colorName: "white",
            priority: .high,
            briefingMessage: briefing
        )
    }

    /// Legacy factory for backward compatibility
    static func intro(userName: String?, updateCount: Int, taskCount: Int) -> PeezyCard {
        return intro(userName: userName, briefing: nil)
    }

    /// Legacy factory for backward compatibility
    static func intro(updateCount: Int) -> PeezyCard {
        return intro(userName: nil, briefing: nil)
    }
    
    /// Create task decision card from MovingTask
    static func fromTask(
        taskId: String,
        title: String,
        subtitle: String,
        workflowId: String? = nil,
        priority: Priority = .normal
    ) -> PeezyCard {
        return PeezyCard(
            type: .task,
            title: title,
            subtitle: subtitle,
            colorName: colorForPriority(priority),
            taskId: taskId,
            workflowId: workflowId,
            priority: priority
        )
    }
    
    /// Create vendor recommendation card
    static func vendorRecommendation(
        title: String,
        subtitle: String,
        vendorCategory: String,
        vendorId: String? = nil
    ) -> PeezyCard {
        return PeezyCard(
            type: .vendor,
            title: title,
            subtitle: subtitle,
            colorName: "blue",
            vendorCategory: vendorCategory,
            vendorId: vendorId,
            priority: .normal
        )
    }
    
    /// Create milestone celebration card
    static func milestone(title: String, subtitle: String) -> PeezyCard {
        return PeezyCard(
            type: .milestone,
            title: title,
            subtitle: subtitle,
            colorName: "purple",
            priority: .low
        )
    }
    
    /// Create question card (Peezy needs input)
    static func question(title: String, subtitle: String, taskId: String? = nil) -> PeezyCard {
        return PeezyCard(
            type: .question,
            title: title,
            subtitle: subtitle,
            colorName: "orange",
            taskId: taskId,
            priority: .high
        )
    }
    
    // MARK: - Helpers

    // Greeting is now handled by TimeOfDay enum in PeezyTheme.swift
    
    private static func colorForPriority(_ priority: Priority) -> String {
        switch priority {
        case .urgent: return "red"
        case .high: return "orange"
        case .normal: return "green"
        case .low: return "gray"
        }
    }
    
    // Equatable is synthesized MEMBERWISE on purpose (Spec 03 Phase A). The old
    // id-only == made SwiftUI skip row bodies when only fields changed, leaving
    // stale UI. Where identity — not value — is intended, compare card.id.
}

// MARK: - Card Payload (empty shells — populated in Specs 04–05)

/// Per-type payload carried by a card. Absent (nil) means no payload.
enum CardPayload: Codable, Equatable {
    case vendor(VendorRef)
    case capture(CaptureRef)
    case packing(PackingSession)
}

/// Shell — vendor fields arrive with the vendor verticals (Spec 04).
struct VendorRef: Codable, Equatable {}

/// Shell — capture fields arrive with the capture registry (Spec 05).
struct CaptureRef: Codable, Equatable {}

// MARK: - Card Action Result
/// Tracks what happened when user swiped a card
struct CardActionResult {
    let card: PeezyCard
    let action: SwipeAction
    let timestamp: Date
    
    init(card: PeezyCard, action: SwipeAction) {
        self.card = card
        self.action = action
        self.timestamp = Date()
    }
}

// MARK: - Swipe Action
enum SwipeAction: String, Codable {
    case doIt = "do_it"
    case later = "later"
}
