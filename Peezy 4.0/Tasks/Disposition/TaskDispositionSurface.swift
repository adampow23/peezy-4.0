import FirebaseFirestore
import Foundation

// S4 (briefs/S4_BRIEF.md; S4-CD3): the sole producer of the shared task surface state (C9.5.24) over the stored
// `dispositionContract` map, the C9.5.20 superseded decoder (D18), the C9.5.21 formatter and copy (D19), the C9.5.22
// undo eligibility (D20), and the C9.5.23 history presentation (D21). Every task row, the Home queue, and the
// disposition views consume the union; no view decodes a stored contract itself.

// MARK: - D18: superseded stored shapes

/// `{source, supersededBy, supersededAt?, copy, detail:{kind:"DATE",at}?}` (C9.5.24).
struct SupersededPresentation: Equatable, Sendable {
    enum Source: String, Sendable { case v2, legacyV1 = "legacy_v1" }

    let source: Source
    let supersededBy: String
    let supersededAt: Date?
    let copy: String
    let detailAt: Date?

    /// C9.5.21: fresh v2 renders `Replaced — {formatter(detail.at)}`; legacy v1 renders the stored copy verbatim.
    func renderedCopy(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        switch source {
        case .v2:
            guard let detailAt else { return copy }
            return "\(copy) \u{2014} \(PlanChangeDateFormatter.string(from: detailAt, locale: locale, timeZone: timeZone))"
        case .legacyV1:
            return copy
        }
    }
}

enum SupersededDecodeResult: Equatable, Sendable {
    case notSuperseded
    case superseded(SupersededPresentation)
    /// Any hybrid/mismatch/missing/surplus superseded record.
    case malformedPresent
}

enum SupersededContractDecoder {
    static let v2Copy = "Replaced"
    static let legacyV1Copy = "Replaced by an updated task"
    static let taskDocumentIdPattern = #"^[A-Za-z0-9_-]{1,1500}$"#

    private static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }

    /// The C9.5.20 decoder over the raw stored map. A record whose `terminal_kind` is `superseded` decodes to exactly
    /// one of v2, legacy v1, or `malformedPresent`; anything else is not superseded.
    static func decode(_ raw: [String: Any]) -> SupersededDecodeResult {
        guard raw["terminal_kind"] as? String == "superseded" else { return .notSuperseded }
        let keys = Set(raw.keys)
        let schema = TaskGenerationEpochStamp.safeInteger(raw["schema_version"])
        switch schema {
        case 2:
            guard keys == ["schema_version", "terminal_kind", "superseded_by", "superseded_at", "visible_status_copy", "visible_status_detail"],
                  let supersededBy = raw["superseded_by"] as? String, !supersededBy.isEmpty,
                  raw["visible_status_copy"] as? String == v2Copy,
                  let supersededAt = date(raw["superseded_at"]),
                  let detail = raw["visible_status_detail"] as? [String: Any], Set(detail.keys) == ["kind", "at"], detail["kind"] as? String == "DATE",
                  let detailAt = date(detail["at"]), detailAt == supersededAt else { return .malformedPresent }
            return .superseded(SupersededPresentation(source: .v2, supersededBy: supersededBy, supersededAt: supersededAt, copy: v2Copy, detailAt: detailAt))
        case 1:
            guard keys == ["schema_version", "terminal_kind", "superseded_by", "visible_status_copy"],
                  let supersededBy = raw["superseded_by"] as? String, supersededBy.range(of: taskDocumentIdPattern, options: .regularExpression) != nil,
                  raw["visible_status_copy"] as? String == legacyV1Copy else { return .malformedPresent }
            return .superseded(SupersededPresentation(source: .legacyV1, supersededBy: supersededBy, supersededAt: nil, copy: legacyV1Copy, detailAt: nil))
        default:
            return .malformedPresent
        }
    }
}

// MARK: - D19: the frozen formatter

