import Foundation

struct PackingPlanItem: Equatable {
    let name: String
    let category: String
    let quantity: Int
    let cubicFeet: Double
    let tier: String

    init(
        name: String,
        category: String = "other",
        quantity: Int = 1,
        cubicFeet: Double = 0,
        tier: String = "boxable"
    ) {
        self.name = name
        self.category = category
        self.quantity = max(quantity, 1)
        self.cubicFeet = max(cubicFeet, 0)
        self.tier = tier
    }
}

struct PackingRoomInput: Equatable {
    let name: String
    let items: [PackingPlanItem]
}

struct PackingSession: Codable, Equatable, Identifiable {
    var id: String { taskId }

    var taskId: String
    let sessionKey: String
    let sourceKeys: [String]
    let rooms: [String]
    let roomLabel: String
    let estMinutes: Int
    let scheduledDate: Date
    let itemSummary: [String]
    let isFirstNightBag: Bool
    var completedAt: Date?
    var isBehindPace: Bool

    var isCompleted: Bool { completedAt != nil }
}

struct PackingPlan: Codable, Equatable {
    let moveDate: Date
    let generatedAt: Date
    var reflowedAt: Date?
    var sessions: [PackingSession]
}

struct PackingCompletion: Equatable {
    let consequenceLine: String
    let nextSessionDate: Date?
}

/// Pure reverse-scheduling engine for the inventory-derived packing plan.
enum PackingPlanEngine {

    private enum RoomBucket: String {
        case storageSeasonal
        case decorBooks
        case guestSpare
        case garage
        case secondaryBedroom
        case kitchenNonEssentials
        case primaryBedroom
        case bathrooms
        case kitchenEssentials
    }

    private struct DraftSession {
        let sourceKeys: [String]
        let rooms: [String]
        let roomLabel: String
        let estMinutes: Int
        let itemSummary: [String]
        let isFirstNightBag: Bool
    }

    private struct WorkUnit {
        let name: String
        let minutes: Int
    }

    static func generate(
        rooms: [PackingRoomInput],
        moveDate: Date,
        today: Date,
        calendar: Calendar = .current,
        configuration: PackingConfiguration,
        preserving previousPlan: PackingPlan? = nil
    ) -> PackingPlan {
        let startToday = calendar.startOfDay(for: today)
        let startMoveDate = calendar.startOfDay(for: moveDate)
        let endDate = max(
            calendar.date(
                byAdding: .day,
                value: -configuration.moveDayBufferDays,
                to: startMoveDate
            ) ?? startToday,
            startToday
        )

        var drafts = roomDrafts(from: rooms, configuration: configuration)
        drafts.append(firstNightDraft(from: rooms, configuration: configuration))

        let availableDays = max(
            (calendar.dateComponents([.day], from: startToday, to: endDate).day ?? 0) + 1,
            1
        )
        drafts = mergeForShortTimeline(drafts, availableDays: availableDays)

        let completedSourceKeys = Set(
            previousPlan?.sessions
                .filter(\.isCompleted)
                .flatMap(\.sourceKeys) ?? []
        )

        var sessions: [PackingSession] = []
        sessions.reserveCapacity(drafts.count)
        for (index, draft) in drafts.enumerated() {
            let daysBack = drafts.count - index - 1
            let proposedDate = calendar.date(byAdding: .day, value: -daysBack, to: endDate) ?? startToday
            let scheduledDate = max(proposedDate, startToday)
            let completedAt: Date? = draft.sourceKeys.allSatisfy(completedSourceKeys.contains)
                ? completionDate(for: draft.sourceKeys, in: previousPlan)
                : nil

            sessions.append(PackingSession(
                taskId: "PACKING_SESSION_\(index + 1)",
                sessionKey: draft.sourceKeys.joined(separator: "+"),
                sourceKeys: draft.sourceKeys,
                rooms: draft.rooms,
                roomLabel: draft.roomLabel,
                estMinutes: draft.estMinutes,
                scheduledDate: scheduledDate,
                itemSummary: draft.itemSummary,
                isFirstNightBag: draft.isFirstNightBag,
                completedAt: completedAt,
                isBehindPace: false
            ))
        }

        return PackingPlan(
            moveDate: startMoveDate,
            generatedAt: startToday,
            reflowedAt: nil,
            sessions: sessions
        )
    }

