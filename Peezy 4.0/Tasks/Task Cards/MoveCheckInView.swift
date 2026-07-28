import SwiftUI

struct MoveCheckInView: View {
    let userId: String
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
    @State private var isSubmitting = false
    @State private var isSubmitted = false
    @State private var errorMessage: String?

    private let service = CheckInService()
    private let usesFixtureContext: Bool

    init(
        userId: String,
        onDismiss: @escaping () -> Void,
        onStatusAction: @escaping (TaskFlowStatusAction) -> Void,
        fixtureBookingContext: CheckInBookingContext? = nil,
        fixtureContextLoaded: Bool = false
    ) {
        self.userId = userId
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

            TaskFlowStack(cardsRemaining: 1, currentIndex: 0) {
                content
            }
        }
        .task {
            if !usesFixtureContext {
                await loadContext()
            }
        }
        .accessibilityIdentifier("checkin.flow")
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
            TaskFlowHeader(taskTitle: "Moving-day check-in")

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "checkmark.message.fill")
                        .font(.largeTitle)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .accessibilityHidden(true)

                    Text(bookingContext.map { "How did \($0.vendorName) do?" } ?? "How did moving day go?")
                        .font(.title)
                        .bold()
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .accessibilityIdentifier("checkin.title")

                    Text("Four facts. No rating games. This is how Peezy follows through.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("checkin.intro")

                    yesNoQuestion(
                        "Did they arrive in the window?",
                        selection: arrivedInWindow,
                        id: "arrival",
                        onSelect: { arrivedInWindow = $0 }
                    )
                    yesNoQuestion(
                        "Did the crew work steadily?",
                        selection: crewWorkedSteadily,
                        id: "steady",
                        onSelect: { crewWorkedSteadily = $0 }
                    )
                    yesNoQuestion(
                        "Did anything cost more than quoted?",
                        selection: costMoreThanQuoted,
                        id: "cost",
                        onSelect: { costMoreThanQuoted = $0 }
                    )
                    yesNoQuestion(
                        "Was anything damaged?",
                        selection: damaged,
                        id: "damage",
                        onSelect: { damaged = $0 }
                    )

                    TextField(
                        "Anything else we should know? (optional)",
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("checkin.note")

                    if let bookingContext {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Peezy estimate: \(money(bookingContext.estimatedRange.low))–\(money(bookingContext.estimatedRange.high))"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("checkin.estimated_range")

                            TextField("What was the final bill? (optional)", text: $finalBill)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }

            VStack(spacing: 12) {
                PeezyAssessmentButton(
                    isSubmitting ? "Saving…" : "Submit check-in",
                    disabled: !hasAllAnswers || isSubmitting,
                    action: submit
                )
                .accessibilityIdentifier("checkin.submit")

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
        onDismiss: {},
        onStatusAction: { _ in }
    )
}
#endif
