import SwiftUI
import MapKit

struct AddressAutocompleteView: View {
    let placeholder: String
    let onAddressSelected: (String) -> Void
    var showUnitField: Bool = false
    var unitNumber: Binding<String>? = nil

    @State private var manager = AddressSearchManager()
    @FocusState private var isFieldFocused: Bool
    @FocusState private var isUnitFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            addressInputSection
            unitFieldSection
            suggestionsSection
        }
        .animation(.easeOut(duration: 0.2), value: manager.suggestions.count)
        .animation(.easeOut(duration: 0.2), value: manager.selectedAddress.isEmpty)
        .onAppear {
            isFieldFocused = true
        }
    }

    // MARK: - Address Input / Selected Display

    @ViewBuilder
    private var addressInputSection: some View {
        if manager.selectedAddress.isEmpty {
            searchField
        } else {
            selectedAddressDisplay
        }
    }

    private var searchField: some View {
        TextField(
            "",
            text: $manager.queryFragment,
            prompt: Text(placeholder).foregroundColor(.white.opacity(0.3))
        )
        .font(.title3)
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .textContentType(.fullStreetAddress)
        .focused($isFieldFocused)
        .submitLabel(.done)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(isFieldFocused ? 0.4 : 0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
    }

    private var selectedAddressDisplay: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(manager.selectedAddress)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                manager.clearSelection()
                isFieldFocused = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(8)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    )
            }
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
        .transition(.opacity.combined(with: .offset(y: 4)))
    }

    // MARK: - Apt / Unit Field

    @ViewBuilder
    private var unitFieldSection: some View {
        if showUnitField, !manager.selectedAddress.isEmpty, let unitBinding = unitNumber {
            UnitNumberField(unitNumber: unitBinding, isUnitFieldFocused: $isUnitFieldFocused)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .transition(.opacity.combined(with: .offset(y: -6)))
        }
    }

    // MARK: - Suggestions

    @ViewBuilder
    private var suggestionsSection: some View {
        if !manager.suggestions.isEmpty && manager.selectedAddress.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(manager.suggestions.enumerated()), id: \.offset) { index, suggestion in
                    Button {
                        isFieldFocused = false
                        Task {
                            await manager.selectSuggestion(suggestion)
                            onAddressSelected(manager.selectedAddress)
                        }
                    } label: {
                        SuggestionRow(suggestion: suggestion)
                    }
                    .buttonStyle(.plain)

                    if index < manager.suggestions.count - 1 {
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.horizontal, 16)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .transition(.opacity.combined(with: .offset(y: -8)))
        }
    }
}

// MARK: - Unit Number Field

private struct UnitNumberField: View {
    @Binding var unitNumber: String
    var isUnitFieldFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            TextField(
                "",
                text: $unitNumber,
                prompt: Text("Apt / Unit #").foregroundColor(.white.opacity(0.3))
            )
            .font(.system(size: 17))
            .foregroundColor(.white)
            .multilineTextAlignment(.leading)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .focused(isUnitFieldFocused)
            .submitLabel(.done)
            .onChange(of: unitNumber) { _, newValue in
                if newValue.hasPrefix("N/A") && newValue.count > 3 {
                    unitNumber = String(newValue.dropFirst(3))
                }
            }

            Button {
                unitNumber = "N/A"
            } label: {
                Text("N/A")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(unitNumber == "N/A" ? .black : .white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(unitNumber == "N/A" ? Color.white : Color.white.opacity(0.12))
                            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    )
            }
            .animation(.easeOut(duration: 0.15), value: unitNumber)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(isUnitFieldFocused.wrappedValue ? 0.4 : 0.15), lineWidth: 1)
                )
        )
    }
}

// MARK: - Suggestion Row

private struct SuggestionRow: View {
    let suggestion: MKLocalSearchCompletion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.4))

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if !suggestion.subtitle.isEmpty {
                    Text(suggestion.subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
