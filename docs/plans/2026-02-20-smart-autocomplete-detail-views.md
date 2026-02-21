# Smart Autocomplete — Financial, Healthcare & Fitness Detail Views

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add search-as-you-type business name suggestions to FinancialDetails, HealthcareDetails, and FitnessDetails — using MKLocalSearch for location-based categories and filtered hardcoded lists for corporate/online services.

**Architecture:** Two new files (`BusinessSearchManager.swift`, `SuggestiveTextField.swift`) provide the reusable infrastructure. The three detail views are modified to replace plain `TextField` with `SuggestiveTextField`. `BusinessSearchManager` is `@Observable`, geocodes `currentAddress` once, caches coordinates, debounces MKLocalSearch 0.3 s. `SuggestiveTextField` accepts a `SuggestionSource` enum — either `.local([String])` or `.mapSearch(category:nearAddress:)` — and renders a suggestion dropdown below the field.

**Tech Stack:** Swift 5.9+, SwiftUI, MapKit (`MKLocalSearch`, `CLGeocoder`), `@Observable` (Observation framework), `async/await`

---

## Critical Context (Read Before Any Task)

- **CLAUDE.md rule:** Do NOT modify `.pbxproj`. After creating new `.swift` files, the user must add them to the Xcode project manually. State this clearly after each new file creation.
- **Build command:** `xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build` — run from `/Users/adampowell/Desktop/Peezy 4.0`.
- **`AssessmentDataManager`** uses `ObservableObject` + `@Published` (legacy Combine), NOT `@Observable`. Views use `@EnvironmentObject`. This is fine — `BusinessSearchManager` is a separate `@Observable` class instantiated inside `SuggestiveTextField` via `@State`.
- **No Components folder exists.** The `SuggestiveTextField.swift` file will be the first file created there. The user must add it to Xcode.
- **`AddressSearchManager`** uses `MKLocalSearchCompleter` with a delegate. `BusinessSearchManager` uses a different API: `MKLocalSearch(request:)` with async/await. Do not conflate them.
- **`@FocusState`** is used in all three detail views — `SuggestiveTextField` will manage its own focus internally with a `focusedField` binding passed in.

---

### Task 1: Create `BusinessSearchManager.swift`

**Files:**
- Create: `Peezy 4.0/Assessment/AssessmentModels/BusinessSearchManager.swift`

This is an `@Observable` class that:
- Accepts a search query and a coordinate for region biasing
- Geocodes an address string once and caches the coordinate
- Debounces MKLocalSearch by 0.3 s
- Returns deduplicated business names (up to 5)
- Falls back to US-center region if geocoding fails

**Step 1: Create the file**

```swift
import Foundation
import MapKit
import Observation

@Observable
@MainActor
final class BusinessSearchManager {

    // MARK: - Output

    var suggestions: [String] = []

    // MARK: - Private

    private var debounceTask: Task<Void, Never>?
    private var cachedCoordinate: CLLocationCoordinate2D?
    private var cachedAddress: String = ""

    // US geographic center — fallback when geocoding fails
    private let usCenterCoordinate = CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35)

    // MARK: - Public API

    /// Geocode the given address once and cache the result.
    /// Call this on .onAppear in the parent view.
    func primeLocation(address: String) async {
        guard !address.isEmpty, address != cachedAddress else { return }
        cachedAddress = address
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            if let location = placemarks.first?.location {
                cachedCoordinate = location.coordinate
            }
        } catch {
            cachedCoordinate = nil // will fall back to US center
        }
    }

    /// Trigger a debounced search. Pass empty string to clear suggestions.
    func search(query: String, category: String) {
        debounceTask?.cancel()
        guard query.count >= 2 else {
            suggestions = []
            return
        }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 s
            guard !Task.isCancelled else { return }
            await performSearch(query: query, category: category)
        }
    }

    func clearSuggestions() {
        debounceTask?.cancel()
        suggestions = []
    }

    // MARK: - Private

    private func performSearch(query: String, category: String) async {
        let naturalQuery = "\(query) \(category)"
        let coordinate = cachedCoordinate ?? usCenterCoordinate
        let spanDelta: CLLocationDegrees = cachedCoordinate != nil ? 0.5 : 60.0

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = naturalQuery
        request.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            // Deduplicate by name, take first 5
            var seen = Set<String>()
            var names: [String] = []
            for item in response.mapItems {
                guard let name = item.name, !name.isEmpty else { continue }
                if seen.insert(name).inserted {
                    names.append(name)
                    if names.count == 5 { break }
                }
            }
            suggestions = names
        } catch {
            suggestions = []
        }
    }
}
```

