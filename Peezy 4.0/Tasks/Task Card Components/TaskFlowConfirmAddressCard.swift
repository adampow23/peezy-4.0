//
//  TaskFlowConfirmAddressCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI
import MapKit

// MARK: - Task Flow Confirm Address Card
// Displays a user's address and asks them to confirm or update it.
// Read state: display container + confirm/change buttons (vertical stack).
// Edit state: address search with autocomplete + cancel/save buttons (horizontal stack).
// Keyboard-aware — uses the same padding hack as BusinessSearchCard.
//
// Usage:
//   TaskFlowConfirmAddressCard(
//       taskTitle: "Reserve unloading parking",
//       question: "Is this where you're headed?",
//       currentAddress: "4201 Main St, Unit 12\nDenver, CO 80205",
//       onConfirm: { address in advance() },
//       onBack: { goBack() }
//   )

struct TaskFlowConfirmAddressCard: View {
    let taskTitle: String
    let question: String
    let currentAddress: String
    var displayIcon: String = "mappin.and.ellipse"
    var confirmLabel: String = "That's right"
    var changeLabel: String = "Update this"
    var showBack: Bool = false
    let onConfirm: (String) -> Void
    var onBack: (() -> Void)? = nil

    // MARK: - State

    @State private var isEditing = false
    @State private var confirmedAddress: String = ""
    @State private var searchText = ""
    @State private var searchManager = AddressSearchManager()
    @FocusState private var isFieldFocused: Bool

    private var showResults: Bool {
        isFieldFocused && !searchManager.suggestions.isEmpty
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: taskTitle, showBack: showBack, onBack: onBack)

            if !isEditing {
                readState
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                editState
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.15), value: isEditing)
        .onAppear {
            confirmedAddress = currentAddress
        }
    }

    // MARK: - Read State

    private var readState: some View {
        VStack(spacing: 0) {
            Spacer()

            // Question text
            VStack(alignment: .leading, spacing: 15) {
                Text(question)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Display container
            HStack(spacing: 14) {
                Image(systemName: displayIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))

                Text(confirmedAddress)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .padding(.horizontal, 24)

            Spacer().frame(height: 24)

            // Buttons — vertical (flow navigation pattern)
            VStack(spacing: 12) {
                PeezyAssessmentButton(confirmLabel) {
                    onConfirm(confirmedAddress)
                }

                Button(action: {
                    PeezyHaptics.light()
                    searchText = confirmedAddress
                    searchManager.queryFragment = ""
                    withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                        isEditing = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isFieldFocused = true
                    }
                }) {
                    Text(changeLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Edit State

    private var editState: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 24)

            // Simplified header for edit mode
            Text("Update address")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

            // Compressible middle — results or spacer
            if showResults {
                addressResultsDropdown
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Spacer()
            }

            // Search field + buttons
            VStack(spacing: 16) {
                addressSearchField

                // Buttons — horizontal (edit/modal pattern)
                HStack(spacing: 12) {
                    // Cancel
                    Button(action: {
                        PeezyHaptics.light()
                        isFieldFocused = false
                        withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                            isEditing = false
                        }
                    }) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)

                    // Save
                    Button(action: {
                        PeezyHaptics.light()
                        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            confirmedAddress = trimmed
                        }
                        isFieldFocused = false
                        withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                            isEditing = false
                        }
                    }) {
                        Text("Save")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(PeezyTheme.Colors.deepInk)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1.0)
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, isFieldFocused ? 210 : 24)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFieldFocused = false }
        .animation(.easeOut(duration: 0.25), value: isFieldFocused)
        .animation(.easeOut(duration: 0.25), value: showResults)
    }

    // MARK: - Address Search Field

    private var addressSearchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))

            TextField("Search address...", text: $searchText)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .focused($isFieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .textContentType(.fullStreetAddress)
                .submitLabel(.done)
                .onSubmit { isFieldFocused = false }
                .onChange(of: searchText) { _, newValue in
                    searchManager.queryFragment = newValue
                }

            if !searchText.isEmpty {
                Button(action: {
                    PeezyHaptics.light()
                    searchText = ""
                    searchManager.queryFragment = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, searchText.isEmpty ? 16 : 0)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isFieldFocused
                        ? PeezyTheme.Colors.deepInk.opacity(0.2)
                        : Color.primary.opacity(0.07),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 24)
    }

    // MARK: - Address Results Dropdown

    private var addressResultsDropdown: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(searchManager.suggestions.enumerated()), id: \.offset) { index, suggestion in
                    Button(action: {
                        PeezyHaptics.light()
                        Task {
                            await searchManager.selectSuggestion(suggestion)
                            searchText = searchManager.selectedAddress
                            isFieldFocused = false
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                                    .lineLimit(1)

                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.system(size: 13))
                                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < searchManager.suggestions.count - 1 {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Confirm Address — Read") {
    TaskFlowConfirmAddressCard(
        taskTitle: "Reserve unloading parking",
        question: "Is this where you're headed?",
        currentAddress: "4201 Main St, Unit 12\nDenver, CO 80205",
        showBack: true,
        onConfirm: { address in print("✅ Confirmed: \(address)") },
        onBack: { print("⏪ Back") }
    )
    .peezyCardChrome()
}

#Preview("Confirm Address — From") {
    TaskFlowConfirmAddressCard(
        taskTitle: "Reserve loading parking",
        question: "Is this the address you're moving from?",
        currentAddress: "1842 Oak Park Ave, Apt 3B\nKansas City, MO 64108",
        displayIcon: "mappin",
        showBack: true,
        onConfirm: { address in print("✅ Confirmed: \(address)") },
        onBack: { print("⏪ Back") }
    )
    .peezyCardChrome()
}
#endif
