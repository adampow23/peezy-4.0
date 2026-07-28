import SwiftUI

struct BoxReturnView: View {
    let userId: String
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var deliveredCount: Int?
    @State private var returnedCount = 0
    @State private var ranOut: Bool?
    @State private var requestsPickup = false
    @State private var submittedCalibration: KitCalibration?
    @State private var submittedWithPickup = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let service = BoxReturnService()

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: 1, currentIndex: 0) {
                content
            }
        }
        .task { await loadDeliveredCount() }
        .onChange(of: returnedCount) { _, newValue in
            if newValue == 0 {
                requestsPickup = false
            }
        }
        .accessibilityIdentifier("box_return.flow")
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
            TaskFlowHeader(taskTitle: "Box return")

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "shippingbox.and.arrow.backward.fill")
                        .font(.largeTitle)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .accessibilityHidden(true)

                    Text("How many boxes are you returning or recycling?")
                        .font(.title)
                        .bold()
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
                                .font(.title2)
                                .bold()
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Did you run out of boxes before move day?")
                            .font(.headline)
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("box_return.ran_out_question")

                        HStack(spacing: 12) {
                            ranOutButton("Yes", value: true)
                            ranOutButton("No", value: false)
                        }
                    }

                    Toggle("I'd like Peezy to arrange pickup", isOn: $requestsPickup)
                        .tint(PeezyTheme.Colors.successGreen)
                        .disabled(returnedCount == 0)
                        .accessibilityIdentifier("box_return.pickup_toggle")

                    if requestsPickup {
                        Text("We'll send the count to the concierge team and follow up about pickup.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("box_return.pickup_note")
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                            .accessibilityIdentifier("box_return.error_message")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }

            VStack(spacing: 12) {
                PeezyAssessmentButton(
                    isSubmitting ? "Saving…" : "Save box count",
                    disabled: ranOut == nil || isSubmitting,
                    action: submit
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

    private func submittedCard(_ calibration: KitCalibration) -> some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Box return")
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(PeezyTheme.Colors.successGreen)
                    .accessibilityHidden(true)
                Text("Got it — \(calibration.returned) of \(calibration.delivered) boxes recorded.")
                    .font(.title2)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityIdentifier("box_return.submitted_message")
                if submittedWithPickup {
                    Text("Your pickup request is with the concierge team.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("box_return.pickup_submitted")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            Spacer()
            PeezyAssessmentButton("Done") {
                onStatusAction(submittedWithPickup ? .submittedToPeezy : .done)
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
        let pickup = requestsPickup
        Task {
            do {
                let calibration = try await service.submit(
                    userId: userId,
                    returned: returnedCount,
                    ranOut: ranOut,
                    requestPickup: pickup
                )
                submittedWithPickup = pickup
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
        onDismiss: {},
        onStatusAction: { _ in }
    )
}
#endif
