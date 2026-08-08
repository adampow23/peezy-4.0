import SwiftUI

/// One saved quote row on the user task doc — persisted as
/// `{company, notes, crew?, hours?, perManRate?, travelFee?}` inside the
/// `quotes` array by `TaskActionService.updateQuotes`. v1 rows omit the numerics.
struct TaskQuote: Equatable {
    var company: String
    var notes: String
    var crew: Int?
    var hours: Double?
    var perManRate: Double?
    var travelFee: Double?

    init(
        company: String,
        notes: String,
        crew: Int? = nil,
        hours: Double? = nil,
        perManRate: Double? = nil,
        travelFee: Double? = nil
    ) {
        self.company = company
        self.notes = notes
        self.crew = crew
        self.hours = hours
        self.perManRate = perManRate
        self.travelFee = travelFee
    }

    init?(data: [String: Any]) {
        guard let company = data["company"] as? String, !company.isEmpty else { return nil }
        self.company = company
        self.notes = data["notes"] as? String ?? ""
        self.crew = (data["crew"] as? NSNumber)?.intValue
        self.hours = (data["hours"] as? NSNumber)?.doubleValue
        self.perManRate = (data["perManRate"] as? NSNumber)?.doubleValue
        self.travelFee = (data["travelFee"] as? NSNumber)?.doubleValue
    }

    var firestoreData: [String: Any] {
        var data: [String: Any] = ["company": company, "notes": notes]
        if let crew { data["crew"] = crew }
        if let hours { data["hours"] = hours }
        if let perManRate { data["perManRate"] = perManRate }
        if let travelFee { data["travelFee"] = travelFee }
        return data
    }

    /// Complete structured quote for the normalizer; a missing travel fee is 0.
    var moverQuote: MoverQuote? {
        guard let crew, let hours, let perManRate else { return nil }
        return MoverQuote(
            company: company,
            crew: crew,
            hours: hours,
            perManRate: perManRate,
            travelFee: travelFee ?? 0
        )
    }
}

/// Quote tracker (Spec 09 Phase 5/6). `tracker == "v1"` keeps the name + notes
/// rows; `tracker == "manHours"` adds structured fields per quote and the
/// man-hour comparison table for BOOK_MOVERS.
struct QuoteTrackerView: View {
    @Binding var quotes: [TaskQuote]
    var tracker: String = "v1"
    let onPersist: ([TaskQuote]) -> Void

    @State private var isAdding = false
    @State private var newCompany = ""
    @State private var newNotes = ""
    @State private var newCrew = ""
    @State private var newHours = ""
    @State private var newRate = ""
    @State private var newTravel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
            TaskContentSectionTitle(title: "Quotes", systemImage: "list.clipboard.fill")

            ForEach(Array(quotes.enumerated()), id: \.offset) { index, quote in
                VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                    Text(quote.company)
                        .font(PeezyTheme.Typography.headline)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if tracker == "manHours", let mover = quote.moverQuote {
                        Text("\(mover.crew) crew · \(hoursText(mover.hours)) hrs · \(moneyText(mover.perManRate))/man-hr · \(moneyText(mover.travelFee)) travel")
                            .font(PeezyTheme.Typography.callout)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }

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

            if tracker == "manHours", !normalized.isEmpty {
                comparisonSection
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

    // MARK: - Man-hour comparison

    private var normalized: [NormalizedQuote] {
        ManHourNormalizer.normalize(quotes.compactMap(\.moverQuote))
    }

    private var fleetAverageManHours: Double {
        let hours = normalized.map(\.totalManHours)
        guard !hours.isEmpty else { return 0 }
        return hours.reduce(0, +) / Double(hours.count)
    }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            Grid(
                alignment: .leading,
                horizontalSpacing: PeezyTheme.Layout.verticalSpacingSmall,
                verticalSpacing: PeezyTheme.Layout.verticalSpacingSmall
            ) {
                GridRow {
                    Text("Company")
                    Text("Man-hrs")
                    Text("At avg")
                }
                .font(PeezyTheme.Typography.caption)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))

                ForEach(Array(normalized.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.company)
                                .font(PeezyTheme.Typography.headline)
                                .foregroundStyle(PeezyTheme.Colors.deepInk)
                                .fixedSize(horizontal: false, vertical: true)
                            if row.lowball {
                                Text("Lowball")
                                    .font(PeezyTheme.Typography.caption)
                                    .foregroundStyle(.red)
                                    .accessibilityIdentifier("quoteTracker.lowball.\(index)")
                            }
                        }
                        .accessibilityIdentifier("quoteTracker.comparisonRow.\(index)")

                        Text(hoursText(row.totalManHours))
                            .font(PeezyTheme.Typography.body)
                            .foregroundStyle(PeezyTheme.Colors.deepInk)

                        Text(moneyText(row.repricedTotal))
                            .font(PeezyTheme.Typography.body)
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                    }
                }
            }

            Text("Fleet average: \(hoursText(fleetAverageManHours)) man-hours")
                .font(PeezyTheme.Typography.callout)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.7))
                .accessibilityIdentifier("quoteTracker.fleetAverage")
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
        .accessibilityIdentifier("quoteTracker.comparisonTable")
    }

    private func hoursText(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func moneyText(_ value: Double) -> String {
        String(format: "$%.0f", value)
    }

    // MARK: - Add form

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

            if tracker == "manHours" {
                numericField("Crew size", text: $newCrew, id: "quoteTracker.crewField")
                numericField("Quoted hours", text: $newHours, id: "quoteTracker.hoursField")
                numericField("Per-man hourly rate", text: $newRate, id: "quoteTracker.rateField")
                numericField("Travel fee", text: $newTravel, id: "quoteTracker.travelField")
            }

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

    private func numericField(_ placeholder: String, text: Binding<String>, id: String) -> some View {
        TextField(placeholder, text: text)
            .font(PeezyTheme.Typography.body)
            .foregroundStyle(PeezyTheme.Colors.deepInk)
            .keyboardType(.decimalPad)
            .padding(PeezyTheme.Layout.cardPaddingSmall)
            .background(
                Color.white.opacity(0.42),
                in: RoundedRectangle(
                    cornerRadius: PeezyTheme.Layout.cornerRadiusSmall,
                    style: .continuous
                )
            )
            .accessibilityIdentifier(id)
    }

    private var trimmedCompany: String {
        newCompany.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveNewQuote() {
        var quote = TaskQuote(
            company: trimmedCompany,
            notes: newNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if tracker == "manHours" {
            quote.crew = Int(newCrew.trimmingCharacters(in: .whitespaces))
            quote.hours = Double(newHours.trimmingCharacters(in: .whitespaces))
            quote.perManRate = Double(newRate.trimmingCharacters(in: .whitespaces))
            quote.travelFee = Double(newTravel.trimmingCharacters(in: .whitespaces))
        }
        guard !quote.company.isEmpty else { return }
        quotes.append(quote)
        newCompany = ""
        newNotes = ""
        newCrew = ""
        newHours = ""
        newRate = ""
        newTravel = ""
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

#Preview("Man-hour tracker") {
    ScrollView {
        QuoteTrackerView(
            quotes: .constant([
                TaskQuote(company: "Two Men and a Truck", notes: "", crew: 3, hours: 5, perManRate: 50, travelFee: 100),
                TaskQuote(company: "Piece of Cake", notes: "Includes wrap", crew: 2, hours: 6, perManRate: 60, travelFee: 0)
            ]),
            tracker: "manHours",
            onPersist: { _ in }
        )
        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
    }
    .background(PeezyTheme.Colors.lightBase)
}
