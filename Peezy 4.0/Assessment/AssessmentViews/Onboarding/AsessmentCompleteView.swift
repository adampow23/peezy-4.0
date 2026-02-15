//
//  AssessmentCompleteView.swift
//  Peezy
//
//  Three-stage completion experience:
//    Stage 1 — "Generating" with typewriter loading messages (5s minimum)
//    Stage 2 — Animated checkmark with "See Your Custom Plan" button
//    Stage 3 — Confetti reveal + total task count + "Let's Get Started"
//              → routes to PaywallFlowView → then main app
//
//  Presented via .fullScreenCover from AssessmentFlowView when coordinator.isComplete = true.
//  Task generation has ALREADY run in the coordinator before this view appears.
//  This view queries Firestore for the generated tasks to build the summary.
//
//  Dependencies:
//  - AssessmentCoordinator (@EnvironmentObject)
//  - AssessmentDataManager (@EnvironmentObject)
//  - ConfettiView (PeezyTheme folder)
//  - PaywallFlowView (same module)
//  - Firestore SDK (reads users/{uid}/tasks/)
//  - Firebase Auth (current user UID)
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AssessmentCompleteView: View {
    
    @EnvironmentObject var coordinator: AssessmentCoordinator
    @EnvironmentObject var dataManager: AssessmentDataManager
    
    // MARK: - Stage Machine
    
    enum Stage {
        case generating
        case ready
        case summary
    }
    
    @State private var stage: Stage = .generating
    
    // MARK: - Loading Animation State
    
    @State private var activeMessageIndex: Int = 0
    @State private var messageOpacity: Double = 0
    @State private var spinnerRotation: Double = 0
    @State private var messageTimer: Timer? = nil
    
    // MARK: - Ready Stage State
    
    @State private var checkmarkTrim: CGFloat = 0
    @State private var checkmarkCircleTrim: CGFloat = 0
    @State private var checkmarkScale: CGFloat = 0.6
    @State private var readyTextOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    
    // MARK: - Summary State
    
    @State private var showConfetti: Bool = false
    @State private var summaryOpacity: Double = 0
    
    // MARK: - Paywall
    
    @State private var showPaywall: Bool = false
    
    // MARK: - Task Count
    
    @State private var totalTasks: Int = 0
    
    // MARK: - User Name
    
    @State private var userName: String = "Your"
    
    // MARK: - Completion Tracking
    
    @State private var queryComplete: Bool = false
    @State private var timerComplete: Bool = false
    
    // MARK: - Loading Messages
    
    private let loadingMessages: [String] = [
        "Analyzing your move timeline...",
        "Checking logistics requirements...",
        "Evaluating your household needs...",
        "Building your personalized task list...",
        "Matching vendor categories...",
        "Prioritizing by your move date...",
        "Finalizing your custom plan..."
    ]
    
    // MARK: - Theme
    
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            // Subtle gradient overlay
            RadialGradient(
                colors: [
                    Color.blue.opacity(0.08),
                    Color.purple.opacity(0.05),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()
            
            // Stage content
            switch stage {
            case .generating:
                generatingView
                    .transition(.opacity)
            case .ready:
                readyView
                    .transition(.opacity)
            case .summary:
                summaryView
                    .transition(.opacity)
            }
            
            // Confetti overlay
            if showConfetti {
                ConfettiView(isActive: $showConfetti, intensity: .high)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .interactiveDismissDisabled()
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallFlowView()
                .environmentObject(SubscriptionManager.shared)
        }
        .onAppear {
            startLoadingSequence()
        }
        .onDisappear {
            messageTimer?.invalidate()
        }
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - STAGE 1: Generating
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    private var generatingView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 28) {
                // Spinner
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 3)
                        .frame(width: 56, height: 56)
                    
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(
                            AngularGradient(
                                colors: [.cyan, .blue, .purple, .cyan],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(spinnerRotation))
                }
                
                Text(loadingMessages[activeMessageIndex])
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .opacity(messageOpacity)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 24)
                    .animation(.easeInOut(duration: 0.4), value: messageOpacity)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(charcoalColor.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.06), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 48)
            
            Spacer()
        }
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - STAGE 2: Ready
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    private var readyView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 28) {
                // Animated checkmark
                ZStack {
                    Circle()
                        .trim(from: 0, to: checkmarkCircleTrim)
                        .stroke(
                            LinearGradient(
                                colors: [.green.opacity(0.8), .cyan.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                    
                    CheckmarkShape()
                        .trim(from: 0, to: checkmarkTrim)
                        .stroke(
                            Color.green,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 28, height: 28)
                }
                .scaleEffect(checkmarkScale)
                
                VStack(spacing: 8) {
                    Text("Your task list is ready")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("\(totalTasks) tasks customized for your move")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                }
                .opacity(readyTextOpacity)
                
                Button(action: revealSummary) {
                    Text("See Your Custom Plan")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white)
                        )
                }
                .opacity(buttonOpacity)
                .padding(.top, 4)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(charcoalColor.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.06), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 48)
            
            Spacer()
        }
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - STAGE 3: Summary
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    private var summaryView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Text("\(userName) Personalized Moving Plan")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("Here's what we built for you")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                // Total count — hero number
                VStack(spacing: 4) {
                    Text("\(totalTasks)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("personalized tasks")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
            
            // CTA
            Button(action: finishAndContinue) {
                Text("Let's Get Started")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.9)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
        }
        .opacity(summaryOpacity)
    }
    
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Sequence Logic
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    private func startLoadingSequence() {
        // Load user name
        if let name = dataManager.getAllAssessmentData()["userName"] as? String, !name.isEmpty {
            userName = name + "'s"
        }
        
        // Start spinner rotation
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            spinnerRotation = 360
        }
        
        // Fade in first message
        withAnimation(.easeIn(duration: 0.3)) {
            messageOpacity = 1
        }
        
        // Cycle messages every ~1.8 seconds so each can be read
        messageTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { timer in
            withAnimation(.easeOut(duration: 0.2)) {
                messageOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                activeMessageIndex = (activeMessageIndex + 1) % loadingMessages.count
                withAnimation(.easeIn(duration: 0.3)) {
                    messageOpacity = 1
                }
            }
        }
        
        // Minimum timer (7 seconds) — enough to show several messages at a readable pace
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            timerComplete = true
            checkTransitionToReady()
        }
        
        // Query tasks from Firestore
        fetchTaskCount()
    }
    
    private func fetchTaskCount() {
        guard let uid = Auth.auth().currentUser?.uid else {
            queryComplete = true
            totalTasks = 0
            checkTransitionToReady()
            return
        }
        
        let db = Firestore.firestore()
        
        Task {
            do {
                let snapshot = try await db.collection("users").document(uid)
                    .collection("tasks")
                    .getDocuments()
                
                var total = 0
                
                for doc in snapshot.documents {
                    let data = doc.data()
                    
                    // Skip parent containers
                    let taskType = data["taskType"] as? String ?? ""
                    if taskType == "miniAssessmentParent" { continue }
                    
                    // Skip already completed/skipped
                    let status = data["status"] as? String ?? "Upcoming"
                    guard status != "Completed" && status != "Skipped" else { continue }
                    
                    total += 1
                }
                
                await MainActor.run {
                    totalTasks = total
                    queryComplete = true
                    checkTransitionToReady()
                }
            } catch {
                await MainActor.run {
                    queryComplete = true
                    checkTransitionToReady()
                }
            }
        }
    }
    
    private func checkTransitionToReady() {
        guard queryComplete && timerComplete else { return }
        
        messageTimer?.invalidate()
        messageTimer = nil
        
        withAnimation(.easeInOut(duration: 0.4)) {
            stage = .ready
        }
        
        animateCheckmark()
    }
    
    private func animateCheckmark() {
        withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
            checkmarkCircleTrim = 1.0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.6)) {
            checkmarkTrim = 1.0
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.5)) {
            checkmarkScale = 1.0
        }
        withAnimation(.easeIn(duration: 0.4).delay(0.9)) {
            readyTextOpacity = 1.0
        }
        withAnimation(.easeIn(duration: 0.4).delay(1.2)) {
            buttonOpacity = 1.0
        }
    }
    
    private func revealSummary() {
        showConfetti = true
        
        withAnimation(.easeInOut(duration: 0.5)) {
            stage = .summary
        }
        withAnimation(.easeIn(duration: 0.6).delay(0.3)) {
            summaryOpacity = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(.easeOut(duration: 1.0)) {
                showConfetti = false
            }
        }
    }
    
    private func finishAndContinue() {
        showPaywall = true
    }
}

// MARK: - Checkmark Shape

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.15, y: rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.width * 0.40, y: rect.height * 0.80))
        path.addLine(to: CGPoint(x: rect.width * 0.85, y: rect.height * 0.20))
        return path
    }
}

// MARK: - Preview

#Preview {
    AssessmentCompleteView()
        .environmentObject(AssessmentCoordinator(dataManager: AssessmentDataManager()))
        .environmentObject(AssessmentDataManager())
}
