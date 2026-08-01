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

enum ProviderIntent: String, Codable, Equatable {
    case cancel
    case updateAddress
    case transferLocation
    case transferRecords
    case closeAccount
}

enum ProviderRequirementKind: String, Codable, Equatable {
    case noticePeriod
    case deliveryMethod
    case contractTerms
}

struct ProviderRequirement: Codable, Equatable {
    let kind: ProviderRequirementKind
    let text: String
    let noticeDays: Int?
    let citationUrl: String
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
    let requirements: [ProviderRequirement]

    static func concierge(named name: String) -> ProviderResolution {
        ProviderResolution(
            providerId: nil,
            name: name.isEmpty ? "Provider" : name,
            method: .concierge,
            url: nil,
            phone: nil,
            citations: [],
            requirements: []
        )
    }
}

private struct ProviderDirectoryRecord: Decodable {
    let providerId: String
    let name: String
    let aliases: [String]
    let category: String
    let source: String?
    let intent: ProviderIntent?
    let addressChangeURL: String?
    let cancellationURL: String?
    let transferLocationURL: String?
    let transferRecordsURL: String?
    let closeAccountURL: String?
    let phone: String?
    let method: ProviderActionMethod
    let citations: [ProviderCitation]
    let requirements: [ProviderRequirement]?

    func url(for intent: ProviderIntent) -> String? {
        switch intent {
        case .cancel: cancellationURL
        case .updateAddress: addressChangeURL
        case .transferLocation: transferLocationURL
        case .transferRecords: transferRecordsURL
        case .closeAccount: closeAccountURL
        }
    }

    func supports(_ requestedIntent: ProviderIntent) -> Bool {
        if source == "resolved" && intent == nil { return false }
        if let intent { return intent == requestedIntent }
        switch method {
        case .link: return url(for: requestedIntent) != nil
        case .call, .concierge: return true
        }
    }
}

@MainActor
final class ProviderDirectoryService {
    static let shared = ProviderDirectoryService()

    private var directoryCache: [ProviderDirectoryRecord]?

    func resolve(name: String, category: String, intent: ProviderIntent) async -> ProviderResolution {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.count >= 2 else { return .concierge(named: trimmedName) }

        if let record = await directoryRecord(named: trimmedName, category: category, intent: intent) {
            return Self.safeResolution(
                providerId: record.providerId,
                name: record.name,
                method: record.method,
                rawURL: record.url(for: intent),
                phone: record.phone,
                citations: record.citations,
                requirements: record.requirements ?? [],
                fallbackName: trimmedName
            )
        }

        do {
            let result = try await Functions.functions()
                .httpsCallable("resolveProvider")
                .call(["name": trimmedName, "category": category, "intent": intent.rawValue])
            guard let data = result.data as? [String: Any] else {
                return .concierge(named: trimmedName)
            }
            return Self.resolution(from: data, fallbackName: trimmedName)
        } catch {
            return .concierge(named: trimmedName)
        }
    }

    private func directoryRecord(
        named name: String,
        category: String,
        intent: ProviderIntent
    ) async -> ProviderDirectoryRecord? {
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
            return nameMatches &&
                Self.categoryFamily(record.category) == Self.categoryFamily(category) &&
                record.supports(intent)
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
        guard let requirements = requirements(from: data["requirements"], citations: citations) else {
            return .concierge(named: data["name"] as? String ?? fallbackName)
        }
        return safeResolution(
            providerId: data["providerId"] as? String,
            name: data["name"] as? String ?? fallbackName,
            method: (data["method"] as? String).flatMap(ProviderActionMethod.init(rawValue:)) ?? .concierge,
            rawURL: data["url"] as? String,
            phone: data["phone"] as? String,
            citations: citations,
            requirements: requirements,
            fallbackName: fallbackName
        )
    }

    private static func requirements(
        from rawValue: Any?,
        citations: [ProviderCitation]
    ) -> [ProviderRequirement]? {
        guard let rawValue else { return [] }
        guard let items = rawValue as? [[String: Any]] else { return nil }

        var requirements: [ProviderRequirement] = []
        for item in items {
            guard let rawKind = item["kind"] as? String,
                  let kind = ProviderRequirementKind(rawValue: rawKind),
                  let text = item["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let citationUrl = item["citationUrl"] as? String,
                  citations.contains(where: { $0.url == citationUrl }),
                  let citationURL = URL(string: citationUrl),
                  citationURL.scheme?.lowercased() == "https" else { return nil }

            let noticeDays = item["noticeDays"] as? Int
            if kind == .noticePeriod,
               !(noticeDays.map { (1...365).contains($0) } ?? false) {
                return nil
            }
            requirements.append(
                ProviderRequirement(
                    kind: kind,
                    text: text,
                    noticeDays: noticeDays,
                    citationUrl: citationUrl
                )
            )
        }
        return requirements
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
        requirements: [ProviderRequirement],
        fallbackName: String
    ) -> ProviderResolution {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = displayName.isEmpty ? fallbackName : displayName
        guard requirements.allSatisfy({ requirement in
            citations.contains(where: { $0.url == requirement.citationUrl }) &&
                URL(string: requirement.citationUrl)?.scheme?.lowercased() == "https" &&
                (requirement.kind != .noticePeriod || requirement.noticeDays.map { (1...365).contains($0) } == true)
        }) else {
            return .concierge(named: safeName)
        }

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
                citations: citations,
                requirements: requirements
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
                citations: citations,
                requirements: requirements
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
