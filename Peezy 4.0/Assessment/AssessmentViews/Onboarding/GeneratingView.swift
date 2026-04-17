//
//  GeneratingView.swift
//  Peezy
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct GeneratingView: View {

    let isSaving: Bool
    let onTasksCounted: (Int) -> Void
    let onReady: () -> Void

    // MARK: - Animation State

    @State private var activeMessageIndex: Int = 0
    @State private var messageOpacity: Double = 0
    @State private var progress: Double = 0 // Replaced spinner with 0-100% progress
    @State private var messageTimer: Timer? = nil
    @State private var progressTimer: Timer? = nil

    // MARK: - Completion Tracking

    @State private var timerComplete: Bool = false
    @State private var queryComplete: Bool = false
    @State private var generationComplete: Bool = false

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

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 36) { // Increased breathing room
                
                // 0-100% Radial Progress
                ZStack {
                    // Subtle background track
                    Circle()
                        .stroke(PeezyTheme.Colors.deepInk.opacity(0.06), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    
                    // Vibrant glowing progress track
                    Circle()
                        .trim(from: 0, to: CGFloat(progress) / 100.0)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.cyan, .blue, .purple, .cyan]),
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: .purple.opacity(0.3), radius: 10, x: 0, y: 4)
                    
                    // Monospaced, stable percentage
                    Text("\(Int(progress))%")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: progress))
                        .foregroundColor(PeezyTheme.Colors.deepInk)
                }
                .frame(width: 160, height: 160) // Scaled up for premium impact

                // Cycling Messages
                Text(loadingMessages[activeMessageIndex])
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.8))
                    .opacity(messageOpacity)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 24)
                    .animation(.easeInOut(duration: 0.4), value: messageOpacity)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 48)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.2))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1.5) // Adds a frosted glass "lip"
            )
            .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 40)

            Spacer()
        }
        .onAppear {
            startLoadingSequence()
        }
        .onDisappear {
            messageTimer?.invalidate()
            progressTimer?.invalidate()
        }
        .onChange(of: isSaving) { _, newValue in
            if !newValue && !generationComplete {
                generationComplete = true
                // Small delay to ensure Firestore batch write has committed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    fetchTaskCount()
                }
            }
        }
    }

    // MARK: - Sequence Logic

    private func startLoadingSequence() {
        let countUpTickInterval = 0.082
        let creepTickInterval = 0.8

        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: countUpTickInterval, repeats: true) { timer in
            guard progress < 85 else {
                timer.invalidate()
                progressTimer = Timer.scheduledTimer(withTimeInterval: creepTickInterval, repeats: true) { creepTimer in
                    guard !queryComplete, progress < 95 else {
                        creepTimer.invalidate()
                        return
                    }

                    withAnimation(.linear(duration: creepTickInterval)) {
                        progress = min(progress + 1, 95)
                    }
                }
                return
            }

            withAnimation(.linear(duration: countUpTickInterval)) {
                progress = min(progress + 1, 85)
            }
        }

        // Fade in first message
        withAnimation(.easeIn(duration: 0.3)) {
            messageOpacity = 1
        }

        // Cycle messages
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

        // Minimum timer (7 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            timerComplete = true
            checkReady()
        }

        // Failsafe
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            timerComplete = true
            queryComplete = true
            checkReady()
        }

        if !isSaving {
            generationComplete = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                fetchTaskCount()
            }
        }
    }

    // MARK: - Firestore Task Count (Untouched Logic)
    private func fetchTaskCount() {
        guard let uid = Auth.auth().currentUser?.uid else {
            queryComplete = true
            onTasksCounted(0)
            checkReady()
            return
        }

        let db = Firestore.firestore()

        Task {
            var lastCount = -1
            var finalCount = 0

            // Poll up to 3 times, 1.5s apart, to let Firestore batch writes settle
            for attempt in 0..<3 {
                // Wait before each attempt (except the first) to let writes complete
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
                }

                do {
                    let snapshot = try await db.collection("users").document(uid)
                        .collection("tasks")
                        .getDocuments()

                    var total = 0
                    for doc in snapshot.documents {
                        let data = doc.data()
                        let taskType = data["taskType"] as? String ?? ""
                        if taskType == "miniAssessmentParent" { continue }

                        let status = data["status"] as? String ?? "Upcoming"
                        guard status != "Completed" && status != "Skipped" else { continue }

                        total += 1
                    }

                    finalCount = total

                    // If this count matches the previous one, writes have settled - we're done
                    if total == lastCount && total > 0 {
                        break
                    }
                    lastCount = total
                } catch {
                    // On error, keep the last good count and exit
                    break
                }
            }

            await MainActor.run {
                onTasksCounted(finalCount)
                queryComplete = true
                checkReady()
            }
        }
    }

    private func checkReady() {
        guard queryComplete && timerComplete else { return }

        messageTimer?.invalidate()
        messageTimer = nil
        progressTimer?.invalidate()
        progressTimer = nil

        // Visually complete the circle before moving to ReadyView
        withAnimation(.easeOut(duration: 0.4)) {
            progress = 100
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onReady()
        }
    }
}
