import SwiftUI

struct MoveCheckInView: View {
    let userId: String
    let taskId: String
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var bookingContext: CheckInBookingContext?
    @State private var hasLoadedContext = false
    @State private var arrivedInWindow: Bool?
    @State private var crewWorkedSteadily: Bool?
    @State private var costMoreThanQuoted: Bool?
    @State private var damaged: Bool?
    @State private var note = ""
    @State private var finalBill = ""
    @State private var questionIndex = 0
    @State private var isSubmitting = false
    @State private var isSubmitted = false
    @State private var errorMessage: String?

    private let service = CheckInService()
    private let usesFixtureContext: Bool

    init(
        userId: String,
        taskId: String,
        onDismiss: @escaping () -> Void,
        onStatusAction: @escaping (TaskFlowStatusAction) -> Void,
        fixtureBookingContext: CheckInBookingContext? = nil,
        fixtureContextLoaded: Bool = false
    ) {
        self.userId = userId
        self.taskId = taskId
        self.onDismiss = onDismiss
        self.onStatusAction = onStatusAction
        usesFixtureContext = fixtureContextLoaded
        _bookingContext = State(initialValue: fixtureBookingContext)
        _hasLoadedContext = State(initialValue: fixtureContextLoaded)
    }

    private var hasAllAnswers: Bool {
        arrivedInWindow != nil
            && crewWorkedSteadily != nil
            && costMoreThanQuoted != nil
            && damaged != nil
            && isFinalBillValid
    }

