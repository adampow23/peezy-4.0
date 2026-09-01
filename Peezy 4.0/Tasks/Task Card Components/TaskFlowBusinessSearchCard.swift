//
//  TaskFlowBusinessSearchCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI
import MapKit

enum BusinessSearchIdentity {
    nonisolated static func makeManual(
        label: String,
        existing: FlowAnswerIdentity?,
        uuid: () -> String = { UUID().uuidString }
    ) -> FlowAnswerIdentity {
        FlowAnswerIdentity(
            id: existing?.id ?? uuid(),
            label: label,
            source: existing?.source ?? .manual
        )
    }

    @MainActor
    static func resolveMapKitID(for completion: MKLocalSearchCompletion) async -> String? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        if #available(iOS 18.0, *) { return item.identifier?.rawValue }
        return nil
    }
}

@MainActor
@Observable
final class BusinessSearchSelectionController {
    private(set) var searchText: String
    private(set) var hasSelection: Bool
    private(set) var selectedIdentity: FlowAnswerIdentity?
    private(set) var isResolving = false

    private let uuid: () -> String
    private var resolutionGeneration = 0
    private var resolutionTask: Task<Void, Never>?

    init(
        selected: FlowAnswerIdentity? = nil,
        uuid: @escaping () -> String = { UUID().uuidString }
    ) {
        self.selectedIdentity = selected
        self.searchText = selected?.label ?? ""
        self.hasSelection = selected != nil
        self.uuid = uuid
    }

    var canConfirm: Bool {
        !isResolving && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var allowsFieldInteraction: Bool { !isResolving }

    func userEditedText(_ text: String) {
        cancelPendingResolution()
        searchText = text
        hasSelection = false
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            selectedIdentity = nil
            return
        }
        // A manual identity represents the typed provider and survives a true
        // label edit. Editing a MapKit selection changes its canonical entity,
        // so it must become a new manual identity on confirmation.
        if let selectedIdentity,
           selectedIdentity.source == .mapkit,
           trimmed != selectedIdentity.label {
            self.selectedIdentity = nil
        }
    }

    func clear() {
        cancelPendingResolution()
        searchText = ""
        hasSelection = false
        selectedIdentity = nil
    }

    func beginAutocompleteSelection(
        label: String,
        resolveID: @escaping @MainActor () async -> String?,
        onResolved: @escaping @MainActor () -> Void = {}
    ) {
        resolutionTask?.cancel()
        resolutionGeneration += 1
        let generation = resolutionGeneration
        selectedIdentity = nil
        searchText = label
        hasSelection = false
        isResolving = true

        resolutionTask = Task { @MainActor [weak self] in
            let resolvedID = await resolveID()
            guard let self,
                  generation == self.resolutionGeneration,
                  !Task.isCancelled else { return }
            self.selectedIdentity = FlowAnswerIdentity(
                id: resolvedID ?? self.uuid(),
                label: label,
                source: .mapkit
            )
            self.hasSelection = true
            self.isResolving = false
            self.resolutionTask = nil
            onResolved()
        }
    }

    func confirm() -> FlowAnswerIdentity? {
        guard canConfirm else { return nil }
        let label = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selectedIdentity,
           selectedIdentity.source == .mapkit,
           selectedIdentity.label == label {
            return selectedIdentity
        }
        let reusableManual = selectedIdentity?.source == .manual ? selectedIdentity : nil
        let identity = BusinessSearchIdentity.makeManual(
            label: label,
            existing: reusableManual,
            uuid: uuid
        )
        selectedIdentity = identity
        hasSelection = true
        return identity
    }

    func cancelPendingResolution() {
        resolutionGeneration += 1
        resolutionTask?.cancel()
        resolutionTask = nil
        isResolving = false
    }

