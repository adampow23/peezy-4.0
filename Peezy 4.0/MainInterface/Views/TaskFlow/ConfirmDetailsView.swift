import SwiftUI

// MARK: - ConfirmField

struct ConfirmField: Identifiable {
    let id = UUID()
    let label: String
    let fieldType: FieldType

    enum FieldType {
        case currentAddress
        case newAddress
        case moveDate
        case userInput(placeholder: String)
    }
}

// MARK: - Field Mapping

extension ConfirmField {
    static func fields(for taskId: String?) -> [ConfirmField] {
        switch taskId {

        // NEW ADDRESS + MOVE DATE
        case "ARRANGE_PARKING_NEW", "RESERVE_ELEVATORS_NEW", "SETUP_UTILITIES", "SETUP_DAYCARE":
            return [
                ConfirmField(label: "New address", fieldType: .newAddress),
                ConfirmField(label: "Move date", fieldType: .moveDate)
            ]

        // OLD ADDRESS + MOVE DATE
        case "ARRANGE_PARKING_OLD", "RESERVE_ELEVATORS_OLD", "CANCEL_UTILITIES":
            return [
                ConfirmField(label: "Current address", fieldType: .currentAddress),
                ConfirmField(label: "Move date", fieldType: .moveDate)
            ]

        // NEW ADDRESS ONLY
        case "NEW_DRIVERS_LICENSE", "REGISTER_VEHICLE":
            return [
                ConfirmField(label: "New address", fieldType: .newAddress)
            ]

        // BOTH ADDRESSES + MOVE DATE
        case "TRANSFER_UTILITIES", "TRANSFER_DAYCARE", "UPDATE_DRIVERS_LICENSE":
            return [
                ConfirmField(label: "Current address", fieldType: .currentAddress),
                ConfirmField(label: "New address", fieldType: .newAddress),
                ConfirmField(label: "Move date", fieldType: .moveDate)
            ]

        // OLD ADDRESS + INSURANCE + MOVE DATE
        case "CANCEL_CONDO_INSURANCE", "CANCEL_HOMEOWNERS_INSURANCE", "CANCEL_RENTERS_INSURANCE":
            return [
                ConfirmField(label: "Current address", fieldType: .currentAddress),
                ConfirmField(label: "Insurance company", fieldType: .userInput(placeholder: "Insurance company name")),
                ConfirmField(label: "Move date", fieldType: .moveDate)
            ]

        // NEW ADDRESS + INSURANCE + MOVE DATE
        case "SETUP_CONDO_INSURANCE", "SETUP_HOMEOWNERS_INSURANCE", "SETUP_RENTERS_INSURANCE":
            return [
                ConfirmField(label: "New address", fieldType: .newAddress),
                ConfirmField(label: "Insurance company", fieldType: .userInput(placeholder: "Insurance company name")),
                ConfirmField(label: "Move date", fieldType: .moveDate)
            ]

        // BOTH ADDRESSES + INSURANCE + MOVE DATE
        case "TRANSFER_CONDO_INSURANCE", "TRANSFER_HOMEOWNERS_INSURANCE", "TRANSFER_RENTERS_INSURANCE", "UPDATE_AUTO_INSURANCE":
            return [
                ConfirmField(label: "Current address", fieldType: .currentAddress),
                ConfirmField(label: "New address", fieldType: .newAddress),
                ConfirmField(label: "Insurance company", fieldType: .userInput(placeholder: "Insurance company name")),
                ConfirmField(label: "Move date", fieldType: .moveDate)
            ]

        // BOTH ADDRESSES + PROVIDER NAME
        case "TRANSFER_PHARMACY_RECORDS":
            return [
                ConfirmField(label: "Current address", fieldType: .currentAddress),
                ConfirmField(label: "New address", fieldType: .newAddress),
                ConfirmField(label: "Pharmacy name", fieldType: .userInput(placeholder: "Pharmacy name"))
            ]

        case "TRANSFER_SPECIALISTS_RECORDS":
            return [
                ConfirmField(label: "Current address", fieldType: .currentAddress),
                ConfirmField(label: "New address", fieldType: .newAddress),
                ConfirmField(label: "Specialist name", fieldType: .userInput(placeholder: "Specialist name"))
            ]

        // PROVIDER NAME ONLY
        case "MANAGE_BANK":
            return [ConfirmField(label: "Bank or credit union", fieldType: .userInput(placeholder: "Bank or credit union name"))]
        case "MANAGE_DENTIST":
            return [ConfirmField(label: "Dentist office", fieldType: .userInput(placeholder: "Dentist office name"))]
        case "MANAGE_DOCTOR":
            return [ConfirmField(label: "Doctor office", fieldType: .userInput(placeholder: "Doctor office name"))]
        case "MANAGE_GOLF":
            return [ConfirmField(label: "Golf course or club", fieldType: .userInput(placeholder: "Golf course or club name"))]
        case "MANAGE_GYM":
            return [ConfirmField(label: "Gym", fieldType: .userInput(placeholder: "Gym name"))]
        case "MANAGE_MASSAGE":
            return [ConfirmField(label: "Massage or spa", fieldType: .userInput(placeholder: "Massage or spa name"))]
        case "MANAGE_SPIN":
            return [ConfirmField(label: "Spin or cycling studio", fieldType: .userInput(placeholder: "Spin or cycling studio name"))]
        case "MANAGE_VET":
            return [ConfirmField(label: "Vet office", fieldType: .userInput(placeholder: "Vet office name"))]
        case "MANAGE_YOGA":
            return [ConfirmField(label: "Yoga studio", fieldType: .userInput(placeholder: "Yoga studio name"))]
        case "UPDATE_INVESTMENT":
            return [ConfirmField(label: "Investment firm", fieldType: .userInput(placeholder: "Investment firm name"))]
        case "UPDATE_STUDENT_LOANS":
            return [ConfirmField(label: "Student loan provider", fieldType: .userInput(placeholder: "Student loan provider name"))]

        // SKIP — no confirmation needed
        case "RENT_TRUCK":
            return []

        // DEFAULT
        default:
            return [
                ConfirmField(label: "New address", fieldType: .newAddress),
                ConfirmField(label: "Move date", fieldType: .moveDate)
            ]
        }
    }
}