**Step 2: Confirm the file compiles in isolation**

The file won't be in the Xcode project yet. Proceed to Task 2 immediately — full build verification happens after Task 3.

> **NOTE FOR USER:** After this task, add `BusinessSearchManager.swift` to the Xcode project: File → Add Files to "Peezy 4.0" → select the file → ensure the target "Peezy 4.0" is checked.

---

### Task 2: Create `SuggestiveTextField.swift`

**Files:**
- Create: `Peezy 4.0/Assessment/AssessmentViews/Components/SuggestiveTextField.swift`

This is a reusable SwiftUI view that:
- Accepts a `placeholder`, `text: Binding<String>`, `label: String` (displayed above the field), `source: SuggestionSource`, and `isFocused: Bool`
- `SuggestionSource` is an enum: `.local([String])` or `.mapSearch(category: String, nearAddress: String)`
- Shows up to 5 suggestions below the field when text ≥ 2 characters
- Tapping a suggestion fills the field and clears suggestions
- Free-text always works — suggestions are non-blocking

**Step 1: Create the file**

```swift
import SwiftUI
import MapKit

// MARK: - Suggestion Source

enum SuggestionSource {
    case local([String])
    case mapSearch(category: String, nearAddress: String)
}

// MARK: - SuggestiveTextField

struct SuggestiveTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let source: SuggestionSource
    var isFocused: Bool = false

    @State private var suggestions: [String] = []
    @State private var searchManager: BusinessSearchManager? = nil
    @State private var showSuggestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            // Text field
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.3)))
                .font(.system(size: 16))
                .foregroundColor(.white)
                .textInputAutocapitalization(.words)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(isFocused ? 0.4 : 0.15), lineWidth: 1)
                        )
                )
                .onChange(of: text) { _, newValue in
                    handleTextChange(newValue)
                }

            // Suggestion dropdown
            if showSuggestions && !suggestions.isEmpty {
                suggestionList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showSuggestions)
        .task {
            await primeSearchManagerIfNeeded()
        }
    }

    // MARK: - Suggestion List

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                Button {
                    text = suggestion
                    suggestions = []
                    showSuggestions = false
                    searchManager?.clearSuggestions()
                } label: {
                    HStack {
                        Text(suggestion)
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }

                if index < suggestions.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.1))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(.top, 2)
    }

    // MARK: - Helpers

    private func handleTextChange(_ newValue: String) {
        switch source {
        case .local(let list):
            if newValue.count >= 2 {
                let query = newValue.lowercased()
                suggestions = list.filter { $0.lowercased().hasPrefix(query) }.prefix(5).map { $0 }
                showSuggestions = !suggestions.isEmpty
            } else {
                suggestions = []
                showSuggestions = false
            }

        case .mapSearch(let category, _):
            if newValue.count >= 2 {
                searchManager?.search(query: newValue, category: category)
            } else {
                searchManager?.clearSuggestions()
                suggestions = []
                showSuggestions = false
            }
        }
    }

    private func primeSearchManagerIfNeeded() async {
        guard case .mapSearch(_, let address) = source else { return }
        let manager = BusinessSearchManager()
        searchManager = manager
        await manager.primeLocation(address: address)
        // Observe suggestions changes via withObservationTracking would be ideal,
        // but since BusinessSearchManager is @Observable, we use a polling task
    }
}
```

**Step 2: Add observation bridging for `BusinessSearchManager` suggestions**

