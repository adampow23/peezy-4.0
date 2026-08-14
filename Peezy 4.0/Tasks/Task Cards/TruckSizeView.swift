import FirebaseFirestore
import SwiftUI

struct TruckSizeView: View {
    let userId: String
    let totalCubicFeet: Double
    let distanceMiles: Double?

    @State private var configuration: TruckSizingConfiguration?
    @State private var selectedTierKey: String?
    @State private var resolvedDistanceMiles: Double?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
            Label("Truck size", systemImage: "truck.box.fill")
                .font(.title3.bold())
                .foregroundStyle(PeezyTheme.Colors.deepInk)

            Text("Choose the load style that best matches how you'll pack the truck.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let configuration {
                tierOptions(configuration)

                if let tier = configuration.tiers.first(where: { $0.key == selectedTierKey }) {
                    recommendation(configuration, tier: tier)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("truck.preference.error")
                }
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("truck.config.error")
            } else {
                ProgressView("Loading truck sizes…")
                    .tint(PeezyTheme.Colors.deepInk)
                    .accessibilityIdentifier("truck.config.loading")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PeezyTheme.Layout.cardPadding)
        .background(Color.white.opacity(0.68), in: .rect(cornerRadius: PeezyTheme.Layout.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius)
                .stroke(PeezyTheme.Colors.deepInk.opacity(0.12))
        }
        .task(id: userId) { await load() }
        .accessibilityIdentifier("truck.size")
    }

    private func tierOptions(_ configuration: TruckSizingConfiguration) -> some View {
        VStack(spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            ForEach(configuration.tiers) { tier in
                Button {
                    selectedTierKey = tier.key
                    Task { await persistTier(tier.key) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: selectedTierKey == tier.key ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(
                                selectedTierKey == tier.key
                                    ? PeezyTheme.Colors.successGreen
                                    : PeezyTheme.Colors.deepInk.opacity(0.45)
                            )
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(tier.label)
                                .font(.headline)
                                .foregroundStyle(PeezyTheme.Colors.deepInk)

                            Text(tier.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(PeezyTheme.Layout.cardPaddingSmall)
                    .background(
                        selectedTierKey == tier.key
                            ? PeezyTheme.Colors.deepInk.opacity(0.35)
                            : PeezyTheme.Colors.deepInk.opacity(0.04),
                        in: .rect(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tier.label), \(tier.description)")
                .accessibilityAddTraits(selectedTierKey == tier.key ? .isSelected : [])
                .accessibilityIdentifier("truck.tier.\(tier.key)")
            }
        }
    }

    @ViewBuilder
    private func recommendation(
        _ configuration: TruckSizingConfiguration,
        tier: TruckSizingConfiguration.Tier
    ) -> some View {
        let result = configuration.recommendation(
            cubicFeet: totalCubicFeet,
            tierKey: tier.key
        )

        switch result {
        case .truck(let recommended, let comfortable):
            VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                Text("Recommended truck")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Text(recommended.key)
                    .font(.title2.bold())
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityIdentifier("truck.recommended")

                if let comfortable {
                    Text("\(comfortable.key) — \(configuration.comfortableChoiceLabel)")
                        .font(.subheadline.bold())
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .accessibilityIdentifier("truck.comfortable")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PeezyTheme.Layout.cardPaddingSmall)
            .background(
                PeezyTheme.Colors.backgroundSecondary,
                in: .rect(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall)
            )

        case .aboveLargest:
            aboveLargest(configuration)
        }
    }

    private func aboveLargest(_ configuration: TruckSizingConfiguration) -> some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            Text(configuration.aboveLargest.message)
                .font(.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .accessibilityIdentifier("truck.above_largest.message")

            ForEach(configuration.aboveLargest.options) { option in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: recommendedAboveLargestKey(configuration) == option.key
                          ? "checkmark.circle.fill"
                          : "circle")
                        .foregroundStyle(
                            recommendedAboveLargestKey(configuration) == option.key
                                ? PeezyTheme.Colors.successGreen
                                : .secondary
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.label)
                            .font(.subheadline.bold())
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                        Text("Tradeoff: \(option.tradeoff)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("truck.above_largest.\(option.key)")
            }

            Text("Distance guide: \(configuration.aboveLargest.driveTimeDescription). Shorter moves favor a second trip; longer moves favor a second truck.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let key = recommendedAboveLargestKey(configuration),
               let option = configuration.aboveLargest.options.first(where: { $0.key == key }) {
                Text("Recommended for this distance: \(option.label). You choose based on schedule and rental availability.")
                    .font(.subheadline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("truck.above_largest.recommendation")
            } else {
                Text("Compare both options using drive time, fuel, rental availability, and who can drive each truck.")
                    .font(.subheadline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("truck.above_largest.recommendation")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PeezyTheme.Layout.cardPaddingSmall)
        .background(
            PeezyTheme.Colors.backgroundSecondary,
            in: .rect(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall)
        )
    }

    private func recommendedAboveLargestKey(
        _ configuration: TruckSizingConfiguration
    ) -> String? {
        guard let resolvedDistanceMiles else { return nil }
        return resolvedDistanceMiles < configuration.aboveLargest.distanceThresholdMiles
            ? configuration.aboveLargest.underThresholdRecommendation
            : configuration.aboveLargest.overThresholdRecommendation
    }

    @MainActor
    private func load() async {
        errorMessage = nil
        do {
            let db = Firestore.firestore()
            async let configurationRequest = db.collection("appConfig")
                .document("trucks").getDocument()
            async let preferenceRequest = db.collection("users").document(userId)
                .collection("preferences").document("truckSizing").getDocument()

            let (configurationSnapshot, preferenceSnapshot) = try await (
                configurationRequest,
                preferenceRequest
            )
            guard let data = configurationSnapshot.data(),
                  let configuration = TruckSizingConfiguration(data: data)
            else { throw TruckSizingError.invalidConfiguration }

            let persistedTierKey = preferenceSnapshot.data()?["tierKey"] as? String
            self.configuration = configuration
            self.selectedTierKey = configuration.tiers.contains(where: { $0.key == persistedTierKey })
                ? persistedTierKey
                : configuration.tiers.first?.key

            if let distanceMiles {
                resolvedDistanceMiles = distanceMiles
            } else {
                resolvedDistanceMiles = await IdentityService.shared
                    .loadOrMigrate(userId: userId)?.moveDistanceMiles
            }
        } catch {
            errorMessage = "Truck guidance is unavailable because its current configuration could not be loaded."
        }
    }

    private func persistTier(_ tierKey: String) async {
        guard !userId.isEmpty else { return }
        do {
            try await Firestore.firestore().collection("users").document(userId)
                .collection("preferences").document("truckSizing")
                .setData([
                    "tierKey": tierKey,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
        } catch {
            await MainActor.run {
                errorMessage = "The tier is selected for this screen, but it could not be saved."
            }
        }
    }
}

private struct TruckSizingConfiguration {
    struct Truck: Identifiable {
        var id: String { key }
        let key: String
        let cubicFeet: Double
        let fitsUpTo: [String: Double]
    }

    struct Tier: Identifiable {
        var id: String { key }
        let key: String
        let label: String
        let multiplier: Double
        let description: String
    }

    struct AboveLargest {
        struct Option: Identifiable {
            var id: String { key }
            let key: String
            let label: String
            let tradeoff: String
        }

        let message: String
        let distanceThresholdMiles: Double
        let driveTimeDescription: String
        let underThresholdRecommendation: String
        let overThresholdRecommendation: String
        let options: [Option]
    }

    enum Recommendation {
        case truck(recommended: Truck, comfortable: Truck?)
        case aboveLargest
    }

    let trucks: [Truck]
    let tiers: [Tier]
    let comfortableChoiceLabel: String
    let aboveLargest: AboveLargest

    init?(data: [String: Any]) {
        guard let rawTrucks = data["capacities"] as? [[String: Any]],
              let rawTiers = data["tiers"] as? [[String: Any]],
              let comfortableChoiceLabel = data["comfortableChoiceLabel"] as? String,
              let rawAboveLargest = data["above26"] as? [String: Any]
        else { return nil }

        let trucks = rawTrucks.compactMap { raw -> Truck? in
            guard let key = raw["key"] as? String,
                  let cubicFeet = (raw["cubicFeet"] as? NSNumber)?.doubleValue,
                  let rawThresholds = raw["fitsUpTo"] as? [String: Any]
            else { return nil }
            let thresholds = rawThresholds.compactMapValues {
                ($0 as? NSNumber)?.doubleValue
            }
            return Truck(key: key, cubicFeet: cubicFeet, fitsUpTo: thresholds)
        }

        let tiers = rawTiers.compactMap { raw -> Tier? in
            guard let key = raw["key"] as? String,
                  let label = raw["label"] as? String,
                  let multiplier = (raw["multiplier"] as? NSNumber)?.doubleValue,
                  let description = raw["description"] as? String
            else { return nil }
            return Tier(
                key: key,
                label: label,
                multiplier: multiplier,
                description: description
            )
        }

        guard trucks.count == rawTrucks.count,
              tiers.count == rawTiers.count,
              !trucks.isEmpty,
              !tiers.isEmpty,
              trucks.allSatisfy({ truck in
                  tiers.allSatisfy { truck.fitsUpTo[$0.key] != nil }
              }),
              let message = rawAboveLargest["message"] as? String,
              let threshold = (rawAboveLargest["distanceThresholdMiles"] as? NSNumber)?.doubleValue,
              let driveTimeDescription = rawAboveLargest["driveTimeDescription"] as? String,
              let underRecommendation = rawAboveLargest["underThresholdRecommendation"] as? String,
              let overRecommendation = rawAboveLargest["overThresholdRecommendation"] as? String,
              let rawOptions = rawAboveLargest["options"] as? [[String: Any]]
        else { return nil }

        let options = rawOptions.compactMap { raw -> AboveLargest.Option? in
            guard let key = raw["key"] as? String,
                  let label = raw["label"] as? String,
                  let tradeoff = raw["tradeoff"] as? String
            else { return nil }
            return AboveLargest.Option(key: key, label: label, tradeoff: tradeoff)
        }
        guard options.count == rawOptions.count,
              options.contains(where: { $0.key == underRecommendation }),
              options.contains(where: { $0.key == overRecommendation })
        else { return nil }

        self.trucks = trucks
        self.tiers = tiers
        self.comfortableChoiceLabel = comfortableChoiceLabel
        self.aboveLargest = AboveLargest(
            message: message,
            distanceThresholdMiles: threshold,
            driveTimeDescription: driveTimeDescription,
            underThresholdRecommendation: underRecommendation,
            overThresholdRecommendation: overRecommendation,
            options: options
        )
    }

    func recommendation(cubicFeet: Double, tierKey: String) -> Recommendation {
        guard let index = trucks.firstIndex(where: {
            ($0.fitsUpTo[tierKey] ?? -.infinity) >= cubicFeet
        }) else { return .aboveLargest }

        return .truck(
            recommended: trucks[index],
            comfortable: trucks.indices.contains(index + 1) ? trucks[index + 1] : nil
        )
    }
}

private enum TruckSizingError: Error {
    case invalidConfiguration
}