    /// Re-spreads only when at least one incomplete session is past due.
    /// Sessions are never dropped or merged during reflow; compressed plans may
    /// therefore place more than one task on a date, while daily-dose selection
    /// still admits at most one.
    static func reflowIfNeeded(
        _ plan: PackingPlan,
        today: Date,
        calendar: Calendar = .current,
        configuration: PackingConfiguration
    ) -> PackingPlan {
        let startToday = calendar.startOfDay(for: today)
        guard plan.sessions.contains(where: {
            !$0.isCompleted && calendar.startOfDay(for: $0.scheduledDate) < startToday
        }) else { return plan }

        var reflowed = plan
        let endDate = max(
            calendar.date(
                byAdding: .day,
                value: -configuration.moveDayBufferDays,
                to: calendar.startOfDay(for: plan.moveDate)
            ) ?? startToday,
            startToday
        )
        let remainingIndices = reflowed.sessions.indices.filter { !reflowed.sessions[$0].isCompleted }
        guard !remainingIndices.isEmpty else { return plan }

        let availableDays = max(
            (calendar.dateComponents([.day], from: startToday, to: endDate).day ?? 0) + 1,
            1
        )
        let requiredPerDay = Double(remainingIndices.count) / Double(availableDays)

        for index in reflowed.sessions.indices {
            reflowed.sessions[index].isBehindPace = false
        }

        for (position, sessionIndex) in remainingIndices.enumerated() {
            let offset: Int
            if remainingIndices.count == 1 {
                offset = 0
            } else if remainingIndices.count <= availableDays {
                offset = Int(
                    (Double(position) * Double(availableDays - 1) / Double(remainingIndices.count - 1)).rounded()
                )
            } else {
                offset = min(
                    Int(Double(position) * Double(availableDays) / Double(remainingIndices.count)),
                    availableDays - 1
                )
            }

            let original = reflowed.sessions[sessionIndex]
            reflowed.sessions[sessionIndex] = PackingSession(
                taskId: original.taskId,
                sessionKey: original.sessionKey,
                sourceKeys: original.sourceKeys,
                rooms: original.rooms,
                roomLabel: original.roomLabel,
                estMinutes: original.estMinutes,
                scheduledDate: calendar.date(byAdding: .day, value: offset, to: startToday) ?? startToday,
                itemSummary: original.itemSummary,
                isFirstNightBag: original.isFirstNightBag,
                completedAt: original.completedAt,
                isBehindPace: position == 0
                    && requiredPerDay > configuration.behindPaceSessionsPerDay
            )
        }
        reflowed.reflowedAt = startToday
        return reflowed
    }

    static func completion(
        afterCompleting taskId: String,
        in plan: PackingPlan,
        at completedAt: Date,
        calendar: Calendar = .current
    ) -> (plan: PackingPlan, result: PackingCompletion)? {
        guard let completedIndex = plan.sessions.firstIndex(where: { $0.taskId == taskId }) else { return nil }

        var updated = plan
        updated.sessions[completedIndex].completedAt = completedAt
        let completedSession = updated.sessions[completedIndex]

        let roomNames = Set(updated.sessions.filter { !$0.isFirstNightBag }.flatMap(\.rooms))
        let completedRooms = roomNames.filter { room in
            updated.sessions
                .filter { !$0.isFirstNightBag && $0.rooms.contains(room) }
                .allSatisfy(\.isCompleted)
        }
        let moveDate = formattedMoveDate(updated.moveDate, calendar: calendar)
        let line = "\(completedSession.roomLabel) done — \(completedRooms.count) of \(roomNames.count) rooms packed. On pace for \(moveDate)."
        let nextDate = updated.sessions.first(where: { !$0.isCompleted })?.scheduledDate

        return (
            updated,
            PackingCompletion(consequenceLine: line, nextSessionDate: nextDate)
        )
    }

    // MARK: - Session construction

