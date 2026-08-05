import CryptoKit
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

nonisolated struct PackingV2InventoryDocument {
    let id: String
    let data: [String: Any]
}

nonisolated enum PackingV2InventoryRevision {
    static func room(documentID: String, items: Any) -> String? {
        digest(["roomId": documentID, "items": items])
    }

    static func aggregate(inventoryDocuments: [PackingV2InventoryDocument]) -> String? {
        let revisions = inventoryDocuments
            .sorted { $0.id < $1.id }
            .compactMap { document -> [String: String]? in
                guard let items = document.data["items"] as? [[String: Any]],
                      let inventoryRevision = room(documentID: document.id, items: items)
                else { return nil }
                return ["id": document.id, "inventoryRevision": inventoryRevision]
            }
        guard revisions.count == inventoryDocuments.count else { return nil }
        return digest(revisions)
    }

    private static func digest(_ value: Any) -> String? {
        guard let json = canonicalJSONString(value),
              let data = json.data(using: .utf8)
        else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Mirrors `JSON.stringify(canonicalize(value))` in processInventory.js.
    /// Foundation's JSONSerialization expands binary floating-point tails, so
    /// it cannot be used for the cross-runtime revision stamp.
    private static func canonicalJSONString(_ value: Any) -> String? {
        if value is NSNull { return "null" }
        if let string = value as? String { return quoted(string) }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return javascriptNumber(number.doubleValue)
        }
        if let values = value as? [Any] {
            let encoded = values.compactMap(canonicalJSONString)
            guard encoded.count == values.count else { return nil }
            return "[\(encoded.joined(separator: ","))]"
        }
        if let values = value as? [String: Any] {
            let encoded = values.keys.sorted().compactMap { key -> String? in
                guard let value = values[key],
                      let encodedValue = canonicalJSONString(value)
                else { return nil }
                return "\(quoted(key)):\(encodedValue)"
            }
            guard encoded.count == values.count else { return nil }
            return "{\(encoded.joined(separator: ","))}"
        }
        return nil
    }

    private static func quoted(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: [value],
            options: [.withoutEscapingSlashes]
        ) else { return "\"\"" }
        let arrayJSON = String(decoding: data, as: UTF8.self)
        return String(arrayJSON.dropFirst().dropLast())
    }

    private static func javascriptNumber(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        guard value != 0 else { return "0" }

        let swiftValue = String(value).lowercased()
        let magnitude = abs(value)
        if let exponentIndex = swiftValue.firstIndex(of: "e") {
            if magnitude >= 0.000001, magnitude < 1_000_000_000_000_000_000_000 {
                return expandedDecimal(swiftValue, exponentIndex: exponentIndex)
            }
            let mantissa = swiftValue[..<exponentIndex]
            let exponent = swiftValue[swiftValue.index(after: exponentIndex)...]
            let sign: Character? = exponent.first == "+" || exponent.first == "-"
                ? exponent.first
                : nil
            let digits = sign == nil ? exponent[...] : exponent.dropFirst()
            let normalizedDigits = digits.drop { $0 == "0" }
            let exponentDigits = normalizedDigits.isEmpty ? "0" : String(normalizedDigits)
            return "\(mantissa)e\(sign.map(String.init) ?? "")\(exponentDigits)"
        }
        return swiftValue.hasSuffix(".0") ? String(swiftValue.dropLast(2)) : swiftValue
    }

    private static func expandedDecimal(
        _ value: String,
        exponentIndex: String.Index
    ) -> String {
        let mantissa = String(value[..<exponentIndex])
        let exponent = Int(value[value.index(after: exponentIndex)...]) ?? 0
        let isNegative = mantissa.hasPrefix("-")
        let unsigned = isNegative ? String(mantissa.dropFirst()) : mantissa
        let digits = unsigned.filter { $0 != "." }
        let originalDecimalPosition = unsigned.firstIndex(of: ".").map {
            unsigned.distance(from: unsigned.startIndex, to: $0)
        } ?? unsigned.count
        let decimalPosition = originalDecimalPosition + exponent
        let expanded: String
        if decimalPosition <= 0 {
            expanded = "0." + String(repeating: "0", count: -decimalPosition) + digits
        } else if decimalPosition >= digits.count {
            expanded = digits + String(repeating: "0", count: decimalPosition - digits.count)
        } else {
            let split = digits.index(digits.startIndex, offsetBy: decimalPosition)
            expanded = String(digits[..<split]) + "." + String(digits[split...])
        }
        return isNegative ? "-" + expanded : expanded
    }
}

