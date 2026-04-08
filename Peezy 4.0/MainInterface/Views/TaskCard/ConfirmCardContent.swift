import SwiftUI

// MARK: - Confirm Card Content

struct ConfirmCardContent: View {
    let data: TaskCardConfirmData
    let userState: UserState?
    let showVerifiedBadge: Bool
    let onConfirm: ([String: String]) -> Void
    let onBack: () -> Void

    @State private var fieldValues: [String: String] = [:]
    @State private var editingFieldLabel: String?
    @State private var hasInitialized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            if showVerifiedBadge {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(PeezyTheme.Colors.successGreen)
                    Text("PEEZY VERIFIED")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(PeezyTheme.Colors.successGreen)
                    Spacer()
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: data.headerIcon)
                        .font(.system(size: 11))
                    Text(data.category.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.5)
                    Spacer()
                }
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                .padding(.top, 24)
                .padding(.horizontal, 24)
            }

            // Title
            VStack(alignment: .leading, spacing: 6) {
                Text("Just to confirm...")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)

                Text("For: \(data.taskTitle)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Rectangle()
                    .fill(Color.black.opacity(0.15))
                    .frame(width: 50, height: 2)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            // Scrollable fields
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(data.fields) { field in
                        confirmFieldRow(field)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)

            // Buttons
            VStack(spacing: 12) {
                PeezyAssessmentButton("Looks Good") {
                    onConfirm(fieldValues)
                }

                Button("Go Back") {
                    onBack()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            initializeFieldValues()
        }
    }

    private func initializeFieldValues() {
        for field in data.fields {
            switch field.fieldType {
            case .currentAddress:
                let parts = [userState?.originCity, userState?.originState].compactMap { $0 }
                fieldValues[field.label] = parts.isEmpty ? "Not provided" : parts.joined(separator: ", ")
            case .newAddress:
                let parts = [userState?.destinationCity, userState?.destinationState].compactMap { $0 }
                fieldValues[field.label] = parts.isEmpty ? "Not provided" : parts.joined(separator: ", ")
            case .moveDate:
                if let moveDate = userState?.moveDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    fieldValues[field.label] = formatter.string(from: moveDate)
                } else {
                    fieldValues[field.label] = "Not set"
                }
            case .userInput:
                fieldValues[field.label] = ""
            }
        }
    }

    @ViewBuilder
    private func confirmFieldRow(_ field: ConfirmField) -> some View {
        let isEditing = editingFieldLabel == field.label

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(field.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .textCase(.uppercase)

                Spacer()

                if case .userInput = field.fieldType {
                    // Always editable
                } else {
                    Button(isEditing ? "Done" : "Edit") {
                        PeezyHaptics.light()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            editingFieldLabel = isEditing ? nil : field.label
                        }
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isEditing ? PeezyTheme.Colors.accentBlue : .secondary)
                    .frame(minHeight: 44)
                    .padding(.leading, 8)
                }
            }

            if case .userInput(let placeholder) = field.fieldType {
                confirmInputField(placeholder: placeholder, key: field.label)
            } else if isEditing {
                confirmInputField(placeholder: field.label, key: field.label)
            } else {
                Text(fieldValues[field.label, default: ""])
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func confirmInputField(placeholder: String, key: String) -> some View {
        TextField(placeholder, text: Binding(
            get: { fieldValues[key, default: ""] },
            set: { fieldValues[key] = $0 }
        ), axis: .vertical)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(PeezyTheme.Colors.deepInk)
            .frame(minHeight: 44)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.04))
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                }
            }
    }
}
