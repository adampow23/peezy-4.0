import SwiftUI

struct MoversQuotesView: View {
    @Bindable var model: MoversFlowViewModel

    @State private var isEditing = false
    @State private var editingIndex: Int?
    @State private var companyName = ""
    @State private var crewSize = 2
    @State private var estimatedHours = 0.0
    @State private var hourlyRate = 0.0
    @State private var travelFee = 0.0
    @State private var quoteNotes = ""

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: "Waiting on your quotes")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                    VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                        Text("Add quotes as they come in")
                            .font(.title)
                            .bold()
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .accessibilityIdentifier("movers.quotes.title")

                        Text("Use the crew's total hourly rate. Peezy converts it to a per-man rate so every time estimate can be compared fairly.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("movers.quotes.instructions")
                    }

                    ForEach(Array(model.quotes.enumerated()), id: \.offset) { index, quote in
                        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                            Text(quote.company)
                                .font(.title3)
                                .bold()
                                .foregroundStyle(PeezyTheme.Colors.deepInk)

                            if let crew = quote.crew,
                               let hours = quote.hours,
                               let perManRate = quote.perManRate {
                                let crewHourlyRate = perManRate * Double(crew)
                                Text("\(crew)-person crew · \(hours.formatted(.number.precision(.fractionLength(0...1)))) hours")
                                    .font(.body)
                                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                                Text("\(crewHourlyRate.formatted(.currency(code: "USD").precision(.fractionLength(0)))) hourly · \((quote.travelFee ?? 0).formatted(.currency(code: "USD").precision(.fractionLength(0)))) travel")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Finish this quote before summarizing.")
                                    .font(.callout)
                                    .foregroundStyle(PeezyTheme.Colors.warningOrange)
                            }

                            if !quote.notes.isEmpty {
                                Text(quote.notes)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                                Button("Edit", systemImage: "pencil") {
                                    beginEditing(index: index)
                                }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("movers.quotes.edit.\(index)")

                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    Task { await model.deleteQuote(at: index) }
                                }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("movers.quotes.delete.\(index)")
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .taskContentCard()
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("movers.quotes.row.\(index)")
                    }

                    if isEditing {
                        quoteForm
                    } else {
                        Button("Add quote", systemImage: "plus", action: beginAdding)
                            .font(PeezyTheme.Typography.headline)
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: PeezyTheme.Layout.buttonHeightSmall
                            )
                            .buttonStyle(.bordered)
                            .tint(PeezyTheme.Colors.deepInk)
                            .accessibilityIdentifier("movers.quotes.add")
                    }
                }
                .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
                .padding(.vertical, PeezyTheme.Layout.verticalSpacing)
            }
            .scrollIndicators(.hidden)

            PeezyAssessmentButton(
                "Summarize my quotes",
                disabled: !model.canSummarize,
                action: summarize
            )
            .accessibilityIdentifier("movers.quotes.summarize")
            .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
            .padding(.bottom, PeezyTheme.Layout.verticalSpacing)
        }
        .accessibilityIdentifier("movers.quotes.screen")
    }

    private var quoteForm: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
            Text(editingIndex == nil ? "New quote" : "Edit quote")
                .font(.title3)
                .bold()
                .foregroundStyle(PeezyTheme.Colors.deepInk)

            TextField("Company name", text: $companyName)
                .textInputAutocapitalization(.words)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("movers.quotes.company")

            TextField("Crew size", value: $crewSize, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("movers.quotes.crew")

            TextField("Estimated hours", value: $estimatedHours, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("movers.quotes.hours")

            TextField("Hourly rate for the crew", value: $hourlyRate, format: .currency(code: "USD"))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("movers.quotes.hourlyRate")

            TextField("Travel or trip fee", value: $travelFee, format: .currency(code: "USD"))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("movers.quotes.travelFee")

            TextField("Notes", text: $quoteNotes, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("movers.quotes.notes")

            PeezyAssessmentButton(
                "Save quote",
                disabled: !canSave,
                action: saveQuote
            )
            .accessibilityIdentifier("movers.quotes.save")

            Button("Cancel", action: cancelEditing)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("movers.quotes.cancel")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .taskContentCard()
        .accessibilityIdentifier("movers.quotes.editor")
    }

    private var canSave: Bool {
        !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && crewSize > 0
            && estimatedHours > 0
            && hourlyRate > 0
            && travelFee >= 0
    }

    private func beginAdding() {
        editingIndex = nil
        companyName = ""
        crewSize = 2
        estimatedHours = 0
        hourlyRate = 0
        travelFee = 0
        quoteNotes = ""
        isEditing = true
    }

    private func beginEditing(index: Int) {
        guard model.quotes.indices.contains(index) else { return }
        let quote = model.quotes[index]
        editingIndex = index
        companyName = quote.company
        crewSize = quote.crew ?? 2
        estimatedHours = quote.hours ?? 0
        hourlyRate = (quote.perManRate ?? 0) * Double(quote.crew ?? 2)
        travelFee = quote.travelFee ?? 0
        quoteNotes = quote.notes
        isEditing = true
    }

    private func saveQuote() {
        guard canSave else { return }
        let quote = TaskQuote(
            company: companyName.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: quoteNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            crew: crewSize,
            hours: estimatedHours,
            perManRate: hourlyRate / Double(crewSize),
            travelFee: travelFee
        )
        let index = editingIndex
        Task {
            await model.saveQuote(quote, editing: index)
            cancelEditing()
        }
    }

    private func cancelEditing() {
        isEditing = false
        editingIndex = nil
    }

    private func summarize() {
        Task { await model.summarizeQuotes() }
    }
}