/// Gregorian calendar, current locale and time zone, `.medium` date style, no time (C9.5.21); locale and zone are
/// injectable for the day-rollover fixtures.
enum PlanChangeDateFormatter {
    static func string(from date: Date, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - D20: undo eligibility

/// The first-confirmation undo descriptor as the client holds it: exists exactly in the first CF while unused.
struct PlanChangeUndoDescriptor: Equatable, Sendable {
    let firstConfirmationUndoUntil: Date
    let used: Bool
    let inFirstConfirmation: Bool
}

enum PlanChangeUndo {
    /// Available only while the descriptor is in the first CF, unused, and the retry-scoped `server_write_time` is at
    /// or before `first_confirmation_undo_until`; the device clock never decides.
    static func isAvailable(_ descriptor: PlanChangeUndoDescriptor?, serverWriteTime: Date) -> Bool {
        guard let descriptor, descriptor.inFirstConfirmation, !descriptor.used else { return false }
        return serverWriteTime <= descriptor.firstConfirmationUndoUntil
    }
}

// MARK: - D21: history presentation

struct PlanChangeHistoryRow: Equatable, Sendable {
    enum Action: String, CaseIterable, Sendable {
        case supersede
        case replacementOutcome = "replacement_outcome"
        case confirmAmendment = "confirm_amendment"
        case undoConfirmation = "undo_confirmation"
        case reopen

        var title: String {
            switch self {
            case .supersede: return "Plan update started"
            case .replacementOutcome: return "Updated task outcome recorded"
            case .confirmAmendment: return "Plan update confirmed"
            case .undoConfirmation: return "Confirmation undone"
            case .reopen: return "Original task reopened"
            }
        }
    }

    let action: Action
    let occurredAt: Date
}

struct PlanChangeHistoryRollup: Equatable, Sendable {
    let count: Int
    let firstAt: Date
    let lastAt: Date
}

enum PlanChangeHistoryPresentation {
    /// `"{title} · {formatter(occurred_at)}"`.
    static func line(_ row: PlanChangeHistoryRow, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        "\(row.action.title) \u{00B7} \(PlanChangeDateFormatter.string(from: row.occurredAt, locale: locale, timeZone: timeZone))"
    }

    /// Byte-equal first/last dates collapse to one date; otherwise `{firstDate}–{lastDate}` (U+2013).
    static func rollupLine(_ rollup: PlanChangeHistoryRollup, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let first = PlanChangeDateFormatter.string(from: rollup.firstAt, locale: locale, timeZone: timeZone)
        let last = PlanChangeDateFormatter.string(from: rollup.lastAt, locale: locale, timeZone: timeZone)
        return first == last ? "Earlier plan changes (\(rollup.count)) \u{00B7} \(first)" : "Earlier plan changes (\(rollup.count)) \u{00B7} \(first)\u{2013}\(last)"
    }

    /// Ordinary rows in exact reverse of their stored append order, then the sole rollup once as the final row.
    static func lines(rows: [PlanChangeHistoryRow], rollup: PlanChangeHistoryRollup?, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> [String] {
        var lines = rows.reversed().map { line($0, locale: locale, timeZone: timeZone) }
        if let rollup { lines.append(rollupLine(rollup, locale: locale, timeZone: timeZone)) }
        return lines
    }
}

// MARK: - S4-CD3: the shared surface state

enum TaskDispositionReadOnlyReason: String, CaseIterable, Sendable {
    case completed
    case dismissed
    case malformedPresent = "malformed_present"
    case gateNonclear = "gate_nonclear"
    case storeBlocked = "store_blocked"
}

enum TaskDispositionSurfaceState: Equatable, Sendable {
    /// A policy-absent or policy-bearing nonterminal contract whose row buttons are enabled.
    case actionable
    /// `contract` absent only for `malformed_present`.
    case readOnly(reason: TaskDispositionReadOnlyReason, contractPresent: Bool)
    case superseded(SupersededPresentation)

    var isActionable: Bool { if case .actionable = self { return true }; return false }
}

enum TaskDispositionSurface {
    /// The required set the task row's operations depend on: a blocked route or handoff store makes every row read-only.
    static let requiredStores: [DurableStore] = [.route, .handoff]

    /// The raw-input seam of C9.5.24: the stored map unmodified (never the card mapper's projection).
    static func state(rawContract: [String: Any]?, status: TaskStatus, gateProjection: AccountDeletionGateProjection, readiness: ReadinessVector) -> TaskDispositionSurfaceState {
        let present = rawContract != nil
        if gateProjection != .clear { return .readOnly(reason: .gateNonclear, contractPresent: present) }
        if requiredStores.contains(where: { if case .blocked = readiness[$0] { return true }; return false }) { return .readOnly(reason: .storeBlocked, contractPresent: present) }
        if let rawContract {
            switch SupersededContractDecoder.decode(rawContract) {
            case let .superseded(presentation): return .superseded(presentation)
            case .malformedPresent: return .readOnly(reason: .malformedPresent, contractPresent: false)
            case .notSuperseded: break
            }
            if let disposition = rawContract["disposition"] as? String {
                if disposition == "COMPLETED" { return .readOnly(reason: .completed, contractPresent: true) }
                if disposition == "NOT_APPLICABLE" || rawContract["terminal_kind"] != nil { return .readOnly(reason: .dismissed, contractPresent: true) }
            }
        }
        switch status {
        case .completed: return .readOnly(reason: .completed, contractPresent: present)
        case .dismissed: return .readOnly(reason: .dismissed, contractPresent: present)
        default: return .actionable
        }
    }

    /// The one line a row shows beneath its header for a nonactionable state; nil for actionable rows.
    static func statusLine(for state: TaskDispositionSurfaceState) -> String? {
        switch state {
        case .actionable: return nil
        case let .superseded(presentation): return presentation.renderedCopy()
        case let .readOnly(reason, _):
            switch reason {
            case .completed, .dismissed: return nil
            case .malformedPresent: return "This task's status could not be read."
            case .gateNonclear: return "Actions are paused while your account is being cleared."
            case .storeBlocked: return "Actions are paused until local recovery finishes."
            }
        }
    }
}