    private static func roomDrafts(
        from rooms: [PackingRoomInput],
        configuration: PackingConfiguration
    ) -> [DraftSession] {
        var ordered: [(
            bucket: RoomBucket,
            roomName: String,
            variant: String,
            items: [PackingPlanItem],
            targetMinutes: Int
        )] = []

        for room in rooms {
            let packable = room.items.filter { $0.tier.lowercased() != "furniture" }
            guard !packable.isEmpty else { continue }

            if roomBucket(for: room.name) == .kitchenNonEssentials {
                let essentials = packable.filter { isKitchenEssential($0) }
                let nonEssentials = packable.filter { !isKitchenEssential($0) }
                var variants: [(bucket: RoomBucket, variant: String, items: [PackingPlanItem])] = []
                if !nonEssentials.isEmpty {
                    variants.append((.kitchenNonEssentials, "non_essentials", nonEssentials))
                }
                if !essentials.isEmpty {
                    variants.append((.kitchenEssentials, "essentials", essentials))
                }

                let rawMinutes = variants.map {
                    workUnits(from: $0.items, configuration: configuration)
                        .reduce(0) { $0 + $1.minutes }
                }
                let roomMinutes = max(
                    rawMinutes.reduce(0, +),
                    PackingConstants.minimumRoomMinutes(
                        for: room.name,
                        configuration: configuration
                    ),
                    configuration.minimumSessionMinutes
                )
                let targets = distributedTargets(rawMinutes: rawMinutes, totalMinutes: roomMinutes)
                for (index, variant) in variants.enumerated() {
                    ordered.append((
                        variant.bucket,
                        room.name,
                        variant.variant,
                        variant.items,
                        targets[index]
                    ))
                }
            } else {
                let itemMinutes = workUnits(from: packable, configuration: configuration)
                    .reduce(0) { $0 + $1.minutes }
                let roomMinutes = max(
                    itemMinutes,
                    PackingConstants.minimumRoomMinutes(
                        for: room.name,
                        configuration: configuration
                    ),
                    configuration.minimumSessionMinutes
                )
                ordered.append((roomBucket(for: room.name), room.name, "room", packable, roomMinutes))
            }
        }

        ordered.sort {
            let leftWeight = configuration.sequencingWeights[$0.bucket.rawValue]
                ?? Int.max
            let rightWeight = configuration.sequencingWeights[$1.bucket.rawValue]
                ?? Int.max
            if leftWeight != rightWeight { return leftWeight < rightWeight }
            if $0.roomName != $1.roomName {
                return $0.roomName.localizedCaseInsensitiveCompare($1.roomName) == .orderedAscending
            }
            return $0.variant < $1.variant
        }

        return ordered.flatMap { entry in
            let label: String
            switch entry.bucket {
            case .kitchenNonEssentials: label = "\(entry.roomName) non-essentials"
            case .kitchenEssentials: label = "\(entry.roomName) essentials"
            default: label = entry.roomName
            }
            return chunkDrafts(
                roomName: entry.roomName,
                label: label,
                variant: entry.variant,
                items: entry.items,
                targetMinutes: entry.targetMinutes,
                configuration: configuration
            )
        }
    }

    private static func chunkDrafts(
        roomName: String,
        label: String,
        variant: String,
        items: [PackingPlanItem],
        targetMinutes: Int,
        configuration: PackingConfiguration
    ) -> [DraftSession] {
        var units = workUnits(from: items, configuration: configuration)
        guard !units.isEmpty else { return [] }

        let itemMinutes = units.reduce(0) { $0 + $1.minutes }
        let padding = max(targetMinutes - itemMinutes, 0)
        if padding > 0 {
            units[0] = WorkUnit(name: units[0].name, minutes: units[0].minutes + padding)
        }

        let chunkCount = max(
            Int(ceil(Double(targetMinutes) / Double(configuration.targetSessionMinutes))),
            1
        )
        let baseChunkMinutes = targetMinutes / chunkCount
        let remainder = targetMinutes % chunkCount
        let capacities = (0..<chunkCount).map { index in
            baseChunkMinutes + (index < remainder ? 1 : 0)
        }

        var chunks: [[WorkUnit]] = []
        chunks.reserveCapacity(chunkCount)
        var unitIndex = 0
        var unitMinutesRemaining = units[0].minutes

        for capacity in capacities {
            var capacityRemaining = capacity
            var chunk: [WorkUnit] = []
            while capacityRemaining > 0 && unitIndex < units.count {
                let consumed = min(capacityRemaining, unitMinutesRemaining)
                chunk.append(WorkUnit(name: units[unitIndex].name, minutes: consumed))
                capacityRemaining -= consumed
                unitMinutesRemaining -= consumed
                if unitMinutesRemaining == 0 {
                    unitIndex += 1
                    if unitIndex < units.count {
                        unitMinutesRemaining = units[unitIndex].minutes
                    }
                }
            }
            chunks.append(chunk)
        }

        let normalizedRoom = slug(roomName)
        return chunks.enumerated().map { index, chunk in
            let chunkLabel = chunks.count > 1 ? "\(label) — part \(index + 1)" : label
            let sourceKey = "\(normalizedRoom):\(variant):\(index + 1)"
            return DraftSession(
                sourceKeys: [sourceKey],
                rooms: [roomName],
                roomLabel: chunkLabel,
                estMinutes: capacities[index],
                itemSummary: summarized(chunk),
                isFirstNightBag: false
            )
        }
    }

    private static func workUnits(
        from items: [PackingPlanItem],
        configuration: PackingConfiguration
    ) -> [WorkUnit] {
        items.flatMap { item -> [WorkUnit] in
            let boxEquivalents = max(
                Int(ceil(item.cubicFeet / configuration.boxEquivalentCubicFeet)),
                1
            )
            let minutes = max(
                boxEquivalents * configuration.minutesPerBoxEquivalent,
                configuration.minutesPerBoxEquivalent
            )
            return (0..<item.quantity).map { _ in WorkUnit(name: item.name, minutes: minutes) }
        }
    }

