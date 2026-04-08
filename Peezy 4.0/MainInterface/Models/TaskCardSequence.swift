import Foundation

// MARK: - Task Card Sequence
// Describes a task as an ordered sequence of cards.
// Each task type produces a different sequence, but every card
// renders through the same template.

struct TaskCardSequence: Identifiable, Equatable {
    let id: String
    let task: PeezyCard
    let cards: [TaskCardSpec]
    let isPaywallGated: Bool
    let needsWorkflowContinue: Bool

    static func == (lhs: TaskCardSequence, rhs: TaskCardSequence) -> Bool {
        lhs.id == rhs.id && lhs.cards.map(\.id) == rhs.cards.map(\.id)
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

    enum TileMode: Equatable {
        case single
        case multi
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
