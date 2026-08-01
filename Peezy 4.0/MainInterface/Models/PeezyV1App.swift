//
//  PeezyV1App.swift
//  PeezyV1.0
//
//  Updated by user285836 on 11/11/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseCrashlytics
import GoogleSignIn

@main
struct PeezyV1App: App {

    // This runs ONCE when the app launches, before any views appear
    init() {
        FirebaseApp.configure()
        _ = Crashlytics.crashlytics()
        // Start StoreKit transaction listener early
        _ = SubscriptionManager.shared
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .preferredColorScheme(.light)
                .environmentObject(SubscriptionManager.shared)
                .onOpenURL { url in
                    // Handle Google Sign-In URL callback
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onReceive(SubscriptionManager.shared.$subscriptionStatus) { status in
                    AnalyticsEvents.setHasSubscription(status.isActive)
                }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--phase-a-flow-exit-saved") {
            PhaseASavedExitFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--phase-a-flow-exit") {
            PhaseAFlowExitFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--estimate-integrity-phase-f-booked") {
            EstimateIntegrityPhaseFCheckInFixture(booked: true)
        } else if ProcessInfo.processInfo.arguments.contains("--estimate-integrity-phase-f-general") {
            EstimateIntegrityPhaseFCheckInFixture(booked: false)
        } else if ProcessInfo.processInfo.arguments.contains("--estimate-integrity-phase-d") {
            EstimateIntegrityPhaseDStorageFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--estimate-integrity-phase-c") {
            EstimateIntegrityPhaseCConciergeFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--estimate-integrity-phase-b") {
            EstimateIntegrityPhaseBCoverageFixture()
        } else {
            AppRootView()
        }
        #else
        AppRootView()
        #endif
    }
}

#if DEBUG
private struct PhaseASavedExitFixture: View {
    @State private var isPresented = true

    var body: some View {
        if isPresented {
            OutermostTaskFlowContainer(
                userId: "phase-a-fixture",
                taskId: "PHASE_A_SAVED_FIXTURE",
                onDismiss: { isPresented = false }
            ) { _ in
                PhaseASavedAnswerContent()
            }
        } else {
            Text("TERMINAL: saved flow dismissed")
                .accessibilityIdentifier("phase_a.saved_terminal")
        }
    }
}

private struct PhaseASavedAnswerContent: View {
    @Environment(FlowExitCoordinator.self) private var coordinator

    var body: some View {
        Text("Saved answer fixture")
            .task {
                coordinator.noteExternallyPersistedAnswer(
                    path: ["saved_step"],
                    answers: ["saved_step": ["answer"]]
                )
            }
    }
}

private struct PhaseAFlowExitFixture: View {
    @State private var routeIndex = 0
    @State private var completedRoutes: [String] = []

    private let runID = ProcessInfo.processInfo.environment["PHASE_A_RUN_ID"] ?? "default"

    private let routes: [String] = {
        let raw = ProcessInfo.processInfo.environment["PHASE_A_FLOW_IDS"] ?? "manage_bank"
        return raw.split(separator: ",").map(String.init)
    }()

    var body: some View {
        ZStack {
            if routeIndex < routes.count {
                let route = routes[routeIndex]
                TaskFlowRouter.flow(
                    for: route,
                    userId: "phase-a-fixture",
                    taskId: "PHASE_A_\(runID)_\(route.uppercased())",
                    userState: nil,
                    onComplete: { finish(route) },
                    onDismiss: { finish(route) },
                    onStatusAction: { _ in finish(route) }
                )
                .id(route)

                VStack {
                    HStack {
                        Text("ROUTE \(routeIndex + 1)/\(routes.count): \(route)")
                            .font(.caption2.bold())
                            .padding(6)
                            .background(.black.opacity(0.72), in: Capsule())
                            .foregroundStyle(.white)
                            .accessibilityIdentifier("phase_a.current_route")
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 58)
                .padding(.leading, 8)
                .allowsHitTesting(false)
                .zIndex(200)
            } else {
                Text("TERMINAL: dismissed \(completedRoutes.count)/\(routes.count) routes")
                    .font(.headline)
                    .accessibilityIdentifier("phase_a.flow_terminal")
            }
        }
    }

    private func finish(_ route: String) {
        completedRoutes.append(route)
        routeIndex += 1
    }
}

private struct EstimateIntegrityPhaseFCheckInFixture: View {
    let booked: Bool

    private var bookingContext: CheckInBookingContext? {
        guard booked else { return nil }
        return CheckInBookingContext(
            vendorId: "test_mover_a",
            vendorName: "Test Mover A",
            estimatedRange: CheckInEstimatedRange(low: 1_200, high: 1_600),
            scopeSnapshot: [
                "cubicFeet": 980,
                "driveMinutes": 45
            ]
        )
    }

    var body: some View {
        MoveCheckInView(
            userId: "phase-f-fixture",
            taskId: "MOVE_CHECKIN_FIXTURE",
            onDismiss: {},
            onStatusAction: { _ in },
            fixtureBookingContext: bookingContext,
            fixtureContextLoaded: true
        )
    }
}

@MainActor
private struct EstimateIntegrityPhaseDStorageFixture: View {
    @State private var model = MoversFlowViewModel()

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()
            MoveRefinementView(model: model, onContinue: {}, onBack: {})
        }
    }
}

private struct EstimateIntegrityPhaseCConciergeFixture: View {
    @State private var notes = ""

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()
            MoversConciergeQuoteCard(
                copy: MoversConciergeReason.physicalHours.copy,
                notes: $notes,
                errorMessage: nil,
                isSubmitting: false,
                onBack: {},
                onSubmit: {}
            )
        }
    }
}

@MainActor
private struct EstimateIntegrityPhaseBCoverageFixture: View {
    @State private var sessionManager = InventorySessionManager()
    @State private var didConfigure = false

    var body: some View {
        InventoryRoomHubView(
            sessionManager: sessionManager,
            onDismiss: {},
            onSubmitted: {}
        )
        .onAppear {
            guard !didConfigure else { return }
            didConfigure = true
            sessionManager.state = .roomList
            sessionManager.configureCoverage(
                bedroomsAnswer: "2 Bedrooms",
                dwellingType: "House"
            )
            sessionManager.scannedRooms = [
                room("Family Room"),
                room("Kitchen"),
                room("Bathroom"),
                room("Bedroom 1"),
                room("Garage"),
                room("Office")
            ]
        }
    }

    private func room(_ name: String) -> ScannedRoom {
        ScannedRoom(
            id: name.lowercased().replacingOccurrences(of: " ", with: "-"),
            name: name,
            items: [],
            scannedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}
#endif
