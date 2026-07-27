import SwiftUI

struct PackingSessionView: View {
    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var session: PackingSession?
    @State private var consequenceLine: String?
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let actionService = TaskActionService()

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: 1, currentIndex: 0) {
                content
            }
        }
        .task { await loadSession() }
        .accessibilityIdentifier("packing.session.flow")
    }

    @ViewBuilder
    private var content: some View {
        if let consequenceLine {
            consequence(consequenceLine)
        } else if let session {
            sessionCard(session)
        } else if let errorMessage {
            errorCard(errorMessage)
        } else {
            ProgressView("Loading today's session…")
                .tint(PeezyTheme.Colors.deepInk)
                .accessibilityIdentifier("packing.session.loading")
        }
    }

    private func sessionCard(_ session: PackingSession) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Packing plan")

            Spacer()

            VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                Image(systemName: "shippingbox.fill")
                    .font(.largeTitle)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityHidden(true)

                Text("Today: \(session.roomLabel). About \(session.estMinutes) minutes.")
                    .font(.title)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("packing.session.title")

                Text("Here's what's in it")
                    .font(.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityIdentifier("packing.session.summary_heading")

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(session.itemSummary.enumerated()), id: \.offset) { index, item in
                        Label(item, systemImage: "checklist")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("packing.session.item.\(index)")
                    }
                }
                .accessibilityIdentifier("packing.session.summary")

                if session.isBehindPace {
                    // Copy LOCKED (Spec 06 Phase C).
                    Text("You're behind pace — movers charge by the hour, and unpacked homes run long. Today's session matters.")
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("packing.session.behind_pace")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                PeezyAssessmentButton(
                    isSaving ? "Saving…" : "I packed this",
                    disabled: isSaving,
                    action: complete
                )
                .accessibilityIdentifier("packing.session.complete")

                SecondaryActionButton(title: "Do this later") {
                    onStatusAction(.later)
                }
                .disabled(isSaving)
                .accessibilityIdentifier("packing.session.snooze")

                Button("Close", action: onDismiss)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .disabled(isSaving)
                    .accessibilityIdentifier("packing.session.close")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("packing.session.card")
    }

    private func consequence(_ line: String) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Packing plan")

            Spacer()

            VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(PeezyTheme.Colors.successGreen)
                    .accessibilityHidden(true)

                Text(line)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("packing.session.consequence")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer()

            PeezyAssessmentButton("Done", action: onComplete)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .accessibilityIdentifier("packing.session.done")
        }
        .accessibilityIdentifier("packing.session.completed")
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Packing plan")
            Spacer()
            ContentUnavailableView {
                Label("Couldn't load this session", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(message)
                    .accessibilityIdentifier("packing.session.error_message")
            }
            Spacer()
            VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                PeezyAssessmentButton("Try again") { Task { await loadSession() } }
                    .accessibilityIdentifier("packing.session.retry")
                Button("Close", action: onDismiss)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("packing.session.error_close")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("packing.session.error")
    }

    private func loadSession() async {
        errorMessage = nil
        do {
            session = try await actionService.loadPackingSession(userId: userId, taskId: taskId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func complete() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                let result = try await actionService.completePackingSession(
                    userId: userId,
                    taskId: taskId
                )
                await MainActor.run {
                    consequenceLine = result.consequenceLine
                    isSaving = false
                    PeezyHaptics.taskComplete()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    session = nil
                    isSaving = false
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    PackingSessionView(
        userId: "preview",
        taskId: "PACKING_SESSION_1",
        onComplete: {},
        onDismiss: {},
        onStatusAction: { _ in }
    )
}
#endif
