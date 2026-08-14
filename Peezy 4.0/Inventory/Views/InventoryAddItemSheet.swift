//
//  InventoryAddItemSheet.swift
//  Peezy 4.0
//

import SwiftUI

struct InventoryAddItemSheet: View {
    let roomName: String
    let onAdd: (InventoryItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var itemName = ""
    @State private var itemTier = "furniture"
    @State private var itemCategory = "furniture"
    @State private var itemSize = "medium"
    @State private var questionIndex = 0

    private let categories = ["furniture", "electronics", "boxes", "appliance", "decor", "other"]
    private let sizes = ["small", "medium", "large", "oversized"]

    private enum Question: Int, CaseIterable {
        case name
        case tier
        case category
        case size

        var title: String {
            switch self {
            case .name: "What item are you adding?"
            case .tier: "What kind of item is it?"
            case .category: "Which category fits best?"
            case .size: "What size is it?"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Question \(questionIndex + 1) of \(Question.allCases.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("inventory.add_item.progress")

                Text(currentQuestion.title)
                    .font(.title.bold())
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inventory.add_item.question.\(currentQuestion.rawValue)")

                questionControl

                Spacer()

                PeezyAssessmentButton(
                    questionIndex == Question.allCases.count - 1 ? "Add" : "Continue",
                    disabled: currentQuestion == .name && itemName.trimmingCharacters(in: .whitespaces).isEmpty,
                    action: advance
                )
                .accessibilityIdentifier("inventory.add_item.continue")
            }
            .padding(24)
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                        .accessibilityIdentifier("inventory.add_item.cancel")
                }
                if questionIndex > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { questionIndex -= 1 }
                            .accessibilityIdentifier("inventory.add_item.back")
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var currentQuestion: Question {
        Question.allCases[min(questionIndex, Question.allCases.count - 1)]
    }

    @ViewBuilder
    private var questionControl: some View {
        switch currentQuestion {
        case .name:
            TextField("e.g. Floor Lamp", text: $itemName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("inventory.add_item.name")
        case .tier:
            Picker("Tier", selection: $itemTier) {
                Text("Furniture / Large Item").tag("furniture")
                Text("Packable / Goes in a Box").tag("boxable")
            }
            .pickerStyle(.inline)
            .accessibilityIdentifier("inventory.add_item.tier")
        case .category:
            Picker("Category", selection: $itemCategory) {
                ForEach(categories, id: \.self) { category in
                    Label(category.capitalized, systemImage: icon(for: category))
                        .tag(category)
                }
            }
            .pickerStyle(.inline)
            .accessibilityIdentifier("inventory.add_item.category")
        case .size:
            Picker("Size", selection: $itemSize) {
                ForEach(sizes, id: \.self) { size in
                    Text(size.capitalized).tag(size)
                }
            }
            .pickerStyle(.inline)
            .accessibilityIdentifier("inventory.add_item.size")
        }
    }

    private func advance() {
        if questionIndex < Question.allCases.count - 1 {
            questionIndex += 1
            return
        }

        guard !itemName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onAdd(InventoryItem(
            id: UUID().uuidString,
            name: itemName,
            category: itemCategory,
            tier: itemTier,
            quantity: 1,
            sizeEstimate: itemSize,
            cubicFeet: 0,
            isFragile: false,
            isHighValue: false,
            confidence: 1.0,
            frameIndex: nil,
            boundingBox: nil,
            roomName: roomName,
            shouldMove: true,
            notes: ""
        ))
        dismiss()
    }

    private func icon(for category: String) -> String {
        switch category {
        case "furniture": "sofa.fill"
        case "electronics": "tv.fill"
        case "boxes": "shippingbox.fill"
        case "appliance": "refrigerator.fill"
        case "decor": "lamp.desk.fill"
        default: "questionmark.circle"
        }
    }
}
