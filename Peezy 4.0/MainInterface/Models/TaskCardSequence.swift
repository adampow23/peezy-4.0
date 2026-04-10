import Foundation

// MARK: - Card Condition

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
    let taskTitle: String
    let title: String
    let body: String
    let primaryLabel: String
    let secondaryLabel: String?

    init(cardId: String, category: String, headerIcon: String, taskTitle: String = "", title: String, body: String, primaryLabel: String, secondaryLabel: String? = nil) {
        self.cardId = cardId
        self.category = category
        self.headerIcon = headerIcon
        self.taskTitle = taskTitle
        self.title = title
        self.body = body
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
    }
}

struct TaskCardInfoData: Equatable {
    let cardId: String
    let category: String
    let headerIcon: String
    let taskTitle: String
    let title: String
    let body: String
    let primaryLabel: String
    let showWhen: CardCondition?
    let linkURL: String?
    let linkLabel: String?
    let cautionIcon: String?
    let boldPrefix: String?

    init(cardId: String, category: String, headerIcon: String, taskTitle: String = "", title: String, body: String, primaryLabel: String, showWhen: CardCondition? = nil, linkURL: String? = nil, linkLabel: String? = nil, cautionIcon: String? = nil, boldPrefix: String? = nil) {
        self.cardId = cardId
        self.category = category
        self.headerIcon = headerIcon
        self.taskTitle = taskTitle
        self.title = title
        self.body = body
        self.primaryLabel = primaryLabel
        self.showWhen = showWhen
        self.linkURL = linkURL
        self.linkLabel = linkLabel
        self.cautionIcon = cautionIcon
        self.boldPrefix = boldPrefix
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
    let taskTitle: String
    let skipLabel: String?
    let showDivider: Bool

    enum TileMode: Equatable {
        case single
        case multi
    }

    init(cardId: String, category: String, headerIcon: String, title: String, body: String? = nil, tiles: [TileOption], mode: TileMode, answerKey: String, workflowQuestionId: String? = nil, showWhen: CardCondition? = nil, taskTitle: String = "", skipLabel: String? = nil, showDivider: Bool = true) {
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
        self.taskTitle = taskTitle
        self.skipLabel = skipLabel
        self.showDivider = showDivider
    }
}

struct TileOption: Identifiable, Equatable {
    let id: String
    let label: String
    let icon: String
    let subtitle: String?
    let isExclusive: Bool
    let fillPercent: Double?

    init(id: String, label: String, icon: String, subtitle: String? = nil, isExclusive: Bool = false, fillPercent: Double? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.subtitle = subtitle
        self.isExclusive = isExclusive
        self.fillPercent = fillPercent
    }
}

struct TaskCardConfirmData: Equatable {
    let cardId: String
    let category: String
    let headerIcon: String
    let taskTitle: String
    let fields: [ConfirmField]

    init(cardId: String, category: String, headerIcon: String, taskTitle: String = "", fields: [ConfirmField]) {
        self.cardId = cardId
        self.category = category
        self.headerIcon = headerIcon
        self.taskTitle = taskTitle
        self.fields = fields
    }

    static func == (lhs: TaskCardConfirmData, rhs: TaskCardConfirmData) -> Bool {
        lhs.cardId == rhs.cardId
    }
}

struct TaskCardSummaryData: Equatable {
    let cardId: String
    let category: String
    let headerIcon: String
    let taskTitle: String
    let title: String
    let body: String
    let primaryLabel: String
    let subtext: String?

    init(cardId: String, category: String, headerIcon: String, taskTitle: String = "", title: String, body: String, primaryLabel: String, subtext: String? = nil) {
        self.cardId = cardId
        self.category = category
        self.headerIcon = headerIcon
        self.taskTitle = taskTitle
        self.title = title
        self.body = body
        self.primaryLabel = primaryLabel
        self.subtext = subtext
    }
}