nonisolated struct PackingV2TimeRange: Equatable {
    let lowerFactor: Double
    let upperFactor: Double
    let roundingMinutes: Int

    init?(firestoreData data: [String: Any]) {
        guard let lowerFactor = (data["rangeLowerFactor"] as? NSNumber)?.doubleValue,
              let upperFactor = (data["rangeUpperFactor"] as? NSNumber)?.doubleValue,
              let roundingMinutes = (data["rangeRoundingMinutes"] as? NSNumber)?.intValue,
              lowerFactor > 0,
              lowerFactor < 1,
              upperFactor > 1,
              roundingMinutes > 0
        else { return nil }
        self.lowerFactor = lowerFactor
        self.upperFactor = upperFactor
        self.roundingMinutes = roundingMinutes
    }

    func label(centralMinutes: Double) -> String {
        let increment = Double(roundingMinutes)
        let lower = max(
            roundingMinutes,
            Int(floor((centralMinutes * lowerFactor) / increment)) * roundingMinutes
        )
        let roundedUpper = Int(ceil((centralMinutes * upperFactor) / increment)) * roundingMinutes
        let upper = max(roundedUpper, lower + roundingMinutes)
        return "about \(lower)–\(upper) min"
    }
}

nonisolated struct PackingV2RenderConfiguration: Equatable {
    let configVersion: String
    let timeRange: PackingV2TimeRange
    let transportGuidance: [String: String]

    init?(firestoreData data: [String: Any]) {
        guard let configVersion = data["configVersion"] as? String,
              !configVersion.isEmpty,
              let timeData = data["timeEstimation"] as? [String: Any],
              let timeRange = PackingV2TimeRange(firestoreData: timeData),
              let policyData = data["transportPolicies"] as? [String: Any]
        else { return nil }

        let guidance = policyData.reduce(into: [String: String]()) { result, entry in
            guard let policy = entry.value as? [String: Any],
                  let copy = policy["userFacingCopy"] as? String,
                  !copy.isEmpty
            else { return }
            result[entry.key] = copy
        }
        guard !guidance.isEmpty else { return nil }
        self.configVersion = configVersion
        self.timeRange = timeRange
        transportGuidance = guidance
    }
}

nonisolated struct PackingV2BoxItem: Equatable {
    let name: String
    let qty: Int
}

nonisolated struct PackingV2Box: Equatable {
    let n: Int
    let size: String
    let lane: String
    let items: [PackingV2BoxItem]
    let layers: [String]
    let estMinutes: Double
    let roomID: String
}

nonisolated struct PackingV2Leftover: Equatable, Identifiable {
    let name: String
    let handlingNote: String

    var id: String { "\(name):\(handlingNote)" }
}

nonisolated struct PackingV2RestrictedItem: Equatable, Identifiable {
    let name: String
    let policy: String

    var id: String { "\(name):\(policy)" }
}

nonisolated struct PackingV2CoverageItem: Equatable, Identifiable {
    let name: String
    let qty: Int
    let reason: String

    var id: String { "\(name):\(reason)" }
}

nonisolated struct PackingV2UncertainItem: Equatable, Identifiable {
    let name: String
    let reasons: [String]

    var id: String { "\(name):\(reasons.joined(separator: ":"))" }
}

nonisolated struct PackingV2Evidence: Equatable {
    let assignedCount: Int
    let reserveCount: Int
    let coverageGrade: String
    let basedOn: String
    let notIncluded: String
    let couldNotVerify: [PackingV2CoverageItem]
    let mostUncertain: [PackingV2UncertainItem]
}

