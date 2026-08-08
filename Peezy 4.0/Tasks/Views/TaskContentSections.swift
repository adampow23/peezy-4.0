import FirebaseFirestore
import Observation
import SwiftUI

// MARK: - Content model (Spec 09 Phase 5)

/// Catalog-owned surface content for the gated task detail. Content lives on
/// `taskCatalog/{taskId}` only — never copied onto user task docs — so a
/// Firestore edit ships new copy without a release.
struct TaskContent: Equatable {
    let reframe: String
    let insiderItems: [String]
    let callSheet: TaskCallSheet?
    let tripKit: TaskTripKit?
    let walkthrough: [String]
    let deepLink: URL?
    let notesEnabled: Bool
    let quoteTracker: String

    init(data: [String: Any]) {
        reframe = data["reframe"] as? String ?? ""
        insiderItems = data["insiderItems"] as? [String] ?? []
        callSheet = (data["callSheet"] as? [String: Any]).flatMap(TaskCallSheet.init(data:))
        tripKit = (data["tripKit"] as? [String: Any]).flatMap(TaskTripKit.init(data:))
        walkthrough = data["walkthrough"] as? [String] ?? []
        deepLink = (data["deepLink"] as? String).flatMap(Self.safeURL(from:))
        notesEnabled = (data["notesEnabled"] as? NSNumber)?.boolValue ?? false
        quoteTracker = (data["quoteTracker"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "none"
    }

    var hasDetailContent: Bool {
        !reframe.isEmpty
            || !insiderItems.isEmpty
            || callSheet != nil
            || tripKit != nil
            || !walkthrough.isEmpty
            || deepLink != nil
            || notesEnabled
            || quoteTracker != "none"
    }

    private static func safeURL(from string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }
}

struct TaskCallSheet: Equatable {
    let say: [String]
    let ask: [String]
    let get: [String]

    init?(data: [String: Any]) {
        say = data["say"] as? [String] ?? []
        ask = data["ask"] as? [String] ?? []
        get = data["get"] as? [String] ?? []
        guard !(say.isEmpty && ask.isEmpty && get.isEmpty) else { return nil }
    }
}

struct TaskTripKit: Equatable {
    let docs: [String]

    init?(data: [String: Any]) {
        docs = data["docs"] as? [String] ?? []
        guard !docs.isEmpty else { return nil }
    }
}

// MARK: - Store

/// Per-task catalog cache behind the detail surface. The detail view model
/// reads task metadata and surface content from this one payload — the
/// single catalog fetch path (no second Firestore→PeezyCard decoder).
@MainActor
@Observable
final class TaskContentStore {
    static let shared = TaskContentStore()

    private var cache: [String: [String: Any]] = [:]

    func catalogData(for taskId: String) async -> [String: Any] {
        guard !taskId.isEmpty else { return [:] }
        if let cached = cache[taskId] { return cached }
        guard let snapshot = try? await Firestore.firestore()
            .collection("taskCatalog").document(taskId).getDocument() else {
            return [:]
        }
        let data = snapshot.data() ?? [:]
        cache[taskId] = data
        return data
    }

    func content(for taskId: String) async -> TaskContent {
        TaskContent(data: await catalogData(for: taskId))
    }
}

// MARK: - Container

/// Single mount point for all Phase 5 detail content — placed above the
/// research module. Renders nothing at all for a bare catalog row.
struct TaskContentContainer: View {
    let taskId: String
    let taskTitle: String
    let content: TaskContent

    @State private var notes: String
    @State private var quotes: [TaskQuote]

    init(
        taskId: String,
        taskTitle: String,
        content: TaskContent,
        initialNotes: String?,
        initialQuotes: [TaskQuote]
    ) {
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.content = content
        _notes = State(initialValue: initialNotes ?? "")
        _quotes = State(initialValue: initialQuotes)
    }

    var body: some View {
        if content.hasDetailContent {
            VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                if !content.reframe.isEmpty {
                    ReframeSection(reframe: content.reframe)
                }
                if !content.insiderItems.isEmpty {
                    InsiderItemsSection(items: content.insiderItems)
                }
                if let callSheet = content.callSheet {
                    CallSheetSection(callSheet: callSheet)
                }
                if let tripKit = content.tripKit {
                    TripKitSection(tripKit: tripKit, directionsQuery: taskTitle)
                }
                if let deepLink = content.deepLink {
                    DeepLinkFork(url: deepLink, walkthrough: content.walkthrough)
                } else if !content.walkthrough.isEmpty {
                    WalkthroughDisclosure(steps: content.walkthrough)
                }
                if content.notesEnabled {
                    TaskNotesSection(notes: $notes) {
                        let value = notes
                        let id = taskId
                        Task { await TaskActionService().updateNotes(taskId: id, notes: value) }
                    }
                }
                if content.quoteTracker != "none" {
                    QuoteTrackerView(quotes: $quotes, tracker: content.quoteTracker) { updated in
                        let id = taskId
                        Task { await TaskActionService().updateQuotes(taskId: id, quotes: updated) }
                    }
                }
            }
            .accessibilityIdentifier("taskContent.container")
        }
    }
}

// MARK: - Sections

struct ReframeSection: View {
    let reframe: String

