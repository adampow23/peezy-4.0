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
    
    // Retake assessment confirmation
    @State private var showRetakeAlert = false

    // Move details editing
    @State private var moveDetailDate: Date = Date()
    @State private var moveDetailCurrentAddress: String = ""
    @State private var moveDetailNewAddress: String = ""
    @State private var showEditMoveDate = false
    @State private var showEditCurrentAddress = false
    @State private var showEditNewAddress = false
    @State private var moveDetailsLoaded = false
    
    // Sign out confirmation
    @State private var showSignOutAlert = false
    
    // Processing state (for destructive actions)
    @State private var isProcessing = false
    @State private var processingMessage = ""
    
    // Toast feedback
    @State private var toastMessage: String? = nil
    
    // Theme
    private let deepInk = PeezyTheme.Colors.deepInk
    
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

                    // Move details
                    moveDetailsSection
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
                        .tint(deepInk)
                    Text(processingMessage)
                        .font(.subheadline)
                        .foregroundColor(deepInk.opacity(0.8))
                }
            }
            
            // Toast
            if let toast = toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(deepInk)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.9))
                                .overlay(Capsule().stroke(Color.black.opacity(0.1), lineWidth: 0.5))
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
        .onAppear { loadMoveDetails() }
        .sheet(isPresented: $showEditMoveDate) {
            EditMoveDateSheet(currentDate: moveDetailDate) { newDate in
                moveDetailDate = newDate
                userState?.moveDate = newDate
                saveMoveDetailField("moveDate", value: Timestamp(date: newDate))
                toastMessage = "Move date updated"
            }
        }
        .sheet(isPresented: $showEditCurrentAddress) {
            EditAddressSheet(title: "Current Address", currentValue: moveDetailCurrentAddress) { newValue in
                moveDetailCurrentAddress = newValue
                saveMoveDetailField("currentAddress", value: newValue)
                toastMessage = "Current address updated"
            }
        }
        .sheet(isPresented: $showEditNewAddress) {
            EditAddressSheet(title: "New Address", currentValue: moveDetailNewAddress) { newValue in
                moveDetailNewAddress = newValue
                saveMoveDetailField("newAddress", value: newValue)
                toastMessage = "New address updated"
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
                .foregroundColor(deepInk)
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
                        .foregroundColor(deepInk)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(userState?.name ?? "Peezy User")
                        .font(.title3.bold())
                        .foregroundColor(deepInk)
                    
                    if let email = Auth.auth().currentUser?.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(Color.gray)
                    }
                }
                
                Spacer()
            }
            .padding(20)
        }
        .background(glassBackground)
    }
    
    // MARK: - Move Details Section

    private var moveDetailsSection: some View {
        VStack(spacing: 0) {
            sectionLabel("Edit Move Details")

            VStack(spacing: 0) {
                // Move Date
                settingsValueRow(
                    icon: "calendar",
                    label: "Move Date",
                    value: formattedDate(moveDetailDate),
                    color: .blue
                ) {
                    showEditMoveDate = true
                }

                Divider().background(Color.black.opacity(0.08))

                // Current Address
                settingsValueRow(
                    icon: "house",
                    label: "Current Address",
                    value: moveDetailCurrentAddress.isEmpty ? "Not set" : truncated(moveDetailCurrentAddress),
                    color: .green
                ) {
                    showEditCurrentAddress = true
                }

                Divider().background(Color.black.opacity(0.08))

                // New Address
                settingsValueRow(
                    icon: "house.fill",
                    label: "New Address",
                    value: moveDetailNewAddress.isEmpty ? "Not set" : truncated(moveDetailNewAddress),
                    color: .purple
                ) {
                    showEditNewAddress = true
                }

                Divider().background(Color.black.opacity(0.08))

                // Retake Assessment
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
                            .foregroundColor(deepInk)

                        if !subscriptionDetailLabel.isEmpty {
                            Text(subscriptionDetailLabel)
                                .font(.caption)
                                .foregroundColor(Color.gray)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().background(Color.black.opacity(0.08))

                settingsRow(icon: "creditcard", label: "Manage Subscription", color: .cyan) {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }

                Divider().background(Color.black.opacity(0.08))

                settingsRow(icon: "arrow.triangle.2.circlepath", label: "Restore Purchases", color: Color.gray) {
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
                
                Divider().background(Color.black.opacity(0.08))
                
                settingsRow(icon: "doc.text", label: "Privacy Policy", color: Color.gray) {
                    openURL("https://peezy.move/privacy")
                }
                
                Divider().background(Color.black.opacity(0.08))
                
                settingsRow(icon: "doc.text", label: "Terms of Service", color: Color.gray) {
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
                .foregroundColor(Color.gray.opacity(0.4))
            
            Text("Version \(appVersion)")
                .font(.caption2)
                .foregroundColor(Color.gray.opacity(0.4))
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
                    .foregroundColor(label == "Sign Out" ? .red : deepInk)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Color.gray.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
    
    private func settingsValueRow(
        icon: String,
        label: String,
        value: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(deepInk)
                    Text(value)
                        .font(.caption)
                        .foregroundColor(Color.gray)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Color.gray.opacity(0.4))
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
                .foregroundColor(Color.gray.opacity(0.6))
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
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.5))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
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

    private func truncated(_ text: String, maxLength: Int = 30) -> String {
        text.count > maxLength ? String(text.prefix(maxLength)) + "..." : text
    }

    // MARK: - Move Details Firestore

    private func loadMoveDetails() {
        guard !moveDetailsLoaded else { return }
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
                    moveDetailCurrentAddress = data["currentAddress"] as? String ?? ""
                    moveDetailNewAddress = data["newAddress"] as? String ?? ""
                    if let timestamp = data["moveDate"] as? Timestamp {
                        moveDetailDate = timestamp.dateValue()
                    } else if let dateValue = data["moveDate"] as? Date {
                        moveDetailDate = dateValue
                    } else if let existingDate = userState?.moveDate {
                        moveDetailDate = existingDate
                    }
                    moveDetailsLoaded = true
                }
            } catch {
                // Silently fail — fields stay at defaults
            }
        }
    }

    private func saveMoveDetailField(_ key: String, value: Any) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()

        Task {
            do {
                let snapshot = try await db.collection("users").document(uid)
                    .collection("user_assessments")
                    .limit(to: 1)
                    .getDocuments()

                guard let doc = snapshot.documents.first else { return }

                try await doc.reference.updateData([key: value])
                try? await db.collection("userKnowledge").document(uid).updateData([key: value])
            } catch {
                await MainActor.run {
                    toastMessage = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Edit Move Date Sheet

struct EditMoveDateSheet: View {
    let currentDate: Date
    var onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date = Date()
    private let deepInk = PeezyTheme.Colors.deepInk

    var body: some View {
        NavigationView {
            ZStack {
                PeezyTheme.Colors.lightBase.ignoresSafeArea()

                VStack(spacing: 24) {
                    DatePicker(
                        "Move Date",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(.blue)
                    .padding(20)

                    Button {
                        onSave(selectedDate)
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .background(Color.white)
                    .cornerRadius(16)
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationTitle("Move Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(deepInk)
                }
            }
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { selectedDate = currentDate }
    }
}

// MARK: - Edit Address Sheet

struct EditAddressSheet: View {
    let title: String
    let currentValue: String
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address: String = ""
    @FocusState private var isFocused: Bool
    private let deepInk = PeezyTheme.Colors.deepInk

    var body: some View {
        NavigationView {
            ZStack {
                PeezyTheme.Colors.lightBase.ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color.gray.opacity(0.6))
                            .tracking(0.5)

                        TextField("Enter address", text: $address)
                            .textContentType(.fullStreetAddress)
                            .font(.system(size: 16))
                            .foregroundColor(deepInk)
                            .focused($isFocused)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                                    )
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Button {
                        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .background(Color.white)
                    .cornerRadius(16)
                    .padding(.horizontal, 20)
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

                    Spacer()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(deepInk)
                }
            }
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            address = currentValue
            isFocused = true
        }
    }
}

// MARK: - Edit Name & Email Sheet

struct EditNameEmailSheet: View {
    var userState: UserState?
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var isSaving = false
    @State private var error: String? = nil
    private let deepInk = PeezyTheme.Colors.deepInk

    var body: some View {
        NavigationView {
            ZStack {
                PeezyTheme.Colors.lightBase.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        fieldGroup(label: "Name") {
                            TextField("Your name", text: $name)
                                .textContentType(.name)
                        }

                        fieldGroup(label: "Email") {
                            TextField("Email address", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                        }

                        if let error = error {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Button(action: save) {
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
                        .foregroundColor(deepInk)
                }
            }
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            name = userState?.name ?? ""
            email = Auth.auth().currentUser?.email ?? ""
        }
    }

    private func fieldGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundColor(Color.gray.opacity(0.6))
                .tracking(0.5)

            content()
                .font(.system(size: 16))
                .foregroundColor(deepInk)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                        )
                )
                .tint(.blue)
        }
    }

    private func save() {
        guard let uid = Auth.auth().currentUser?.uid else {
            error = "Not signed in"
            return
        }

        isSaving = true
        error = nil

        let db = Firestore.firestore()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        Task {
            do {
                // Update name in Firestore
                let snapshot = try await db.collection("users").document(uid)
                    .collection("user_assessments")
                    .limit(to: 1)
                    .getDocuments()

                if let doc = snapshot.documents.first {
                    try await doc.reference.updateData(["userName": trimmedName])
                }
                try? await db.collection("userKnowledge").document(uid)
                    .updateData(["userName": trimmedName])

                // Update email in Firebase Auth if changed
                let currentEmail = Auth.auth().currentUser?.email ?? ""
                if !trimmedEmail.isEmpty && trimmedEmail != currentEmail {
                    try await Auth.auth().currentUser?.sendEmailVerification(beforeUpdatingEmail: trimmedEmail)
                }

                await MainActor.run {
                    isSaving = false
                    onSave(trimmedName)
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
