import SwiftUI

struct BoxReturnView: View {
    let userId: String
    let taskId: String
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var deliveredCount: Int?
    @State private var returnedCount = 0
    @State private var didEditReturnedCount = false
    @State private var ranOut: Bool?
    @State private var submittedCalibration: KitCalibration?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var questionIndex = 0

    private let service = BoxReturnService()

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(
                cardsRemaining: submittedCalibration == nil
                    ? max(boxReturnQuestions.count - questionIndex, 1)
                    : 1,
                currentIndex: submittedCalibration == nil ? questionIndex : 0
            ) {
                content
            }
        }
        .task { await loadDeliveredCount() }
        .onChange(of: returnedCount) { _, _ in
            didEditReturnedCount = true
        }
        .accessibilityIdentifier("box_return.flow")
        .resumableFlowProgress(
            path: [submittedCalibration == nil ? "box_return" : "submitted"],
            answers: progressAnswers
        ) { restored in
            if let raw = restored.answers["returned_count"]?.first, let count = Int(raw) {
                returnedCount = count
                didEditReturnedCount = true
            }
            if let raw = restored.answers["ran_out"]?.first {
                ranOut = raw == "true"
            }
        }
    }

    private var progressAnswers: [String: [String]] {
        var result: [String: [String]] = [:]
        if didEditReturnedCount { result["returned_count"] = [String(returnedCount)] }
        if let ranOut { result["ran_out"] = [String(ranOut)] }
        return result
    }

    private enum BoxReturnQuestion {
        case returnedCount
        case ranOut
    }

    private var boxReturnQuestions: [BoxReturnQuestion] {
        [.returnedCount, .ranOut]
    }

    private var currentBoxReturnQuestion: BoxReturnQuestion {
        boxReturnQuestions[min(questionIndex, boxReturnQuestions.count - 1)]
    }

    @ViewBuilder
    private var content: some View {
        if let submittedCalibration {
            submittedCard(submittedCalibration)
        } else if let deliveredCount {
            formCard(deliveredCount)
        } else if let errorMessage {
            errorCard(errorMessage)
        } else {
            ProgressView("Finding your packing kit…")
                .tint(PeezyTheme.Colors.deepInk)
                .accessibilityIdentifier("box_return.loading")
        }
    }

    private func formCard(_ delivered: Int) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(
                taskTitle: "Box return",
                showBack: questionIndex > 0,
                onBack: { questionIndex = max(questionIndex - 1, 0) }
            )

            VStack(alignment: .leading, spacing: 20) {
                Text("Question \(questionIndex + 1) of \(boxReturnQuestions.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("box_return.progress")

                boxReturnQuestionContent(delivered: delivered)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                        .accessibilityIdentifier("box_return.error_message")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 28)

            Spacer(minLength: 16)

            VStack(spacing: 12) {
                PeezyAssessmentButton(
                    questionIndex >= boxReturnQuestions.count - 1
                        ? (isSubmitting ? "Saving…" : "Save box count")
                        : "Continue",
                    disabled: (currentBoxReturnQuestion == .ranOut && ranOut == nil) || isSubmitting,
                    action: advanceBoxReturn
                )
                .accessibilityIdentifier("box_return.submit")

                Button("Close", action: onDismiss)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("box_return.close")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .accessibilityIdentifier("box_return.card")
    }

    @ViewBuilder
    private func boxReturnQuestionContent(delivered: Int) -> some View {
        switch currentBoxReturnQuestion {
        case .returnedCount:
            Text("How many boxes are you returning or recycling?")
                .font(.title.bold())
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("box_return.title")
            Text("Your kit included \(delivered) boxes. The count helps us size future kits with less waste.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("box_return.delivered")
            Stepper(value: $returnedCount, in: 0...999) {
                HStack {
                    Text("Boxes")
                        .font(.headline)
                    Spacer()
                    Text("\(returnedCount)")
                        .font(.title2.bold())
                        .monospacedDigit()
                        .accessibilityIdentifier("box_return.returned_value")
                }
            }
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Boxes returning or recycling")
            .accessibilityValue("\(returnedCount)")
            .accessibilityIdentifier("box_return.returned_stepper")

        case .ranOut:
            Text("Did you run out of boxes before move day?")
                .font(.title.bold())
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("box_return.ran_out_question")
            HStack(spacing: 12) {
                ranOutButton("Yes", value: true)
                ranOutButton("No", value: false)
            }

        }
    }

    private func advanceBoxReturn() {
        if questionIndex >= boxReturnQuestions.count - 1 {
            submit()
        } else {
            questionIndex += 1
        }
    }

    private func submittedCard(_ calibration: KitCalibration) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Box return")
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(PeezyTheme.Colors.successGreen)
                    .accessibilityHidden(true)
                Text("You're set. Here's everything you need.")
                    .font(.title2)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityIdentifier("box_return.submitted_message")
                Text("\(calibration.returned) of \(calibration.delivered) boxes recorded.")
                    .font(.body.bold())
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                Text("Offer clean boxes through a local reuse group or donation center. Flatten boxes that cannot be reused, remove tape and packing material, and check your local recycling rules.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("box_return.reuse_guidance")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            Spacer()
            PeezyAssessmentButton("Done") {
                onStatusAction(.done)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .accessibilityIdentifier("box_return.done")
        }
        .accessibilityIdentifier("box_return.submitted")
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Box return")
            Spacer()
            ContentUnavailableView {
                Label("Couldn't load your kit", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(message)
                    .accessibilityIdentifier("box_return.load_error")
            }
            Spacer()
            VStack(spacing: 12) {
                PeezyAssessmentButton("Try again") {
                    Task { await loadDeliveredCount() }
                }
                .accessibilityIdentifier("box_return.retry")
                Button("Close", action: onDismiss)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("box_return.error_close")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("box_return.error")
    }

    private func loadDeliveredCount() async {
        errorMessage = nil
        do {
            deliveredCount = try await service.loadDeliveredCount(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() {
        guard let ranOut, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                let calibration = try await service.submit(
                    userId: userId,
                    returned: returnedCount,
                    ranOut: ranOut,
                    requestPickup: false
                )
                submittedCalibration = calibration
                isSubmitting = false
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    private func ranOutButton(_ label: String, value: Bool) -> some View {
        Button {
            ranOut = value
            PeezyHaptics.selection()
        } label: {
            Text(label)
                .font(.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    ranOut == value
                        ? AnyShapeStyle(PeezyTheme.Colors.successGreen.opacity(0.2))
                        : AnyShapeStyle(.regularMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            ranOut == value ? PeezyTheme.Colors.successGreen : .clear,
                            lineWidth: 2
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(ranOut == value ? "Selected" : "Not selected")
        .accessibilityIdentifier("box_return.ran_out.\(value ? "yes" : "no")")
    }

}

#if DEBUG
#Preview {
    BoxReturnView(
        userId: "preview",
        taskId: "BOX_RETURN",
        onDismiss: {},
        onStatusAction: { _ in }
    )
}
#endif
