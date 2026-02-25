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
    @State private var justSelected = false
    @State private var mapManager = BusinessSearchManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))

            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Color.gray.opacity(0.6)))
                .font(.system(size: 16))
                .foregroundColor(PeezyTheme.Colors.deepInk)
                .textInputAutocapitalization(.words)
                .padding(16)
                .background(Color.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
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
                    justSelected = true
                    text = suggestion
                    suggestions = []
                    showSuggestions = false
                    mapManager.clearSuggestions()
                } label: {
                    HStack {
                        Text(suggestion)
                            .font(.system(size: 15))
                            .foregroundColor(PeezyTheme.Colors.deepInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 11))
                            .foregroundColor(Color.gray)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                if index < suggestions.count - 1 {
                    Divider()
                        .background(PeezyTheme.Colors.deepInk.opacity(0.08))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(PeezyTheme.Colors.deepInk.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.top, 2)
    }

    // MARK: - Text change handler

    private func handleTextChange(_ newValue: String) {
        if justSelected {
            justSelected = false
            return
        }
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
