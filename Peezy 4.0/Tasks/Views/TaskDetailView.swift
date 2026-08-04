import FirebaseFirestore
import FirebaseFunctions
import Observation
import SwiftUI

struct TaskDetailView: View {
    let userId: String
    let taskDocumentId: String
    let fallbackFlowId: String
    let onStart: () -> Void
    let onComplete: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void

    @State private var model: TaskDetailViewModel

    init(
        userId: String,
        taskDocumentId: String,
        fallbackFlowId: String,
        onStart: @escaping () -> Void,
        onComplete: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.userId = userId
        self.taskDocumentId = taskDocumentId
        self.fallbackFlowId = fallbackFlowId
        self.onStart = onStart
        self.onComplete = onComplete
        self.onSnooze = onSnooze
        self.onDismiss = onDismiss
        _model = State(
            initialValue: TaskDetailViewModel(
                userId: userId,
                taskDocumentId: taskDocumentId,
                fallbackFlowId: fallbackFlowId
            )
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            InteractiveBackground()
                .ignoresSafeArea()

            Group {
                if let task = model.task {
                    taskContent(task)
                } else {
                    ProgressView("Loading task details…")
                        .tint(PeezyTheme.Colors.deepInk)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close task")
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
        .task {
            await model.start()
        }
        .onDisappear {
            model.stop()
        }
    }

    private func taskContent(_ task: TaskDetailTask) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                header(task)

                if !task.tips.isEmpty {
                    pointers(task.tips)
                }

                researchModule(task)

                if task.hasGuidedFlow {
                    Button(action: onStart) {
                        Label("Start", systemImage: "arrow.right.circle.fill")
                            .font(.headline)
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(
                                PeezyTheme.Gradients.brandYellow,
                                in: RoundedRectangle(
                                    cornerRadius: PeezyTheme.Layout.cornerRadius,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the guided steps for this task")
                }
            }
            .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
            .padding(.top, 64)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
    }

    private func header(_ task: TaskDetailTask) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(task.title)
                .font(.largeTitle.bold())
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .fixedSize(horizontal: false, vertical: true)

            if !task.description.isEmpty {
                Text(task.description)
                    .font(.body)
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !task.whyNeeded.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why it matters")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.58))

                    Text(task.whyNeeded)
                        .font(.headline)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    PeezyTheme.Colors.brandYellow.opacity(0.28),
                    in: RoundedRectangle(
                        cornerRadius: PeezyTheme.Layout.cornerRadius,
                        style: .continuous
                    )
                )
            }
        }
        .padding(20)
        .taskDetailCard()
        .accessibilityElement(children: .contain)
    }

    private func pointers(_ tips: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TaskDetailSectionTitle(title: "Pointers", systemImage: "lightbulb.fill")

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(PeezyTheme.Colors.successGreen)
                    .accessibilityHidden(true)

                Text(tips)
                    .font(.body)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .taskDetailCard()
    }

    @ViewBuilder
    private func researchModule(_ task: TaskDetailTask) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TaskDetailSectionTitle(title: "Research", systemImage: "sparkles")

            if !task.researchEnabled {
                Text("The task details and guided steps contain what you need for this one.")
                    .font(.body)
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.7))
            } else {
                researchStateContent(task)
            }
        }
        .padding(20)
        .taskDetailCard()
    }

    @ViewBuilder
    private func researchStateContent(_ task: TaskDetailTask) -> some View {
        switch model.researchState {
        case .loading:
            ProgressView("Checking for saved research…")
                .tint(PeezyTheme.Colors.deepInk)

        case .absent:
            researchStart(task, buttonTitle: "Research this for me")

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

        case .ready(let brief, let degraded):
            ResearchBriefView(
                brief: brief,
                degraded: degraded,
                animateOnReveal: model.shouldAnimateBrief
            )

            Button("Refresh research") {
                Task { await model.generateResearch(force: true) }
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.68))
            .frame(minHeight: 44)
            .accessibilityHint("Generates a new brief using your current move details")

        case .failed:
            Text("Peezy couldn't finish this research.")
                .font(.body)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
            researchStart(task, buttonTitle: "Try research again")
        }
    }

    private func researchStart(_ task: TaskDetailTask, buttonTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !task.researchPreferences.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(task.researchPreferences) { preference in
                        ResearchPreferenceQuestion(
                            preference: preference,
                            selection: model.selectedPreferences[preference.id],
                            onSelect: { model.select(option: $0, for: preference.id) }
                        )
                    }
                }
            }

            Button {
                Task { await model.generateResearch(force: false) }
            } label: {
                Label(buttonTitle, systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        PeezyTheme.Colors.brandYellow,
                        in: RoundedRectangle(
                            cornerRadius: PeezyTheme.Layout.cornerRadiusMedium,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!model.canGenerateResearch)
            .opacity(model.canGenerateResearch ? 1 : 0.45)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            TaskDetailFooterButton(
                title: "Complete",
                systemImage: "checkmark.circle.fill",
                action: onComplete
            )

            TaskDetailFooterButton(
                title: "Snooze",
                systemImage: "clock.fill",
                action: onSnooze
            )

            TaskDetailFooterButton(
                title: "Chat",
                systemImage: "message.fill",
                isEnabled: false,
                action: {}
            )
            .accessibilityHint("Task chat is not available yet")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct TaskDetailSectionTitle: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.title3.bold())
            .foregroundStyle(PeezyTheme.Colors.deepInk)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct TaskDetailFooterButton: View {
    let title: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.headline)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(PeezyTheme.Colors.deepInk)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
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
                            ? PeezyTheme.Colors.brandYellow.opacity(0.42)
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
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ResearchBriefView: View {
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

                    ForEach(Array(brief.sources.enumerated()), id: \.offset) { _, source in
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
                        }
                    }
                }
            }

            ResearchListSection(
                title: "What could go wrong",
                items: brief.whatCouldGoWrong,
                symbol: "exclamationmark.triangle.fill",
                tint: PeezyTheme.Colors.warningOrange,
                animateOnReveal: animateOnReveal
            )
        }
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
    }
}

