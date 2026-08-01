//
//  AssessmentFlowView.swift
//  Peezy
//
//  Hosts the entire assessment flow.
//  Each question view owns its full page (typewriter, morph, tiles, everything).
//  This view only provides the progress bar and routes to the right question.
//

import SwiftUI

struct AssessmentFlowView: View {
    
    @Binding var showAssessment: Bool
    @StateObject private var coordinator: AssessmentCoordinator
    @StateObject private var dataManager: AssessmentDataManager
    @State private var didLogAssessmentStart = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    init(showAssessment: Binding<Bool>) {
        _showAssessment = showAssessment
        let dm = AssessmentDataManager()
        _dataManager = StateObject(wrappedValue: dm)
        _coordinator = StateObject(wrappedValue: AssessmentCoordinator(dataManager: dm))
    }
    
    var body: some View {
        ZStack {
            // Background ignores keyboard so it doesn't squish
            InteractiveBackground()
                .ignoresSafeArea(.keyboard)
            
            // Content VStack — SwiftUI shrinks this naturally when keyboard appears
            VStack(spacing: 0) {
                // Progress bar — stays pinned at top
                if coordinator.currentNode != nil {
                    progressBar
                        .transition(.opacity)
                }
                
                // Question — each one owns its full layout
                if let node = coordinator.currentNode {
                    questionView(for: node)
                        .id(coordinator.currentIndex)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(
                reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.85),
                value: coordinator.currentIndex
            )
        }
        .environmentObject(coordinator)
        .environmentObject(dataManager)
        .onAppear {
            guard !didLogAssessmentStart else { return }
            didLogAssessmentStart = true
            AnalyticsEvents.assessmentStarted()
        }
        .fullScreenCover(isPresented: $coordinator.isComplete) {
            CompletionFlowView(coordinator: coordinator)
                .environmentObject(SubscriptionManager.shared)
        }
    }
    
    // MARK: - Chapter Tracker
    
    private var progressBar: some View {
        let step = coordinator.currentNode?.inputStep ?? .userName
        let chapterProgress = coordinator.chapterProgress(for: step)
        let chapter = chapterProgress.chapter

        return VStack(spacing: 7) {
            HStack {
                if coordinator.currentInputStepNumber > 1 {
                    Button {
                        coordinator.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                    }
                }
                
                Text(chapter.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(chapter.accent)

                Spacer()

                Text("\(chapterProgress.position) of \(chapterProgress.total)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.45))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(chapter.accent.opacity(0.12))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [chapter.accent.opacity(0.45), chapter.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * chapterProgress.fraction, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: chapterProgress.fraction)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chapter.title), question \(chapterProgress.position) of \(chapterProgress.total)")
        .accessibilityIdentifier("assessment.chapter.\(chapter.rawValue)")
    }
    
    // MARK: - Question Routing
    
    @ViewBuilder
    private func questionView(for node: AssessmentNode) -> some View {
        switch node {
        case .input(let step):
            VStack(spacing: 0) {
                // Reflect-back beat (Spec 04 Phase E): confirmation banner on
                // the question following pets / kids / address pair / services.
                if let reflectText = coordinator.reflectBack(for: step) {
                    ReflectBackBanner(text: reflectText)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                PeezyLucideIcon(
                    id: PeezyQuestionVisuals.assessmentIcon(for: step),
                    size: 54,
                    color: PeezyQuestionVisuals.chapter(for: step).accent.opacity(0.78)
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .accessibilityIdentifier("assessment.questionIcon.\(step.rawValue)")

                questionContent(for: step)
            }
        }
    }
    
    @ViewBuilder
    private func questionContent(for step: AssessmentInputStep) -> some View {
        switch step {
        // --- Section 1: Basics ---
        case .userName:              UserName()
        case .moveDate:              MoveDate()
        case .moveDateType:          MoveDateType()

        // --- Section 2: Current Home ---
        case .currentRentOrOwn:      CurrentRentOrOwn()
        case .currentDwellingType:   CurrentDwellingType()
        case .currentAddress:        CurrentAddress()
        case .currentFloorAccess:    CurrentFloorAccess()
        case .currentBedrooms:       CurrentBedrooms()

        // --- Section 3: New Home ---
        case .newRentOrOwn:          NewRentOrOwn()
        case .newDwellingType:       NewDwellingType()
        case .newAddress:            NewAddress()
        case .newFloorAccess:        NewFloorAccess()
        case .newBedrooms:           NewBedrooms()

        // --- Storage (with home details) ---
        case .hasStorage:            HasStorage()
        case .storageSize:           StorageSize()
        case .storageFullness:       StorageFullness()

        // --- Section 4: People ---
        case .anyKids:               AnyKids()
        case .childrenInSchool:      ChildrenInSchool()
        case .childrenInDaycare:     ChildrenInDaycare()
        case .hasVet:                HasVet()
        case .hasVehicles:           HasVehicles()

        // --- Section 5: Services ---
        case .servicesIntro:         ServicesIntro()
        case .hireMovers:            HireMovers()
        case .truckRental:           TruckRental()
        case .hasDeclutter:          HasDeclutter()
        case .wantToSell:            WantToSell()
        case .hireCleaners:          HireCleaners()

        // --- Section 6: Accounts ---
        case .addressChangeIntro:    AddressChangeIntro()
        case .financialInstitutions: FinancialInstitutions()
        case .healthcareProviders:   HealthcareProviders()
        case .fitnessWellness:       FitnessWellness()

        // --- Wrap-up ---
        case .howHeard:              HowHeard()

        default:                     EmptyView()
        }
    }
}

// MARK: - Reflect-Back Banner (Spec 04 Phase E)

/// Confirmation beat rendered above the question that follows it —
/// "your answer just did something" made visible.
struct ReflectBackBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PeezyTheme.Colors.successGreen)

            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PeezyTheme.Colors.successGreen.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PeezyTheme.Colors.successGreen.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .accessibilityIdentifier("assessment.reflect_back")
    }
}

#if DEBUG
#Preview {
    AssessmentFlowView(showAssessment: .constant(true))
}
#endif
