//
//  AppRootView.swift
//  Peezy 4.0
//
//  Updated to use PeezyStackView with UserState
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// Note: Notification.Name.assessmentCompleted and .retakeAssessment are defined in AssessmentCoordinator.swift

enum AppState {
    case loading
    case notAuthenticated
    case needsAssessment
    case hasAssessment
}

/// S4 (P1-R): an assessment or `UserState` async completion is applied only while the UID that started it is still
/// current and the load token minted for that start is still the live one.
struct AppRootLoadGuard: Equatable, Sendable {
    let uid: String
    let token: UUID

    func admits(currentUID: String?, liveToken: UUID) -> Bool { currentUID == uid && liveToken == token }
}

/// Renders the C2.5 completion surface over the root while the presenter holds a snapshot (S7 supplies the model).
struct AccountDeletionCompletionHost: View {
    @ObservedObject var model: DurableStoreRecoveryModel

    var body: some View {
        if let completion = model.completion {
            List {
                AccountDeletionCompletionSurface(content: CompletionSurfaceContent.content(for: completion.result), open: { provider in _ = await model.open(provider) }, done: { _ = await model.acknowledgeCompletion() })
            }
            .task { await model.refresh() }
        }
    }
}

struct AppRootView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @State private var appState: AppState = .loading
    @State private var showAssessment = false
    @State private var userState: UserState?  // Holds user context for Peezy
    @State private var explainerSeen = UserDefaults.standard.bool(forKey: "peezy.explainer.seen")
    /// The live load token; every start of an assessment/UserState load mints a new one (P1-R).
    @State private var loadToken = UUID()
    /// The recovery model S7 mounts; nil keeps the root exactly as before (no completion surface).
    var recoveryModel: DurableStoreRecoveryModel? = nil

    var body: some View {
        ZStack {
            rootContent
            if let recoveryModel {
                AccountDeletionCompletionHost(model: recoveryModel)
            }
        }
    }

    private var rootContent: some View {
        Group {
            #if DEBUG
            // Spec 04 validation harness — active only when launched with
            // FLOW_HARNESS_WORKFLOW in the environment; inert in normal runs.
            if FlowEngineHarness.isActive {
                FlowEngineHarness()
            } else {
                appStateContent
            }
            #else
            appStateContent
            #endif
        }
        .onAppear {
            checkAppState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .assessmentCompleted)) { _ in
            #if DEBUG
            print("📢 Received AssessmentCompleted notification - rechecking state")
            #endif
            checkAssessmentStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .retakeAssessment)) { _ in
            #if DEBUG
            print("📢 Received retakeAssessment notification - routing to assessment")
            #endif
            userState = nil
            checkAssessmentStatus()
        }
        .onChange(of: authViewModel.isAuthenticated) { _, isAuthenticated in
            loadToken = UUID() // every auth transition retires the in-flight loads
            if isAuthenticated {
                checkAssessmentStatus()
            } else {
                appState = .notAuthenticated
                userState = nil
            }
        }
    }

    @ViewBuilder
    private var appStateContent: some View {
        switch appState {
        case .loading:
            AppLoadingView()

        case .notAuthenticated:
            if !explainerSeen {
                ExplainerView(onFinished: {
                    explainerSeen = true
                })
            } else {
                AuthView()
                    .environmentObject(authViewModel)
            }

        case .needsAssessment:
            if showAssessment {
                AssessmentFlowView(showAssessment: $showAssessment)
            } else {
                AssessmentIntroView(showAssessment: $showAssessment)
            }

        case .hasAssessment:
            PeezyMainContainer(userState: $userState)
                .environmentObject(authViewModel)
        }
    }

    // MARK: - State Management
    
    private func checkAppState() {
        #if DEBUG
        print("🔍 checkAppState() called - currentUser: \(Auth.auth().currentUser?.uid ?? "nil")")
        #endif
        if let user = Auth.auth().currentUser {
            #if DEBUG
            print("🔍 User found: \(user.uid) - setting isAuthenticated = true")
            #endif
            authViewModel.currentUser = user
            authViewModel.isAuthenticated = true
            checkAssessmentStatus()
        } else {
            #if DEBUG
            print("🔍 No user found - setting appState = .notAuthenticated")
            #endif
            appState = .notAuthenticated
        }
    }
    
    private func checkAssessmentStatus() {
        #if DEBUG
        print("🔍 checkAssessmentStatus() called - currentUser: \(Auth.auth().currentUser?.uid ?? "nil")")
        #endif
        guard let userId = Auth.auth().currentUser?.uid else {
            #if DEBUG
            print("🔍 No userId in checkAssessmentStatus - setting appState = .notAuthenticated")
            #endif
            appState = .notAuthenticated
            return
        }
        #if DEBUG
        print("🔍 Checking assessment for userId: \(userId)")
        #endif
        let token = UUID()
        loadToken = token
        let guardToken = AppRootLoadGuard(uid: userId, token: token)

        let db = FirestoreRuntime.firestore()
        db.collection("users")
            .document(userId)
            .collection("user_assessments")
            .limit(to: 1)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    // P1-R: a stale callback (sign-out, A→B, or a later load) is dropped before any state changes
                    guard guardToken.admits(currentUID: Auth.auth().currentUser?.uid, liveToken: loadToken) else {
                        return
                    }
                    
                    if let error = error {
                        #if DEBUG
                        print("❌ Error checking assessment status: \(error)")
                        #endif
                        appState = .needsAssessment
                        return
                    }

                    if let snapshot = snapshot, let document = snapshot.documents.first {
                        #if DEBUG
                        print("✅ User has completed assessment")
                        #endif

                        // Build UserState from assessment data + identity doc
                        // (migrating the identity doc on first launch if absent)
                        let assessmentData = document.data()
                        Task { @MainActor in
                            let loaded = await UserState.load(userId: userId, assessment: assessmentData)
                            guard guardToken.admits(currentUID: Auth.auth().currentUser?.uid, liveToken: loadToken) else { return }
                            self.userState = loaded
                            self.appState = .hasAssessment
                        }
                    } else {
                        #if DEBUG
                        print("📝 User needs to complete assessment")
                        #endif
                        appState = .needsAssessment
                    }
                }
            }
    }
}

// MARK: - App Loading View

struct AppLoadingView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Peezy logo or icon with liquid glass background
                ZStack {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 100, height: 100)
                        .peezyLiquidGlass(
                            cornerRadius: 50,
                            intensity: 0.55,
                            speed: 0.22,
                            tintOpacity: 0.05,
                            highlightOpacity: 0.12
                        )
                    
                    Circle()
                        .fill(PeezyTheme.Colors.deepInk.opacity(0.15))
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .strokeBorder(PeezyTheme.Colors.deepInk.opacity(0.3), lineWidth: 1)
                        .frame(width: 100, height: 100)
                    
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(PeezyTheme.Colors.deepInk)
                }
                
                Text("Loading...")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(40)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.clear)
                        .peezyLiquidGlass(
                            cornerRadius: 24,
                            intensity: 0.55,
                            speed: 0.22,
                            tintOpacity: 0.05,
                            highlightOpacity: 0.12
                        )
                    
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(PeezyTheme.Colors.deepInk.opacity(0.15), lineWidth: 0.5)
                }
            )
            .shadow(
                color: Color.black.opacity(0.1),
                radius: 20,
                y: 10
            )
        }
    }
}

#Preview {
    AppRootView()
}
