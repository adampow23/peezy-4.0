import SwiftUI

struct PackingReadinessView: View {
    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    @State private var record: ReadinessGateRecord?
    @State private var savingItem: ReadinessItem?
    @State private var errorMessage: String?
    @State private var hasUnpersistedReadinessAttempt = false
    @Environment(FlowExitCoordinator.self) private var exitCoordinator

    private let actionService = TaskActionService()

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: 1, currentIndex: 0) {
                content
            }
        }
        .task { await load() }
        .accessibilityIdentifier("readiness.flow")
        .resumableFlowProgress(
            path: [record?.checklist.isComplete == true ? "complete" : "checklist"],
            answers: readinessProgressAnswers
        ) { _ in }
        .flowAnswerProbe {
            savingItem != nil
                || hasUnpersistedReadinessAttempt
                || !readinessProgressAnswers.isEmpty
        }
    }

    private var readinessProgressAnswers: [String: [String]] {
        guard let record else { return [:] }
        return Self.progressAnswers(for: record.checklist)
    }

    private static func progressAnswers(for checklist: ReadinessChecklist) -> [String: [String]] {
        let readyItems = ReadinessItem.allCases
            .filter { checklist[$0] }
            .map(\.rawValue)
        return readyItems.isEmpty ? [:] : ["ready_items": readyItems]
    }

    @ViewBuilder
    private var content: some View {
        if let record {
            gateCard(record)
        } else if let errorMessage {
            errorCard(errorMessage)
        } else {
            ProgressView("Loading your readiness check…")
                .tint(PeezyTheme.Colors.deepInk)
                .accessibilityIdentifier("readiness.loading")
        }
    }

    private func gateCard(_ record: ReadinessGateRecord) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Moving-day readiness")

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "checklist.checked")
                        .font(.largeTitle)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .accessibilityHidden(true)

                    Text("One last readiness check")
                        .font(.title)
                        .bold()
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .accessibilityIdentifier("readiness.title")

                    Text("Set for \(record.scheduledDate.formatted(date: .abbreviated, time: .omitted)) — the day before your move.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("readiness.scheduled_date")

                    VStack(spacing: 10) {
                        ForEach(ReadinessItem.allCases) { item in
                            checklistButton(item, record: record)
                        }
                    }
                    .accessibilityIdentifier("readiness.items")

                    if record.checklist.showsIncompleteConsequence(
                        scheduledDate: record.scheduledDate
                    ) {
                        // Copy LOCKED (Spec 06 Phase C).
                        Text("Heads up: unready homes are the #1 cause of moving-day overages.")
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("readiness.incomplete_consequence")
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                            .accessibilityIdentifier("readiness.error_message")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }

            VStack(spacing: 12) {
                if record.checklist.isComplete {
                    PeezyAssessmentButton("Done", action: onComplete)
                        .accessibilityIdentifier("readiness.done")
                } else {
                    Button("Close", action: onDismiss)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                        .disabled(savingItem != nil)
                        .accessibilityIdentifier("readiness.close")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("readiness.card")
    }

    private func checklistButton(
        _ item: ReadinessItem,
        record: ReadinessGateRecord
    ) -> some View {
        Button {
            toggle(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: record.checklist[item] ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(
                        record.checklist[item]
                            ? PeezyTheme.Colors.successGreen
                            : PeezyTheme.Colors.deepInk
                    )
                Text(item.label)
                    .font(.body)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if savingItem == item {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(14)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(savingItem != nil)
        .accessibilityLabel(item.label)
        .accessibilityValue(record.checklist[item] ? "Ready" : "Not ready")
        .accessibilityIdentifier("readiness.item.\(item.rawValue)")
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Moving-day readiness")
            Spacer()
            ContentUnavailableView {
                Label("Couldn't load readiness", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(message)
                    .accessibilityIdentifier("readiness.load_error")
            }
            Spacer()
            VStack(spacing: 12) {
                PeezyAssessmentButton("Try again") { Task { await load() } }
                    .accessibilityIdentifier("readiness.retry")
                Button("Close", action: onDismiss)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("readiness.error_close")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("readiness.error")
    }

    private func load() async {
        errorMessage = nil
        do {
            record = try await actionService.loadReadinessGate(
                userId: userId,
                taskId: taskId
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggle(_ item: ReadinessItem) {
        guard var updated = record, savingItem == nil else { return }
        updated.checklist[item].toggle()
        updated.completedAt = updated.checklist.isComplete ? Date() : nil
        savingItem = item
        errorMessage = nil
        hasUnpersistedReadinessAttempt = true
        exitCoordinator.noteExternalPersistencePending()

        Task {
            do {
                try await actionService.saveReadinessGate(userId: userId, record: updated)
                await MainActor.run {
                    exitCoordinator.noteExternallyPersistedAnswer(
                        path: [updated.checklist.isComplete ? "complete" : "checklist"],
                        answers: Self.progressAnswers(for: updated.checklist)
                    )
                    hasUnpersistedReadinessAttempt = false
                    record = updated
                    savingItem = nil
                    PeezyHaptics.selection()
                }
            } catch {
                await MainActor.run {
                    exitCoordinator.noteExternalPersistenceFailure(error)
                    errorMessage = error.localizedDescription
                    savingItem = nil
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    PackingReadinessView(
        userId: "preview",
        taskId: ReadinessChecklist.taskId,
        onComplete: {},
        onDismiss: {}
    )
}
#endif
