//
//  PeezyV1App.swift
//  PeezyV1.0
//
//  Updated by user285836 on 11/11/25.
//

import SwiftUI
import UserNotifications
import FirebaseCore
import FirebaseAuth
import FirebaseCrashlytics
import FirebaseFirestore
import FirebaseMessaging
import GoogleSignIn

final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var pendingFCMToken: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        _ = Crashlytics.crashlytics()

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        PushNotificationAuthorization.registerIfAlreadyAuthorized(application)

        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self, let user else { return }
            guard let token = self.pendingFCMToken ?? Messaging.messaging().fcmToken else { return }
            self.persist(token: token, userId: user.uid)
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        pendingFCMToken = fcmToken

        guard let userId = Auth.auth().currentUser?.uid else { return }
        persist(token: fcmToken, userId: userId)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.notification.request.content.userInfo["thread"] as? String == "support" else {
            completionHandler()
            return
        }

        Task { @MainActor in
            SupportChatNavigation.requestOpen()
            completionHandler()
        }
    }

    private func persist(token: String, userId: String) {
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("fcmTokens")
            .document(token)
            .setData([
                "createdAt": FieldValue.serverTimestamp(),
                "platform": "ios"
            ], merge: true) { error in
                if let error {
                    print("Failed to sync push token: \(error.localizedDescription)")
                }
            }
    }
}

enum PushNotificationAuthorization {
    static func request() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("Notification authorization failed: \(error.localizedDescription)")
            }
            guard granted else { return }

            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    static func registerIfAlreadyAuthorized(_ application: UIApplication) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }
}

@main
struct PeezyV1App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // This runs ONCE when the app launches, before any views appear
    init() {
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
        } else if ProcessInfo.processInfo.arguments.contains("--phase-b-provider-requirements") {
            PhaseBProviderRequirementsFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--estimate-integrity-phase-f-booked") {
            EstimateIntegrityPhaseFCheckInFixture(booked: true)
        } else if ProcessInfo.processInfo.arguments.contains("--estimate-integrity-phase-f-general") {
            EstimateIntegrityPhaseFCheckInFixture(booked: false)
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
private struct PhaseBProviderRequirementsFixture: View {
    private let citationURL = "https://provider.example/cancellation-policy"

    private var moveDate: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 30)) ?? Date()
    }

    var body: some View {
        ProviderActionCard(
            taskTitle: "Handle my memberships",
            resolution: ProviderResolution(
                providerId: "phase-b-fixture",
                name: "Example Gym",
                method: .link,
                url: URL(string: citationURL),
                phone: nil,
                citations: [ProviderCitation(url: citationURL, title: "Official cancellation policy")],
                requirements: [
                    ProviderRequirement(
                        kind: .noticePeriod,
                        text: "Give 30 days' notice before cancellation.",
                        noticeDays: 30,
                        citationUrl: citationURL
                    )
                ]
            ),
            actionKind: .cancellation,
            userId: "phase-b-fixture",
            showBack: false,
            onDone: {},
            onBack: {},
            identityOverride: PeezyIdentity(
                name: "Phase B",
                email: "phase-b@example.com",
                moveDate: moveDate
            )
        )
    }
}

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