The `SuggestiveTextField` uses `@State private var searchManager: BusinessSearchManager?` but doesn't automatically observe suggestion updates. We need to wire the manager's `suggestions` into the local `suggestions` state. The cleanest approach for `@Observable` in SwiftUI is to use `.onChange` on a helper property or use a separate child view that can `@Bindable` the manager.

Replace the `primeSearchManagerIfNeeded` and add a `MapSearchObserver` subview to avoid polling:

The `SuggestiveTextField` body for the `.mapSearch` case should conditionally embed a hidden observer view. Revise the file:

**Full revised `SuggestiveTextField.swift`:**

```swift
import SwiftUI
import MapKit

// MARK: - Suggestion Source

enum SuggestionSource {
    case local([String])
    case mapSearch(category: String, nearAddress: String)
}

// MARK: - SuggestiveTextField

struct SuggestiveTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let source: SuggestionSource
    var isFocused: Bool = false

    @State private var suggestions: [String] = []
    @State private var showSuggestions = false
    @State private var mapManager = BusinessSearchManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.3)))
                .font(.system(size: 16))
                .foregroundColor(.white)
                .textInputAutocapitalization(.words)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(isFocused ? 0.4 : 0.15), lineWidth: 1)
                        )
                )
                .onChange(of: text) { _, newValue in
                    handleTextChange(newValue)
                }

            // Bridge @Observable manager suggestions into local @State
            // SwiftUI re-renders this Color.clear whenever mapManager.suggestions changes
            if case .mapSearch = source {
                Color.clear
                    .frame(height: 0)
                    .onChange(of: mapManager.suggestions) { _, newSuggestions in
                        suggestions = newSuggestions
                        showSuggestions = !newSuggestions.isEmpty
                    }
            }

            if showSuggestions && !suggestions.isEmpty {
                suggestionList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showSuggestions)
        .task {
            if case .mapSearch(_, let address) = source {
                await mapManager.primeLocation(address: address)
            }
        }
    }

    // MARK: - Suggestion List

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                Button {
                    text = suggestion
                    suggestions = []
                    showSuggestions = false
                    mapManager.clearSuggestions()
                } label: {
                    HStack {
                        Text(suggestion)
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                if index < suggestions.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.1))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(.top, 2)
    }

    // MARK: - Text change handler

    private func handleTextChange(_ newValue: String) {
        switch source {
        case .local(let list):
            if newValue.count >= 2 {
                let query = newValue.lowercased()
                suggestions = list.filter { $0.lowercased().hasPrefix(query) }.prefix(5).map { $0 }
                showSuggestions = !suggestions.isEmpty
            } else {
                suggestions = []
                showSuggestions = false
            }

        case .mapSearch(let category, _):
            if newValue.count >= 2 {
                mapManager.search(query: newValue, category: category)
            } else {
                mapManager.clearSuggestions()
                suggestions = []
                showSuggestions = false
            }
        }
    }
}
```

