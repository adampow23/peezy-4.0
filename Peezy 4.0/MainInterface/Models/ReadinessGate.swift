import Foundation

enum ReadinessItem: String, CaseIterable, Codable, Identifiable {
    case allSessionsComplete
    case furnitureDisassembled
    case accessReserved
    case pathClear
    case firstNightBagSetAside

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allSessionsComplete: return "All packing sessions complete"
        case .furnitureDisassembled: return "Furniture disassembled"
        case .accessReserved: return "Elevator and parking reserved"
        case .pathClear: return "Moving path clear"
        case .firstNightBagSetAside: return "First-night bag set aside"
        }
    }
}

struct ReadinessChecklist: Codable, Equatable {
    nonisolated static let taskId = "PACKING_READINESS_GATE"

    private var values: [ReadinessItem: Bool]

    init(
        allSessionsComplete: Bool = false,
        furnitureDisassembled: Bool = false,
        accessReserved: Bool = false,
        pathClear: Bool = false,
        firstNightBagSetAside: Bool = false
    ) {
        values = [
            .allSessionsComplete: allSessionsComplete,
            .furnitureDisassembled: furnitureDisassembled,
            .accessReserved: accessReserved,
            .pathClear: pathClear,
            .firstNightBagSetAside: firstNightBagSetAside
        ]
    }

    init(items: [String: Bool]) {
        values = Dictionary(uniqueKeysWithValues: ReadinessItem.allCases.map { item in
            (item, items[item.rawValue] ?? false)
        })
    }

    subscript(item: ReadinessItem) -> Bool {
        get { values[item] ?? false }
        set { values[item] = newValue }
    }

    var items: [String: Bool] {
        Dictionary(uniqueKeysWithValues: ReadinessItem.allCases.map { item in
            (item.rawValue, self[item])
        })
    }

    var isComplete: Bool {
        ReadinessItem.allCases.allSatisfy { self[$0] }
    }

    func showsIncompleteConsequence(
        scheduledDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard !isComplete,
              let moveDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: scheduledDate)
              ) else { return false }
        return now >= moveDay
    }
}

struct ReadinessGateRecord: Equatable {
    var checklist: ReadinessChecklist
    let scheduledDate: Date
    var completedAt: Date?
}
