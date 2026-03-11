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
    var autoFocus: Bool = false          // NEW: auto-opens keyboard on appear

    @State private var suggestions: [String] = []
    @State private var showSuggestions = false
    @State private var justSelected = false
    @State private var mapManager = BusinessSearchManager()
    @FocusState private var fieldFocused: Bool   // NEW: internal focus state

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(PeezyTheme.Typography.callout)
                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))

            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Color.gray.opacity(0.6)))
                .font(.system(size: 16))
                .foregroundColor(PeezyTheme.Colors.deepInk)
                .tint(PeezyTheme.Colors.accentBlue)
                .textInputAutocapitalization(.words)
                .focused($fieldFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(minHeight: 52)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.06))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            (isFocused || fieldFocused) ? PeezyTheme.Colors.accentBlue.opacity(0.6) : Color.black.opacity(0.1),
                            lineWidth: (isFocused || fieldFocused) ? 2 : 1
                        )
                )
                .shadow(
                    color: (isFocused || fieldFocused) ? PeezyTheme.Colors.accentBlue.opacity(0.2) : Color.black.opacity(0.3),
                    radius: 10,
                    y: 5
                )
                .onChange(of: text) { _, newValue in
                    handleTextChange(newValue)
                }

            // Bridge @Observable manager suggestions into local @State
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
        .onAppear {
            if autoFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    fieldFocused = true
                }
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
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.06))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
    }

    // MARK: - Text Change Handler

    private func handleTextChange(_ newValue: String) {
        if justSelected {
            justSelected = false
            return
        }

        switch source {
        case .local(let list):
            if newValue.count >= 2 {
                suggestions = list.filter { $0.localizedCaseInsensitiveContains(newValue) }.prefix(5).map { $0 }
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
