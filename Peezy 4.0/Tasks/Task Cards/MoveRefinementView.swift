//
//  MoveRefinementView.swift
//  Peezy 4.0
//

import SwiftUI

struct MoveRefinementView: View {
    @Bindable var model: MoversFlowViewModel
    let onContinue: () -> Void
    let onBack: () -> Void

    @State private var questionIndex = 0

    private let bedrooms = ["1 Bedroom", "2 Bedrooms", "3 Bedrooms", "4 Bedrooms", "5 Bedrooms", "6+ Bedrooms"]
    private let accessOptions = ["Unknown", "Ground Floor", "Stairs", "Elevator", "Reserved Elevator"]

    private enum Question: String {
        case currentHome
        case destinationHome
        case includeStorage
        case storageSize
        case storageFullness
        case storageStop
        case storageAddress
        case originAccess
        case originLongCarry
        case destinationAccess
        case destinationLongCarry
        case packedStatus
        case coverage
        case arrivalWindow
    }

    private var questions: [Question] {
        var result: [Question] = []
        if !model.hasInventory {
            result += [.currentHome, .destinationHome]
        }
        result.append(.includeStorage)
        if model.hasStorage {
            result += [.storageSize, .storageFullness, .storageStop]
            if model.storageStopOnMovingDay { result.append(.storageAddress) }
        }
        result += [
            .originAccess,
            .originLongCarry,
            .destinationAccess,
            .destinationLongCarry,
            .packedStatus,
            .coverage,
            .arrivalWindow
        ]
        return result
    }

    private var currentQuestion: Question {
        questions[min(questionIndex, questions.count - 1)]
    }

    private var isLastQuestion: Bool {
        questionIndex >= questions.count - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Book your movers", showBack: true, onBack: goBack)

            VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                Text("Question \(questionIndex + 1) of \(questions.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("movers.refinement.progress")

                Text(questionTitle)
                    .font(.title)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("movers.refinement.question.\(currentQuestion.rawValue)")

                questionControl
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 28)

            Spacer(minLength: 20)

            PeezyAssessmentButton(
                isLastQuestion ? "Compare prices" : "Continue",
                disabled: isLastQuestion && !model.canCompare,
                action: advance
            )
            .accessibilityIdentifier("movers.refinement.continue")
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("movers.refinement")
    }

    private var questionTitle: String {
        switch currentQuestion {
        case .currentHome: "How many bedrooms are in your current home?"
        case .destinationHome: "How many bedrooms are in your destination home?"
        case .includeStorage: "Are you moving anything from storage?"
        case .storageSize: "How large is the storage unit?"
        case .storageFullness: "How full is the storage unit?"
        case .storageStop: "Is the storage unit a stop on moving day?"
        case .storageAddress: "Where is the storage unit?"
        case .originAccess: "What's the access like at your current home?"
        case .originLongCarry: "Is there a long carry at your current home?"
        case .destinationAccess: "What's the access like at your destination?"
        case .destinationLongCarry: "Is there a long carry at your destination?"
        case .packedStatus: "How packed will you be when the movers arrive?"
        case .coverage: "What kind of protection do you want?"
        case .arrivalWindow: "What arrival window works for you?"
        }
    }

    @ViewBuilder
    private var questionControl: some View {
        switch currentQuestion {
        case .currentHome:
            menuPicker(
                title: "Current home",
                selection: $model.bedroomsAnswer,
                options: bedrooms,
                id: "movers.refinement.bedrooms"
            )
        case .destinationHome:
            menuPicker(
                title: "Destination home",
                selection: $model.destinationBedroomsAnswer,
                options: bedrooms,
                id: "movers.refinement.destination_bedrooms"
            )
        case .includeStorage:
            booleanChoices(selection: $model.hasStorage, id: "movers.refinement.has_storage")
        case .storageSize:
            menuPicker(
                title: "Storage size",
                selection: $model.storageSize,
                options: ["Small", "Medium", "Large"],
                id: "movers.refinement.storage_size"
            )
        case .storageFullness:
            menuPicker(
                title: "Storage fullness",
                selection: $model.storageFullness,
                options: ["1/4", "1/2", "3/4", "Full"],
                id: "movers.refinement.storage_fullness"
            )
        case .storageStop:
            booleanChoices(selection: $model.storageStopOnMovingDay, id: "movers.refinement.storage_stop")
        case .storageAddress:
            TextField("Storage unit address or city (optional)", text: $model.storageUnitAddress)
                .textInputAutocapitalization(.words)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("movers.refinement.storage_address")
        case .originAccess:
            menuPicker(
                title: "Origin access",
                selection: $model.originAccessAnswer,
                options: accessOptions,
                id: "movers.refinement.origin_access"
            )
        case .originLongCarry:
            booleanChoices(selection: $model.originLongCarry, id: "movers.refinement.origin_long_carry")
        case .destinationAccess:
            menuPicker(
                title: "Destination access",
                selection: $model.destinationAccessAnswer,
                options: accessOptions,
                id: "movers.refinement.destination_access"
            )
        case .destinationLongCarry:
            booleanChoices(selection: $model.destinationLongCarry, id: "movers.refinement.destination_long_carry")
        case .packedStatus:
            Picker("Packing status", selection: $model.packedStatus) {
                Text("Packed before arrival").tag(PackedStatus.packed)
                Text("Some boxes unpacked").tag(PackedStatus.unpacked)
                Text("Not sure yet").tag(PackedStatus.unknown)
            }
            .pickerStyle(.inline)
            .accessibilityIdentifier("movers.refinement.packed_status")
        case .coverage:
            menuPicker(
                title: "Protection",
                selection: $model.coveragePreference,
                options: ["standard", "full"],
                labels: ["Standard valuation", "Full-value protection"],
                id: "movers.refinement.coverage"
            )
        case .arrivalWindow:
            TextField("Example: 8–10 AM", text: $model.requestedArrivalWindow)
                .textInputAutocapitalization(.sentences)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("movers.refinement.arrival_window")
        }
    }

    private func menuPicker(
        title: String,
        selection: Binding<String>,
        options: [String],
        labels: [String]? = nil,
        id: String
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, value in
                Text(labels?[index] ?? value).tag(value)
            }
        }
        .pickerStyle(.inline)
        .accessibilityIdentifier(id)
    }

    private func booleanChoices(selection: Binding<Bool>, id: String) -> some View {
        HStack(spacing: 12) {
            choiceButton("Yes", selected: selection.wrappedValue) {
                selection.wrappedValue = true
            }
            choiceButton("No", selected: !selection.wrappedValue) {
                selection.wrappedValue = false
            }
        }
        .accessibilityIdentifier(id)
    }

    private func choiceButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(selected ? PeezyTheme.Colors.successGreen.opacity(0.2) : Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected ? PeezyTheme.Colors.successGreen : .clear, lineWidth: 2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func advance() {
        if isLastQuestion {
            onContinue()
        } else {
            questionIndex += 1
        }
    }

    private func goBack() {
        if questionIndex == 0 {
            onBack()
        } else {
            questionIndex -= 1
        }
    }
}
