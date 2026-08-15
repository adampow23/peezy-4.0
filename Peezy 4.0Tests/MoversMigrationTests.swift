import Foundation
import Testing
@testable import Peezy_4_0

struct MoversMigrationTests {

    // MARK: - Legacy predicate (plan A5)

    @Test func stageAloneClassifiesLegacy() {
        #expect(MoversLegacyClassifier.isLegacyInline(stageRaw: "compare", quotesCount: 0))
        #expect(MoversLegacyClassifier.isLegacyInline(stageRaw: "verify", quotesCount: 0))
        // .complete is legacy-terminal residue: the old flow wrote it before
        // Home's detached, failure-swallowing status write.
        #expect(MoversLegacyClassifier.isLegacyInline(stageRaw: "complete", quotesCount: 0))
    }

    @Test func quotesAloneClassifyLegacyRegardlessOfStage() {
        #expect(MoversLegacyClassifier.isLegacyInline(stageRaw: nil, quotesCount: 2))
        #expect(MoversLegacyClassifier.isLegacyInline(stageRaw: "notStarted", quotesCount: 1))
    }

    @Test func bothSignalsClassifyLegacy() {
        #expect(MoversLegacyClassifier.isLegacyInline(stageRaw: "verify", quotesCount: 3))
    }

    @Test func stateFreeDocsAreChain() {
        #expect(!MoversLegacyClassifier.isLegacyInline(stageRaw: nil, quotesCount: 0))
        #expect(!MoversLegacyClassifier.isLegacyInline(stageRaw: "notStarted", quotesCount: 0))
        #expect(!MoversLegacyClassifier.isLegacyInline(stageRaw: "capture", quotesCount: 0))
        #expect(!MoversLegacyClassifier.isLegacyInline(stageRaw: "garbage-value", quotesCount: 0))
    }

    // MARK: - Title migration payload (round-4 finding 1 + round-5 finding 3)

    @Test func stateFreePayloadUsesExactTitleAndDescKeys() throws {
        let payload = try #require(MoversTitleMigration.payload(
            isLegacyInline: false,
            currentTitle: "Book your movers"
        ))
        // Exact keys: `title` and `desc` — the stored/read field is `desc`,
        // never `description`. Nothing else may ride along (quote safety).
        #expect(Set(payload.keys) == ["title", "desc"])
        #expect(payload["title"] as? String == "Get Moving Quotes")
        #expect(payload["desc"] as? String == MoversTitleMigration.chainDesc)
    }

    @Test func legacyPayloadGetsTheLegacyTitle() throws {
        let payload = try #require(MoversTitleMigration.payload(
            isLegacyInline: true,
            currentTitle: "Book your movers"
        ))
        #expect(Set(payload.keys) == ["title", "desc"])
        #expect(payload["title"] as? String == "Compare your moving quotes")
        #expect(payload["desc"] as? String == MoversTitleMigration.legacyDesc)
    }

    @Test func matchingTitleProducesNoPayload() {
        #expect(MoversTitleMigration.payload(
            isLegacyInline: false,
            currentTitle: "Get Moving Quotes"
        ) == nil)
        #expect(MoversTitleMigration.payload(
            isLegacyInline: true,
            currentTitle: "Compare your moving quotes"
        ) == nil)
    }

    // MARK: - Predecessor company chips (plan A3)

    @Test func chipsDedupCaseInsensitivelyPreservingOrder() {
        let chips = MoversPredecessorChips.companyChips(fromQuotesData: [
            ["company": "Acme Moving"],
            ["company": "  Bravo Bros  "],
            ["company": "acme moving"],
            ["company": "Bravo Bros"],
            ["company": "Charlie & Co"]
        ])
        #expect(chips == ["Acme Moving", "Bravo Bros", "Charlie & Co"])
    }

    @Test func chipsSkipEmptyAndMalformedEntries() {
        let chips = MoversPredecessorChips.companyChips(fromQuotesData: [
            ["company": "   "],
            ["notes": "no company key"],
            ["company": 42],
            ["company": "Real Mover"]
        ])
        #expect(chips == ["Real Mover"])
    }

    @Test func emptyQuotesYieldNoChips() {
        #expect(MoversPredecessorChips.companyChips(fromQuotesData: []).isEmpty)
    }
}