nonisolated struct PackingV2RoomPlan: Equatable {
    let id: String
    let name: String
    let boxes: [PackingV2Box]
    let leftovers: [PackingV2Leftover]
    let restricted: [PackingV2RestrictedItem]
    let openFirst: [String]
    let evidence: PackingV2Evidence

    init?(
        inventoryDocument: PackingV2InventoryDocument,
        configuration: PackingV2RenderConfiguration
    ) {
        let data = inventoryDocument.data
        guard let items = data["items"] as? [[String: Any]],
              let currentRevision = PackingV2InventoryRevision.room(
                  documentID: inventoryDocument.id,
                  items: items
              ),
              let metadata = data["packMeta"] as? [String: Any],
              metadata["status"] as? String == "complete",
              metadata["inventoryRevision"] as? String == currentRevision,
              metadata["configVersion"] as? String == configuration.configVersion,
              let plan = data["packPlan"] as? [String: Any],
              plan["engineVersion"] as? String == "sim-v2",
              plan["configVersion"] as? String == configuration.configVersion,
              let boxesData = plan["boxes"] as? [[String: Any]],
              let leftoversData = plan["leftovers"] as? [[String: Any]],
              let restrictedData = plan["restricted"] as? [[String: Any]],
              let openFirst = plan["openFirst"] as? [String],
              let totalsBySize = Self.nonnegativeCounts(plan["totalsBySize"]),
              let reserveBySize = Self.nonnegativeCounts(metadata["reserveBySize"]),
              let uncertainty = metadata["uncertainty"] as? [String: Any],
              let coverageGrade = uncertainty["coverageGrade"] as? String,
              let basedOn = uncertainty["basedOn"] as? String,
              let notIncluded = uncertainty["notIncluded"] as? String,
              let couldNotVerifyData = uncertainty["couldNotVerify"] as? [[String: Any]],
              let mostUncertainData = uncertainty["mostUncertain"] as? [[String: Any]]
        else { return nil }

        let decodedBoxes = boxesData.compactMap(Self.box(from:))
        let decodedLeftovers = leftoversData.compactMap(Self.leftover(from:))
        let decodedRestricted = restrictedData.compactMap(Self.restricted(from:))
        let couldNotVerify = couldNotVerifyData.compactMap(Self.coverageItem(from:))
        let mostUncertain = mostUncertainData.compactMap(Self.uncertainItem(from:))
        guard decodedBoxes.count == boxesData.count,
              decodedLeftovers.count == leftoversData.count,
              decodedRestricted.count == restrictedData.count,
              decodedRestricted.allSatisfy({
                  configuration.transportGuidance[$0.policy] != nil
              }),
              couldNotVerify.count == couldNotVerifyData.count,
              mostUncertain.count == mostUncertainData.count
        else { return nil }

        id = inventoryDocument.id
        name = data["name"] as? String
            ?? data["roomName"] as? String
            ?? inventoryDocument.id
        boxes = decodedBoxes
        leftovers = decodedLeftovers
        restricted = decodedRestricted
        self.openFirst = openFirst
        evidence = PackingV2Evidence(
            assignedCount: totalsBySize.values.reduce(0, +),
            reserveCount: reserveBySize.values.reduce(0, +),
            coverageGrade: coverageGrade,
            basedOn: basedOn,
            notIncluded: notIncluded,
            couldNotVerify: couldNotVerify,
            mostUncertain: mostUncertain
        )
    }

    private static func box(from data: [String: Any]) -> PackingV2Box? {
        guard let n = (data["n"] as? NSNumber)?.intValue,
              n > 0,
              let size = data["size"] as? String,
              !size.isEmpty,
              let lane = data["lane"] as? String,
              !lane.isEmpty,
              let itemData = data["items"] as? [[String: Any]],
              let layers = data["layers"] as? [String],
              let estMinutes = (data["estMinutes"] as? NSNumber)?.doubleValue,
              estMinutes > 0,
              let roomID = data["roomId"] as? String
        else { return nil }
        let items = itemData.compactMap { item -> PackingV2BoxItem? in
            guard let name = item["name"] as? String,
                  !name.isEmpty,
                  let qty = (item["qty"] as? NSNumber)?.intValue,
                  qty > 0
            else { return nil }
            return PackingV2BoxItem(name: name, qty: qty)
        }
        guard items.count == itemData.count else { return nil }
        return PackingV2Box(
            n: n,
            size: size,
            lane: lane,
            items: items,
            layers: layers,
            estMinutes: estMinutes,
            roomID: roomID
        )
    }

    private static func leftover(from data: [String: Any]) -> PackingV2Leftover? {
        guard let name = data["name"] as? String,
              !name.isEmpty,
              let note = data["handlingNote"] as? String,
              !note.isEmpty
        else { return nil }
        return PackingV2Leftover(name: name, handlingNote: note)
    }

    private static func restricted(from data: [String: Any]) -> PackingV2RestrictedItem? {
        guard let name = data["name"] as? String,
              !name.isEmpty,
              let policy = data["policy"] as? String,
              !policy.isEmpty
        else { return nil }
        return PackingV2RestrictedItem(name: name, policy: policy)
    }

    private static func coverageItem(from data: [String: Any]) -> PackingV2CoverageItem? {
        guard let name = data["name"] as? String,
              !name.isEmpty,
              let reason = data["reason"] as? String,
              !reason.isEmpty,
              let qty = (data["qty"] as? NSNumber)?.intValue,
              qty > 0
        else { return nil }
        return PackingV2CoverageItem(name: name, qty: qty, reason: reason)
    }

    private static func uncertainItem(from data: [String: Any]) -> PackingV2UncertainItem? {
        guard let name = data["name"] as? String,
              !name.isEmpty,
              let reasons = data["reasons"] as? [String],
              !reasons.isEmpty
        else { return nil }
        return PackingV2UncertainItem(name: name, reasons: reasons)
    }

    private static func nonnegativeCounts(_ value: Any?) -> [String: Int]? {
        guard let raw = value as? [String: Any] else { return nil }
        var result: [String: Int] = [:]
        for (key, value) in raw {
            guard let count = (value as? NSNumber)?.intValue,
                  count >= 0
            else { return nil }
            result[key] = count
        }
        return result
    }
}

