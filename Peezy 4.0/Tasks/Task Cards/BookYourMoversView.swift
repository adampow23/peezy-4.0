//
//  BookYourMoversView.swift
//  Peezy 4.0
//
//  BOOK_YOUR_MOVERS (plan A3): one screen. "Yes" captures optional booking
//  details and completes with ONE awaited atomic write (status "Completed" +
//  completedAt + bookingDetails). "Not yet" is an awaited throwing two-day
//  snooze. Both terminals invoke only already-persisted local callbacks.
//

import FirebaseFirestore
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class BookYourMoversModel {
    private(set) var companyChips: [String] = []
    private(set) var isSaving = false
    private(set) var actionError: String?

    var company = ""
    var arrivalWindow = ""
    var crewSizeText = ""
    var crewHourlyRateText = ""
    var includesMoveDate = false
    var moveDate = Date()

    private var userId = ""
    private var taskDocumentId = ""
    private let actionService = TaskActionService()

    func prepare(userId: String, taskDocumentId: String) async {
        self.userId = userId
        self.taskDocumentId = taskDocumentId
        guard !userId.isEmpty, !taskDocumentId.isEmpty else { return }

        // Prefill chips come from the predecessor doc via spawnedFrom.id —
        // quotes never live on this spawned doc (plan A3). Any failure here is
        // nonblocking: free-text entry still works.
        do {
            let db = Firestore.firestore()
            let tasks = db.collection("users").document(userId).collection("tasks")
            let taskData = try await tasks.document(taskDocumentId).getDocument().data() ?? [:]
            guard let spawnedFrom = taskData["spawnedFrom"] as? [String: Any],
                  let predecessorId = spawnedFrom["id"] as? String,
                  !predecessorId.isEmpty else { return }
            let predecessorData = try await tasks.document(predecessorId).getDocument().data() ?? [:]
            companyChips = MoversPredecessorChips.companyChips(
                fromQuotesData: predecessorData["quotes"] as? [[String: Any]] ?? []
            )
        } catch {
            print("⚠️ Booking chips unavailable: \(error.localizedDescription)")
        }
    }

    private var bookingDetails: MoversBookingDetails {
        MoversBookingDetails(
            company: company.trimmingCharacters(in: .whitespacesAndNewlines),
            moveDate: includesMoveDate ? moveDate : nil,
            arrivalWindow: arrivalWindow.trimmingCharacters(in: .whitespacesAndNewlines),
            crewSize: Int(crewSizeText.trimmingCharacters(in: .whitespaces)),
            crewHourlyRate: Double(crewHourlyRateText.trimmingCharacters(in: .whitespaces))
        )
    }

    /// "Yes" terminal — returns true only after the atomic write succeeded.
    func confirmBooking() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        actionError = nil
        defer { isSaving = false }
        do {
            try await actionService.completeBookingThrowing(
                userId: userId,
                taskDocumentId: taskDocumentId,
                details: bookingDetails
            )
            return true
        } catch {
            actionError = "Couldn't save your booking — check your connection and try again."
            return false
        }
    }

    /// "Not yet" terminal — awaited throwing two-day snooze, no booked state.
    func bookLater() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        actionError = nil
        defer { isSaving = false }
        do {
            try await actionService.snoozeTwoDaysThrowing(
                userId: userId,
                taskDocumentId: taskDocumentId
            )
            return true
        } catch {
            actionError = "Couldn't snooze this task — check your connection and try again."
            return false
        }
    }
}

struct BookYourMoversView: View {
    let userId: String
    let taskDocumentId: String
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var model = BookYourMoversModel()
    @State private var saidYes = false

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TaskFlowHeader(taskTitle: "Book your movers")

                ScrollView {
                    VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                            Text("Did you book with the company you chose?")
                                .font(.title)
                                .bold()
                                .foregroundStyle(PeezyTheme.Colors.deepInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("movers.book.question")

                            Text("Every detail is optional — save what you have and Peezy holds them to it.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("movers.book.subtitle")
                        }

                        if saidYes {
                            captureForm
                        }
                    }
                    .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
                    .padding(.vertical, PeezyTheme.Layout.verticalSpacing)
                }
                .scrollIndicators(.hidden)

                if let actionError = model.actionError {
                    Text(actionError)
                        .font(.callout)
                        .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
                        .padding(.bottom, PeezyTheme.Layout.verticalSpacingSmall)
                        .accessibilityIdentifier("movers.book.error")
                }

                terminalButtons
            }
        }
        .task {
            await model.prepare(userId: userId, taskDocumentId: taskDocumentId)
        }
        .accessibilityIdentifier("movers.book.screen")
    }

    @ViewBuilder
    private var terminalButtons: some View {
        VStack(spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            if saidYes {
                PeezyAssessmentButton(
                    model.isSaving ? "Saving…" : "Done",
                    disabled: model.isSaving,
                    action: confirm
                )
                .accessibilityIdentifier("movers.book.done")
            } else {
                PeezyAssessmentButton("Yes, I booked", action: { saidYes = true })
                    .accessibilityIdentifier("movers.book.yes")
            }

            Button(model.isSaving ? "Saving…" : "I'll book later") {
                later()
            }
            .font(PeezyTheme.Typography.headline)
            .foregroundStyle(PeezyTheme.Colors.deepInk)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(model.isSaving)
            .accessibilityIdentifier("movers.book.later")
        }
        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
        .padding(.bottom, PeezyTheme.Layout.verticalSpacing)
    }

    private var captureForm: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
            if !model.companyChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                        ForEach(Array(model.companyChips.enumerated()), id: \.offset) { index, chip in
                            Button(chip) {
                                model.company = chip
                            }
                            .font(PeezyTheme.Typography.callout)
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .padding(.horizontal, PeezyTheme.Layout.cardPaddingSmall)
                            .frame(minHeight: 36)
                            .background(
                                PeezyTheme.Colors.deepInk.opacity(model.company == chip ? 0.42 : 0.14),
                                in: Capsule()
                            )
                            .accessibilityIdentifier("movers.book.chip.\(index)")
                        }
                    }
                }
                .accessibilityIdentifier("movers.book.chips")
            }

            TextField("Company", text: $model.company)
                .textInputAutocapitalization(.words)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("movers.book.companyField")

            Toggle("I have the move date confirmed", isOn: $model.includesMoveDate)
                .font(PeezyTheme.Typography.body)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .accessibilityIdentifier("movers.book.moveDateToggle")

            if model.includesMoveDate {
                DatePicker("Move date", selection: $model.moveDate, displayedComponents: .date)
                    .font(PeezyTheme.Typography.body)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityIdentifier("movers.book.moveDatePicker")
            }

            TextField("Arrival window (e.g. 8–10 am)", text: $model.arrivalWindow)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("movers.book.arrivalField")

            TextField("Crew size", text: $model.crewSizeText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("movers.book.crewField")

            TextField("Hourly rate for the crew", text: $model.crewHourlyRateText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("movers.book.rateField")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .taskContentCard()
        .accessibilityIdentifier("movers.book.form")
    }

    private func confirm() {
        Task {
            if await model.confirmBooking() {
                onStatusAction(.completedAlreadyPersisted)
            }
        }
    }

    private func later() {
        Task {
            if await model.bookLater() {
                onStatusAction(.laterAlreadyPersisted)
            }
        }
    }
}
