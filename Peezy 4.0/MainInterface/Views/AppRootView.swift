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

struct AppRootView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @State private var appState: AppState = .loading
    @State private var showAssessment = false
    @State private var userState: UserState?  // Holds user context for Peezy
    
    var body: some View {
        Group {
            switch appState {
            case .loading:
                AppLoadingView()
                
            case .notAuthenticated:
                AuthView()
                    .environmentObject(authViewModel)
                
            case .needsAssessment:
                if showAssessment {
                    AssessmentFlowView(showAssessment: $showAssessment)                } else {
                    AssessmentIntroView(showAssessment: $showAssessment)
                }
                
            case .hasAssessment:
                PeezyMainContainer(userState: $userState)
                    .environmentObject(authViewModel)
            }
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
            if isAuthenticated {
                checkAssessmentStatus()
            } else {
                appState = .notAuthenticated
                userState = nil
            }
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
        
        let db = Firestore.firestore()
        db.collection("users")
            .document(userId)
            .collection("user_assessments")
            .limit(to: 1)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    // Guard against stale callback if user signed out during fetch
                    guard Auth.auth().currentUser != nil else {
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
                        
                        // Build UserState from assessment data
                        let assessmentData = document.data()
                        self.userState = UserState(userId: userId, from: assessmentData)
                        
                        appState = .hasAssessment
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
                        .fill(PeezyTheme.Colors.brandYellow.opacity(0.15))
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .strokeBorder(PeezyTheme.Colors.brandYellow.opacity(0.3), lineWidth: 1)
                        .frame(width: 100, height: 100)
                    
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(PeezyTheme.Colors.brandYellow)
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
                        .strokeBorder(PeezyTheme.Colors.brandYellow.opacity(0.15), lineWidth: 0.5)
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