    func waitUntilResolutionFinishes() async {
        while isResolving { await Task.yield() }
    }
}

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
    var selectedBusiness: FlowAnswerIdentity? = nil
    var confirmLabel: String = "Continue"
    var showBack: Bool = false
    let onConfirm: (FlowAnswerIdentity) -> Void
    var onBack: (() -> Void)? = nil
    var resolveMapKitID: @MainActor (MKLocalSearchCompletion) async -> String? = BusinessSearchIdentity.resolveMapKitID
    var uuid: () -> String = { UUID().uuidString }

    init(
        taskTitle: String,
        question: String,
        placeholder: String = "Search...",
        searchHint: String = "",
        selectedBusiness: FlowAnswerIdentity? = nil,
        confirmLabel: String = "Continue",
        showBack: Bool = false,
        onConfirm: @escaping (FlowAnswerIdentity) -> Void,
        onBack: (() -> Void)? = nil,
        resolveMapKitID: @escaping @MainActor (MKLocalSearchCompletion) async -> String? = BusinessSearchIdentity.resolveMapKitID,
        uuid: @escaping () -> String = { UUID().uuidString }
    ) {
        self.taskTitle = taskTitle
        self.question = question
        self.placeholder = placeholder
        self.searchHint = searchHint
        self.selectedBusiness = selectedBusiness
        self.confirmLabel = confirmLabel
        self.showBack = showBack
        self.onConfirm = onConfirm
        self.onBack = onBack
        self.resolveMapKitID = resolveMapKitID
        self.uuid = uuid
        _selectionController = State(
            initialValue: BusinessSearchSelectionController(
                selected: selectedBusiness,
                uuid: uuid
            )
        )
    }

    /// Source-compatible bridge for bespoke flows that still consume labels.
    init(
        taskTitle: String,
        question: String,
        placeholder: String = "Search...",
        searchHint: String = "",
        selectedBusiness: String? = nil,
        confirmLabel: String = "Continue",
        showBack: Bool = false,
        onConfirm: @escaping (String) -> Void,
        onBack: (() -> Void)? = nil
    ) {
        self.init(
            taskTitle: taskTitle,
            question: question,
            placeholder: placeholder,
            searchHint: searchHint,
            selectedBusiness: selectedBusiness.map {
                FlowAnswerIdentity(id: UUID().uuidString, label: $0, source: .manual)
            },
            confirmLabel: confirmLabel,
            showBack: showBack,
            onConfirm: { onConfirm($0.label) },
            onBack: onBack
        )
    }

    // MARK: - Internal State

    @State private var completer = BusinessSearchCompleter()
    @State private var selectionController: BusinessSearchSelectionController
    @FocusState private var isFieldFocused: Bool

    private var showResults: Bool {
        isFieldFocused && !completer.results.isEmpty
            && !selectionController.hasSelection && !selectionController.isResolving
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

            // 2. Flexible middle — results must claim the available card height
            // while the keyboard padding raises the pinned search controls.
            if showResults {
                resultsDropdown
                    .padding(.top, 16)
                    .frame(maxHeight: .infinity)
                    .layoutPriority(1)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Spacer()
            }

            // 3. Pinned bottom group — search field + button
            VStack(spacing: 24) {
                searchField

                PeezyAssessmentButton(
                    confirmLabel,
                    disabled: !selectionController.canConfirm
                ) {
                    guard let identity = selectionController.confirm() else { return }
                    onConfirm(identity)
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, showResults ? 8 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFieldFocused = false }
        // Raise the pinned controls for the keyboard only while no dropdown is
        // open. Results need that middle-card space to remain visible.
        .padding(.bottom, isFieldFocused ? (showResults ? 48 : 210) : 24)
        .animation(.easeOut(duration: 0.25), value: showResults)
        .animation(.easeOut(duration: 0.25), value: isFieldFocused)
        .onAppear {
            completer.searchHint = searchHint
            // UX Interaction Fix: Auto-focus after card transition completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if selectionController.allowsFieldInteraction {
                    isFieldFocused = true
                }
            }
        }
        .onDisappear {
            selectionController.cancelPendingResolution()
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))

            TextField(
                placeholder,
                text: Binding(
                    get: { selectionController.searchText },
                    set: { newValue in
                        selectionController.userEditedText(newValue)
                        completer.update(newValue)
                    }
                )
            )
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .focused($isFieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit { isFieldFocused = false }
                .disabled(!selectionController.allowsFieldInteraction)

            if selectionController.isResolving {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Resolving business")
            } else if !selectionController.searchText.isEmpty {
                Button(action: {
                    PeezyHaptics.light()
                    selectionController.clear()
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
                .disabled(!selectionController.allowsFieldInteraction)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, selectionController.searchText.isEmpty ? 16 : 0)
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
                        selectionController.beginAutocompleteSelection(
                            label: result.title,
                            resolveID: { await resolveMapKitID(result) },
                            onResolved: {
                                isFieldFocused = false
                                completer.clear()
                            }
                        )
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
                    .disabled(!selectionController.allowsFieldInteraction)
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
        .accessibilityIdentifier("flow.businessSearch.results")
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
        onConfirm: { identity in print("✅ Selected: \(identity.label)") },
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
        onConfirm: { identity in print("✅ Selected: \(identity.label)") },
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
        selectedBusiness: FlowAnswerIdentity(id: "preview", label: "CVS Pharmacy", source: .manual),
        showBack: true,
        onConfirm: { identity in print("✅ Selected: \(identity.label)") },
        onBack: { print("⏪ Back") }
    )
    .peezyCardChrome()
}
#endif
