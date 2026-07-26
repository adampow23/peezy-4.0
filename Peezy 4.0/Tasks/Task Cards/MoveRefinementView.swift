//
//  MoveRefinementView.swift
//  Peezy 4.0
//

import SwiftUI

struct MoveRefinementView: View {
    @Bindable var model: MoversFlowViewModel
    let onContinue: () -> Void
    let onBack: () -> Void

    private let bedrooms = ["1 Bedroom", "2 Bedrooms", "3 Bedrooms", "4 Bedrooms", "5 Bedrooms", "6+ Bedrooms"]
    private let accessOptions = ["Unknown", "Ground Floor", "Stairs", "Elevator", "Reserved Elevator"]

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Book your movers", showBack: true, onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                    Text("Tighten the estimate")
                        .font(.title2)
                        .bold()
                        .foregroundStyle(PeezyTheme.Colors.deepInk)

                    if !model.hasInventory {
                        fieldLabel("Current home")
                        Picker("Current home", selection: $model.bedroomsAnswer) {
                            ForEach(bedrooms, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("movers.refinement.bedrooms")

                        fieldLabel("Destination home")
                        Picker("Destination home", selection: $model.destinationBedroomsAnswer) {
                            ForEach(bedrooms, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("movers.refinement.destination_bedrooms")
                    }

                    Toggle("Include a storage stop", isOn: $model.hasStorage)
                        .font(.body)
                        .accessibilityIdentifier("movers.refinement.has_storage")

                    if model.hasStorage {
                        fieldLabel("Storage size")
                        Picker("Storage size", selection: $model.storageSize) {
                            Text("Small").tag("Small")
                            Text("Medium").tag("Medium")
                            Text("Large").tag("Large")
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("movers.refinement.storage_size")

                        fieldLabel("Storage fullness")
                        Picker("Storage fullness", selection: $model.storageFullness) {
                            Text("1/4").tag("1/4")
                            Text("1/2").tag("1/2")
                            Text("3/4").tag("3/4")
                            Text("Full").tag("Full")
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("movers.refinement.storage_fullness")
                    }

                    fieldLabel("Origin access")
                    Picker("Origin access", selection: $model.originAccessAnswer) {
                        ForEach(accessOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("movers.refinement.origin_access")

                    Toggle("Long carry at origin", isOn: $model.originLongCarry)
                        .accessibilityIdentifier("movers.refinement.origin_long_carry")

                    fieldLabel("Destination access")
                    Picker("Destination access", selection: $model.destinationAccessAnswer) {
                        ForEach(accessOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("movers.refinement.destination_access")

                    Toggle("Long carry at destination", isOn: $model.destinationLongCarry)
                        .accessibilityIdentifier("movers.refinement.destination_long_carry")

                    fieldLabel("Packing status")
                    Picker("Packing status", selection: $model.packedStatus) {
                        Text("Packed before arrival").tag(PackedStatus.packed)
                        Text("Some boxes unpacked").tag(PackedStatus.unpacked)
                        Text("Not sure yet").tag(PackedStatus.unknown)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("movers.refinement.packed_status")

                    fieldLabel("Protection")
                    Picker("Protection", selection: $model.coveragePreference) {
                        Text("Standard valuation").tag("standard")
                        Text("Full-value protection").tag("full")
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("movers.refinement.coverage")

                    fieldLabel("Requested arrival window")
                    TextField("Example: 8–10 AM", text: $model.requestedArrivalWindow)
                        .textInputAutocapitalization(.sentences)
                        .padding(PeezyTheme.Layout.cardPaddingSmall)
                        .background(Color.white.opacity(0.65), in: .rect(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall))
                        .accessibilityIdentifier("movers.refinement.arrival_window")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, PeezyTheme.Layout.verticalSpacing)
            }
            .scrollIndicators(.hidden)

            PeezyAssessmentButton("Compare prices", disabled: !model.canCompare, action: onContinue)
                .accessibilityIdentifier("movers.refinement.continue")
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .accessibilityIdentifier("movers.refinement")
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .bold()
            .foregroundStyle(.secondary)
    }
}
