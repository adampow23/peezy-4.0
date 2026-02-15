#if DEBUG
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Notification posted when persona is loaded - observers should update their state
extension Notification.Name {
    static let debugPersonaLoaded = Notification.Name("debugPersonaLoaded")
    static let debugClearChatHistory = Notification.Name("debugClearChatHistory")
    static let debugForceSignOut = Notification.Name("debugForceSignOut")
}

/// Debug menu for testing different user states and time travel.
struct DebugMenuView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - External References

    /// Optional viewModel reference for direct state updates
    var viewModel: PeezyStackViewModel?

    // MARK: - State

    @State private var selectedPersona: DebugPersona?
    @State private var simulatedDateDisplay: Date = DateProvider.shared.now
    @State private var moveDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var showingDeleteConfirmation = false
    @State private var statusMessage: String?

    // MARK: - Computed Properties

    private var daysUntilMove: Int {
        Calendar.current.dateComponents([.day], from: simulatedDateDisplay, to: moveDate).day ?? 0
    }

    private var isSimulating: Bool {
        DateProvider.shared.isSimulating
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // Status message banner
                if let status = statusMessage {
                    Section {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                personasSection
                timeTravelSection
                actionsSection
                loggingSection
            }
            .navigationTitle("🛠 Debug Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Delete User?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { deleteUserAndRestart() }
            } message: {
                Text("This will delete all user data and return to the login screen. This cannot be undone.")
            }
        }
    }

    // MARK: - Sections

    private var personasSection: some View {
        Section {
            ForEach(DebugPersona.allCases) { persona in
                Button {
                    selectedPersona = persona
                    loadPersona(persona)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(persona.rawValue)
                                .fontWeight(selectedPersona == persona ? .semibold : .regular)
                            Text(persona.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedPersona == persona {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        } header: {
            Text("Load Persona")
        } footer: {
            Text("Loading a persona replaces current user state and regenerates tasks.")
        }
    }

    private var timeTravelSection: some View {
        Section {
            // Current state display
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Simulated Date:")
                    Spacer()
                    Text(simulatedDateDisplay.formatted(date: .abbreviated, time: .omitted))
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Days Until Move:")
                    Spacer()
                    Text("\(daysUntilMove)")
                        .fontWeight(.medium)
                        .foregroundStyle(daysUntilMove <= 7 ? .red : (daysUntilMove <= 14 ? .orange : .primary))
                }

                if isSimulating {
                    Label("Time simulation active", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)

            // Day navigation
            HStack {
                Button {
                    DateProvider.shared.goBackOneDay()
                    updateDateDisplay()
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    DateProvider.shared.advanceOneDay()
                    updateDateDisplay()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .buttonStyle(.bordered)
            }

            // Quick jump buttons
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    timeJumpButton("8 wks", days: 56)
                    timeJumpButton("4 wks", days: 28)
                    timeJumpButton("2 wks", days: 14)
                    timeJumpButton("1 wk", days: 7)
                }
                HStack(spacing: 8) {
                    timeJumpButton("3 days", days: 3)
                    timeJumpButton("Move Day", days: 0)
                    timeJumpButton("Post +3", days: -3)
                    timeJumpButton("Post +7", days: -7)
                }
            }
            .padding(.vertical, 4)

            // Reset button
            Button {
                DateProvider.shared.resetToRealTime()
                updateDateDisplay()
            } label: {
                Label("Reset to Real Time", systemImage: "arrow.counterclockwise")
            }
            .foregroundStyle(.secondary)

        } header: {
            Text("Time Travel")
        } footer: {
            Text("Simulates different points in the moving timeline. Affects task surfacing and urgency.")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                clearConversationHistory()
            } label: {
                Label("Clear Conversation History", systemImage: "trash")
            }

            Button {
                resetAllTasks()
            } label: {
                Label("Reset All Tasks to Incomplete", systemImage: "arrow.uturn.backward")
            }

            Button {
                completeAllTasks()
            } label: {
                Label("Mark All Tasks Complete", systemImage: "checkmark.circle")
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete User & Restart", systemImage: "person.crop.circle.badge.xmark")
            }
        } header: {
            Text("Actions")
        }
    }

    private var loggingSection: some View {
        Section {
            NavigationLink {
                DebugLogView(title: "Last AI Prompt", content: getLastPrompt())
            } label: {
                Label("View Last AI Prompt", systemImage: "arrow.up.doc")
            }

            NavigationLink {
                DebugLogView(title: "Last AI Response", content: getLastResponse())
            } label: {
                Label("View Last AI Response", systemImage: "arrow.down.doc")
            }
        } header: {
            Text("Logging")
        } footer: {
            Text("View the raw prompts and responses sent to/from the AI.")
        }
    }

    // MARK: - Helper Views

    private func timeJumpButton(_ label: String, days: Int) -> some View {
        Button(label) {
            DateProvider.shared.setDaysUntil(days, before: moveDate)
            updateDateDisplay()
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func loadPersona(_ persona: DebugPersona) {
        print("DEBUG: Loading persona: \(persona.rawValue)")

        let newUserState = persona.createUserState()

        // Update move date for time travel reference
        moveDate = newUserState.moveDate ?? moveDate

        // Update viewModel directly if available
        if let vm = viewModel {
            vm.userState = newUserState
            // Clear existing cards and reload
            vm.cards.removeAll()
            Task {
                await vm.loadInitialCards()
            }
        }

        // Also post notification for any other observers
        NotificationCenter.default.post(
            name: .debugPersonaLoaded,
            object: nil,
            userInfo: ["userState": newUserState]
        )

        updateDateDisplay()
        showStatus("Loaded persona: \(persona.rawValue)")
    }

    private func updateDateDisplay() {
        simulatedDateDisplay = DateProvider.shared.now
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        // Auto-clear after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }

    private func clearConversationHistory() {
        print("DEBUG: Clearing conversation history")

        // Post notification for ChatView to clear its messages
        NotificationCenter.default.post(name: .debugClearChatHistory, object: nil)

        // Also clear any Firestore chat history if it exists
        Task {
            await clearFirestoreChatHistory()
        }

        showStatus("Cleared conversation history")
    }

    private func clearFirestoreChatHistory() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("DEBUG: No user signed in, skipping Firestore chat clear")
            return
        }

        do {
            let db = Firestore.firestore()
            let messagesRef = db.collection("users").document(uid).collection("messages")
            let snapshot = try await messagesRef.getDocuments()

            for doc in snapshot.documents {
                try await doc.reference.delete()
            }
            print("DEBUG: Cleared \(snapshot.documents.count) messages from Firestore")
        } catch {
            print("DEBUG: Error clearing Firestore chat: \(error.localizedDescription)")
        }
    }

    private func resetAllTasks() {
        print("DEBUG: Resetting all tasks to incomplete")

        Task {
            guard let uid = Auth.auth().currentUser?.uid else {
                await MainActor.run { showStatus("No user signed in") }
                return
            }

            do {
                let db = Firestore.firestore()
                let tasksRef = db.collection("users").document(uid).collection("tasks")
                let snapshot = try await tasksRef.getDocuments()

                var resetCount = 0
                for doc in snapshot.documents {
                    try await doc.reference.updateData([
                        "status": "Upcoming",
                        "snoozedUntil": FieldValue.delete(),
                        "completedAt": FieldValue.delete()
                    ])
                    resetCount += 1
                }

                // Also reset local state if viewModel available
                await MainActor.run {
                    if var userState = viewModel?.userState {
                        userState.completedTasks.removeAll()
                        userState.pendingTasks.removeAll()
                        userState.deferredTasks.removeAll()
                        viewModel?.userState = userState
                    }

                    // Reload cards
                    Task {
                        await viewModel?.refreshCards()
                    }

                    showStatus("Reset \(resetCount) tasks")
                }
                print("DEBUG: Reset \(resetCount) tasks")
            } catch {
                await MainActor.run { showStatus("Error: \(error.localizedDescription)") }
                print("DEBUG: Error resetting tasks: \(error.localizedDescription)")
            }
        }
    }

    private func completeAllTasks() {
        print("DEBUG: Marking all tasks complete")

        Task {
            guard let uid = Auth.auth().currentUser?.uid else {
                await MainActor.run { showStatus("No user signed in") }
                return
            }

            do {
                let db = Firestore.firestore()
                let tasksRef = db.collection("users").document(uid).collection("tasks")
                let snapshot = try await tasksRef.getDocuments()

                var completedCount = 0
                let now = Timestamp(date: Date())
                for doc in snapshot.documents {
                    try await doc.reference.updateData([
                        "status": "Completed",
                        "completedAt": now
                    ])
                    completedCount += 1
                }

                // Also update local state if viewModel available
                await MainActor.run {
                    if var userState = viewModel?.userState {
                        // Move all task IDs to completed
                        let allTaskIds = snapshot.documents.map { $0.documentID }
                        userState.completedTasks = allTaskIds
                        userState.pendingTasks.removeAll()
                        userState.deferredTasks.removeAll()
                        viewModel?.userState = userState
                    }

                    // Reload cards
                    Task {
                        await viewModel?.refreshCards()
                    }

                    showStatus("Completed \(completedCount) tasks")
                }
                print("DEBUG: Completed \(completedCount) tasks")
            } catch {
                await MainActor.run { showStatus("Error: \(error.localizedDescription)") }
                print("DEBUG: Error completing tasks: \(error.localizedDescription)")
            }
        }
    }

    private func deleteUserAndRestart() {
        print("DEBUG: Deleting user and restarting")

        Task {
            do {
                guard let uid = Auth.auth().currentUser?.uid else {
                    await MainActor.run { showStatus("No user signed in") }
                    return
                }

                let db = Firestore.firestore()
                let userRef = db.collection("users").document(uid)

                // 1. Delete subcollections
                // Messages
                let messages = try await userRef.collection("messages").getDocuments()
                for doc in messages.documents {
                    try await doc.reference.delete()
                }
                print("DEBUG: Deleted \(messages.documents.count) messages")

                // Tasks
                let tasks = try await userRef.collection("tasks").getDocuments()
                for doc in tasks.documents {
                    try await doc.reference.delete()
                }
                print("DEBUG: Deleted \(tasks.documents.count) tasks")

                // User assessments
                let assessments = try await userRef.collection("user_assessments").getDocuments()
                for doc in assessments.documents {
                    try await doc.reference.delete()
                }
                print("DEBUG: Deleted \(assessments.documents.count) assessments")

                // 2. Delete user document
                try await userRef.delete()
                print("DEBUG: Deleted user document")

                // 3. Clear local state
                await MainActor.run {
                    viewModel?.userState = nil
                    viewModel?.cards.removeAll()
                }

                // 4. Dismiss the debug menu FIRST (before sign out)
                await MainActor.run {
                    dismiss()
                }

                // 5. Small delay to let dismiss complete
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

                // 6. Sign out - this triggers AuthViewModel's listener
                try Auth.auth().signOut()
                print("DEBUG: Signed out - auth state listener should navigate to login")

                // 7. Post notification as backup to force app state reset
                await MainActor.run {
                    NotificationCenter.default.post(name: .debugForceSignOut, object: nil)
                }

            } catch {
                await MainActor.run { showStatus("Error: \(error.localizedDescription)") }
                print("DEBUG: Error deleting user: \(error.localizedDescription)")
            }
        }
    }

    private func getLastPrompt() -> String {
        return PeezyClient.lastPromptSent.isEmpty
            ? "No prompt sent yet.\n\nThis will show the full request body sent to the Peezy backend."
            : PeezyClient.lastPromptSent
    }

    private func getLastResponse() -> String {
        return PeezyClient.lastResponseReceived.isEmpty
            ? "No response received yet.\n\nThis will show the raw response received from the Peezy backend."
            : PeezyClient.lastResponseReceived
    }
}

// MARK: - Debug Log View

struct DebugLogView: View {
    let title: String
    let content: String

    var body: some View {
        ScrollView {
            Text(content)
                .font(.system(.caption, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview {
    DebugMenuView()
}
#endif