> **NOTE FOR USER:** After creating this file, add `SuggestiveTextField.swift` to the Xcode project under the group `Assessment/AssessmentViews/Components` (create the group if it doesn't exist). Ensure target "Peezy 4.0" is checked.

---

### Task 3: Build verification (Tasks 1 & 2)

**Files:** none — verification only

**Step 1: Run xcodebuild**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild \
  -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  build 2>&1 | grep -E "(error:|warning:|BUILD)"
```

Expected: `BUILD SUCCEEDED` — no errors referencing `BusinessSearchManager` or `SuggestiveTextField`.

**Step 2: Fix any compile errors before proceeding.**

Common issues to watch for:
- `@Observable` + `@MainActor` — ensure `import Observation` is present in `BusinessSearchManager.swift`
- `Task.sleep(nanoseconds:)` throws — ensure `try? await` not bare `await`
- `mapManager.suggestions` conformance — `suggestions: [String]` is a stored property on `@Observable`, so `onChange(of:)` should work

---

### Task 4: Modify `FinancialDetails.swift`

**Files:**
- Modify: `Peezy 4.0/Assessment/AssessmentViews/Questions/FinancialDetails.swift`

**Hardcoded lists (define as private constants at file scope, above the struct):**

```swift
private let creditCardSuggestions = [
    "Chase", "American Express", "Capital One", "Citi", "Discover",
    "Bank of America", "Wells Fargo", "Barclays", "US Bank", "Synchrony"
]

private let investmentSuggestions = [
    "Fidelity", "Charles Schwab", "Vanguard", "E*TRADE", "TD Ameritrade",
    "Merrill Lynch", "Morgan Stanley", "Edward Jones", "Robinhood",
    "Wealthfront", "Betterment", "Northwestern Mutual", "Raymond James"
]

private let studentLoanSuggestions = [
    "Navient", "Nelnet", "Great Lakes", "FedLoan", "SoFi", "Earnest",
    "CommonBond", "Mohela", "Aidvantage", "EdFinancial"
]
```

**Category → source mapping (define as a function or computed property inside the struct):**

```swift
private func suggestionSource(for category: String) -> SuggestionSource {
    switch category {
    case "Bank / Credit Union":
        return .mapSearch(category: "bank", nearAddress: assessmentData.currentAddress)
    case "Credit Card":
        return .local(creditCardSuggestions)
    case "Investment Account":
        return .local(investmentSuggestions)
    case "Student Loans":
        return .local(studentLoanSuggestions)
    default:
        return .local([])
    }
}
```

**Replace the `ForEach` body in the `ScrollView`:**

Current code (lines 36–57):
```swift
ForEach(assessmentData.financialInstitutions, id: \.self) { category in
    VStack(alignment: .leading, spacing: 6) {
        Text(category)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white.opacity(0.6))

        TextField("", text: binding(for: category), prompt: Text("e.g. Chase, Amex...").foregroundColor(.white.opacity(0.3)))
            .font(.system(size: 16))
            .foregroundColor(.white)
            .textInputAutocapitalization(.words)
            .focused($focusedCategory, equals: category)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(focusedCategory == category ? 0.4 : 0.15), lineWidth: 1)
                    )
            )
    }
}
```

Replace with:
```swift
ForEach(assessmentData.financialInstitutions, id: \.self) { category in
    SuggestiveTextField(
        label: category,
        placeholder: "e.g. Chase, Amex...",
        text: binding(for: category),
        source: suggestionSource(for: category),
        isFocused: focusedCategory == category
    )
    .onTapGesture {
        focusedCategory = category
    }
}
```

Note: `@FocusState` can remain declared but the `SuggestiveTextField` doesn't use it internally — the `isFocused` Bool is computed from the parent's `focusedCategory` state. The `onTapGesture` sets it. The `focused()` modifier is removed from the inner field since `SuggestiveTextField` manages its own internal text field without a `FocusState` binding (keep it simple — the visual focus indicator still works via `isFocused`).

**Step 1: Make the edits described above to `FinancialDetails.swift`**

**Step 2: Run xcodebuild and verify BUILD SUCCEEDED**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild \
  -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  build 2>&1 | grep -E "(error:|warning:|BUILD)"
```

**Step 3: Commit**

```bash
git add "Peezy 4.0/Assessment/AssessmentViews/Questions/FinancialDetails.swift"
git commit -m "feat: add autocomplete suggestions to FinancialDetails"
```

---

### Task 5: Modify `HealthcareDetails.swift`

**Files:**
- Modify: `Peezy 4.0/Assessment/AssessmentViews/Questions/HealthcareDetails.swift`

**Category → source mapping (inside the struct):**

```swift
private func suggestionSource(for category: String) -> SuggestionSource {
    switch category {
    case "Doctor":
        return .mapSearch(category: "doctor", nearAddress: assessmentData.currentAddress)
    case "Dentist":
        return .mapSearch(category: "dentist", nearAddress: assessmentData.currentAddress)
    case "Specialists":
        return .mapSearch(category: "medical specialist", nearAddress: assessmentData.currentAddress)
    case "Pharmacy":
        return .mapSearch(category: "pharmacy", nearAddress: assessmentData.currentAddress)
    default:
        return .local([])
    }
}
```

