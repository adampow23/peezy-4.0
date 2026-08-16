import FirebaseFirestore
import Observation
import SwiftUI

struct TaskDetailView: View {
    let userId: String
    let taskDocumentId: String
    let fallbackFlowId: String
    let onComplete: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void

    @Environment(SupportChatService.self) private var chatService
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var model: TaskDetailViewModel
    @State private var isTaskChatPresented = false
    @State private var pendingResearchRequest: TaskResearchRequest?

    init(
        userId: String,
        taskDocumentId: String,
        fallbackFlowId: String,
        onComplete: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.userId = userId
        self.taskDocumentId = taskDocumentId
        self.fallbackFlowId = fallbackFlowId
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
        .sheet(isPresented: $isTaskChatPresented) {
            if let task = model.task {
                NavigationStack {
                    SupportChatView(
                        chatService: chatService,
                        taskContext: SupportTaskContext(
                            userTaskId: taskDocumentId,
                            catalogTaskId: task.catalogTaskId,
                            title: task.title
                        )
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                isTaskChatPresented = false
                            }
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                        }
                    }
                }
                .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: researchPaywallBinding) {
            PaywallGateSheet(surface: .research) { subscribed in
                let request = pendingResearchRequest
                pendingResearchRequest = nil
                guard subscribed, let request else { return }
                performResearchRequest(request)
            }
        }
    }

    private func taskContent(_ task: TaskDetailTask) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                header(task)

                if !task.tips.isEmpty {
                    pointers(task.tips)
                }

                TaskContentContainer(
                    taskId: taskDocumentId,
                    taskTitle: task.title,
                    content: task.content,
                    initialNotes: task.notes,
                    initialQuotes: task.quotes
                )

                if model.research.isEligible {
                    researchModule
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
                    PeezyTheme.Colors.backgroundSecondary,
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

    private var researchModule: some View {
        VStack(alignment: .leading, spacing: 16) {
            TaskDetailSectionTitle(title: "Research", systemImage: "sparkles")

            TaskResearchModuleView(
                model: model.research,
                startButtonTitle: "Want us to dig up the easiest way to get this done?",
                hasAccess: subscriptionManager.isSubscribed,
                onRequest: requestResearch
            )
        }
        .padding(20)
        .taskDetailCard()
        .accessibilityIdentifier("task_detail.research")
    }

    private var researchPaywallBinding: Binding<Bool> {
        Binding(
            get: { pendingResearchRequest != nil },
            set: { if !$0 { pendingResearchRequest = nil } }
        )
    }

    private func requestResearch(_ request: TaskResearchRequest) {
        guard subscriptionManager.isSubscribed else {
            pendingResearchRequest = request
            return
        }
        performResearchRequest(request)
    }

    private func performResearchRequest(_ request: TaskResearchRequest) {
        switch request {
        case .generate(let force):
            Task {
                let outcome = await model.research.generateResearch(force: force)
                if outcome == .movePassRequired {
                    pendingResearchRequest = request
                }
            }
        case .reveal:
            break
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
                action: {
                    isTaskChatPresented = true
                }
            )
            .accessibilityHint("Opens chat about this task")
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
    let workflowId: String
    let researchConfiguration: TaskResearchConfiguration
    let content: TaskContent
    let notes: String?
    let quotes: [TaskQuote]
}

@MainActor
@Observable
private final class TaskDetailViewModel {
    private(set) var task: TaskDetailTask?
    private(set) var flowAnswers: [String: [String]] = [:]
    let research: TaskResearchModel

    @ObservationIgnored private let userId: String
    @ObservationIgnored private let taskDocumentId: String
    @ObservationIgnored private let fallbackFlowId: String
    @ObservationIgnored private let db = Firestore.firestore()
    @ObservationIgnored private var hasStarted = false

    init(userId: String, taskDocumentId: String, fallbackFlowId: String) {
        self.userId = userId
        self.taskDocumentId = taskDocumentId
        self.fallbackFlowId = fallbackFlowId
        research = TaskResearchModel(userId: userId)
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
        // Single catalog fetch path: the cached store payload feeds both the
        // task metadata and the Phase 5 surface content.
        let catalogData = await TaskContentStore.shared.catalogData(for: catalogTaskId)

        let resolvedTask = Self.makeTask(
            catalogTaskId: catalogTaskId,
            catalogData: catalogData,
            userData: userData,
            fallbackFlowId: fallbackFlowId
        )
        task = resolvedTask
        flowAnswers = await loadRecordedFlowAnswers(
            workflowId: resolvedTask.workflowId,
            userData: userData
        )
        research.configure(
            configuration: resolvedTask.researchConfiguration,
            flowAnswers: flowAnswers
        )
        research.start()
    }

    func stop() {
        research.stop()
    }

    private func loadRecordedFlowAnswers(
        workflowId: String,
        userData: [String: Any]
    ) async -> [String: [String]] {
        var recorded = TaskResearchPolicy.decodeFlowAnswers(userData["qualifyingAnswers"])

        if !userId.isEmpty, !workflowId.isEmpty,
           let snapshot = try? await db.collection("users").document(userId)
            .collection("workflowResponses").document(workflowId).getDocument() {
            recorded.merge(
                TaskResearchPolicy.decodeFlowAnswers(snapshot.data()?["answers"])
            ) { _, submitted in
                submitted
            }
        }

        recorded.merge(
            TaskResearchPolicy.decodeFlowAnswers(userData["flowAnswers"])
        ) { _, active in
            active
        }
        return recorded.filter { !$0.value.isEmpty }
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

        let fallbackTitle = fallbackFlowId
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        return TaskDetailTask(
            catalogTaskId: catalogTaskId,
            title: string("title").isEmpty ? fallbackTitle : string("title"),
            description: string("desc"),
            whyNeeded: string("whyNeeded"),
            tips: string("tips"),
            workflowId: string("workflowId").isEmpty ? fallbackFlowId : string("workflowId"),
            researchConfiguration: TaskResearchConfiguration(
                catalogTaskId: catalogTaskId,
                catalogData: catalogData
            ),
            content: TaskContent(data: catalogData),
            notes: userData["notes"] as? String,
            quotes: (userData["quotes"] as? [[String: Any]])?
                .compactMap(TaskQuote.init(data:)) ?? []
        )
    }
}
