import SwiftUI

struct RoomListView: View {
    var sessionManager: InventorySessionManager
    var onDismiss: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var roomToDelete: ScannedRoom?
    @State private var newRoomName = ""
    @State private var showRoomNameEntry = false
    @State private var savePressed = false
    @State private var scanPressed = false

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 16)

                if sessionManager.scannedRooms.isEmpty {
                    emptyState
                } else {
                    roomList
                }

                Spacer()

                bottomButtons
            }
        }
        .alert("Delete Room", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let room = roomToDelete,
                   let index = sessionManager.scannedRooms.firstIndex(where: { $0.id == room.id }) {
                    withAnimation(PeezyTheme.Animation.spring) {
                        sessionManager.deleteRoom(at: IndexSet(integer: index))
                    }
                }
                roomToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                roomToDelete = nil
            }
        } message: {
            if let room = roomToDelete {
                Text("Remove \(room.name) and its \(room.items.count) items?")
            }
        }
        .sheet(isPresented: $showRoomNameEntry) {
            roomNameSheet
        }
        .overlay(alignment: .topTrailing) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(.regularMaterial)
                    .clipShape(Circle())
            }
            .padding(.trailing, PeezyTheme.Layout.horizontalPadding)
            .padding(.top, 16)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            Text("Your Inventory")
                .font(PeezyTheme.Typography.title)
                .foregroundStyle(PeezyTheme.Colors.textPrimary)

            if !sessionManager.scannedRooms.isEmpty {
                let roomCount = sessionManager.scannedRooms.count
                Text("\(sessionManager.totalItemCount) items across \(roomCount) room\(roomCount == 1 ? "" : "s")")
                    .font(PeezyTheme.Typography.callout)
                    .foregroundStyle(PeezyTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PeezyTheme.Layout.cardPadding)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: PeezyTheme.Layout.sectionSpacing) {
            Spacer()

            VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.25))

                Text("Scan your first room to start\nbuilding your inventory")
                    .font(PeezyTheme.Typography.callout)
                    .foregroundStyle(PeezyTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
    }

    // MARK: - Room List

    private var roomList: some View {
        ScrollView {
            LazyVStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                ForEach(sessionManager.scannedRooms) { room in
                    roomRow(room)
                }
            }
            .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
            .padding(.top, PeezyTheme.Layout.verticalSpacing)
        }
    }

    private func roomRow(_ room: ScannedRoom) -> some View {
        HStack(spacing: PeezyTheme.Layout.verticalSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(PeezyTheme.Typography.bodyMedium)
                    .foregroundStyle(PeezyTheme.Colors.textPrimary)

                Text("\(room.items.count) item\(room.items.count == 1 ? "" : "s")")
                    .font(PeezyTheme.Typography.callout)
                    .foregroundStyle(PeezyTheme.Colors.textSecondary)
            }

            Spacer()

            // Item count badge
            Text("\(room.items.count)")
                .font(PeezyTheme.Typography.calloutMedium)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(width: 32, height: 32)
                .background(PeezyTheme.Colors.brandYellow.opacity(0.3))
                .clipShape(Circle())

            // Delete button
            Button {
                roomToDelete = room
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(PeezyTheme.Colors.emotionalRed.opacity(0.7))
                    .frame(width: 32, height: 32)
            }
        }
        .padding(PeezyTheme.Layout.cardPadding)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                    .fill(.regularMaterial)

                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.15))

                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
        )
        .shadow(color: PeezyTheme.Shadows.subtleShadowColor, radius: PeezyTheme.Shadows.subtleShadowRadius, x: 0, y: PeezyTheme.Shadows.subtleShadowY)
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            // Primary: Submit for Review
            Button {
                PeezyHaptics.light()
                submitForReview()
            } label: {
                Text("Submit for Review")
                    .font(PeezyTheme.Typography.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .frame(height: PeezyTheme.Layout.buttonHeight)
                    .frame(maxWidth: .infinity)
                    .background(PeezyTheme.Gradients.brandYellow)
                    .clipShape(RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusPill, style: .continuous))
                    .shadow(color: PeezyTheme.Shadows.buttonShadowColor, radius: PeezyTheme.Shadows.buttonShadowRadius, x: 0, y: PeezyTheme.Shadows.buttonShadowY)
            }
            .disabled(sessionManager.scannedRooms.isEmpty)
            .opacity(sessionManager.scannedRooms.isEmpty ? 0.4 : 1.0)

            // Secondary: Save for Later
            if !sessionManager.scannedRooms.isEmpty {
                Button(action: {
                    PeezyHaptics.light()
                    saveForLater()
                }) {
                    Text("Save for later")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PeezyTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
        .padding(.bottom, PeezyTheme.Layout.cardPadding)
    }

    private func submitForReview() {
        Task {
            do {
                try await sessionManager.saveAllToFirestore()
                await MainActor.run {
                    onDismiss()
                }
            } catch {
                sessionManager.error = error.localizedDescription
            }
        }
    }

    private func saveForLater() {
        Task {
            do {
                try await sessionManager.saveAllToFirestore()
                await MainActor.run {
                    onDismiss()
                }
            } catch {
                sessionManager.error = error.localizedDescription
            }
        }
    }

    // MARK: - Room Name Sheet

    private var roomNameSheet: some View {
        NavigationStack {
            VStack(spacing: PeezyTheme.Layout.sectionSpacing) {
                Spacer()

                VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                    Text("What room are you scanning?")
                        .font(PeezyTheme.Typography.title2)
                        .foregroundStyle(PeezyTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    TextField("e.g. Living Room", text: $newRoomName)
                        .font(PeezyTheme.Typography.body)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                                .fill(PeezyTheme.Colors.backgroundSecondary)
                        )
                        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
                }

                Button {
                    let name = newRoomName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    showRoomNameEntry = false
                    newRoomName = ""
                    sessionManager.startNewRoom(name: name)
                } label: {
                    Text("Start Scanning")
                        .font(PeezyTheme.Typography.headline)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .frame(height: PeezyTheme.Layout.buttonHeight)
                        .frame(maxWidth: .infinity)
                        .background(PeezyTheme.Gradients.brandYellow)
                        .clipShape(RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusPill, style: .continuous))
                }
                .disabled(newRoomName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(newRoomName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
                .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showRoomNameEntry = false
                        newRoomName = ""
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

}