**Replace the `ForEach` body:**

Current (lines 36–57) — same structure as FinancialDetails but with healthcare categories.

Replace with:
```swift
ForEach(assessmentData.healthcareProviders, id: \.self) { category in
    SuggestiveTextField(
        label: category,
        placeholder: "e.g. Dr. Smith, Aetna...",
        text: binding(for: category),
        source: suggestionSource(for: category),
        isFocused: focusedCategory == category
    )
    .onTapGesture {
        focusedCategory = category
    }
}
```

**Step 1: Make the edits to `HealthcareDetails.swift`**

**Step 2: Run xcodebuild and verify BUILD SUCCEEDED**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild \
  -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  build 2>&1 | grep -E "(error:|warning:|BUILD)"
```

**Step 3: Commit**

```bash
git add "Peezy 4.0/Assessment/AssessmentViews/Questions/HealthcareDetails.swift"
git commit -m "feat: add location-based autocomplete suggestions to HealthcareDetails"
```

---

### Task 6: Modify `FitnessDetails.swift`

**Files:**
- Modify: `Peezy 4.0/Assessment/AssessmentViews/Questions/FitnessDetails.swift`

**Category → source mapping (inside the struct):**

```swift
private func suggestionSource(for category: String) -> SuggestionSource {
    switch category {
    case "Gym / CrossFit":
        return .mapSearch(category: "gym crossfit", nearAddress: assessmentData.currentAddress)
    case "Yoga / Pilates":
        return .mapSearch(category: "yoga pilates studio", nearAddress: assessmentData.currentAddress)
    case "Spin / Cycling":
        return .mapSearch(category: "cycling spin studio", nearAddress: assessmentData.currentAddress)
    case "Massage / Spa":
        return .mapSearch(category: "spa massage", nearAddress: assessmentData.currentAddress)
    case "Country Club / Golf":
        return .mapSearch(category: "golf country club", nearAddress: assessmentData.currentAddress)
    default:
        return .local([])
    }
}
```

**Replace the `ForEach` body:**

Current (lines 36–57) — same structure as previous detail views.

Replace with:
```swift
ForEach(assessmentData.fitnessWellness, id: \.self) { category in
    SuggestiveTextField(
        label: category,
        placeholder: "e.g. Planet Fitness, YMCA...",
        text: binding(for: category),
        source: suggestionSource(for: category),
        isFocused: focusedCategory == category
    )
    .onTapGesture {
        focusedCategory = category
    }
}
```

**Step 1: Make the edits to `FitnessDetails.swift`**

**Step 2: Run final xcodebuild and verify BUILD SUCCEEDED**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild \
  -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  build 2>&1 | grep -E "(error:|warning:|BUILD)"
```

**Step 3: Final commit**

```bash
git add "Peezy 4.0/Assessment/AssessmentViews/Questions/FitnessDetails.swift"
git commit -m "feat: add location-based autocomplete suggestions to FitnessDetails"
```

---

## Summary of All New/Modified Files

| Action | File |
|--------|------|
| **CREATE** | `Peezy 4.0/Assessment/AssessmentModels/BusinessSearchManager.swift` |
| **CREATE** | `Peezy 4.0/Assessment/AssessmentViews/Components/SuggestiveTextField.swift` |
| **MODIFY** | `Peezy 4.0/Assessment/AssessmentViews/Questions/FinancialDetails.swift` |
| **MODIFY** | `Peezy 4.0/Assessment/AssessmentViews/Questions/HealthcareDetails.swift` |
| **MODIFY** | `Peezy 4.0/Assessment/AssessmentViews/Questions/FitnessDetails.swift` |

## User Action Required After Each New File

After creating `BusinessSearchManager.swift` and `SuggestiveTextField.swift`, the user **must** add them to the Xcode project target manually (CLAUDE.md rule: do not modify `.pbxproj`).
