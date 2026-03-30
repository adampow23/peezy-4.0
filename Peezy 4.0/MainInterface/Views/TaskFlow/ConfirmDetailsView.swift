import SwiftUI

struct ConfirmDetailsView: View {
    let task: PeezyCard
    let userState: UserState?
    let onConfirm: ([String: String]) -> Void
    let onBack: () -> Void

    @State private var currentAddress: String
    @State private var newAddress: String
    @State private var moveDateText: String

    @State private var editingField: EditableField? = nil

    enum EditableField {
        case currentAddress, newAddress, moveDate
    }

    init(task: PeezyCard, userState: UserState?, onConfirm: @escaping ([String: String]) -> Void, onBack: @escaping () -> Void) {
        self.task = task
        self.userState = userState
        self.onConfirm = onConfirm
        self.onBack = onBack

        let currentParts = [userState?.originCity, userState?.originState].compactMap { $0 }
        _currentAddress = State(initialValue: currentParts.isEmpty ? "Not provided" : currentParts.joined(separator: ", "))

        let newParts = [userState?.destinationCity, userState?.destinationState].compactMap { $0 }
        _newAddress = State(initialValue: newParts.isEmpty ? "Not provided" : newParts.joined(separator: ", "))

        if let moveDate = userState?.moveDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            _moveDateText = State(initialValue: formatter.string(from: moveDate))
        } else {
            _moveDateText = State(initialValue: "Not set")
        }
    }

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            ScrollView {
                glassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Just to confirm...")
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .padding(.horizontal, 30)
                            .padding(.top, 30)

                        Text("For: \(task.title)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                            .padding(.horizontal, 30)
                            .padding(.top, 4)

                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .frame(width: 50, height: 2)
                            .padding(.horizontal, 30)
                            .padding(.top, 14)

                        VStack(spacing: 14) {
                            detailRow(
                                label: "Current address",
                                value: $currentAddress,
                                isEditing: editingField == .currentAddress,
                                onEdit: { editingField = editingField == .currentAddress ? nil : .currentAddress }
                            )
                            detailRow(
                                label: "New address",
                                value: $newAddress,
                                isEditing: editingField == .newAddress,
                                onEdit: { editingField = editingField == .newAddress ? nil : .newAddress }
                            )
                            detailRow(
                                label: "Move date",
                                value: $moveDateText,
                                isEditing: editingField == .moveDate,
                                onEdit: { editingField = editingField == .moveDate ? nil : .moveDate }
                            )
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 20)

                        VStack(spacing: 12) {
                            PeezyAssessmentButton("Looks Good — Go Ahead") {
                                onConfirm([
                                    "currentAddress": currentAddress,
                                    "newAddress": newAddress,
                                    "moveDate": moveDateText
                                ])
                            }

                            Button("Go Back") {
                                onBack()
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 24)
                        .padding(.bottom, 30)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 40)
            }
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: Binding<String>, isEditing: Bool, onEdit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.45))
                    .tracking(0.5)
                    .textCase(.uppercase)
                Spacer()
                Button(isEditing ? "Done" : "Edit") {
                    onEdit()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
            }

            if isEditing {
                TextField(label, text: value)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .foregroundStyle(.regularMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                            }
                    }
            } else {
                Text(value.wrappedValue)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
            }
        }
    }

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
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    .padding(1)
            }
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 15)

            content()
        }
        .frame(width: 340)
    }
}

#Preview {
    ConfirmDetailsView(
        task: PeezyCard(
            type: .task,
            title: "Transfer Internet Service",
            subtitle: "Let us notify your provider of your move.",
            taskType: "research"
        ),
        userState: {
            var state = UserState(userId: "preview", name: "Alex")
            state.originCity = "Austin"
            state.originState = "TX"
            state.destinationCity = "Denver"
            state.destinationState = "CO"
            state.moveDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())
            return state
        }(),
        onConfirm: { _ in },
        onBack: {}
    )
}
