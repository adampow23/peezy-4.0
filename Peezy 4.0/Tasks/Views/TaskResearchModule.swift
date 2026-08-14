import FirebaseFirestore
import FirebaseFunctions
import Observation
import SwiftUI

struct TaskResearchConfiguration {
    let catalogTaskId: String
    let researchScope: String
    let preferences: [ResearchPreference]

    var isEnabled: Bool {
        researchScope == "web" || researchScope == "reasoning"
    }

    init(catalogTaskId: String, catalogData: [String: Any]) {
        self.catalogTaskId = catalogTaskId
        researchScope = catalogData["researchScope"] as? String ?? "none"
        preferences = (catalogData["researchPrefs"] as? [[String: Any]] ?? [])
            .compactMap(ResearchPreference.init(data:))
    }

    @MainActor
    static func load(
        userId: String,
        taskDocumentId: String,
        fallbackCatalogTaskId: String
    ) async -> TaskResearchConfiguration {
        let userData: [String: Any]
        if !userId.isEmpty, !taskDocumentId.isEmpty,
           let snapshot = try? await Firestore.firestore()
            .collection("users").document(userId)
            .collection("tasks").document(taskDocumentId)
            .getDocument() {
            userData = snapshot.data() ?? [:]
        } else {
            userData = [:]
        }

        let catalogTaskId = (userData["taskId"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? (taskDocumentId.isEmpty ? fallbackCatalogTaskId : taskDocumentId)
        let catalogData = await TaskContentStore.shared.catalogData(for: catalogTaskId)
        return TaskResearchConfiguration(
            catalogTaskId: catalogTaskId,
            catalogData: catalogData
        )
    }
}

enum TaskResearchPolicy {
    static func isEligible(
        configuration: TaskResearchConfiguration,
        flowAnswers: [String: [String]]
    ) -> Bool {
        configuration.isEnabled && hasRecordedFlowAnswers(flowAnswers)
    }

    static func hasRecordedFlowAnswers(_ flowAnswers: [String: [String]]) -> Bool {
        flowAnswers.values.contains { !$0.isEmpty }
    }

    static func decodeFlowAnswers(_ value: Any?) -> [String: [String]] {
        guard let data = value as? [String: Any] else { return [:] }
        if let nested = data["answers"] as? [String: Any] {
            return decodeFlowAnswers(nested)
        }
        return data.compactMapValues { entry in
            guard let values = entry as? [String], !values.isEmpty else { return nil }
            return values
        }
    }

    static func normalizedFlowAnswers(
        _ answers: [String: [String]]
    ) -> [String: [String]] {
        answers.mapValues { $0.sorted() }
    }
}

struct ResearchPreference: Identifiable, Equatable {
    let id: String
    let question: String
    let options: [String]

    nonisolated init?(data: [String: Any]) {
        guard let id = data["id"] as? String,
              !id.isEmpty,
              let question = data["question"] as? String,
              !question.isEmpty,
              let options = data["options"] as? [String],
              !options.isEmpty else { return nil }
        self.id = id
        self.question = question
        self.options = options
    }
}

struct ResearchBrief: Equatable {
    let headline: String
    let sections: [ResearchBriefSection]
    let questionsToAsk: [String]
    let redFlags: [String]
    let whatCouldGoWrong: [String]
    let sources: [ResearchSource]
    let script: String

    nonisolated init?(data: [String: Any]) {
        guard let headline = data["headline"] as? String,
              !headline.isEmpty,
              let sectionData = data["sections"] as? [[String: Any]],
              let questionsToAsk = data["questionsToAsk"] as? [String],
              let redFlags = data["redFlags"] as? [String],
              let whatCouldGoWrong = data["whatCouldGoWrong"] as? [String],
              let sourceData = data["sources"] as? [[String: Any]] else { return nil }

        let sections = sectionData.compactMap(ResearchBriefSection.init(data:))
        guard sections.count == sectionData.count else { return nil }

        self.headline = headline
        self.sections = sections
        self.questionsToAsk = questionsToAsk
        self.redFlags = redFlags
        self.whatCouldGoWrong = whatCouldGoWrong
        self.sources = sourceData.compactMap(ResearchSource.init(data:))
        self.script = data["script"] as? String ?? ""
    }
}

struct ResearchBriefSection: Equatable {
    let heading: String
    let items: [String]

    nonisolated init?(data: [String: Any]) {
        guard let heading = data["heading"] as? String,
              !heading.isEmpty,
              let items = data["items"] as? [String] else { return nil }
        self.heading = heading
        self.items = items
    }
}

struct ResearchSource: Equatable {
    let title: String
    let publisher: String
    let url: String

    nonisolated init?(data: [String: Any]) {
        guard let title = data["title"] as? String,
              !title.isEmpty,
              let publisher = data["publisher"] as? String,
              !publisher.isEmpty,
              let url = data["url"] as? String,
              !url.isEmpty else { return nil }
        self.title = title
        self.publisher = publisher
        self.url = url
    }

    var safeURL: URL? {
        guard let candidate = URL(string: url),
              let scheme = candidate.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return candidate
    }
}

enum TaskResearchState {
    case loading
    case absent
    case generating
    case ready(ResearchBrief, degraded: Bool)
    case failed
}

enum TaskResearchRequest {
    case generate(force: Bool)
    case reveal
}

@MainActor
@Observable
final class TaskResearchModel {
    private(set) var configuration: TaskResearchConfiguration?
    private(set) var researchState: TaskResearchState = .loading
    private(set) var shouldAnimateBrief = false
    private(set) var selectedPreferences: [String: String] = [:]
    private(set) var flowAnswers: [String: [String]] = [:]

    @ObservationIgnored private let userId: String
    @ObservationIgnored private let db = Firestore.firestore()
    @ObservationIgnored private var researchListener: ListenerRegistration?
    @ObservationIgnored private var hasReceivedResearchSnapshot = false

    init(userId: String) {
        self.userId = userId
    }

    var isEligible: Bool {
        guard let configuration else { return false }
        return TaskResearchPolicy.isEligible(
            configuration: configuration,
            flowAnswers: flowAnswers
        )
    }

    var canGenerateResearch: Bool {
        guard let configuration, isEligible else { return false }
        return configuration.preferences.allSatisfy {
            selectedPreferences[$0.id] != nil
        }
    }

    var hasPreferences: Bool {
        !(configuration?.preferences.isEmpty ?? true)
    }

    func configure(
        configuration: TaskResearchConfiguration,
        flowAnswers: [String: [String]]
    ) {
        stop()
        self.configuration = configuration
        self.flowAnswers = flowAnswers.filter { !$0.value.isEmpty }
        selectedPreferences = [:]
        shouldAnimateBrief = false
        researchState = configuration.isEnabled ? .loading : .absent
    }

    func start() {
        guard let configuration, configuration.isEnabled, !userId.isEmpty else {
            researchState = .absent
            return
        }
        listenForResearch(taskId: configuration.catalogTaskId)
    }

    func stop() {
        researchListener?.remove()
        researchListener = nil
    }

    func select(option: String, for preferenceId: String) {
        selectedPreferences[preferenceId] = option
    }

    func generateResearch(force: Bool) async {
        guard let configuration, canGenerateResearch else { return }
        shouldAnimateBrief = false
        researchState = .generating

        var payload: [String: Any] = [
            "taskId": configuration.catalogTaskId,
            "force": force,
            "flowAnswers": flowAnswers
        ]
        if !selectedPreferences.isEmpty {
            payload["prefs"] = selectedPreferences
        }
        if let entityName {
            payload["entityName"] = entityName
        }

        do {
            _ = try await Functions.functions()
                .httpsCallable("researchTask")
                .call(payload)
        } catch {
            researchState = .failed
        }
    }

    private func listenForResearch(taskId: String) {
        researchListener?.remove()
        hasReceivedResearchSnapshot = false
        researchState = .loading

        researchListener = db.collection("users").document(userId)
            .collection("research").document(taskId)
            .addSnapshotListener { [weak self] snapshot, error in
                let data = snapshot?.data()
                Task { @MainActor [weak self] in
                    self?.applyResearchSnapshot(data: data, error: error)
                }
            }
    }

    private func applyResearchSnapshot(data: [String: Any]?, error: Error?) {
        let isFirstSnapshot = !hasReceivedResearchSnapshot
        hasReceivedResearchSnapshot = true

        guard error == nil else {
            researchState = .failed
            return
        }
        guard let data else {
            researchState = .absent
            return
        }

        switch data["status"] as? String {
        case "generating":
            shouldAnimateBrief = false
            researchState = .generating

        case "ready":
            guard let briefData = data["brief"] as? [String: Any],
                  let brief = ResearchBrief(data: briefData) else {
                researchState = .failed
                return
            }
            guard TaskResearchPolicy.normalizedFlowAnswers(
                TaskResearchPolicy.decodeFlowAnswers(data["flowAnswersUsed"])
            ) == TaskResearchPolicy.normalizedFlowAnswers(flowAnswers) else {
                shouldAnimateBrief = false
                researchState = .absent
                return
            }
            if let prefsUsed = data["prefsUsed"] as? [String: Any] {
                let savedSelections = prefsUsed.compactMapValues { $0 as? String }
                if !savedSelections.isEmpty {
                    selectedPreferences = savedSelections
                }
            }
            shouldAnimateBrief = !isFirstSnapshot
            researchState = .ready(brief, degraded: data["degraded"] as? Bool ?? false)

        case "failed":
            shouldAnimateBrief = false
            researchState = .failed

        default:
            researchState = .absent
        }
    }

    private var entityName: String? {
        let answerKeys = flowAnswers.keys.sorted()
        for businessSearchKey in ["business_name", "current_business", "provider_name", "provider"] {
            guard let answerKey = answerKeys.first(where: {
                $0 == businessSearchKey || $0.hasSuffix(".\(businessSearchKey)")
            }),
            let value = flowAnswers[answerKey]?.first?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else { continue }
            return value
        }
        return nil
    }
}

struct TaskResearchModuleView: View {
    let model: TaskResearchModel
    let startButtonTitle: String
    let hasAccess: Bool
    let onRequest: (TaskResearchRequest) -> Void
    var onDone: (() -> Void)?

    @ViewBuilder
    var body: some View {
        switch model.researchState {
        case .loading:
            ProgressView("Checking for saved research…")
                .tint(PeezyTheme.Colors.deepInk)
                .accessibilityIdentifier("research.loading")

        case .absent:
            researchStart

        case .generating:
            HStack(spacing: 12) {
                ProgressView()
                    .tint(PeezyTheme.Colors.deepInk)
                Text("Peezy is researching your situation…")
                    .font(.body.weight(.medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Peezy is researching your situation")
            .accessibilityIdentifier("research.generating")

        case .ready(let brief, let degraded):
            if hasAccess {
                ResearchBriefView(
                    brief: brief,
                    degraded: degraded,
                    animateOnReveal: model.shouldAnimateBrief
                )

                Button("Refresh research") {
                    onRequest(.generate(force: true))
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.68))
                .frame(minHeight: 44)
                .accessibilityHint("Generates a new brief using your current move details")
                .accessibilityIdentifier("research.refresh")

                if let onDone {
                    PeezyAssessmentButton("Done") {
                        onDone()
                    }
                        .accessibilityIdentifier("research.done")
                }
            } else {
                researchAccessButton(
                    title: "View research",
                    request: .reveal,
                    identifier: "research.unlock"
                )
            }

        case .failed:
            Text("Peezy couldn't finish this research.")
                .font(.body)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .accessibilityIdentifier("research.failed")
            researchStart
        }
    }

    private var researchStart: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let configuration = model.configuration,
               !configuration.preferences.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(configuration.preferences) { preference in
                        ResearchPreferenceQuestion(
                            preference: preference,
                            selection: model.selectedPreferences[preference.id],
                            onSelect: { model.select(option: $0, for: preference.id) }
                        )
                    }
                }
            }

            researchAccessButton(
                title: startButtonTitle,
                request: .generate(force: false),
                identifier: "research.start"
            )
            .disabled(!model.canGenerateResearch)
            .opacity(model.canGenerateResearch ? 1 : 0.45)
        }
        .accessibilityIdentifier("research.start_content")
    }

