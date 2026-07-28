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
        if ProcessInfo.processInfo.arguments.contains("--estimate-integrity-phase-c") {
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
