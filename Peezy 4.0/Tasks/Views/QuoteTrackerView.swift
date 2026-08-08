import SwiftUI

/// One saved quote row on the user task doc — persisted as `{company, notes}`
/// inside the `quotes` array by `TaskActionService.updateQuotes`.
struct TaskQuote: Equatable {
    var company: String
    var notes: String

    init(company: String, notes: String) {
        self.company = company
        self.notes = notes
    }

    init?(data: [String: Any]) {
        guard let company = data["company"] as? String, !company.isEmpty else { return nil }
        self.company = company
        self.notes = data["notes"] as? String ?? ""
    }

    var firestoreData: [String: String] {
        ["company": company, "notes": notes]
    }
}

/// v1 quote tracker (Spec 09 Phase 5): name + notes rows only. Phase 6 owns
/// the structured man-hour math for BOOK_MOVERS.
struct QuoteTrackerView: View {
    @Binding var quotes: [TaskQuote]
    let onPersist: ([TaskQuote]) -> Void

    @State private var isAdding = false
    @State private var newCompany = ""
    @State private var newNotes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
            TaskContentSectionTitle(title: "Quotes", systemImage: "list.clipboard.fill")

            ForEach(Array(quotes.enumerated()), id: \.offset) { index, quote in
                VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                    Text(quote.company)
                        .font(PeezyTheme.Typography.headline)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if !quote.notes.isEmpty {
                        Text(quote.notes)
                            .font(PeezyTheme.Typography.callout)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(PeezyTheme.Layout.cardPaddingSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.white.opacity(0.42),
                    in: RoundedRectangle(
                        cornerRadius: PeezyTheme.Layout.cornerRadiusSmall,
                        style: .continuous
                    )
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("quoteTracker.row.\(index)")
            }

            if isAdding {
                addForm
            } else {
                Button {
                    isAdding = true
                } label: {
                    Text("+ Add company")
                        .font(PeezyTheme.Typography.headline)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .frame(maxWidth: .infinity, minHeight: PeezyTheme.Layout.buttonHeightSmall)
                        .background(
                            PeezyTheme.Colors.brandYellow.opacity(0.42),
                            in: RoundedRectangle(
                                cornerRadius: PeezyTheme.Layout.cornerRadiusMedium,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quoteTracker.addCompany")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .taskContentCard()
        .accessibilityIdentifier("quoteTracker.container")
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            TextField("Company name", text: $newCompany)
                .font(PeezyTheme.Typography.body)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .padding(PeezyTheme.Layout.cardPaddingSmall)
                .background(
                    Color.white.opacity(0.42),
                    in: RoundedRectangle(
                        cornerRadius: PeezyTheme.Layout.cornerRadiusSmall,
                        style: .continuous
                    )
                )
                .accessibilityIdentifier("quoteTracker.companyField")

            TextEditor(text: $newNotes)
                .font(PeezyTheme.Typography.body)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(PeezyTheme.Layout.cardPaddingSmall)
                .background(
                    Color.white.opacity(0.42),
                    in: RoundedRectangle(
                        cornerRadius: PeezyTheme.Layout.cornerRadiusSmall,
                        style: .continuous
                    )
                )
                .accessibilityLabel("Quote notes")
                .accessibilityIdentifier("quoteTracker.notesField")

            Button {
                saveNewQuote()
            } label: {
                Text("Save quote")
                    .font(PeezyTheme.Typography.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .frame(maxWidth: .infinity, minHeight: PeezyTheme.Layout.buttonHeightSmall)
                    .background(
                        PeezyTheme.Colors.brandYellow,
                        in: RoundedRectangle(
                            cornerRadius: PeezyTheme.Layout.cornerRadiusMedium,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(trimmedCompany.isEmpty)
            .opacity(trimmedCompany.isEmpty ? 0.45 : 1)
            .accessibilityIdentifier("quoteTracker.save")
        }
    }

    private var trimmedCompany: String {
        newCompany.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveNewQuote() {
        let quote = TaskQuote(
            company: trimmedCompany,
            notes: newNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !quote.company.isEmpty else { return }
        quotes.append(quote)
        newCompany = ""
        newNotes = ""
        isAdding = false
        onPersist(quotes)
    }
}

#Preview("Quote tracker") {
    ScrollView {
        QuoteTrackerView(
            quotes: .constant([
                TaskQuote(company: "Two Men and a Truck", notes: "$140/hr · 3 movers"),
                TaskQuote(company: "Piece of Cake", notes: "Flat $1,200, includes wrap")
            ]),
            onPersist: { _ in }
        )
        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
    }
    .background(PeezyTheme.Colors.lightBase)
}
