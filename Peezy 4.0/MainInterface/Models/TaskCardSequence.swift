import Foundation

// MARK: - Card Condition (for conditional skip)
// When present on a card spec, the card is only shown if the user's
// previous answers match the condition. Otherwise advance() skips it.

struct CardCondition: Equatable {
    let answerKey: String
    let requiredValues: Set<String>
}

// MARK: - Task Card Sequence

struct TaskCardSequence: Identifiable, Equatable {
    let id: String
    let task: PeezyCard
    let cards: [TaskCardSpec]
    let isPaywallGated: Bool
    let needsWorkflowContinue: Bool
    let showVerifiedBadge: Bool

    static func == (lhs: TaskCardSequence, rhs: TaskCardSequence) -> Bool {
        lhs.id == rhs.id && lhs.cards.map(\.id) == rhs.cards.map(\.id) && lhs.showVerifiedBadge == rhs.showVerifiedBadge
    }
}

// MARK: - Card Spec Variants

enum TaskCardSpec: Identifiable, Equatable {
    case title(TaskCardTitleData)
    case info(TaskCardInfoData)
    case tiles(TaskCardTilesData)
    case confirm(TaskCardConfirmData)
    case summary(TaskCardSummaryData)
    case paywall

    var id: String {
        switch self {
        case .title(let d): return "title-\(d.cardId)"
        case .info(let d): return "info-\(d.cardId)"
        case .tiles(let d): return "tiles-\(d.cardId)"
        case .confirm(let d): return "confirm-\(d.cardId)"
        case .summary(let d): return "summary-\(d.cardId)"
        case .paywall: return "paywall"
        }
    }

    /// Condition that must be met for this card to show.
    /// If nil, card always shows. If present, advance() checks answers.
    var showWhen: CardCondition? {
        switch self {
        case .tiles(let d): return d.showWhen
        case .info(let d): return d.showWhen
        default: return nil
        }
    }

    static func == (lhs: TaskCardSpec, rhs: TaskCardSpec) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Card Data Structs

struct TaskCardTitleData: Equatable {
    let cardId: String
    let category: String
    let headerIcon: String
    let title: String
    let body: String
    let primaryLabel: String
    let secondaryLabel: String?
}

struct TaskCardInfoData: Equatable {
    let cardId: String
    let category: String
    let headerIcon: String
    let title: String
    let body: String
    let primaryLabel: String
    let showWhen: CardCondition?

    init(cardId: String, category: String, headerIcon: String, title: String, body: String, primaryLabel: String, showWhen: CardCondition? = nil) {
        self.cardId = cardId
        self.category = category
        self.headerIcon = headerIcon
        self.title = title
        self.body = body
        self.primaryLabel = primaryLabel
        self.showWhen = showWhen
    }
}

struct TaskCardTilesData: Equatable {
    let cardId: String
    let category: String
    let headerIcon: String
    let title: String
    let body: String?
    let tiles: [TileOption]
    let mode: TileMode
    let answerKey: String
    let workflowQuestionId: String?
    let showWhen: CardCondition?

    enum TileMode: Equatable {
        case single
        case multi
    }

    init(cardId: String, category: String, headerIcon: String, title: String, body: String? = nil, tiles: [TileOption], mode: TileMode, answerKey: String, workflowQuestionId: String? = nil, showWhen: CardCondition? = nil) {
        self.cardId = cardId
        self.category = category
        self.headerIcon = headerIcon
        self.title = title
        self.body = body
        self.tiles = tiles
        self.mode = mode
        self.answerKey = answerKey
        self.workflowQuestionId = workflowQuestionId
        self.showWhen = showWhen
    }
}

struct TileOption: Identifiable, Equatable {
    let id: String
    let label: String
    let icon: String
    let subtitle: String?
    let isExclusive: Bool

    init(id: String, label: String, icon: String, subtitle: String? = nil, isExclusive: Bool = false) {
        self.id = id
        self.label = label
        self.icon = icon
        self.subtitle = subtitle
        self.isExclusive = isExclusive
    }
}

struct TaskCardConfirmData: Equatable {
    let cardId: String
    let category: String
    let headerIcon: String
    let taskTitle: String
    let fields: [ConfirmField]

    static func == (lhs: TaskCardConfirmData, rhs: TaskCardConfirmData) -> Bool {
        lhs.cardId == rhs.cardId
    }
}

struct TaskCardSummaryData: Equatable {
    let cardId: String
    let category: String
    let headerIcon: String
    let title: String
    let body: String
    let primaryLabel: String
}
