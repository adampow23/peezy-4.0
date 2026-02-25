//
//  GeneratingView.swift
//  Peezy
//
//  Stage 1 of the completion flow: Shows while tasks are being generated.
//  Displays a spinner with cycling loading messages.
//  Waits for both: (a) minimum 7s timer, (b) Firestore task count query.
//  Calls onReady when both conditions are met.
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
    @State private var spinnerRotation: Double = 0
    @State private var messageTimer: Timer? = nil

    // MARK: - Completion Tracking

    @State private var timerComplete: Bool = false
    @State private var queryComplete: Bool = false
    @State private var generationComplete: Bool = false

    // MARK: - Loading Messages (from original)

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

            VStack(spacing: 28) {
                // Spinner
                ZStack {
                    Circle()
                        .stroke(PeezyTheme.Colors.deepInk.opacity(0.08), lineWidth: 3)
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
                    .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.8))
                    .opacity(messageOpacity)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 24)
                    .animation(.easeInOut(duration: 0.4), value: messageOpacity)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 48)

            Spacer()
        }
        .onAppear {
            startLoadingSequence()
        }
        .onDisappear {
            messageTimer?.invalidate()
        }
        .onChange(of: isSaving) { _, newValue in
            if !newValue && !generationComplete {
                generationComplete = true
                fetchTaskCount()
            }
        }
    }

    // MARK: - Sequence Logic

    private func startLoadingSequence() {
        // Start spinner rotation
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            spinnerRotation = 360
        }

        // Fade in first message
        withAnimation(.easeIn(duration: 0.3)) {
            messageOpacity = 1
        }

        // Cycle messages every ~1.8 seconds
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

        // Failsafe: force transition after 15 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            timerComplete = true
            queryComplete = true
            checkReady()
        }

        // If generation is already done by the time we appear, fetch now
        if !isSaving {
            generationComplete = true
            fetchTaskCount()
        }
    }

    // MARK: - Firestore Task Count (copied from original AssessmentCompleteView)

    private func fetchTaskCount() {
        guard let uid = Auth.auth().currentUser?.uid else {
            queryComplete = true
            onTasksCounted(0)
            checkReady()
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
                    onTasksCounted(total)
                    queryComplete = true
                    checkReady()
                }
            } catch {
                await MainActor.run {
                    onTasksCounted(0)
                    queryComplete = true
                    checkReady()
                }
            }
        }
    }

    private func checkReady() {
        guard queryComplete && timerComplete else { return }

        messageTimer?.invalidate()
        messageTimer = nil

        onReady()
    }
}
