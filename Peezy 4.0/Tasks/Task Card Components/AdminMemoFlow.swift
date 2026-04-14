//
//  AdminMemoFlow.swift
//  Peezy 4.0
//
//  A read-only memo card pushed by the admin dashboard.
//  Shows a title, body message, and optional action items.
//  User taps "Got it" to mark as read/complete.
//
//  Firestore task document shape:
//  {
//    workflowId: "admin_memo",
//    title: "Update on your movers",
//    desc: "Quick update from Peezy",
//    status: "Upcoming",
//    priority: "High",
//    memoBody: "We reached out to 3 companies. Two Men and a Truck...",
//    memoSubtext: "We'll follow up once we hear back." (optional)
//  }
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct AdminMemoFlow: View {
    let taskId: String
    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    @State private var currentCard = 0
    @State private var memoTitle = "Update from Peezy"
    @State private var memoBody = ""
    @State private var memoSubtext: String?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(PeezyTheme.Colors.deepInk)
                    Text("Loading...")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                    Text(error)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                cardContent
                    .peezyCardChrome()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            TaskFlowDismissButton(onDismiss: onDismiss)
        }
        .task {
            await loadMemoData()
        }
    }

    // MARK: - Card Content

    @ViewBuilder
    private var cardContent: some View {
        switch currentCard {
        case 0:
            titleCard
        case 1:
            memoCard
        default:
            EmptyView()
        }
    }

    // MARK: - Title Card

    private var titleCard: some View {
        TaskFlowTitleCard(
            taskTitle: memoTitle,
            icon: "envelope.fill",
            onContinue: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    currentCard = 1
                }
            }
        )
    }

    // MARK: - Memo Card

    private var memoCard: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: memoTitle, showBack: true, onBack: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    currentCard = 0
                }
            })

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.2))

                Text(memoBody)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.7))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtext = memoSubtext, !subtext.isEmpty {
                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                        .frame(width: 40, height: 1.5)

                    Text(subtext)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            PeezyAssessmentButton("Got it") {
                markAsRead()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Load

    private func loadMemoData() async {
        guard !taskId.isEmpty else {
            loadError = "No memo to display"
            isLoading = false
            return
        }

        do {
            let db = Firestore.firestore()
            let doc = try await db.collection("users")
                .document(userId)
                .collection("tasks")
                .document(taskId)
                .getDocument()

            guard let data = doc.data() else {
                loadError = "Memo not found"
                isLoading = false
                return
            }

            await MainActor.run {
                memoTitle = data["title"] as? String ?? "Update from Peezy"
                memoBody = data["memoBody"] as? String ?? data["desc"] as? String ?? ""
                memoSubtext = data["memoSubtext"] as? String

                if memoBody.isEmpty {
                    loadError = "No content in this memo"
                }

                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = "Failed to load memo"
                isLoading = false
            }
        }
    }

    // MARK: - Mark Read

    private func markAsRead() {
        Task {
            let db = Firestore.firestore()
            try? await db.collection("users")
                .document(userId)
                .collection("tasks")
                .document(taskId)
                .updateData([
                    "status": "Completed",
                    "completedAt": FieldValue.serverTimestamp(),
                    "readAt": FieldValue.serverTimestamp()
                ])
        }
        onComplete()
    }
}

#if DEBUG
#Preview("Admin Memo") {
    AdminMemoFlow(
        taskId: "preview",
        userId: "preview",
        onComplete: { },
        onDismiss: { }
    )
}
#endif
