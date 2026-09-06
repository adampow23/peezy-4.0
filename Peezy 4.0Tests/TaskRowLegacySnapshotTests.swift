import FirebaseFirestore
import Foundation
import Testing
@testable import Peezy_4_0

/// S4 (D18/D19): the byte-exact legacy v1 fixture the committed mapper wrote, every malformed shape, and the row copy
/// each source renders (legacy verbatim; fresh v2 `Replaced — {date}`).
struct TaskRowLegacySnapshotTests {
    /// The one byte-exact v1 fixture (C9.5.20): committed nonblank task-document-ID grammar, the verbatim copy.
    static let legacyFixtureJSON = #"{"schema_version":1,"superseded_by":"a2_b6c1f0d9","terminal_kind":"superseded","visible_status_copy":"Replaced by an updated task"}"#

    var legacyFixture: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(Self.legacyFixtureJSON.utf8)) as? [String: Any]) ?? [:]
    }

    @Test func legacyV1FixtureDecodesVerbatimAndNeverResolvesAsAnInstanceLink() {
        guard case let .superseded(presentation) = SupersededContractDecoder.decode(legacyFixture) else { Issue.record("legacy"); return }
        #expect(presentation.source == .legacyV1 && presentation.supersededBy == "a2_b6c1f0d9" && presentation.supersededAt == nil && presentation.detailAt == nil)
        #expect(presentation.copy == "Replaced by an updated task" && presentation.renderedCopy() == "Replaced by an updated task", "no separator, no date")
        #expect(TaskCanonicalV1.data(legacyFixture) == Data(Self.legacyFixtureJSON.utf8), "the fixture is byte-exact canonical JSON")
        #expect(SupersededContractDecoder.decode(["disposition": "USER_ACTION_TRACKED"]) == .notSuperseded)
    }

    @Test func everyMalformedLegacyShapeIsMalformedPresent() {
        var wrongCopy = legacyFixture; wrongCopy["visible_status_copy"] = "Replaced"
        var wrongType = legacyFixture; wrongType["superseded_by"] = 7
        var invalidId = legacyFixture; invalidId["superseded_by"] = "bad/id"
        var blank = legacyFixture; blank["superseded_by"] = ""
        var missing = legacyFixture; missing["superseded_by"] = nil
        var surplus = legacyFixture; surplus["superseded_at"] = Timestamp(date: Date())
        var schemaless = legacyFixture; schemaless["schema_version"] = nil
        var hybrid = legacyFixture; hybrid["visible_status_detail"] = ["kind": "DATE", "at": Timestamp(date: Date())]
        for (name, shape) in [("wrong copy", wrongCopy), ("wrong type", wrongType), ("invalid id", invalidId), ("blank", blank), ("missing", missing), ("surplus", surplus), ("schema-less", schemaless), ("hybrid", hybrid)] {
            #expect(SupersededContractDecoder.decode(shape) == .malformedPresent, Comment(rawValue: name))
            #expect(TaskDispositionSurface.state(rawContract: shape, status: .upcoming, gateProjection: .clear, readiness: ReadinessVector()) == .readOnly(reason: .malformedPresent, contractPresent: false), Comment(rawValue: "\(name) surface"))
        }
    }

    @Test func freshV2RendersReplacedWithTheFrozenFormatterDate() {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let raw: [String: Any] = ["schema_version": 2, "terminal_kind": "superseded", "superseded_by": "inst_7", "superseded_at": Timestamp(date: at), "visible_status_copy": "Replaced", "visible_status_detail": ["kind": "DATE", "at": Timestamp(date: at)]]
        guard case let .superseded(presentation) = SupersededContractDecoder.decode(raw) else { Issue.record("v2"); return }
        let posix = Locale(identifier: "en_US_POSIX")
        let utc = TimeZone(identifier: "UTC")!
        #expect(presentation.renderedCopy(locale: posix, timeZone: utc) == "Replaced \u{2014} Jan 15, 2027")
        #expect(presentation.renderedCopy(locale: posix, timeZone: utc).hasPrefix("Replaced \u{2014} "), "one ASCII space each side of U+2014, no suffix")
        var dateOnly = raw; dateOnly["superseded_at"] = at; (dateOnly["visible_status_detail"] as? [String: Any]).map { _ in dateOnly["visible_status_detail"] = ["kind": "DATE", "at": at] }
        #expect(SupersededContractDecoder.decode(dateOnly) == .superseded(presentation), "a Date and a Timestamp denote the same instant")
        var wrongKind = raw; wrongKind["visible_status_detail"] = ["kind": "TIME", "at": Timestamp(date: at)]
        #expect(SupersededContractDecoder.decode(wrongKind) == .malformedPresent)
        var v1Copy = raw; v1Copy["visible_status_copy"] = "Replaced by an updated task"
        #expect(SupersededContractDecoder.decode(v1Copy) == .malformedPresent, "a fresh write with the v1 copy rejects")
    }
}
