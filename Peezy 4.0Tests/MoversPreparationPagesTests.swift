import SwiftUI
import Testing
import UIKit
@testable import Peezy_4_0

@MainActor
struct MoversPreparationPagesTests {
    private let fullSay = [
        "Volunteer your access info before they ask: stairs, elevator, long walks, how far the truck parks from the door. Hourly crews bill the walk.",
        "Name every specialty item: piano, safe, treadmill, anything oversized.",
        "Tell them you want the packing quote included."
    ]
    private let fullAsk = [
        "Is pricing port-to-port hourly, or a fixed travel fee?",
        "How do you charge for supplies — percentage, per item, or can I supply my own?",
        "What does full-value protection cost for my move?",
        "What are the fees for specialty items?"
    ]
    private let fullGet = [
        "The quote in writing, with crew size, hourly rate, and travel fee broken out.",
        "Their COI turnaround time if your building needs one."
    ]

    private var fullCallSheet: TaskCallSheet {
        TaskCallSheet(data: [
            "say": fullSay,
            "ask": fullAsk,
            "get": fullGet
        ])!
    }

    @Test func educationCopyAndPageOrderAreExact() throws {
        let pages = MoversFlowViewModel.buildPreparationPages(callSheet: fullCallSheet)

        #expect(pages.count == 8)
        #expect(pages.map(\.accessibilityPrefix) == [
            "movers.education.valuationRule",
            "movers.education.valuationMath",
            "movers.education.valuationAction",
            "movers.education.estimates",
            "movers.equip",
            "movers.equip.say",
            "movers.equip.ask",
            "movers.equip.get"
        ])

        let expectedEducation = [
            (
                "If something breaks",
                "By law, moving companies only have to pay 60 cents per pound for anything damaged beyond repair.",
                "shield.lefthalf.filled"
            ),
            (
                "What that means in real money",
                "Say your $1,000 TV weighs 50 pounds and gets destroyed. They legally owe you $30. Not $1,000 — $30.",
                "shield.lefthalf.filled"
            ),
            (
                "What to do about it",
                "If that doesn't worry you, skip it. If it does, ask every company what additional coverage costs and exactly what it covers — before you book.",
                "shield.lefthalf.filled"
            ),
            (
                "How quotes really work",
                "A quote is a guess: their hourly rate × how long they think it'll take. A lower total usually just means a smaller guess — the job costs whatever it actually takes. Compare the hourly rates and crew sizes, not the totals.",
                "clock.badge.questionmark"
            )
        ]

        for (page, expected) in zip(pages.prefix(4), expectedEducation) {
            #expect(page.kind == .education)
            #expect(page.title == expected.0)
            #expect(page.body == expected.1)
            #expect(page.systemImage == expected.2)
        }

        #expect(pages[4].kind == .intro)
        #expect(pages[4].title == "Get three quotes")
        #expect(
            pages[4].body
                == "Give every company the same facts, then get the rate and time estimate in writing."
        )
        #expect(pages[5].kind == .callSheetSection(items: fullSay))
        #expect(pages[6].kind == .callSheetSection(items: fullAsk))
        #expect(pages[7].kind == .callSheetSection(items: fullGet))
        assertFinalAction(pages)
    }

    @Test func finalActionFollowsEveryCallSheetComposition() throws {
        let fixtures: [(String, TaskCallSheet?, Int, String)] = [
            ("full", fullCallSheet, 8, "movers.equip.get"),
            ("nil", nil, 5, "movers.equip"),
            ("leading empty", sheet(say: [], ask: fullAsk, get: fullGet), 7, "movers.equip.get"),
            ("trailing empty", sheet(say: fullSay, ask: fullAsk, get: []), 7, "movers.equip.ask"),
            ("multiple trailing empty", sheet(say: fullSay, ask: [], get: []), 6, "movers.equip.say"),
            ("only say", sheet(say: fullSay, ask: [], get: []), 6, "movers.equip.say"),
            ("only ask", sheet(say: [], ask: fullAsk, get: []), 6, "movers.equip.ask"),
            ("only get", sheet(say: [], ask: [], get: fullGet), 6, "movers.equip.get"),
            ("all empty", sheet(say: [], ask: [], get: []), 5, "movers.equip")
        ]

        for (name, callSheet, expectedCount, expectedFinalPrefix) in fixtures {
            let pages = MoversFlowViewModel.buildPreparationPages(callSheet: callSheet)
            #expect(pages.count == expectedCount, Comment(rawValue: name))
            #expect(
                pages.last?.accessibilityPrefix == expectedFinalPrefix,
                Comment(rawValue: name)
            )
            assertFinalAction(pages, fixture: name)
        }
    }

    @Test func blankFilteringIsPredicateOnlyAndNeverRewritesCatalogCopy() throws {
        let preservedSay = "  Keep this catalog spacing exactly.  "
        let preservedAsk = "\tAsk with tabs intact.\t"
        let callSheet = try #require(sheet(
            say: ["   ", "\n\t", preservedSay],
            ask: [preservedAsk],
            get: [" \n "]
        ))

        let pages = MoversFlowViewModel.buildPreparationPages(callSheet: callSheet)

        #expect(pages.count == 7)
        #expect(pages[5].kind == .callSheetSection(items: [preservedSay]))
        #expect(pages[6].kind == .callSheetSection(items: [preservedAsk]))
        #expect(!pages.contains { $0.accessibilityPrefix == "movers.equip.get" })
        assertFinalAction(pages)

        let whitespaceOnly = MoversFlowViewModel.buildPreparationPages(
            callSheet: sheet(say: [" \t\n "], ask: [], get: [])
        )
        #expect(whitespaceOnly.count == 5)
        #expect(whitespaceOnly.last?.kind == .intro)
        assertFinalAction(whitespaceOnly)
    }

    @Test func preparationIndexIsBoundsGuardedInBothDirections() {
        let model = makeModel(stage: .preparation, callSheet: fullCallSheet)
        let lastIndex = model.preparationPages.count - 1

        for _ in 0..<(model.preparationPages.count + 3) {
            model.advancePreparation()
        }
        #expect(model.preparationIndex == lastIndex)
        let finalPage = model.preparationPages[model.preparationIndex]

        model.advancePreparation()
        model.advancePreparation()
        #expect(model.preparationIndex == lastIndex)
        #expect(model.preparationPages[model.preparationIndex] == finalPage)

        for _ in 0..<(model.preparationPages.count + 3) {
            model.backPreparation()
        }
        #expect(model.preparationIndex == 0)
        let firstPage = model.preparationPages[model.preparationIndex]

        model.backPreparation()
        model.backPreparation()
        #expect(model.preparationIndex == 0)
        #expect(model.preparationPages[model.preparationIndex] == firstPage)

        for _ in 0..<model.preparationPages.count {
            model.advancePreparation()
        }
        #expect(model.preparationIndex == lastIndex)
        #expect(model.preparationPages[model.preparationIndex] == finalPage)

        for _ in 0..<model.preparationPages.count {
            model.backPreparation()
        }
        #expect(model.preparationIndex == 0)
        #expect(model.preparationPages[model.preparationIndex] == firstPage)
    }

    @Test func stackCounterMatchesTheFrozenTruthTable() {
        let preparationCount = 8

        assertCounter(
            role: .getQuotes,
            legacy: false,
            stage: .loading,
            preparationIndex: 0,
            expected: (0, preparationCount + 1)
        )
        assertCounter(
            role: .getQuotes,
            legacy: false,
            stage: .failure,
            preparationIndex: 0,
            expected: (0, preparationCount + 1)
        )
        for index in 0..<preparationCount {
            assertCounter(
                role: .getQuotes,
                legacy: false,
                stage: .preparation,
                preparationIndex: index,
                expected: (index, (preparationCount + 1) - index)
            )
        }
        assertCounter(
            role: .getQuotes,
            legacy: false,
            stage: .confirmation,
            preparationIndex: preparationCount - 1,
            expected: (preparationCount, 1)
        )

        for (stage, expected) in [
            (MoversFlowStage.loading, (0, 5)),
            (.failure, (0, 5)),
            (.quotes, (3, 2)),
            (.matrix, (4, 1)),
            (.confirmation, (4, 1))
        ] {
            assertCounter(role: .getQuotes, legacy: true, stage: stage, expected: expected)
            assertCounter(role: .compareQuotes, legacy: false, stage: stage, expected: expected)
        }
    }

    @Test func counterProgressionPreservesRouteTransitionIdentity() {
        let nonLegacy = (0..<8).map { index -> Int in
            let model = makeModel(stage: .preparation, callSheet: fullCallSheet, preparationIndex: index)
            return model.currentCardIndex
        } + [makeModel(stage: .confirmation, callSheet: fullCallSheet).currentCardIndex]
        #expect(nonLegacy == Array(0...8))

        let compare = [MoversFlowStage.loading, .quotes, .matrix, .confirmation].map { stage -> (Int, Int) in
            let model = makeModel(role: .compareQuotes, stage: stage, callSheet: fullCallSheet)
            return (model.currentCardIndex, model.cardsRemaining)
        }
        #expect(compare.map(\.0) == [0, 3, 4, 4])
        #expect(compare.map(\.1) == [5, 2, 1, 1])
    }

    @Test @MainActor func defaultDynamicTypeFitsEveryProductionPageAtSEClassFloor() {
        let configurations = hostedConfigurations()
        #expect(configurations.count == 9)

        for configuration in configurations {
            let hosted = host(configuration: configuration, dynamicTypeSize: .large)
            let identifiers = accessibilityIdentifiers(in: hosted.controller.view)
            let fitID = "\(configuration.page.accessibilityPrefix).fit"
            let scrollID = "\(configuration.page.accessibilityPrefix).scroll"

            #expect(identifiers.contains(fitID), Comment(rawValue: configuration.name))
            #expect(!identifiers.contains(scrollID), Comment(rawValue: configuration.name))
            #expect(
                scrollViews(in: hosted.controller.view).isEmpty,
                Comment(rawValue: configuration.name)
            )
        }
    }

    @Test @MainActor func accessibility5SelectsExactlyOneBranchAndScrollsToContentBottom() {
        let configurations = hostedConfigurations()
        var longestEducationUsesScroll = false

        for configuration in configurations {
            let hosted = host(configuration: configuration, dynamicTypeSize: .accessibility5)
            let identifiers = accessibilityIdentifiers(in: hosted.controller.view)
            let fitID = "\(configuration.page.accessibilityPrefix).fit"
            let scrollID = "\(configuration.page.accessibilityPrefix).scroll"
            let hasFit = identifiers.contains(fitID)
            let hasScroll = identifiers.contains(scrollID)

            #expect(hasFit != hasScroll, Comment(rawValue: configuration.name))

            if hasScroll {
                let scrollingViews = scrollViews(in: hosted.controller.view)
                    .filter { $0.contentSize.height > $0.bounds.height + 0.5 }
                let scrollView = scrollingViews.max { $0.contentSize.height < $1.contentSize.height }
                #expect(scrollView != nil, Comment(rawValue: configuration.name))
                if let scrollView {
                    let bottomOffset = max(
                        -scrollView.adjustedContentInset.top,
                        scrollView.contentSize.height
                            - scrollView.bounds.height
                            + scrollView.adjustedContentInset.bottom
                    )
                    scrollView.setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: false)
                    scrollView.layoutIfNeeded()
                    #expect(
                        abs(scrollView.contentOffset.y - bottomOffset) < 1,
                        Comment(rawValue: configuration.name)
                    )
                    #expect(
                        scrollView.contentOffset.y
                            + scrollView.bounds.height
                            - scrollView.adjustedContentInset.bottom
                            >= scrollView.contentSize.height - 1,
                        Comment(rawValue: configuration.name)
                    )
                }
            }

            if configuration.page.accessibilityPrefix == "movers.education.estimates" {
                longestEducationUsesScroll = hasScroll
            }
        }

        #expect(longestEducationUsesScroll)
    }

    @Test @MainActor func accessibilityIdentifierSetIsExplicit() {
        var observed: Set<String> = []
        for configuration in hostedConfigurations() {
            for dynamicTypeSize in [DynamicTypeSize.large, .accessibility5] {
                let hosted = host(
                    configuration: configuration,
                    dynamicTypeSize: dynamicTypeSize
                )
                observed.formUnion(accessibilityIdentifiers(in: hosted.controller.view))
            }
        }

        let errorPage = MoversFlowViewModel.buildPreparationPages(callSheet: nil)[4]
        let errorConfiguration = HostedConfiguration(
            name: "intro error",
            page: errorPage,
            hasSubmittedInventory: true,
            actionError: "Try again."
        )
        let errorHosted = host(configuration: errorConfiguration, dynamicTypeSize: .large)
        observed.formUnion(accessibilityIdentifiers(in: errorHosted.controller.view))

        // Branch ids are asserted as "at least one per page": which branch a
        // page selects at a given size is layout behavior (owned by the fit
        // and accessibility tests above), so requiring `.scroll` here would
        // silently demand that every page overflows at accessibility sizes.
        let branchPrefixes = [
            "movers.education.valuationRule",
            "movers.education.valuationMath",
            "movers.education.valuationAction",
            "movers.education.estimates",
            "movers.equip",
            "movers.equip.say",
            "movers.equip.ask",
            "movers.equip.get"
        ]
        let allBranchIDs = Set(branchPrefixes.flatMap { ["\($0).fit", "\($0).scroll"] })
        let requiredCore = Set([
            "movers.education.valuationRule.title",
            "movers.education.valuationRule.message",
            "movers.education.valuationRule.card",
            "movers.education.valuationRule.continue",
            "movers.education.valuationRule.screen",
            "movers.education.valuationMath.title",
            "movers.education.valuationMath.message",
            "movers.education.valuationMath.card",
            "movers.education.valuationMath.continue",
            "movers.education.valuationMath.screen",
            "movers.education.valuationAction.title",
            "movers.education.valuationAction.message",
            "movers.education.valuationAction.card",
            "movers.education.valuationAction.continue",
            "movers.education.valuationAction.screen",
            "movers.education.estimates.title",
            "movers.education.estimates.message",
            "movers.education.estimates.card",
            "movers.education.estimates.continue",
            "movers.education.estimates.screen",
            "movers.equip.title",
            "movers.equip.intro",
            "movers.equip.shareInventory",
            "movers.equip.inventoryMissing",
            "movers.equip.inventoryCard",
            "movers.equip.error",
            "movers.equip.getQuotes",
            "movers.equip.screen",
            "movers.equip.say",
            "movers.equip.ask",
            "movers.equip.get"
        ])

        #expect(
            requiredCore.isSubset(of: observed),
            Comment(rawValue: "Missing: \(requiredCore.subtracting(observed).sorted())")
        )
        #expect(
            observed.isSubset(of: requiredCore.union(allBranchIDs)),
            Comment(
                rawValue: "Unexpected: \(observed.subtracting(requiredCore.union(allBranchIDs)).sorted())"
            )
        )
        for prefix in branchPrefixes {
            #expect(
                observed.contains("\(prefix).fit") || observed.contains("\(prefix).scroll"),
                Comment(rawValue: "No branch id observed for \(prefix)")
            )
        }
        #expect(!observed.contains { $0.hasPrefix("movers.education.protection") })
        #expect(!observed.contains { $0.hasSuffix(".callout") })
    }

    private func assertFinalAction(
        _ pages: [MoversPreparationPage],
        fixture: String = "pages",
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let finalIndexes = pages.indices.filter { pages[$0].primary == .getQuotes }
        #expect(
            finalIndexes == [pages.count - 1],
            Comment(rawValue: fixture),
            sourceLocation: sourceLocation
        )
        #expect(
            pages.dropLast().allSatisfy { $0.primary == .advance },
            Comment(rawValue: fixture),
            sourceLocation: sourceLocation
        )
    }

    private func sheet(say: [String], ask: [String], get: [String]) -> TaskCallSheet? {
        TaskCallSheet(data: ["say": say, "ask": ask, "get": get])
    }

    private func makeModel(
        role: MoversFlowRole = .getQuotes,
        stage: MoversFlowStage,
        legacy: Bool = false,
        callSheet: TaskCallSheet?,
        preparationIndex: Int = 0
    ) -> MoversFlowViewModel {
        let model = MoversFlowViewModel(role: role)
        model._testConfigure(
            userId: "test-user",
            taskDocumentId: "test-task",
            quotes: [],
            stage: stage,
            isLegacyInline: legacy,
            callSheet: callSheet,
            preparationIndex: preparationIndex
        )
        return model
    }

    private func assertCounter(
        role: MoversFlowRole,
        legacy: Bool,
        stage: MoversFlowStage,
        preparationIndex: Int = 0,
        expected: (Int, Int),
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let model = makeModel(
            role: role,
            stage: stage,
            legacy: legacy,
            callSheet: fullCallSheet,
            preparationIndex: preparationIndex
        )
        #expect(model.currentCardIndex == expected.0, sourceLocation: sourceLocation)
        #expect(model.cardsRemaining == expected.1, sourceLocation: sourceLocation)
    }

    private struct HostedConfiguration {
        let name: String
        let page: MoversPreparationPage
        let hasSubmittedInventory: Bool
        var actionError: String? = nil
    }

    private func hostedConfigurations() -> [HostedConfiguration] {
        let pages = MoversFlowViewModel.buildPreparationPages(callSheet: fullCallSheet)
        return pages.flatMap { page in
            if page.kind == .intro {
                return [
                    HostedConfiguration(
                        name: "intro with inventory",
                        page: page,
                        hasSubmittedInventory: true
                    ),
                    HostedConfiguration(
                        name: "intro without inventory",
                        page: page,
                        hasSubmittedInventory: false
                    )
                ]
            }
            return [
                HostedConfiguration(
                    name: page.accessibilityPrefix,
                    page: page,
                    hasSubmittedInventory: true
                )
            ]
        }
    }

    @MainActor
    private final class HostedPage {
        let window: UIWindow
        let controller: UIHostingController<AnyView>

        init(rootView: AnyView) {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
            controller = UIHostingController(rootView: rootView)
            window.rootViewController = controller
            window.isHidden = false
            controller.view.frame = window.bounds
        }
    }

    @MainActor
    private func host(
        configuration: HostedConfiguration,
        dynamicTypeSize: DynamicTypeSize
    ) -> HostedPage {
        let pageView: AnyView
        switch configuration.page.kind {
        case .education:
            pageView = AnyView(
                MoversEducationView(
                    headerTitle: "Get moving quotes",
                    title: configuration.page.title,
                    message: configuration.page.body ?? "",
                    callout: nil,
                    systemImage: configuration.page.systemImage,
                    accessibilityPrefix: configuration.page.accessibilityPrefix,
                    showBack: configuration.page.accessibilityPrefix != "movers.education.valuationRule",
                    onBack: {},
                    onContinue: {}
                )
            )
        case .intro, .callSheetSection:
            pageView = AnyView(
                MoversEquipView(
                    headerTitle: "Get moving quotes",
                    page: configuration.page,
                    inventoryRooms: [],
                    hasSubmittedInventory: configuration.hasSubmittedInventory,
                    showBack: true,
                    isCompleting: false,
                    actionError: configuration.actionError,
                    onBack: {},
                    onPrimary: {}
                )
            )
        }

        let rootView = AnyView(
            TaskFlowStack(cardsRemaining: 9, currentIndex: 0) {
                pageView
            }
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        )
        let hosted = HostedPage(rootView: rootView)
        hosted.window.makeKeyAndVisible()
        hosted.controller.view.setNeedsLayout()
        hosted.controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosted.controller.view.setNeedsLayout()
        hosted.controller.view.layoutIfNeeded()
        return hosted
    }

    private func accessibilityIdentifiers(in root: UIView) -> Set<String> {
        var identifiers: Set<String> = []
        var visited: Set<ObjectIdentifier> = []
        let pattern = try! NSRegularExpression(pattern: #"movers\.[A-Za-z0-9.]+"#)

        func recordIdentifiers(reflecting object: AnyObject) {
            let description = String(reflecting: object)
            let range = NSRange(description.startIndex..., in: description)
            for match in pattern.matches(in: description, range: range) {
                guard let matchRange = Range(match.range, in: description) else { continue }
                identifiers.insert(String(description[matchRange]))
            }
        }

        func visit(_ object: AnyObject) {
            let objectID = ObjectIdentifier(object)
            guard visited.insert(objectID).inserted else { return }

            if let identifiable = object as? UIAccessibilityIdentification,
               let identifier = identifiable.accessibilityIdentifier,
               !identifier.isEmpty {
                identifiers.insert(identifier)
            }
            recordIdentifiers(reflecting: object)

            if let view = object as? UIView {
                view.subviews.forEach { visit($0) }
                view.accessibilityElements?.forEach { element in
                    visit(element as AnyObject)
                }
                let count = view.accessibilityElementCount()
                if count != NSNotFound, count > 0 {
                    for index in 0..<count {
                        if let element = view.accessibilityElement(at: index) as AnyObject? {
                            visit(element)
                        }
                    }
                }
            }

            for child in Mirror(reflecting: object).children {
                recordIdentifiers(reflecting: child.value as AnyObject)
                if child.label == "children" {
                    for nested in Mirror(reflecting: child.value).children {
                        visit(nested.value as AnyObject)
                    }
                }
            }
        }

        visit(root)
        return identifiers
    }

    private func scrollViews(in root: UIView) -> [UIScrollView] {
        root.subviews.reduce(root is UIScrollView ? [root as! UIScrollView] : []) { result, subview in
            result + scrollViews(in: subview)
        }
    }
}
