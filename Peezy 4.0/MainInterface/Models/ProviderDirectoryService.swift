//
//  ProviderDirectoryService.swift
//  Peezy 4.0
//
//  Direct providerDirectory read with resolveProvider callable fallback.
//  All URL-bearing results pass through one exact-citation boundary.
//

import Foundation
import FirebaseFirestore
import FirebaseFunctions

enum ProviderActionMethod: String, Codable, Equatable {
    case link
    case call
    case concierge
}

struct ProviderCitation: Codable, Equatable {
    let url: String
    let title: String
    var citedText: String?
}

struct ProviderResolution: Equatable {
    let providerId: String?
    let name: String
    let method: ProviderActionMethod
    let url: URL?
    let phone: String?
    let citations: [ProviderCitation]

    static func concierge(named name: String) -> ProviderResolution {
        ProviderResolution(
            providerId: nil,
            name: name.isEmpty ? "Provider" : name,
            method: .concierge,
            url: nil,
            phone: nil,
            citations: []
        )
    }
}

private struct ProviderDirectoryRecord: Decodable {
    let providerId: String
    let name: String
    let aliases: [String]
    let category: String
    let addressChangeURL: String?
    let cancellationURL: String?
    let phone: String?
    let method: ProviderActionMethod
    let citations: [ProviderCitation]
}

@MainActor
final class ProviderDirectoryService {
    static let shared = ProviderDirectoryService()

    private var directoryCache: [ProviderDirectoryRecord]?

    func resolve(name: String, category: String) async -> ProviderResolution {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.count >= 2 else { return .concierge(named: trimmedName) }

        if let record = await directoryRecord(named: trimmedName, category: category) {
            return Self.safeResolution(
                providerId: record.providerId,
                name: record.name,
                method: record.method,
                rawURL: record.addressChangeURL ?? record.cancellationURL,
                phone: record.phone,
                citations: record.citations,
                fallbackName: trimmedName
            )
        }

        do {
            let result = try await Functions.functions()
                .httpsCallable("resolveProvider")
                .call(["name": trimmedName, "category": category])
            guard let data = result.data as? [String: Any] else {
                return .concierge(named: trimmedName)
            }
            return Self.resolution(from: data, fallbackName: trimmedName)
        } catch {
            return .concierge(named: trimmedName)
        }
    }

    private func directoryRecord(named name: String, category: String) async -> ProviderDirectoryRecord? {
        let lookupKey = Self.normalize(name)
        guard !lookupKey.isEmpty else { return nil }

        if directoryCache == nil {
            do {
                let snapshot = try await Firestore.firestore()
                    .collection("providerDirectory")
                    .getDocuments()
                directoryCache = snapshot.documents.compactMap { document in
                    try? document.data(as: ProviderDirectoryRecord.self)
                }
            } catch {
                // The callable is the rollout-safe fallback while rules propagate.
                directoryCache = []
            }
        }

        return directoryCache?.first { record in
            let nameMatches = ([record.name] + record.aliases).contains { candidate in
                Self.normalize(candidate) == lookupKey
            }
            return nameMatches && Self.categoryFamily(record.category) == Self.categoryFamily(category)
        }
    }

    private static func resolution(
        from data: [String: Any],
        fallbackName: String
    ) -> ProviderResolution {
        let citationData = data["citations"] as? [[String: Any]] ?? []
        let citations = citationData.compactMap { item -> ProviderCitation? in
            guard let rawURL = item["url"] as? String,
                  let url = URL(string: rawURL),
                  url.scheme?.lowercased() == "https" else { return nil }
            return ProviderCitation(
                url: rawURL,
                title: item["title"] as? String ?? "Official provider source",
                citedText: item["citedText"] as? String
            )
        }
        return safeResolution(
            providerId: data["providerId"] as? String,
            name: data["name"] as? String ?? fallbackName,
            method: (data["method"] as? String).flatMap(ProviderActionMethod.init(rawValue:)) ?? .concierge,
            rawURL: data["url"] as? String,
            phone: data["phone"] as? String,
            citations: citations,
            fallbackName: fallbackName
        )
    }

    /// The sole client boundary that can construct a URL-bearing resolution.
    /// Both direct Firestore rows and callable responses use this exact check.
    private static func safeResolution(
        providerId: String?,
        name: String,
        method: ProviderActionMethod,
        rawURL: String?,
        phone: String?,
        citations: [ProviderCitation],
        fallbackName: String
    ) -> ProviderResolution {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = displayName.isEmpty ? fallbackName : displayName

        switch method {
        case .link:
            guard let rawURL,
                  citations.contains(where: { $0.url == rawURL }),
                  let url = URL(string: rawURL),
                  url.scheme?.lowercased() == "https" else {
                return .concierge(named: safeName)
            }
            return ProviderResolution(
                providerId: providerId,
                name: safeName,
                method: .link,
                url: url,
                phone: nil,
                citations: citations
            )

        case .call:
            guard let phone,
                  !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !citations.isEmpty else {
                return .concierge(named: safeName)
            }
            return ProviderResolution(
                providerId: providerId,
                name: safeName,
                method: .call,
                url: nil,
                phone: phone,
                citations: citations
            )

        case .concierge:
            return .concierge(named: safeName)
        }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }

    private static func categoryFamily(_ value: String) -> String {
        let category = value.lowercased()
        if category.contains("insurance") { return "insurance" }
        if ["bank", "brokerage", "invest", "credit", "loan", "financial"].contains(where: { category.contains($0) }) {
            return "financial"
        }
        if ["membership", "gym", "yoga", "studio", "cycling", "spa", "club"].contains(where: { category.contains($0) }) {
            return "membership"
        }
        if ["subscription", "streaming"].contains(where: { category.contains($0) }) { return "subscription" }
        if ["wireless", "carrier", "cellular"].contains(where: { category.contains($0) }) { return "wireless" }
        if category.contains("utility") { return "utility" }
        return normalize(category)
    }
}
