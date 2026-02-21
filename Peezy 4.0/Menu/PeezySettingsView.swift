//
//  PeezySettingsView.swift
//  Peezy
//
//  Settings & Profile — sign out, edit profile, retake assessment, support.
//  Accessed via hamburger menu "Settings" destination in PeezyMainContainer.
//
//  Dependencies:
//  - AuthViewModel (@EnvironmentObject, injected by AppRootView)
//  - UserState (passed as parameter from PeezyMainContainer)
//  - InteractiveBackground (from PeezyStackView.swift, same module)
//  - Firebase Auth + Firestore (direct access for profile edits)
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct PeezySettingsView: View {
    
    // User state from parent
    @Binding var userState: UserState?
    
    // Auth — injected by AppRootView up the chain
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    // Edit profile sheet
    @State private var showEditProfile = false
    
    // Retake assessment confirmation
    @State private var showRetakeAlert = false
    
    // Sign out confirmation
    @State private var showSignOutAlert = false
    
    // Processing state (for destructive actions)
    @State private var isProcessing = false
    @State private var processingMessage = ""
    
    // Toast feedback
    @State private var toastMessage: String? = nil
    
    // Theme
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)
    
    var body: some View {
        ZStack {
            InteractiveBackground()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    header
                    
                    // Profile card
                    profileCard
                        .padding(.top, 24)
                    
                    // Actions
                    actionsSection
                        .padding(.top, 20)

                    // Subscription
                    subscriptionSection
                        .padding(.top, 20)

                    // Support
                    supportSection
                        .padding(.top, 20)
                    
                    // Danger zone
                    dangerSection
                        .padding(.top, 20)
                    
                    // Footer
                    versionFooter
                        .padding(.top, 32)
                        .padding(.bottom, 60)
                }
                .padding(.horizontal, 20)
            }
            
            // Processing overlay
            if isProcessing {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text(processingMessage)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            // Toast
            if let toast = toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(charcoalColor.opacity(0.9))
                                .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
                        )
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.4), value: toastMessage != nil)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation { toastMessage = nil }
                    }
                }
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet(userState: userState) { updatedName, updatedMoveDate in
                if let date = updatedMoveDate {
                    userState?.moveDate = date
                }
                toastMessage = "Profile updated"
            }
        }
        .alert("Retake Assessment?", isPresented: $showRetakeAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete & Start Over", role: .destructive) {
                retakeAssessment()
            }
        } message: {
            Text("This will delete all your tasks and start the assessment over from scratch. You'll need to sign back in.")
        }
        .alert("Sign Out?", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                try? authViewModel.signOut()
            }
        } message: {
            Text("You'll need to sign back in to access your tasks.")
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("Settings")
                .font(.title2.bold())
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.top, 56)
    }
    
    // MARK: - Profile Card
    
    private var profileCard: some View {
        VStack(spacing: 0) {
            // Avatar + name
            HStack(spacing: 16) {
                // Avatar circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Text(initials)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(userState?.name ?? "Peezy User")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    
                    if let email = Auth.auth().currentUser?.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                
                Spacer()
            }
            .padding(20)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Move date info
            if let moveDate = userState?.moveDate {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.cyan.opacity(0.8))
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Move Date")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        Text(formattedDate(moveDate))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    if let days = userState?.daysUntilMove, days > 0 {
                        Text("\(days) days")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.cyan.opacity(0.15)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .background(glassBackground)
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 0) {
            sectionLabel("Account")
            
            VStack(spacing: 0) {
                settingsRow(icon: "person.crop.circle", label: "Edit Profile", color: .blue) {
                    showEditProfile = true
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                settingsRow(icon: "arrow.counterclockwise", label: "Retake Assessment", color: .orange) {
                    showRetakeAlert = true
                }
            }
            .background(glassBackground)
        }
    }
    
    // MARK: - Subscription Section

    private var subscriptionSection: some View {
        VStack(spacing: 0) {
            sectionLabel("Subscription")

            VStack(spacing: 0) {
                // Status row
                HStack(spacing: 14) {
                    Image(systemName: subscriptionManager.subscriptionStatus.isActive
                          ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(subscriptionManager.subscriptionStatus.isActive ? .green : .orange)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(subscriptionStatusLabel)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)

                        if !subscriptionDetailLabel.isEmpty {
                            Text(subscriptionDetailLabel)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().background(Color.white.opacity(0.1))

                settingsRow(icon: "creditcard", label: "Manage Subscription", color: .cyan) {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                settingsRow(icon: "arrow.triangle.2.circlepath", label: "Restore Purchases", color: .white.opacity(0.6)) {
                    Task { await subscriptionManager.restorePurchases() }
                }
            }
            .background(glassBackground)
        }
    }

    private var subscriptionStatusLabel: String {
        switch subscriptionManager.subscriptionStatus {
        case .trial:
            return "Free Trial Active"
        case .subscribed:
            return "Peezy Premium"
        case .expired:
            return "Subscription Expired"
        case .revoked:
            return "Subscription Revoked"
        case .notSubscribed:
            return "Not Subscribed"
        }
    }

    private var subscriptionDetailLabel: String {
        switch subscriptionManager.subscriptionStatus {
        case .trial(let productId, let expires):
            let planName = productId == "peezy.yearly" ? "Yearly" : "Monthly"
            let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: expires).day ?? 0
            return "\(planName) plan — trial ends in \(daysLeft) day\(daysLeft == 1 ? "" : "s")"
        case .subscribed(let productId, let expires):
            let planName = productId == "peezy.yearly" ? "Yearly" : "Monthly"
            return "\(planName) plan — renews \(formattedDate(expires))"
        case .expired:
            return "Resubscribe to access all features"
        default:
            return ""
        }
    }

    // MARK: - Support Section

    private var supportSection: some View {
        VStack(spacing: 0) {
            sectionLabel("Support")
            
            VStack(spacing: 0) {
                settingsRow(icon: "envelope", label: "Contact Support", color: .green) {
                    openSupportEmail()
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                settingsRow(icon: "doc.text", label: "Privacy Policy", color: .white.opacity(0.6)) {
                    openURL("https://peezy.move/privacy")
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                settingsRow(icon: "doc.text", label: "Terms of Service", color: .white.opacity(0.6)) {
                    openURL("https://peezy.move/terms")
                }
            }
            .background(glassBackground)
        }
    }
    
    // MARK: - Danger Section
    
    private var dangerSection: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                settingsRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    label: "Sign Out",
                    color: .red
                ) {
                    showSignOutAlert = true
                }
            }
            .background(glassBackground)
        }
    }
    
    // MARK: - Version Footer
    
    private var versionFooter: some View {
        VStack(spacing: 4) {
            Text("Peezy")
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.3))
            
            Text("Version \(appVersion)")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.2))
        }
    }
    
    // MARK: - Reusable Row
    
    private func settingsRow(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 28)
                
                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(label == "Sign Out" ? .red : .white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.2))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
    
    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.4))
                .tracking(1)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
    
    // MARK: - Glass Background
    
    private var glassBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(charcoalColor.opacity(0.5))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 0.5)
        )
    }
    
    // MARK: - Retake Assessment
    
    private func retakeAssessment() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        isProcessing = true
        processingMessage = "Resetting your data..."
        
        let db = Firestore.firestore()
        
        Task {
            do {
                // 1. Delete all tasks
                let tasksSnapshot = try await db.collection("users").document(uid)
                    .collection("tasks").getDocuments()
                for doc in tasksSnapshot.documents {
                    try await doc.reference.delete()
                }
                
                // 2. Delete assessment docs
                let assessmentSnapshot = try await db.collection("users").document(uid)
                    .collection("user_assessments").getDocuments()
                for doc in assessmentSnapshot.documents {
                    try await doc.reference.delete()
                }
                
                // 3. Delete userKnowledge doc
                try? await db.collection("userKnowledge").document(uid).delete()
                
                // 4. Sign out — AppRootView will re-evaluate and route to auth
                //    On sign-in, no assessment found → assessment flow starts
                await MainActor.run {
                    isProcessing = false
                    try? authViewModel.signOut()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    toastMessage = "Failed to reset: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var initials: String {
        guard let name = userState?.name, !name.isEmpty else { return "P" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        return fmt.string(from: date)
    }
    
    private func openSupportEmail() {
        if let url = URL(string: "mailto:support@peezy.move") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Edit Profile Sheet

struct EditProfileSheet: View {
    var userState: UserState?
    var onSave: (String, Date?) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var currentAddress: String = ""
    @State private var newAddress: String = ""
    @State private var moveDate: Date = Date()
    @State private var hasMoveDate: Bool = false
    @State private var isSaving = false
    @State private var error: String? = nil
    
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.1)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Name field
                        fieldGroup(label: "Name") {
                            TextField("Your name", text: $name)
                                .textContentType(.name)
                        }
                        
                        // Move date
                        fieldGroup(label: "Move Date") {
                            DatePicker(
                                "",
                                selection: $moveDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(.cyan)
                        }
                        
                        // Current address
                        fieldGroup(label: "Current Address") {
                            TextField("Current address", text: $currentAddress)
                                .textContentType(.fullStreetAddress)
                        }
                        
                        // New address
                        fieldGroup(label: "New Address") {
                            TextField("New address", text: $newAddress)
                                .textContentType(.fullStreetAddress)
                        }
                        
                        // Error
                        if let error = error {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        // Save button
                        Button(action: saveProfile) {
                            if isSaving {
                                ProgressView()
                                    .tint(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                            } else {
                                Text("Save Changes")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(16)
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { loadCurrentValues() }
    }
    
    // MARK: - Field Group
    
    private func fieldGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.4))
                .tracking(0.5)
            
            content()
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(charcoalColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
                .tint(.cyan)
        }
    }
    
    // MARK: - Load Values
    
    private func loadCurrentValues() {
        name = userState?.name ?? ""
        
        // Load addresses from Firestore assessment data
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        
        Task {
            do {
                let snapshot = try await db.collection("users").document(uid)
                    .collection("user_assessments")
                    .limit(to: 1)
                    .getDocuments()
                
                guard let doc = snapshot.documents.first else { return }
                let data = doc.data()
                
                await MainActor.run {
                    currentAddress = data["currentAddress"] as? String ?? ""
                    newAddress = data["newAddress"] as? String ?? ""
                    if let timestamp = data["moveDate"] as? Timestamp {
                        self.moveDate = timestamp.dateValue()
                        self.hasMoveDate = true
                    } else if let dateValue = data["moveDate"] as? Date {
                        self.moveDate = dateValue
                        self.hasMoveDate = true
                    }
                }
            } catch {
                // Silently fail — fields just stay empty
            }
        }
    }
    
    // MARK: - Save
    
    private func saveProfile() {
        guard let uid = Auth.auth().currentUser?.uid else {
            error = "Not signed in"
            return
        }
        
        isSaving = true
        error = nil
        
        let db = Firestore.firestore()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        
        Task {
            do {
                // Find the assessment document
                let snapshot = try await db.collection("users").document(uid)
                    .collection("user_assessments")
                    .limit(to: 1)
                    .getDocuments()
                
                guard let doc = snapshot.documents.first else {
                    await MainActor.run {
                        error = "No assessment data found"
                        isSaving = false
                    }
                    return
                }
                
                // Build update dictionary — only include non-empty fields
                var updates: [String: Any] = [
                    "userName": trimmedName,
                    "moveDate": Timestamp(date: moveDate)
                ]
                if !currentAddress.trimmingCharacters(in: .whitespaces).isEmpty {
                    updates["currentAddress"] = currentAddress.trimmingCharacters(in: .whitespaces)
                }
                if !newAddress.trimmingCharacters(in: .whitespaces).isEmpty {
                    updates["newAddress"] = newAddress.trimmingCharacters(in: .whitespaces)
                }
                
                // Update assessment doc
                try await doc.reference.updateData(updates)
                
                // Also update userKnowledge if it exists
                try? await db.collection("userKnowledge").document(uid).updateData(updates)
                
                await MainActor.run {
                    isSaving = false
                    onSave(trimmedName, moveDate)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = "Save failed: \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PeezySettingsView(
        userState: .constant(UserState(userId: "preview", name: "Adam"))
    )
    .environmentObject(AuthViewModel())
    .environmentObject(SubscriptionManager.shared)
}