// MARK: - ConfirmDetailsView

struct ConfirmDetailsView: View {
    let task: PeezyCard
    let userState: UserState?
    let onConfirm: ([String: String]) -> Void
    let onBack: () -> Void

    private let fields: [ConfirmField]

    @State private var fieldValues: [UUID: String]
    @State private var editingFieldId: UUID?

    init(
        task: PeezyCard,
        userState: UserState?,
        onConfirm: @escaping ([String: String]) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.task = task
        self.userState = userState
        self.onConfirm = onConfirm
        self.onBack = onBack

        let computedFields = ConfirmField.fields(for: task.taskId)
        self.fields = computedFields

        let currentAddressValue: String = {
            let parts = [userState?.originCity, userState?.originState].compactMap { $0 }
            return parts.isEmpty ? "Not provided" : parts.joined(separator: ", ")
        }()

        let newAddressValue: String = {
            let parts = [userState?.destinationCity, userState?.destinationState].compactMap { $0 }
            return parts.isEmpty ? "Not provided" : parts.joined(separator: ", ")
        }()

        let moveDateValue: String = {
            guard let moveDate = userState?.moveDate else { return "Not set" }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: moveDate)
        }()

        var initialValues: [UUID: String] = [:]
        for field in computedFields {
            switch field.fieldType {
            case .currentAddress:
                initialValues[field.id] = currentAddressValue
            case .newAddress:
                initialValues[field.id] = newAddressValue
            case .moveDate:
                initialValues[field.id] = moveDateValue
            case .userInput:
                initialValues[field.id] = ""
            }
        }
        _fieldValues = State(initialValue: initialValues)
    }

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            glassCard {
                VStack(alignment: .leading, spacing: 0) {
                    
                    // MARK: - Fixed Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Just to confirm...")
                            // UX Fix: Scaled down from 44 to 34 to fit dynamically populated lists
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)

                        Text("For: \(task.title)")
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
                    .padding(.top, 24)

                    // MARK: - Scrollable Fields
                    ScrollView {
                        VStack(spacing: 20) { // UX Fix: Better breathing room between fields
                            ForEach(fields) { field in
                                fieldRow(field)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)
                    }
                    .scrollIndicators(.hidden)

                    // MARK: - Fixed Bottom Buttons
                    VStack(spacing: 12) {
                        PeezyAssessmentButton("Looks Good — Go Ahead") {
                            let result = fields.reduce(into: [String: String]()) { dict, field in
                                dict[field.label] = fieldValues[field.id, default: ""]
                            }
                            onConfirm(result)
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
            }
        }
    }

    // MARK: - Field Row Components
    
    @ViewBuilder
    private func fieldRow(_ field: ConfirmField) -> some View {
        let isEditing = editingFieldId == field.id

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(field.label)
                    .font(.system(size: 12, weight: .bold)) // UX Fix: Bold for better label hierarchy
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .textCase(.uppercase)
                
                Spacer()
                
                if case .userInput = field.fieldType {
                    // No edit toggle for free-entry fields (they are always editable)
                } else {
                    Button(isEditing ? "Done" : "Edit") {
                        PeezyHaptics.light()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            editingFieldId = isEditing ? nil : field.id
                        }
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isEditing ? PeezyTheme.Colors.accentBlue : .secondary)
                    .frame(minHeight: 44)
                    .padding(.leading, 8)
                }
            }

            if case .userInput(let placeholder) = field.fieldType {
                inputField(placeholder: placeholder, id: field.id)
            } else if isEditing {
                inputField(placeholder: field.label, id: field.id)
            } else {
                Text(fieldValues[field.id, default: ""])
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true) // UX Fix: Allows multi-line addresses
            }
        }
    }

    @ViewBuilder
    private func inputField(placeholder: String, id: UUID) -> some View {
        // UX Fix: axis: .vertical allows the text field to grow if they type a long address
        TextField(placeholder, text: valueBinding(for: id), axis: .vertical)
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

    private func valueBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { self.fieldValues[id, default: ""] },
            set: { self.fieldValues[id] = $0 }
        )
    }

    // MARK: - Glass Card Container
    
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .foregroundStyle(.regularMaterial)
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.white.opacity(0.15))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    .padding(1)
            }
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 15)

            content()
        }
        .frame(width: 340)
        .frame(maxHeight: 500)
    }
}

// MARK: - Previews

#Preview("Research - Parking") {
    ConfirmDetailsView(
        task: .previewResearch,
        userState: .preview,
        onConfirm: { _ in },
        onBack: {}
    )
}

#Preview("Transfer - Bank") {
    ConfirmDetailsView(
        task: .previewTransfer,
        userState: .preview,
        onConfirm: { _ in },
        onBack: {}
    )
}

#Preview("Transfer - Gym") {
    ConfirmDetailsView(
        task: .previewTransferGym,
        userState: .preview,
        onConfirm: { _ in },
        onBack: {}
    )
}