    private static func distributedTargets(rawMinutes: [Int], totalMinutes: Int) -> [Int] {
        guard rawMinutes.count > 1 else { return [totalMinutes] }
        var result = rawMinutes
        var remaining = max(totalMinutes - rawMinutes.reduce(0, +), 0)
        while remaining > 0 {
            guard let index = result.indices.min(by: { result[$0] < result[$1] }) else { break }
            result[index] += 1
            remaining -= 1
        }
        return result
    }

    private static func firstNightDraft(
        from rooms: [PackingRoomInput],
        configuration: PackingConfiguration
    ) -> DraftSession {
        let matches = rooms.flatMap(\.items).filter { item in
            containsAny(item.name, keywords: PackingConstants.firstNightKeywords)
        }
        let summary: [String]
        if matches.isEmpty {
            summary = [PackingConstants.firstNightFallback]
        } else {
            summary = matches.map { $0.quantity > 1 ? "\($0.quantity)× \($0.name)" : $0.name }
        }
        return DraftSession(
            sourceKeys: ["first_night_bag"],
            rooms: ["First-night bag"],
            roomLabel: "First-night bag",
            estMinutes: configuration.minimumSessionMinutes,
            itemSummary: summary,
            isFirstNightBag: true
        )
    }

    private static func mergeForShortTimeline(
        _ sessions: [DraftSession],
        availableDays: Int
    ) -> [DraftSession] {
        var result = sessions
        while result.count > availableDays {
            let regularCount = result.last?.isFirstNightBag == true ? result.count - 1 : result.count
            guard regularCount > 1 else { break }

            let pairStart = (0..<(regularCount - 1)).min { left, right in
                let leftMinutes = result[left].estMinutes + result[left + 1].estMinutes
                let rightMinutes = result[right].estMinutes + result[right + 1].estMinutes
                return leftMinutes < rightMinutes
            } ?? 0
            let first = result[pairStart]
            let second = result[pairStart + 1]
            let merged = DraftSession(
                sourceKeys: first.sourceKeys + second.sourceKeys,
                rooms: unique(first.rooms + second.rooms),
                roomLabel: [first.roomLabel, second.roomLabel].joined(separator: " + "),
                estMinutes: first.estMinutes + second.estMinutes,
                itemSummary: first.itemSummary + second.itemSummary,
                isFirstNightBag: false
            )
            result.replaceSubrange(pairStart...pairStart + 1, with: [merged])
        }
        return result
    }

    // MARK: - Classification / formatting

    private static func roomBucket(for roomName: String) -> RoomBucket {
        if containsAny(roomName, keywords: PackingConstants.storageRoomKeywords) { return .storageSeasonal }
        if containsAny(roomName, keywords: PackingConstants.guestRoomKeywords) { return .guestSpare }
        if containsAny(roomName, keywords: PackingConstants.garageRoomKeywords) { return .garage }
        if containsAny(roomName, keywords: PackingConstants.kitchenKeywords) { return .kitchenNonEssentials }
        if containsAny(roomName, keywords: PackingConstants.primaryBedroomKeywords) { return .primaryBedroom }
        if containsAny(roomName, keywords: PackingConstants.bathroomKeywords) { return .bathrooms }
        if containsAny(roomName, keywords: PackingConstants.secondaryBedroomKeywords) { return .secondaryBedroom }
        // NEEDS-CLARIFICATION: the locked taxonomy omits common rooms. The
        // decor/books position is the safest early-work fallback.
        return .decorBooks
    }

    private static func isKitchenEssential(_ item: PackingPlanItem) -> Bool {
        containsAny("\(item.name) \(item.category)", keywords: PackingConstants.kitchenEssentialKeywords)
    }

    private static func containsAny(_ value: String, keywords: [String]) -> Bool {
        let normalized = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return keywords.contains { normalized.localizedCaseInsensitiveContains($0) }
    }

    private static func summarized(_ units: [WorkUnit]) -> [String] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for unit in units {
            if counts[unit.name] == nil { order.append(unit.name) }
            counts[unit.name, default: 0] += 1
        }
        return order.map { name in
            let count = counts[name, default: 1]
            return count > 1 ? "\(count)× \(name)" : name
        }
    }

    private static func slug(_ value: String) -> String {
        value.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "_" }
            .reduce(into: "") { result, character in
                if character == "_" && result.hasSuffix("_") { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func completionDate(for sourceKeys: [String], in plan: PackingPlan?) -> Date? {
        plan?.sessions
            .filter { $0.isCompleted && !$0.sourceKeys.isDisjoint(with: sourceKeys) }
            .compactMap(\.completedAt)
            .max()
    }

    private static func formattedMoveDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }
}

private extension Array where Element == String {
    func isDisjoint(with other: [String]) -> Bool {
        Set(self).isDisjoint(with: Set(other))
    }
}
