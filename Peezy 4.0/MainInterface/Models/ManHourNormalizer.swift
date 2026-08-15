struct MoverQuote: Codable, Equatable {
    var company: String
    var crew: Int
    var hours: Double
    var perManRate: Double
    var travelFee: Double
}

struct NormalizedQuote: Equatable {
    let company: String
    let totalManHours: Double   // crew × hours
    let repricedTotal: Double   // avgManHours × perManRate + travelFee
    let lowball: Bool           // totalManHours < avg (only when 2+ quotes)
}

enum ManHourNormalizer {
    struct Basis: Equatable {
        let name: String
        let manHours: Double
        let isPeezy: Bool
    }

    struct CompanyTotal: Equatable {
        let company: String
        let total: Double
    }

    struct Scenario: Equatable {
        let basis: Basis
        let totals: [CompanyTotal]
        let lowballCompany: String?
    }

    static func normalize(_ quotes: [MoverQuote]) -> [NormalizedQuote] {
        guard !quotes.isEmpty else { return [] }
        let manHours = quotes.map { Double($0.crew) * $0.hours }
        let avg = manHours.reduce(0, +) / Double(manHours.count)
        return zip(quotes, manHours).map { quote, mh in
            NormalizedQuote(
                company: quote.company,
                totalManHours: mh,
                repricedTotal: avg * quote.perManRate + quote.travelFee,
                lowball: quotes.count > 1 && mh < avg
            )
        }
    }

    static func scenarios(bases: [Basis], quotes: [MoverQuote]) -> [Scenario] {
        bases.map { basis in
            let totals = quotes.map { quote in
                CompanyTotal(
                    company: quote.company,
                    total: basis.manHours * quote.perManRate + quote.travelFee
                )
            }
            let lowballCompany = quotes
                .map { quote in
                    (company: quote.company, manHours: Double(quote.crew) * quote.hours)
                }
                .filter { $0.manHours < basis.manHours }
                .min { $0.manHours < $1.manHours }?
                .company
            return Scenario(
                basis: basis,
                totals: totals,
                lowballCompany: lowballCompany
            )
        }
    }
}