    var body: some View {
        Text(reframe)
            .font(PeezyTheme.Typography.headline)
            .foregroundStyle(PeezyTheme.Colors.deepInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .taskContentCard()
            .accessibilityIdentifier("taskContent.reframe")
    }
}

struct InsiderItemsSection: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
            TaskContentSectionTitle(title: "Insider info", systemImage: "key.fill")
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                TaskContentBullet(text: item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .taskContentCard()
        .accessibilityIdentifier("taskContent.insiderItems")
    }
}

struct CallSheetSection: View {
    let callSheet: TaskCallSheet

    var body: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
            TaskContentSectionTitle(title: "Call sheet", systemImage: "phone.fill")
            group("Say", items: callSheet.say, symbol: "text.bubble.fill")
            group("Ask", items: callSheet.ask, symbol: "questionmark.bubble.fill")
            group("Get", items: callSheet.get, symbol: "checkmark.seal.fill")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .taskContentCard()
        .accessibilityIdentifier("taskContent.callSheet")
    }

    @ViewBuilder
    private func group(_ title: String, items: [String], symbol: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                Label(title, systemImage: symbol)
                    .font(PeezyTheme.Typography.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    TaskContentBullet(text: item)
                }
            }
        }
    }
}

struct TripKitSection: View {
    let tripKit: TaskTripKit
    let directionsQuery: String

    @State private var checkedDocs: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
            TaskContentSectionTitle(title: "Bring with you", systemImage: "doc.on.doc.fill")

            ForEach(Array(tripKit.docs.enumerated()), id: \.offset) { index, doc in
                Button {
                    if checkedDocs.contains(index) {
                        checkedDocs.remove(index)
                    } else {
                        checkedDocs.insert(index)
                    }
                } label: {
                    HStack(alignment: .top, spacing: PeezyTheme.Layout.verticalSpacing) {
                        Image(systemName: checkedDocs.contains(index) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(
                                checkedDocs.contains(index)
                                    ? PeezyTheme.Colors.successGreen
                                    : PeezyTheme.Colors.deepInk.opacity(0.38)
                            )
                            .accessibilityHidden(true)
                        Text(doc)
                            .font(PeezyTheme.Typography.body)
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: PeezyTheme.Layout.buttonHeightSmall, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(doc)
                .accessibilityAddTraits(checkedDocs.contains(index) ? [.isSelected] : [])
            }

            if let url = directionsURL {
                Link(destination: url) {
                    Label("Directions", systemImage: "map.fill")
                        .font(PeezyTheme.Typography.headline)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .frame(maxWidth: .infinity, minHeight: PeezyTheme.Layout.buttonHeightSmall)
                        .background(
                            PeezyTheme.Colors.brandYellow,
                            in: RoundedRectangle(
                                cornerRadius: PeezyTheme.Layout.cornerRadiusMedium,
                                style: .continuous
                            )
                        )
                }
                .accessibilityIdentifier("taskContent.tripKit.directions")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .taskContentCard()
        .accessibilityIdentifier("taskContent.tripKit")
    }

    private var directionsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: directionsQuery)]
        return components?.url
    }
}

struct WalkthroughDisclosure: View {
    let steps: [String]

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
            Button {
                withAnimation(PeezyTheme.Animation.spring) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("Walk me through it", systemImage: "list.number")
                        .font(PeezyTheme.Typography.headline)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(PeezyTheme.Typography.calloutMedium)
                        .rotationEffect(.degrees(isExpanded ? -180 : 0))
                }
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(minHeight: PeezyTheme.Layout.buttonHeightSmall)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("taskContent.walkthrough.toggle")

            if isExpanded {
                TaskWalkthroughSteps(steps: steps)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .taskContentCard()
    }
}

struct DeepLinkFork: View {
    let url: URL
    let walkthrough: [String]

