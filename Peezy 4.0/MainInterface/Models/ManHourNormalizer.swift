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
}
