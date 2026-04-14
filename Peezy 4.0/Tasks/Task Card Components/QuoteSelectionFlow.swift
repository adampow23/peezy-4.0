//
//  QuoteSelectionFlow.swift
//  Peezy 4.0
//
//  Displays vendor quote options pushed by the admin dashboard.
//  User sees 2-3 options with vendor name, price, details.
//  Taps one to select. Selection writes to Firestore + triggers notification.
//
//  Firestore task document shape:
//  {
//    workflowId: "quote_selection",
//    title: "Your mover quotes are ready",
//    quoteCategory: "movers",
//    quoteOptions: [
//      { id: "opt1", vendorName: "Two Men and a Truck", price: "$2,400",
//        details: "Full service · 3-man crew · Insured", recommended: true },
//      ...
//    ]
//  }
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

struct QuoteSelectionFlow: View {
    let taskId: String
    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    @State private var currentCard = 0
    @State private var quoteOptions: [QuoteOption] = []
    @State private var taskTitle: String = "Your quotes are ready"
    @State private var quoteCategory: String = ""
    @State private var selectedOption: QuoteOption?
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var loadError: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(PeezyTheme.Colors.deepInk)
                    Text("Loading quotes...")
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
            await loadQuoteData()
        }
    }

    // MARK: - Card Content

    @ViewBuilder
    private var cardContent: some View {
        switch currentCard {
        case 0:
            titleCard
        case 1:
            optionsCard
        case 2:
            confirmationCard
        default:
            EmptyView()
        }
    }

    // MARK: - Card 0: Title

    private var titleCard: some View {
        TaskFlowTitleCard(
            taskTitle: taskTitle,
            icon: "tag.fill",
            onContinue: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    currentCard = 1
                }
            }
        )
    }

    // MARK: - Card 1: Quote Options

    private var optionsCard: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: taskTitle, showBack: true, onBack: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    currentCard = 0
                }
            })

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Text("Pick the one that\nworks for you")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Rectangle()
                    .fill(Color.black.opacity(0.15))
                    .frame(width: 50, height: 2)

                Text("Tap an option to select it. You can always change your mind.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Quote option cards
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(quoteOptions) { option in
                        quoteOptionCard(option)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()
        }
    }

    private func quoteOptionCard(_ option: QuoteOption) -> some View {
        Button {
            PeezyHaptics.light()
            selectedOption = option
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                currentCard = 2
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(option.vendorName)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(PeezyTheme.Colors.deepInk)

                            if option.recommended {
                                Text("Recommended")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(PeezyTheme.Colors.brandYellow.opacity(0.5))
                                    .clipShape(Capsule())
                            }
                        }

                        Text(option.details)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text(option.price)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                }

                if let notes = option.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.35))
                        .lineLimit(2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(option.recommended ? 0.25 : 0.15))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(option.recommended ? PeezyTheme.Colors.brandYellow.opacity(0.4) : Color.primary.opacity(0.05), lineWidth: option.recommended ? 1.5 : 1)
                }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card 2: Confirmation

    private var confirmationCard: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: taskTitle, showBack: true, onBack: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    selectedOption = nil
                    currentCard = 1
                }
            })

            Spacer()

            if let selected = selectedOption {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(PeezyTheme.Colors.successGreen)

                    Text("Great choice")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)

                    Rectangle()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 50, height: 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(selected.vendorName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)

                        Text(selected.price)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)

                        Text(selected.details)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )

                    Text("We'll reach out to them and get everything set up for you.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            PeezyAssessmentButton(isSubmitting ? "Submitting..." : "Confirm Selection") {
                Task { await submitSelection() }
            }
            .disabled(isSubmitting)
            .opacity(isSubmitting ? 0.5 : 1.0)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Load Quote Data

    private func loadQuoteData() async {
        guard !taskId.isEmpty else {
            loadError = "No task ID provided"
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
                loadError = "Quote not found"
                isLoading = false
                return
            }

            await MainActor.run {
                taskTitle = data["title"] as? String ?? "Your quotes are ready"
                quoteCategory = data["quoteCategory"] as? String ?? ""

                if let options = data["quoteOptions"] as? [[String: Any]] {
                    quoteOptions = options.compactMap { opt in
                        guard let id = opt["id"] as? String,
                              let name = opt["vendorName"] as? String,
                              let price = opt["price"] as? String else { return nil }
                        return QuoteOption(
                            id: id,
                            vendorName: name,
                            price: price,
                            details: opt["details"] as? String ?? "",
                            notes: opt["notes"] as? String,
                            recommended: opt["recommended"] as? Bool ?? false
                        )
                    }
                }

                if quoteOptions.isEmpty {
                    loadError = "No quote options found"
                }

                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = "Failed to load quotes"
                isLoading = false
            }
        }
    }

    // MARK: - Submit Selection

    private func submitSelection() async {
        guard let selected = selectedOption else { return }

        isSubmitting = true

        do {
            let db = Firestore.firestore()

            // 1. Update the task with the selection
            try await db.collection("users")
                .document(userId)
                .collection("tasks")
                .document(taskId)
                .updateData([
                    "status": "Completed",
                    "completedAt": FieldValue.serverTimestamp(),
                    "selectedQuoteId": selected.id,
                    "selectedVendorName": selected.vendorName,
                    "selectedPrice": selected.price,
                    "selectedAt": FieldValue.serverTimestamp()
                ])

            // 2. Submit via Cloud Function for admin notification
            let callable = Functions.functions().httpsCallable("submitTaskFlow")
            let payload: [String: Any] = [
                "userId": userId,
                "taskId": taskId,
                "taskTitle": taskTitle,
                "taskType": "quote_selection",
                "confirmedFields": [
                    "selectedVendor": selected.vendorName,
                    "selectedPrice": selected.price,
                    "quoteCategory": quoteCategory
                ],
                "transferChoice": "selected_\(selected.id)"
            ]
            _ = try await callable.call(payload)

        } catch {
            print("⚠️ Quote submission error: \(error.localizedDescription)")
            // Non-fatal — selection is already written to Firestore
        }

        await MainActor.run {
            isSubmitting = false
            onComplete()
        }
    }
}

// MARK: - Quote Option Model

struct QuoteOption: Identifiable {
    let id: String
    let vendorName: String
    let price: String
    let details: String
    let notes: String?
    let recommended: Bool
}

// MARK: - Previews

#if DEBUG
#Preview("Quote Selection") {
    QuoteSelectionFlow(
        taskId: "preview",
        userId: "preview",
        onComplete: { },
        onDismiss: { }
    )
}
#endif