    @State private var isWalkthroughShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
            if walkthrough.isEmpty {
                linkButton(title: "Take me there")
                    .accessibilityIdentifier("taskContent.deepLink.open")
            } else {
                linkButton(title: "I've done this")
                    .accessibilityIdentifier("taskContent.deepLink.done")

                Button {
                    withAnimation(PeezyTheme.Animation.spring) {
                        isWalkthroughShown.toggle()
                    }
                } label: {
                    HStack {
                        Label("Walk me through it", systemImage: "list.number")
                            .font(PeezyTheme.Typography.headline)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(PeezyTheme.Typography.calloutMedium)
                            .rotationEffect(.degrees(isWalkthroughShown ? -180 : 0))
                    }
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .frame(minHeight: PeezyTheme.Layout.buttonHeightSmall)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("taskContent.deepLink.walkthrough")

                if isWalkthroughShown {
                    TaskWalkthroughSteps(steps: walkthrough)
                    linkButton(title: "Take me there")
                        .accessibilityIdentifier("taskContent.deepLink.open")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .taskContentCard()
    }

    private func linkButton(title: String) -> some View {
        Link(destination: url) {
            Label(title, systemImage: "arrow.up.right.square")
                .font(PeezyTheme.Typography.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(maxWidth: .infinity, minHeight: PeezyTheme.Layout.buttonHeightSmall)
                .background(
                    PeezyTheme.Colors.brandYellow,
                    in: RoundedRectangle(
                        cornerRadius: PeezyTheme.Layout.cornerRadiusMedium,
                        style: .continuous
                    )
                )
        }
    }
}

struct TaskNotesSection: View {
    @Binding var notes: String
    let onBlurSave: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
            TaskContentSectionTitle(title: "Notes", systemImage: "square.and.pencil")

            TextEditor(text: $notes)
                .focused($isFocused)
                .font(PeezyTheme.Typography.body)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100)
                .padding(PeezyTheme.Layout.cardPaddingSmall)
                .background(
                    Color.white.opacity(0.42),
                    in: RoundedRectangle(
                        cornerRadius: PeezyTheme.Layout.cornerRadiusSmall,
                        style: .continuous
                    )
                )
                .accessibilityIdentifier("taskContent.notes.editor")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .taskContentCard()
        .onChange(of: isFocused) { _, focused in
            if !focused {
                onBlurSave()
            }
        }
    }
}

// MARK: - Shared pieces

struct TaskContentSectionTitle: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.title3.bold())
            .foregroundStyle(PeezyTheme.Colors.deepInk)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("taskContent.title.\(title)")
    }
}

struct TaskContentBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: PeezyTheme.Layout.verticalSpacing) {
            Circle()
                .fill(PeezyTheme.Colors.deepInk.opacity(0.4))
                .frame(width: 7, height: 7)
                .padding(.top, 7)
                .accessibilityHidden(true)

            Text(text)
                .font(PeezyTheme.Typography.body)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("taskContent.bullet")
    }
}

struct TaskWalkthroughSteps: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: PeezyTheme.Layout.verticalSpacing) {
                    Text("\(index + 1)")
                        .font(PeezyTheme.Typography.calloutSemibold)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .frame(width: 24, height: 24)
                        .background(PeezyTheme.Colors.brandYellow.opacity(0.42), in: Circle())
                        .accessibilityHidden(true)

                    Text(step)
                        .font(PeezyTheme.Typography.body)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
        .accessibilityIdentifier("taskContent.walkthrough.steps")
    }
}

/// TaskRow.rowBackground's material treatment, shared by the detail content
/// sections and the quote tracker.
extension View {
    func taskContentCard() -> some View {
        padding(PeezyTheme.Layout.horizontalPadding)
            .background(
                ZStack {
                    RoundedRectangle(
                        cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                        style: .continuous
                    )
                    .fill(.regularMaterial)
                    RoundedRectangle(
                        cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                        style: .continuous
                    )
                    .fill(Color.white.opacity(0.15))
                }
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                    style: .continuous
                )
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
    }
}

// MARK: - Previews

#Preview("Content sections — full") {
    ScrollView {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
            TaskContentContainer(
                taskId: "",
                taskTitle: "Book Professional Movers",
                content: TaskContent(data: [
                    "reframe": "You're not shopping for a price — you're locking a crew for your date.",
                    "insiderItems": [
                        "Quotes far under everyone else's are bait — the price grows on move day.",
                        "Ask for the man-hour rate, not the total."
                    ],
                    "callSheet": [
                        "say": ["I'm moving a 2-bedroom on the 14th."],
                        "ask": ["What's your hourly rate and crew minimum?"],
                        "get": ["A written quote with crew size and rate"]
                    ],
                    "walkthrough": [
                        "Shortlist three movers.",
                        "Call each one with the call sheet.",
                        "Book the best man-hour rate in writing."
                    ],
                    "deepLink": "https://www.example.com/movers",
                    "notesEnabled": true,
                    "quoteTracker": "manHours"
                ]),
                initialNotes: "Front desk says the elevator needs a COI.",
                initialQuotes: [
                    TaskQuote(company: "Two Men and a Truck", notes: "$140/hr · 3 movers")
                ]
            )
        }
        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
        .padding(.vertical, PeezyTheme.Layout.itemSpacing)
    }
    .background(PeezyTheme.Colors.lightBase)
}

#Preview("Trip kit") {
    ScrollView {
        TripKitSection(
            tripKit: TaskTripKit(data: [
                "docs": ["Current license", "Proof of residency ×2", "Payment card"]
            ])!,
            directionsQuery: "DMV"
        )
        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
    }
    .background(PeezyTheme.Colors.lightBase)
}

#Preview("Bare row — renders nothing") {
    VStack {
        Text("Above")
        TaskContentContainer(
            taskId: "",
            taskTitle: "Bare task",
            content: TaskContent(data: [:]),
            initialNotes: nil,
            initialQuotes: []
        )
        Text("Below")
    }
}
