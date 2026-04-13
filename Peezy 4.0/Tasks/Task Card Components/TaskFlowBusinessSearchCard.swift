//
//  TaskFlowBusinessSearchCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI
import MapKit

// MARK: - Business Search Completer
// Modeled after AddressSearchManager.
// Uses .pointOfInterest for business results instead of .address.
// Optional searchHint (e.g. "dentist", "gym") appended to queries for industry filtering.

@Observable
@MainActor
final class BusinessSearchCompleter: NSObject {

    // MARK: - State

    var results: [MKLocalSearchCompletion] = []
    var isSearching = false
    var searchHint = ""

    // MARK: - Private

    private let completer: MKLocalSearchCompleter

    // MARK: - Init

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = .pointOfInterest
    }

    // MARK: - Search

    func update(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            completer.cancel()
            return
        }
        isSearching = true
        completer.queryFragment = searchHint.isEmpty ? trimmed : "\(trimmed) \(searchHint)"
    }

    func clear() {
        results = []
        completer.cancel()
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension BusinessSearchCompleter: MKLocalSearchCompleterDelegate {

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let capped = Array(completer.results.prefix(5))
        Task { @MainActor in
            self.results = capped
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.results = []
            self.isSearching = false
        }
    }
}

// MARK: - Task Flow Business Search Card
// Question card with a live-search text field and autocomplete dropdown.
// User types → results appear → tap a result → fills the field → tap Continue.
// searchHint filters results by industry (e.g. "dentist", "gym", "veterinarian").
//
// Keyboard handling: The card frame does NOT move. The inner Spacers compress
// to accommodate the keyboard. TextField auto-focuses on appear.

struct TaskFlowBusinessSearchCard: View {
    let taskTitle: String
    let question: String
    var placeholder: String = "Search..."
    var searchHint: String = ""
    var selectedBusiness: String? = nil
    var confirmLabel: String = "Continue"
    var showBack: Bool = false
    let onConfirm: (String) -> Void
    var onBack: (() -> Void)? = nil

    // MARK: - Internal State

    @State private var completer = BusinessSearchCompleter()
    @State private var searchText = ""
    @State private var hasSelection = false
    @FocusState private var isFieldFocused: Bool

    private var showResults: Bool {
        isFieldFocused && !completer.results.isEmpty && !hasSelection
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // 1. Pinned top group — header + question
            VStack(alignment: .leading, spacing: 0) {
                TaskFlowHeader(taskTitle: taskTitle, showBack: showBack, onBack: onBack)

                Spacer()
                    .frame(height: 24)

                Text(question)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }

            // 2. Compressible middle — results or spacer
            if showResults {
                resultsDropdown
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Spacer()
            }

            // 3. Pinned bottom group — search field + button
            VStack(spacing: 24) {
                searchField

                PeezyAssessmentButton(
                    confirmLabel,
                    disabled: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    onConfirm(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, showResults ? 8 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFieldFocused = false }
        // UX Keyboard Fix: Raises bottom content inside the card when keyboard opens.
        // The card frame stays locked via .ignoresSafeArea(.keyboard) on TaskFlowStack.
        .padding(.bottom, isFieldFocused ? 210 : 24)
        .animation(.easeOut(duration: 0.25), value: showResults)
        .animation(.easeOut(duration: 0.25), value: isFieldFocused)
        .onAppear {
            completer.searchHint = searchHint
            if let selected = selectedBusiness, !selected.isEmpty {
                searchText = selected
                hasSelection = true
            }
            // UX Interaction Fix: Auto-focus after card transition completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isFieldFocused = true
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))

            TextField(placeholder, text: $searchText)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .focused($isFieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit { isFieldFocused = false }
                .onChange(of: searchText) { _, newValue in
                    hasSelection = false
                    completer.update(newValue)
                }

            if !searchText.isEmpty {
                Button(action: {
                    PeezyHaptics.light()
                    searchText = ""
                    hasSelection = false
                    completer.clear()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                        // UX Hitbox Fix: 44pt invisible tap target
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

    // MARK: - Results Dropdown

    private var resultsDropdown: some View {
        // UX Layout Fix: ScrollView absorbs compressed space when keyboard is open
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(completer.results.enumerated()), id: \.offset) { index, result in
                    Button(action: {
                        PeezyHaptics.light()
                        searchText = result.title
                        hasSelection = true
                        isFieldFocused = false
                        completer.clear()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                                    .lineLimit(1)

                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.system(size: 13))
                                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        // UX Hitbox Fix: Full-width 44pt tap target
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(result.title), \(result.subtitle)")

                    // Divider between results — inset to align with text
                    if index < completer.results.count - 1 {
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
#Preview("Business Search — Dentist") {
    TaskFlowBusinessSearchCard(
        taskTitle: "Handle my dentist",
        question: "Who's your dentist?",
        placeholder: "Search for a dental office...",
        searchHint: "dentist",
        showBack: true,
        onConfirm: { name in print("✅ Selected: \(name)") },
        onBack: { print("⏪ Back") }
    )
    .peezyCardChrome()
}

#Preview("Business Search — Gym") {
    TaskFlowBusinessSearchCard(
        taskTitle: "Handle my gym membership",
        question: "Which gym do you go to?",
        placeholder: "Search for a gym...",
        searchHint: "gym",
        showBack: true,
        onConfirm: { name in print("✅ Selected: \(name)") },
        onBack: { print("⏪ Back") }
    )
    .peezyCardChrome()
}

#Preview("Business Search — Pre-populated") {
    TaskFlowBusinessSearchCard(
        taskTitle: "Transfer my pharmacy",
        question: "Which pharmacy do you use?",
        placeholder: "Search for a pharmacy...",
        searchHint: "pharmacy",
        selectedBusiness: "CVS Pharmacy",
        showBack: true,
        onConfirm: { name in print("✅ Selected: \(name)") },
        onBack: { print("⏪ Back") }
    )
    .peezyCardChrome()
}
#endif