    private func researchAccessButton(
        title: String,
        request: TaskResearchRequest,
        identifier: String
    ) -> some View {
        Button {
            onRequest(request)
        } label: {
            Label(title, systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    PeezyTheme.Colors.deepInk,
                    in: RoundedRectangle(
                        cornerRadius: PeezyTheme.Layout.cornerRadiusMedium,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

private struct ResearchPreferenceQuestion: View {
    let preference: ResearchPreference
    let selection: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preference.question)
                .font(.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(preference.options, id: \.self) { option in
                let isSelected = selection == option
                Button {
                    onSelect(option)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(
                                isSelected
                                    ? PeezyTheme.Colors.deepInk
                                    : PeezyTheme.Colors.deepInk.opacity(0.38)
                            )
                            .accessibilityHidden(true)

                        Text(option)
                            .font(.body)
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(
                        isSelected
                            ? PeezyTheme.Colors.deepInk.opacity(0.42)
                            : Color.white.opacity(0.42),
                        in: RoundedRectangle(
                            cornerRadius: PeezyTheme.Layout.cornerRadiusSmall,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityIdentifier("research.preference.\(preference.id).\(option)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("research.preference.\(preference.id)")
    }
}

struct ResearchBriefView: View {
    let brief: ResearchBrief
    let degraded: Bool
    let animateOnReveal: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            revealText(brief.headline, font: .title3.bold())

            if degraded {
                Label(
                    "Some source links could not be verified, so they were left out.",
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(.callout)
                .foregroundStyle(PeezyTheme.Colors.warningOrange)
                .accessibilityIdentifier("research.brief.degraded")
            }

            ForEach(Array(brief.sections.enumerated()), id: \.offset) { _, section in
                ResearchListSection(
                    title: section.heading,
                    items: section.items,
                    symbol: "text.justify.left",
                    tint: PeezyTheme.Colors.infoBlue,
                    animateOnReveal: animateOnReveal
                )
            }

            if !brief.questionsToAsk.isEmpty {
                ResearchListSection(
                    title: "Questions to ask",
                    items: brief.questionsToAsk,
                    symbol: "questionmark.bubble.fill",
                    tint: PeezyTheme.Colors.infoBlue,
                    animateOnReveal: animateOnReveal
                )
            }

            if !brief.redFlags.isEmpty {
                ResearchListSection(
                    title: "Red flags",
                    items: brief.redFlags,
                    symbol: "flag.fill",
                    tint: PeezyTheme.Colors.emotionalRed,
                    animateOnReveal: animateOnReveal
                )
            }

            if !brief.sources.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sources")
                        .font(.headline)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(Array(brief.sources.enumerated()), id: \.offset) { index, source in
                        if let url = source.safeURL {
                            Link(destination: url) {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(source.publisher)
                                            .font(.callout.weight(.semibold))
                                        Text(source.title)
                                            .font(.footnote)
                                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.66))
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.up.right.square")
                                        .accessibilityHidden(true)
                                }
                                .foregroundStyle(PeezyTheme.Colors.deepInk)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .accessibilityLabel("\(source.publisher): \(source.title)")
                            .accessibilityHint("Opens this source")
                            .accessibilityIdentifier("research.brief.source.\(index)")
                        }
                    }
                }
                .accessibilityIdentifier("research.brief.sources")
            }

            if !brief.whatCouldGoWrong.isEmpty {
                ResearchListSection(
                    title: "What could go wrong",
                    items: brief.whatCouldGoWrong,
                    symbol: "exclamationmark.triangle.fill",
                    tint: PeezyTheme.Colors.warningOrange,
                    animateOnReveal: animateOnReveal
                )
            }

            if !brief.script.isEmpty {
                ResearchListSection(
                    title: "SCRIPT",
                    items: [brief.script],
                    symbol: "phone.fill",
                    tint: PeezyTheme.Colors.successGreen,
                    animateOnReveal: animateOnReveal
                )
            }
        }
        .accessibilityIdentifier("research.brief")
    }

    @ViewBuilder
    private func revealText(_ text: String, font: Font) -> some View {
        if animateOnReveal && !reduceMotion {
            TypewriterText(
                phrases: [text],
                typingSpeed: 0.015,
                font: font,
                foregroundColor: PeezyTheme.Colors.deepInk,
                repeatsPhrases: false,
                textAlignment: .leading,
                showsCursor: false
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ResearchListSection: View {
    let title: String
    let items: [String]
    let symbol: String
    let tint: Color
    let animateOnReveal: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                        .padding(.top, 7)
                        .accessibilityHidden(true)

                    if animateOnReveal && !reduceMotion {
                        TypewriterText(
                            phrases: [item],
                            typingSpeed: 0.012,
                            font: .body,
                            foregroundColor: PeezyTheme.Colors.deepInk,
                            repeatsPhrases: false,
                            textAlignment: .leading,
                            showsCursor: false
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(item)
                            .font(.body)
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .background(
            tint.opacity(0.12),
            in: RoundedRectangle(
                cornerRadius: PeezyTheme.Layout.cornerRadiusMedium,
                style: .continuous
            )
        )
        .accessibilityIdentifier("research.brief.section.\(title)")
    }
}