nonisolated struct PackingV2DisplayBox: Equatable, Identifiable {
    let roomName: String
    let box: PackingV2Box

    var id: String { "\(box.roomID):\(box.n)" }
}

nonisolated struct PackingV2SessionPlan: Equatable {
    let boxes: [PackingV2DisplayBox]
    let leftovers: [PackingV2Leftover]
    let restricted: [PackingV2RestrictedItem]
    let openFirst: [String]
    let evidence: PackingV2Evidence
    let timeRange: PackingV2TimeRange
    let transportGuidance: [String: String]

    static func make(
        session: PackingSession,
        legacyPlan: PackingPlan,
        roomPlans: [PackingV2RoomPlan],
        configuration: PackingV2RenderConfiguration
    ) -> PackingV2SessionPlan? {
        guard !session.isFirstNightBag else { return nil }
        let orderedRoomPlans = session.rooms.compactMap { roomName in
            roomPlans.first { $0.name.caseInsensitiveCompare(roomName) == .orderedSame }
        }
        guard orderedRoomPlans.count == session.rooms.count else { return nil }

        var displayBoxes: [PackingV2DisplayBox] = []
        var leftovers: [PackingV2Leftover] = []
        var restricted: [PackingV2RestrictedItem] = []
        var openFirst: [String] = []

        for roomPlan in orderedRoomPlans {
            let matchingSessions = legacyPlan.sessions.filter { candidate in
                !candidate.isFirstNightBag && candidate.rooms.contains {
                    $0.caseInsensitiveCompare(roomPlan.name) == .orderedSame
                }
            }
            guard let position = matchingSessions.firstIndex(where: { $0.taskId == session.taskId })
            else { return nil }

            let boxSlice = slice(
                roomPlan.boxes,
                position: position,
                partitionCount: matchingSessions.count
            )
            displayBoxes.append(contentsOf: boxSlice.map {
                PackingV2DisplayBox(roomName: roomPlan.name, box: $0)
            })
            if position == matchingSessions.startIndex {
                restricted.append(contentsOf: roomPlan.restricted)
            }
            if position == matchingSessions.index(before: matchingSessions.endIndex) {
                leftovers.append(contentsOf: roomPlan.leftovers)
                openFirst.append(contentsOf: roomPlan.openFirst)
            }
        }

        let evidence = mergeEvidence(orderedRoomPlans.map(\.evidence))
        return PackingV2SessionPlan(
            boxes: displayBoxes,
            leftovers: unique(leftovers),
            restricted: unique(restricted),
            openFirst: unique(openFirst),
            evidence: evidence,
            timeRange: configuration.timeRange,
            transportGuidance: configuration.transportGuidance
        )
    }

    private static func slice<T>(_ values: [T], position: Int, partitionCount: Int) -> ArraySlice<T> {
        guard partitionCount > 0 else { return values[values.startIndex..<values.startIndex] }
        let baseCount = values.count / partitionCount
        let remainder = values.count % partitionCount
        let offset = (position * baseCount) + min(position, remainder)
        let count = baseCount + (position < remainder ? 1 : 0)
        return values[offset..<(offset + count)]
    }

    private static func mergeEvidence(_ values: [PackingV2Evidence]) -> PackingV2Evidence {
        PackingV2Evidence(
            assignedCount: values.reduce(0) { $0 + $1.assignedCount },
            reserveCount: values.reduce(0) { $0 + $1.reserveCount },
            coverageGrade: values.map(\.coverageGrade).contains("Limited")
                ? "Limited"
                : (values.map(\.coverageGrade).contains("Medium") ? "Medium" : "High"),
            basedOn: values.first?.basedOn ?? "",
            notIncluded: values.first?.notIncluded ?? "",
            couldNotVerify: unique(values.flatMap(\.couldNotVerify)),
            mostUncertain: unique(values.flatMap(\.mostUncertain))
        )
    }

    private static func unique<T: Identifiable>(_ values: [T]) -> [T] where T.ID: Hashable {
        var seen: Set<T.ID> = []
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
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
