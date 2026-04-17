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
import MapKit
import StoreKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

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
    
    // Edit profile
    @State private var showEditProfile = false

    // Sign out confirmation
    @State private var showSignOutAlert = false

    @State private var showInventoryScanner = false
    
    // Processing state (for destructive actions)
    @State private var isProcessing = false
    @State private var processingMessage = ""
    
    // Toast feedback
    @State private var toastMessage: String? = nil
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage = ""
    @State private var showDeleteErrorAlert = false
    @State private var restoreMessage: String? = nil

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

                    // Inventory
                    inventorySection
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
                        .padding(.bottom, 80)
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
                        .font(PeezyTheme.Typography.callout)
                        .foregroundColor(deepInk.opacity(0.8))
                }
            }
            
            // Toast
            if let toast = toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(PeezyTheme.Typography.calloutMedium)
                        .foregroundColor(deepInk)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.9))
                                .overlay(Capsule().stroke(Color.black.opacity(0.05), lineWidth: 0.5))
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
        .sheet(isPresented: $showEditProfile) {
            EditNameEmailSheet(userState: userState) { newName in
                userState?.name = newName
                toastMessage = "Profile updated"
            }
        }
        .alert("Retake Assessment?", isPresented: $showRetakeAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Retake", role: .destructive) {
                retakeAssessment()
            }
        } message: {
            Text("This will reset your tasks and personalized plan. Your account will not be affected.")
        }
        .alert("Sign Out?", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                try? authViewModel.signOut()
            }
        } message: {
            Text("You'll need to sign back in to access your tasks.")
        }
        .alert("Delete Account?", isPresented: $showDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Everything", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("This will permanently delete your account, all your tasks, and all your data. This cannot be undone.\n\nIf you have an active subscription, please cancel it first in your Apple ID settings.")
        }
        .alert("Account deletion failed", isPresented: $showDeleteErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage)
        }
        .alert("Restore purchases", isPresented: .init(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } }
        )) {
            Button("OK") { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
        }
        .fullScreenCover(isPresented: $showInventoryScanner) {
            InventoryFlowView()
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
        .padding(.top, 16)
    }

    // MARK: - Profile Card
    
    private var profileCard: some View {
        Button {
            showEditProfile = true
        } label: {
            HStack(spacing: 16) {
                // Avatar circle
                ZStack {
                    Circle()
                        .fill(PeezyTheme.Colors.deepInk)
                        .frame(width: 56, height: 56)

                    Text(initials)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(PeezyTheme.Colors.lightBase)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(userState?.name ?? "Peezy User")
                        .font(.title3.bold())
                        .foregroundColor(deepInk)

                    if let email = Auth.auth().currentUser?.email {
                        Text(email)
                            .font(PeezyTheme.Typography.callout)
                            .foregroundColor(deepInk.opacity(0.5))
                    }
                }

                Spacer()

                Image(systemName: "pencil.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(deepInk.opacity(0.4))
            }
            .padding(20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.peezyPress)
        .background(glassBackground)
        .accessibilityIdentifier("settings_profile_card")
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
                    color: PeezyTheme.Colors.accentBlue
                ) {
                    showEditMoveDate = true
                }
                .accessibilityIdentifier("settings_move_date")

                Divider().background(deepInk.opacity(0.06))

                // Current Address
                settingsValueRow(
                    icon: "house",
                    label: "Current Address",
                    value: moveDetailCurrentAddress.isEmpty ? "Not set" : truncated(moveDetailCurrentAddress),
                    color: PeezyTheme.Colors.successGreen
                ) {
                    showEditCurrentAddress = true
                }
                .accessibilityIdentifier("settings_current_address")

                Divider().background(deepInk.opacity(0.06))

                // New Address
                settingsValueRow(
                    icon: "house.fill",
                    label: "New Address",
                    value: moveDetailNewAddress.isEmpty ? "Not set" : truncated(moveDetailNewAddress),
                    color: PeezyTheme.Colors.supportPurple
                ) {
                    showEditNewAddress = true
                }
                .accessibilityIdentifier("settings_new_address")

                Divider().background(deepInk.opacity(0.06))

                // Retake Assessment
                settingsRow(icon: "arrow.counterclockwise", label: "Retake Assessment", color: PeezyTheme.Colors.warningOrange) {
                    showRetakeAlert = true
                }
                .accessibilityIdentifier("settings_retake_assessment")
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
                        .foregroundColor(subscriptionManager.subscriptionStatus.isActive ? PeezyTheme.Colors.successGreen : PeezyTheme.Colors.warningOrange)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(subscriptionStatusLabel)
                            .font(PeezyTheme.Typography.bodyMedium)
                            .foregroundColor(deepInk)

                        if !subscriptionDetailLabel.isEmpty {
                            Text(subscriptionDetailLabel)
                                .font(PeezyTheme.Typography.caption)
                                .foregroundColor(deepInk.opacity(0.5))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .accessibilityIdentifier("settings_subscription_status")

                Divider().background(deepInk.opacity(0.06))

                settingsRow(icon: "creditcard", label: "Manage Subscription", color: PeezyTheme.Colors.infoBlue) {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
                .accessibilityIdentifier("settings_manage_subscription")

                Divider().background(deepInk.opacity(0.06))

                settingsRow(icon: "arrow.triangle.2.circlepath", label: "Restore purchases", color: deepInk.opacity(0.4)) {
                    Task {
                        await subscriptionManager.restorePurchases()
                        if subscriptionManager.purchaseError == nil {
                            restoreMessage = "Purchases restored successfully."
                        } else {
                            restoreMessage = "Unable to restore purchases. Please try again."
                        }
                    }
                }
                .accessibilityIdentifier("settings_restore_purchases")
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
            let planName = planLabel(for: productId)
            let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: expires).day ?? 0
            return "\(planName) plan — trial ends in \(daysLeft) day\(daysLeft == 1 ? "" : "s")"
        case .subscribed(let productId, let expires):
            let planName = planLabel(for: productId)
            return "\(planName) plan — renews \(formattedDate(expires))"
        case .expired:
            return "Resubscribe to access all features"
        default:
            return ""
        }
    }

    private func planLabel(for productId: String) -> String {
        guard let id = SubscriptionManager.ProductID(rawValue: productId),
              let product = subscriptionManager.product(for: id),
              let subscription = product.subscription else {
            return "Subscription"
        }

        switch subscription.subscriptionPeriod.unit {
        case .day:
            return "Subscription"
        case .week:
            return "Weekly"
        case .month:
            return "Monthly"
        case .year:
            return "Yearly"
        @unknown default:
            return "Subscription"
        }
    }

    // MARK: - Inventory Section

    private var inventorySection: some View {
        VStack(spacing: 0) {
            sectionLabel("Inventory")

            VStack(spacing: 0) {
                settingsRow(icon: "camera.viewfinder", label: "Scan Room Inventory", color: PeezyTheme.Colors.infoBlue) {
                    showInventoryScanner = true
                }
                .accessibilityIdentifier("settings_inventory_scanner")
            }
            .background(glassBackground)
        }
    }

    // MARK: - Support Section

    private var supportSection: some View {
        VStack(spacing: 0) {
            sectionLabel("Support")
            
            VStack(spacing: 0) {
                settingsRow(icon: "envelope", label: "Contact Support", color: PeezyTheme.Colors.successGreen) {
                    openSupportEmail()
                }

                Divider().background(deepInk.opacity(0.06))

                settingsRow(icon: "doc.text", label: "Privacy Policy", color: deepInk.opacity(0.4)) {
                    openURL("https://peezy-1ecrdl.web.app/privacy.html")
                }
                .accessibilityIdentifier("settings_privacy_policy")

                Divider().background(deepInk.opacity(0.06))

                settingsRow(icon: "doc.text", label: "Terms of Service", color: deepInk.opacity(0.4)) {
                    openURL("https://peezy-1ecrdl.web.app/terms.html")
                }
                .accessibilityIdentifier("settings_terms_of_service")
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
                    color: PeezyTheme.Colors.emotionalRed
                ) {
                    showSignOutAlert = true
                }
                .accessibilityIdentifier("settings_sign_out")

                Divider().background(deepInk.opacity(0.06))

                settingsRow(
                    icon: "trash",
                    label: "Delete account",
                    color: PeezyTheme.Colors.emotionalRed
                ) {
                    showDeleteAccountConfirmation = true
                }
                .accessibilityIdentifier("settings_delete_account")
            }
            .background(glassBackground)
        }
    }
    
    // MARK: - Version Footer
    
    private var versionFooter: some View {
        VStack(spacing: 4) {
            Text("Peezy")
                .font(PeezyTheme.Typography.captionMedium)
                .foregroundColor(deepInk.opacity(0.3))

            Text("Version \(appVersion)")
                .font(PeezyTheme.Typography.caption)
                .foregroundColor(deepInk.opacity(0.3))
        }
        .accessibilityIdentifier("settings_version")
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
                    .font(PeezyTheme.Typography.bodyMedium)
                    .foregroundColor(label == "Sign Out" ? PeezyTheme.Colors.emotionalRed : deepInk)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(PeezyTheme.Typography.captionMedium)
                    .foregroundColor(deepInk.opacity(0.3))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.peezyPress)
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
                        .font(PeezyTheme.Typography.bodyMedium)
                        .foregroundColor(deepInk)
                    Text(value)
                        .font(PeezyTheme.Typography.caption)
                        .foregroundColor(deepInk.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(PeezyTheme.Typography.captionMedium)
                    .foregroundColor(deepInk.opacity(0.3))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.peezyPress)
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text.uppercased())
                .font(PeezyTheme.Typography.captionMedium)
                .foregroundColor(deepInk.opacity(0.4))
                .tracking(1)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
    
    // MARK: - Glass Background
    
    private var glassBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.15))
        }
        .overlay(
            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
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
                
                // 4. Post notification — AppRootView will call checkAssessmentStatus(),
                //    find no assessment docs, and route to .needsAssessment
                await MainActor.run {
                    isProcessing = false
                    NotificationCenter.default.post(name: .retakeAssessment, object: nil)
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    toastMessage = "Failed to reset: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteAccount() {
        guard Auth.auth().currentUser != nil else { return }
        isDeletingAccount = true
        isProcessing = true
        processingMessage = "Deleting your account..."

        Task {
            do {
                // Cloud Function runs as admin and handles:
                // 1. Recursive deletion of all user Firestore data
                // 2. Deletion of cross-collection references (conciergeRequests, taskFlowSubmissions, etc.)
                // 3. Deletion of Storage files under users/{uid}/
                // 4. Deletion of the Firebase Auth user (last, only if everything else succeeded)
                let callable = Functions.functions().httpsCallable("deleteAccount")
                _ = try await callable.call([:])

                // Server-side deletion succeeded — sign out the local session
                await MainActor.run {
                    isDeletingAccount = false
                    isProcessing = false
                    try? authViewModel.signOut()
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    isProcessing = false
                    deleteErrorMessage = "Account deletion failed. Please try again or contact support."
                    showDeleteErrorAlert = true
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
    @State private var originalDate: Date = Date()
    @State private var showUpdateConfirmation = false
    private let deepInk = PeezyTheme.Colors.deepInk

    private var hasChanged: Bool {
        !Calendar.current.isDate(selectedDate, inSameDayAs: originalDate)
    }

    var body: some View {
        NavigationView {
            ZStack {
                PeezyTheme.Colors.lightBase.ignoresSafeArea()

                VStack(spacing: 24) {
                    DatePicker(
                        "Move Date",
                        selection: $selectedDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(deepInk)
                    .padding(20)

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
                if hasChanged {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Update") {
                            showUpdateConfirmation = true
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(deepInk)
                    }
                }
            }
            .toolbarColorScheme(.light, for: .navigationBar)
            .alert("Update Move Date?", isPresented: $showUpdateConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Update") {
                    onSave(selectedDate)
                    dismiss()
                }
            } message: {
                Text("This will update your tasks and timeline to reflect the new date.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            selectedDate = currentDate
            originalDate = currentDate
        }
    }
}

// MARK: - Edit Address Sheet

struct EditAddressSheet: View {
    let title: String
    let currentValue: String
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchManager = AddressSearchManager()
    @FocusState private var isFocused: Bool
    private let deepInk = PeezyTheme.Colors.deepInk

    private var saveValue: String {
        searchManager.queryFragment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationView {
            ZStack {
                PeezyTheme.Colors.lightBase.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title.uppercased())
                            .font(PeezyTheme.Typography.captionMedium)
                            .foregroundColor(deepInk.opacity(0.4))
                            .tracking(0.5)

                        TextField("Enter address", text: $searchManager.queryFragment)
                            .textContentType(.fullStreetAddress)
                            .font(PeezyTheme.Typography.body)
                            .foregroundColor(deepInk)
                            .focused($isFocused)
                            .tint(deepInk)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                                    .fill(deepInk.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                                            .stroke(isFocused ? deepInk.opacity(0.2) : deepInk.opacity(0.06), lineWidth: isFocused ? 1 : 0.5)
                                    )
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    if !searchManager.suggestions.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(searchManager.suggestions.enumerated()), id: \.offset) { index, suggestion in
                                Button {
                                    isFocused = false
                                    Task {
                                        await searchManager.selectSuggestion(suggestion)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(deepInk.opacity(0.35))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.title)
                                                .font(PeezyTheme.Typography.body)
                                                .foregroundColor(deepInk)
                                                .lineLimit(1)
                                            if !suggestion.subtitle.isEmpty {
                                                Text(suggestion.subtitle)
                                                    .font(PeezyTheme.Typography.caption)
                                                    .foregroundColor(deepInk.opacity(0.5))
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if index < searchManager.suggestions.count - 1 {
                                    Divider()
                                        .background(deepInk.opacity(0.06))
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                                .fill(deepInk.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                                        .stroke(deepInk.opacity(0.06), lineWidth: 0.5)
                                )
                        )
                        .padding(.horizontal, 20)
                        .animation(.easeOut(duration: 0.2), value: searchManager.suggestions.count)
                    }

                    PeezyAssessmentButton("Save", disabled: saveValue.isEmpty) {
                        guard !saveValue.isEmpty else { return }
                        onSave(saveValue)
                        dismiss()
                    }
                    .padding(.horizontal, 20)

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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            searchManager.queryFragment = currentValue
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
                                .font(PeezyTheme.Typography.caption)
                                .foregroundColor(PeezyTheme.Colors.emotionalRed)
                        }

                        PeezyAssessmentButton(
                            isSaving ? "Saving..." : "Save Changes",
                            disabled: isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty
                        ) {
                            save()
                        }
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
                .font(PeezyTheme.Typography.captionMedium)
                .foregroundColor(deepInk.opacity(0.4))
                .tracking(0.5)

            content()
                .font(PeezyTheme.Typography.body)
                .foregroundColor(deepInk)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                        .fill(deepInk.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                                .stroke(deepInk.opacity(0.06), lineWidth: 0.5)
                        )
                )
                .tint(deepInk)
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
