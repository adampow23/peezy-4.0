import SwiftUI

struct FitnessDetails: View {
    @State private var details: [String: String] = [:]
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @State private var currentEntryIndex: Int = 0
    @State private var showContent = true

    @State private var headerDone = false
    @State private var isHero = true
    @State private var skipped = false
    @State private var showControls = false

    private let speed: Double = 0.04

    private var fieldEntries: [(key: String, label: String, category: String)] {
        var entries: [(String, String, String)] = []
        for category in assessmentData.fitnessWellness {
            let count = assessmentData.fitnessCounts[category] ?? 1
            if count <= 1 {
                entries.append((category, category, category))
            } else {
                for i in 1...count {
                    let key = "\(category) \(i)"
                    entries.append((key, "\(category) \(i)", category))
                }
            }
        }
        return entries
    }

    private var currentEntry: (key: String, label: String, category: String)? {
        guard currentEntryIndex < fieldEntries.count else { return nil }
        return fieldEntries[currentEntryIndex]
    }

    private var headerText: String {
        guard let entry = currentEntry else { return "" }
        return "Where do you go for \(entry.category.lowercased())?"
    }

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea(.keyboard)

            VStack(spacing: 0) {

                if isHero { Spacer() }

                VStack(spacing: 8) {
                    Group {
                        if skipped || !isHero {
                            Text(headerText)
                        } else {
                            TypingText(
                                fullText: headerText,
                                speed: speed,
                                visibleColor: PeezyTheme.Colors.deepInk,
                                onComplete: {
                                    headerDone = true
                                    triggerMorph()
                                }
                            )
                        }
                    }
                    .font(.system(size: isHero ? 32 : 22, weight: .semibold))
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .lineSpacing(4)
                    .multilineTextAlignment(isHero ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: isHero ? .center : .leading)

                    if !isHero && fieldEntries.count > 1 {
                        Text("\(currentEntryIndex + 1) of \(fieldEntries.count)")
                            .font(.caption)
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, isHero ? 0 : 24)
                .padding(.bottom, isHero ? 0 : 40)

                if isHero { Spacer() }

                if !isHero && showControls { Spacer() }

                if showControls, let entry = currentEntry {
                    SuggestiveTextField(
                        label: entry.label,
                        placeholder: placeholderText(for: entry.category),
                        text: binding(for: entry.key),
                        source: suggestionSource(for: entry.category),
                        isFocused: true,
                        autoFocus: true
                    )
                    .id(entry.key)
                    .padding(.horizontal, 24)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.3), value: showContent)
                }

                if !isHero && showControls { Spacer() }

                if showControls {
                    PeezyAssessmentButton("Continue") {
                        if currentEntryIndex < fieldEntries.count - 1 {
                            showContent = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                currentEntryIndex += 1
                                showContent = true
                            }
                        } else {
                            assessmentData.fitnessDetails = details
                            coordinator.goToNext()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isHero { skipToControls() }
        }
        .onAppear {
            details = assessmentData.fitnessDetails
        }
    }

    private func triggerMorph() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard isHero else { return }
            performMorph()
        }
    }

    private func performMorph() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            isHero = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.35)) {
                showControls = true
            }
        }
    }

    private func skipToControls() {
        skipped = true
        headerDone = true
        performMorph()
    }

    private func placeholderText(for category: String) -> String {
        switch category {
        case "Gym":         return "e.g. Planet Fitness, Equinox, LA Fitness"
        case "Yoga":        return "e.g. CorePower, local studio name"
        case "Pilates":     return "e.g. Club Pilates, local studio"
        case "CrossFit":    return "e.g. local CrossFit box name"
        case "Swimming":    return "e.g. local pool, YMCA"
        default:            return "e.g. enter membership name"
        }
    }

    private func suggestionSource(for category: String) -> SuggestionSource {
        switch category {
        case "Gym":
            return .mapSearch(category: "gym fitness", nearAddress: assessmentData.currentAddress)
        case "Yoga":
            return .mapSearch(category: "yoga studio", nearAddress: assessmentData.currentAddress)
        case "Pilates":
            return .mapSearch(category: "pilates studio", nearAddress: assessmentData.currentAddress)
        case "CrossFit":
            return .mapSearch(category: "crossfit gym", nearAddress: assessmentData.currentAddress)
        case "Swimming":
            return .mapSearch(category: "swimming pool", nearAddress: assessmentData.currentAddress)
        default:
            return .local([])
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { details[key] ?? "" },
            set: { details[key] = $0 }
        )
    }
}

#Preview {
    let manager = AssessmentDataManager()
    manager.fitnessWellness = ["Gym", "Yoga"]
    manager.fitnessCounts = ["Gym": 2, "Yoga": 1]
    return FitnessDetails()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