    private var isFinalBillValid: Bool {
        guard bookingContext != nil else { return true }
        let trimmed = finalBill.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || CheckInService.finalBill(from: trimmed) != nil
    }

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(
                cardsRemaining: isSubmitted ? 1 : max(checkInQuestions.count - questionIndex, 1),
                currentIndex: isSubmitted ? 0 : questionIndex
            ) {
                content
            }
        }
        .task {
            if !usesFixtureContext {
                await loadContext()
            }
        }
        .accessibilityIdentifier("checkin.flow")
        .resumableFlowProgress(
            path: [isSubmitted ? "submitted" : "checkin"],
            answers: progressAnswers
        ) { restored in
            arrivedInWindow = Self.decodeBool(restored.answers["arrived_in_window"]?.first)
            crewWorkedSteadily = Self.decodeBool(restored.answers["crew_worked_steadily"]?.first)
            costMoreThanQuoted = Self.decodeBool(restored.answers["cost_more_than_quoted"]?.first)
            damaged = Self.decodeBool(restored.answers["damaged"]?.first)
            note = restored.answers["note"]?.first ?? ""
            finalBill = restored.answers["final_bill"]?.first ?? ""
        }
    }

    private var progressAnswers: [String: [String]] {
        var result: [String: [String]] = [:]
        if let arrivedInWindow { result["arrived_in_window"] = [String(arrivedInWindow)] }
        if let crewWorkedSteadily { result["crew_worked_steadily"] = [String(crewWorkedSteadily)] }
        if let costMoreThanQuoted { result["cost_more_than_quoted"] = [String(costMoreThanQuoted)] }
        if let damaged { result["damaged"] = [String(damaged)] }
        if !note.isEmpty { result["note"] = [note] }
        if !finalBill.isEmpty { result["final_bill"] = [finalBill] }
        return result
    }

    private static func decodeBool(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        return raw == "true"
    }

    private enum CheckInQuestion: String {
        case arrival
        case steady
        case cost
        case damage
        case note
        case finalBill
    }

    private var checkInQuestions: [CheckInQuestion] {
        bookingContext == nil
            ? [.arrival, .steady, .cost, .damage, .note]
            : [.arrival, .steady, .cost, .damage, .note, .finalBill]
    }

    private var currentCheckInQuestion: CheckInQuestion {
        checkInQuestions[min(questionIndex, checkInQuestions.count - 1)]
    }

    @ViewBuilder
    private var content: some View {
        if isSubmitted {
            submittedCard
        } else if hasLoadedContext {
            formCard
        } else if let errorMessage {
            loadErrorCard(errorMessage)
        } else {
            ProgressView("Loading your moving-day check-in…")
                .tint(PeezyTheme.Colors.deepInk)
                .accessibilityIdentifier("checkin.loading")
        }
    }

    private var formCard: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(
                taskTitle: "Moving-day check-in",
                showBack: questionIndex > 0,
                onBack: { questionIndex = max(questionIndex - 1, 0) }
            )

            VStack(alignment: .leading, spacing: 20) {
                Text("Question \(questionIndex + 1) of \(checkInQuestions.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("checkin.progress")

                checkInQuestionContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 28)

            Spacer(minLength: 16)

            VStack(spacing: 12) {
                if currentCheckInQuestion == .note || currentCheckInQuestion == .finalBill {
                    PeezyAssessmentButton(
                        questionIndex == checkInQuestions.count - 1
                            ? (isSubmitting ? "Saving…" : "Submit check-in")
                            : "Continue",
                        disabled: (currentCheckInQuestion == .finalBill && !isFinalBillValid) || isSubmitting,
                        action: advanceCheckIn
                    )
                    .accessibilityIdentifier("checkin.submit")
                }

                Button("Close", action: onDismiss)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("checkin.close")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .accessibilityIdentifier(
            bookingContext == nil ? "checkin.general_card" : "checkin.vendor_card"
        )
    }

    @ViewBuilder
    private var checkInQuestionContent: some View {
        switch currentCheckInQuestion {
        case .arrival:
            yesNoQuestion(
                "Did they arrive in the window?",
                selection: arrivedInWindow,
                id: "arrival"
            ) {
                arrivedInWindow = $0
                advanceCheckIn()
            }
        case .steady:
            yesNoQuestion(
                "Did the crew work steadily?",
                selection: crewWorkedSteadily,
                id: "steady"
            ) {
                crewWorkedSteadily = $0
                advanceCheckIn()
            }
        case .cost:
            yesNoQuestion(
                "Did anything cost more than quoted?",
                selection: costMoreThanQuoted,
                id: "cost"
            ) {
                costMoreThanQuoted = $0
                advanceCheckIn()
            }
        case .damage:
            yesNoQuestion(
                "Was anything damaged?",
                selection: damaged,
                id: "damage"
            ) {
                damaged = $0
                advanceCheckIn()
            }
        case .note:
            VStack(alignment: .leading, spacing: 12) {
                Text("Anything else we should know?")
                    .font(.title.bold())
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityIdentifier("checkin.question.note")
                TextField("Optional note", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("checkin.note")
            }
        case .finalBill:
            VStack(alignment: .leading, spacing: 12) {
                Text("What was the final bill?")
                    .font(.title.bold())
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityIdentifier("checkin.question.final_bill")
                if let bookingContext {
                    Text(
                        "Peezy estimate: \(money(bookingContext.estimatedRange.low))–\(money(bookingContext.estimatedRange.high))"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("checkin.estimated_range")
                }
                TextField("Final bill (optional)", text: $finalBill)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("checkin.final_bill")
                if !isFinalBillValid {
                    Text("Enter a final bill greater than $0, or leave it blank.")
                        .font(.footnote)
                        .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                        .accessibilityIdentifier("checkin.final_bill_error")
                }
            }
        }

        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                .accessibilityIdentifier("checkin.error_message")
        }
    }

    private func advanceCheckIn() {
        if questionIndex >= checkInQuestions.count - 1 {
            submit()
        } else {
            questionIndex += 1
        }
    }

    private var submittedCard: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Moving-day check-in")
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(PeezyTheme.Colors.successGreen)
                    .accessibilityHidden(true)
                Text("Thanks. We saved the facts and we'll follow up on anything that needs attention.")
                    .font(.title2)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityIdentifier("checkin.submitted_message")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            Spacer()
            PeezyAssessmentButton("Done") {
                onStatusAction(.done)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .accessibilityIdentifier("checkin.done")
        }
        .accessibilityIdentifier("checkin.submitted")
    }

    private func loadErrorCard(_ message: String) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Moving-day check-in")
            Spacer()
            ContentUnavailableView {
                Label("Couldn't load your check-in", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(message)
                    .accessibilityIdentifier("checkin.load_error")
            }
            Spacer()
            VStack(spacing: 12) {
                PeezyAssessmentButton("Try again") {
                    Task { await loadContext() }
                }
                .accessibilityIdentifier("checkin.retry")
                Button("Close", action: onDismiss)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("checkin.error_close")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("checkin.error")
    }

    private func yesNoQuestion(
        _ question: String,
        selection: Bool?,
        id: String,
        onSelect: @escaping (Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question)
                .font(.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("checkin.question.\(id)")

            HStack(spacing: 12) {
                answerButton("Yes", value: true, selection: selection, id: "\(id).yes", onSelect: onSelect)
                answerButton("No", value: false, selection: selection, id: "\(id).no", onSelect: onSelect)
            }
        }
        .accessibilityIdentifier("checkin.answer_group.\(id)")
    }

    private func answerButton(
        _ label: String,
        value: Bool,
        selection: Bool?,
        id: String,
        onSelect: @escaping (Bool) -> Void
    ) -> some View {
        Button {
            onSelect(value)
            PeezyHaptics.selection()
        } label: {
            Text(label)
                .font(.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    selection == value
                        ? AnyShapeStyle(PeezyTheme.Colors.successGreen.opacity(0.2))
                        : AnyShapeStyle(.regularMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            selection == value ? PeezyTheme.Colors.successGreen : .clear,
                            lineWidth: 2
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(selection == value ? "Selected" : "Not selected")
        .accessibilityIdentifier("checkin.answer.\(id)")
    }

    private func loadContext() async {
        hasLoadedContext = false
        errorMessage = nil
        do {
            bookingContext = try await service.loadBookingContext(userId: userId)
            hasLoadedContext = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() {
        guard let arrivedInWindow,
              let crewWorkedSteadily,
              let costMoreThanQuoted,
              let damaged,
              hasAllAnswers,
              !isSubmitting
        else { return }
        isSubmitting = true
        errorMessage = nil
        let answers = MoveCheckInAnswers(
            arrivedInWindow: arrivedInWindow,
            crewWorkedSteadily: crewWorkedSteadily,
            costMoreThanQuoted: costMoreThanQuoted,
            damaged: damaged,
            note: note,
            finalBill: bookingContext == nil ? nil : CheckInService.finalBill(from: finalBill)
        )
        Task {
            do {
                _ = try await service.submit(answers)
                isSubmitted = true
                isSubmitting = false
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    private func money(_ amount: Double) -> String {
        amount.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(0))
        )
    }
}

#if DEBUG
#Preview {
    MoveCheckInView(
        userId: "preview",
        taskId: "MOVE_CHECKIN",
        onDismiss: {},
        onStatusAction: { _ in }
    )
}
#endif