private extension View {
    func taskDetailCard() -> some View {
        background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct TaskDetailTask {
    let catalogTaskId: String
    let title: String
    let description: String
    let whyNeeded: String
    let tips: String
    let actionType: String
    let researchScope: String
    let researchPreferences: [ResearchPreference]

    var hasGuidedFlow: Bool {
        ["workflow", "in-app", "in-app-inventory"].contains(actionType)
    }

    var researchEnabled: Bool {
        researchScope == "web" || researchScope == "reasoning"
    }
}

private struct ResearchPreference: Identifiable, Equatable {
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

private struct ResearchBrief: Equatable {
    let headline: String
    let sections: [ResearchBriefSection]
    let questionsToAsk: [String]
    let redFlags: [String]
    let whatCouldGoWrong: [String]
    let sources: [ResearchSource]

    nonisolated init?(data: [String: Any]) {
        guard let headline = data["headline"] as? String,
              !headline.isEmpty,
              let sectionData = data["sections"] as? [[String: Any]],
              let questionsToAsk = data["questionsToAsk"] as? [String],
              let redFlags = data["redFlags"] as? [String],
              let whatCouldGoWrong = data["whatCouldGoWrong"] as? [String],
              !whatCouldGoWrong.isEmpty,
              let sourceData = data["sources"] as? [[String: Any]] else { return nil }

        let sections = sectionData.compactMap(ResearchBriefSection.init(data:))
        guard sections.count == sectionData.count else { return nil }

        self.headline = headline
        self.sections = sections
        self.questionsToAsk = questionsToAsk
        self.redFlags = redFlags
        self.whatCouldGoWrong = whatCouldGoWrong
        self.sources = sourceData.compactMap(ResearchSource.init(data:))
    }
}

private struct ResearchBriefSection: Equatable {
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

private struct ResearchSource: Equatable {
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

private enum TaskResearchState {
    case loading
    case absent
    case generating
    case ready(ResearchBrief, degraded: Bool)
    case failed
}

@MainActor
@Observable
private final class TaskDetailViewModel {
    private(set) var task: TaskDetailTask?
    private(set) var researchState: TaskResearchState = .loading
    private(set) var shouldAnimateBrief = false
    private(set) var selectedPreferences: [String: String] = [:]

    @ObservationIgnored private let userId: String
    @ObservationIgnored private let taskDocumentId: String
    @ObservationIgnored private let fallbackFlowId: String
    @ObservationIgnored private let db = Firestore.firestore()
    @ObservationIgnored private var researchListener: ListenerRegistration?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var hasReceivedResearchSnapshot = false

    init(userId: String, taskDocumentId: String, fallbackFlowId: String) {
        self.userId = userId
        self.taskDocumentId = taskDocumentId
        self.fallbackFlowId = fallbackFlowId
    }

    var canGenerateResearch: Bool {
        guard let task, task.researchEnabled else { return false }
        return task.researchPreferences.allSatisfy {
            selectedPreferences[$0.id] != nil
        }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        let userData: [String: Any]
        if !userId.isEmpty, !taskDocumentId.isEmpty,
           let snapshot = try? await db.collection("users").document(userId)
            .collection("tasks").document(taskDocumentId).getDocument() {
            userData = snapshot.data() ?? [:]
        } else {
            userData = [:]
        }

        let catalogTaskId = (userData["taskId"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? taskDocumentId
        let catalogData: [String: Any]
        if !catalogTaskId.isEmpty,
           let snapshot = try? await db.collection("taskCatalog")
            .document(catalogTaskId).getDocument() {
            catalogData = snapshot.data() ?? [:]
        } else {
            catalogData = [:]
        }

        task = Self.makeTask(
            catalogTaskId: catalogTaskId,
            catalogData: catalogData,
            userData: userData,
            fallbackFlowId: fallbackFlowId
        )

        if task?.researchEnabled == true {
            listenForResearch(taskId: catalogTaskId)
        } else {
            researchState = .absent
        }
    }

    func stop() {
        researchListener?.remove()
        researchListener = nil
    }

    func select(option: String, for preferenceId: String) {
        selectedPreferences[preferenceId] = option
    }

    func generateResearch(force: Bool) async {
        guard let task, canGenerateResearch else { return }
        shouldAnimateBrief = false
        researchState = .generating

        var payload: [String: Any] = [
            "taskId": task.catalogTaskId,
            "force": force
        ]
        if !selectedPreferences.isEmpty {
            payload["prefs"] = selectedPreferences
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

    private static func makeTask(
        catalogTaskId: String,
        catalogData: [String: Any],
        userData: [String: Any],
        fallbackFlowId: String
    ) -> TaskDetailTask {
        func string(_ key: String) -> String {
            (catalogData[key] as? String) ?? (userData[key] as? String) ?? ""
        }

        let preferenceData = catalogData["researchPrefs"] as? [[String: Any]] ?? []
        let preferences = preferenceData.compactMap(ResearchPreference.init(data:))
        let fallbackTitle = fallbackFlowId
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        return TaskDetailTask(
            catalogTaskId: catalogTaskId,
            title: string("title").isEmpty ? fallbackTitle : string("title"),
            description: string("desc"),
            whyNeeded: string("whyNeeded"),
            tips: string("tips"),
            actionType: string("actionType").isEmpty ? "workflow" : string("actionType"),
            researchScope: catalogData["researchScope"] as? String ?? "none",
            researchPreferences: preferences
        )
    }
}
